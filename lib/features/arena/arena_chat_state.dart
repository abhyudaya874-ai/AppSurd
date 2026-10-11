import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/openai_compat_client.dart';
import '../settings/settings_screen.dart';
import 'arena_state.dart';

/// Arena's three ways to compare: open side-by-side, blind battle (names
/// hidden until you vote), and Jury — the existing verification-jury lineup.
enum ArenaMode { sideBySide, battle, jury }

/// Per-card lifecycle inside one comparison round.
enum CardStatus { queued, streaming, done, error }

/// One model's answer inside a round. In Battle mode [displayName] stays
/// "Model A/B" until a vote is cast — [revealName] swaps the real name in.
class ArenaCard {
  const ArenaCard({
    required this.label,
    required this.spec,
    this.status = CardStatus.queued,
    this.text = '',
    this.ms,
    this.error,
    this.revealed = true,
  });

  final String label; // 'A' | 'B'
  final ModelSpec spec;
  final CardStatus status;
  final String text;
  final int? ms;
  final String? error;

  /// Whether the real model name is shown (always true outside Battle).
  final bool revealed;

  ArenaCard copyWith({
    CardStatus? status,
    String? text,
    int? ms,
    String? error,
    bool? revealed,
  }) => ArenaCard(
    label: label,
    spec: spec,
    status: status ?? this.status,
    text: text ?? this.text,
    ms: ms ?? this.ms,
    error: error,
    revealed: revealed ?? this.revealed,
  );

  String get shownName => revealed ? spec.displayName : 'Model $label';
}

/// One user prompt plus the two answers it triggered.
/// [vote]: -1 = none yet, 0 = A better, 1 = tie, 2 = B better.
class ArenaRound {
  const ArenaRound({required this.prompt, required this.cards, this.vote = -1});
  final String prompt;
  final List<ArenaCard> cards;
  final int vote;
}

/// Arena screen state — mode, the two picked models, and the rounds so far.
class ArenaChatState {
  const ArenaChatState({
    this.mode = ArenaMode.sideBySide,
    this.specA,
    this.specB,
    this.rounds = const [],
  });

  final ArenaMode mode;
  final ModelSpec? specA;
  final ModelSpec? specB;
  final List<ArenaRound> rounds;

  ArenaChatState copyWith({
    ArenaMode? mode,
    ModelSpec? specA,
    ModelSpec? specB,
    List<ArenaRound>? rounds,
  }) => ArenaChatState(
    mode: mode ?? this.mode,
    specA: specA ?? this.specA,
    specB: specB ?? this.specB,
    rounds: rounds ?? this.rounds,
  );
}

/// Signature of a "give me this model's answer" call — injectable so the
/// fan-out is unit-testable without network.
typedef ArenaRunner = Future<String> Function(ModelSpec spec, String prompt);

/// Runs one model for a round — the real implementation streams via the
/// OpenAI-compatible client and joins the chunks; unkeyed models or Demo
/// Mode get canned answers so the demo always works.
Future<String> defaultArenaRunner(ModelSpec spec, String prompt) async {
  // Wired at runtime by the notifier (needs key + demo flag), so callers
  // shouldn't reach this — kept as a loud fallback.
  throw UnsupportedError('use ArenaChatNotifier._runner');
}

/// Elo-ish tally stored in the receipts_arena box: {id: [wins, losses]}.
/// Ties count as half a win for both — simple, explainable, deterministic.
Future<void> recordArenaVote({
  required String aId,
  required String bId,
  required int vote, // 0 = A, 1 = tie, 2 = B
}) async {
  final box = await Hive.openBox('receipts_arena');
  List<num> row(String id) => (box.get(id) as List?)?.cast<num>() ?? [0, 0];
  final a = row(aId), b = row(bId);
  if (vote == 0) {
    await box.put(aId, [a[0] + 1, a[1]]);
    await box.put(bId, [b[0], b[1] + 1]);
  } else if (vote == 2) {
    await box.put(aId, [a[0], a[1] + 1]);
    await box.put(bId, [b[0] + 1, b[1]]);
  } else {
    await box.put(aId, [a[0] + 0.5, a[1]]);
    await box.put(bId, [b[0] + 0.5, b[1]]);
  }
}

/// All win/loss rows — Profile's leaderboard reads this.
Future<Map<String, List<num>>> arenaScores() async {
  final box = await Hive.openBox('receipts_arena');
  return {
    for (final k in box.keys) k.toString(): (box.get(k) as List).cast<num>(),
  };
}

/// Arena chat: prompt in, two concurrent answers out, votes persisted.
/// [runnerForTest] lets tests inject fake runners — the concurrency
/// guarantee (one failure never blocks the other card) is the tested part.
final arenaChatProvider = NotifierProvider<ArenaChatNotifier, ArenaChatState>(
  ArenaChatNotifier.new,
);

class ArenaChatNotifier extends Notifier<ArenaChatState> {
  /// Overridden in tests — maps (spec, prompt) → answer text.
  ArenaRunner? runnerForTest;

  @override
  ArenaChatState build() {
    final catalog = ref.watch(liveCatalogProvider).value ?? kModelCatalog;
    final defaults = defaultLineup();
    ModelSpec? pick(int i) {
      if (defaults.length > i) {
        final hit = catalog.where((m) => m.id == defaults[i]);
        if (hit.isNotEmpty) return hit.first;
      }
      return catalog.isNotEmpty ? catalog[i % catalog.length] : null;
    }

    return ArenaChatState(
      specA: _prev?.specA ?? pick(0),
      specB: _prev?.specB ?? pick(1) ?? pick(0),
      rounds: _prev?.rounds ?? const [],
      mode: _prev?.mode ?? ArenaMode.sideBySide,
    );
  }

  /// Previous state during rebuild (Riverpod allows reading `state` inside
  /// build; it throws pre-init, so guard it).
  ArenaChatState? get _prev {
    try {
      return state;
    } catch (_) {
      return null;
    }
  }

  void setMode(ArenaMode m) => state = state.copyWith(mode: m);
  void setSpecA(ModelSpec s) => state = state.copyWith(specA: s);
  void setSpecB(ModelSpec s) => state = state.copyWith(specB: s);

  /// Real runner: streams the model, joins chunks, 30s timeout. No key or
  /// Demo Mode → a canned-but-different answer per model.
  Future<String> _run(ModelSpec spec, String prompt) async {
    if (runnerForTest != null) return runnerForTest!(spec, prompt);
    final demo = ref.read(demoModeProvider);
    final keys = await ref.read(configuredKeysProvider.future);
    final key = keys[spec.provider];
    if (demo || key == null || key.isEmpty) {
      await Future<void>.delayed(
        Duration(milliseconds: 700 + spec.id.hashCode.abs() % 900),
      );
      return 'Demo answer from ${spec.displayName}:\n\n'
          'For "$prompt", ${spec.displayName} would argue the strongest '
          'evidence is a working demo over a slide. It rates this '
          '${60 + spec.id.hashCode.abs() % 35}% provable and suggests one '
          'concrete receipt: a screen recording of the flow working.\n\n'
          '_Demo response — add a key in Settings for a real answer._';
    }
    final client = OpenAiCompatClient(
      baseUrl: spec.provider.baseUrl,
      apiKey: key,
      extraHeaders: spec.provider.extraHeaders,
    );
    final buf = StringBuffer();
    await for (final chunk
        in client
            .streamRich(
              model: spec.id,
              messages: [ChatMessage(role: 'user', content: prompt)],
            )
            .timeout(const Duration(seconds: 30))) {
      buf.write(chunk.text);
    }
    return buf.toString();
  }

  /// Fan-out: append a round with two streaming cards, then fill each
  /// independently — one model failing never stalls the other.
  Future<void> send(String prompt) async {
    final a = state.specA, b = state.specB;
    if (prompt.trim().isEmpty || a == null || b == null) return;
    final idx = state.rounds.length;
    final battle = state.mode == ArenaMode.battle;
    state = state.copyWith(
      rounds: [
        ...state.rounds,
        ArenaRound(
          prompt: prompt,
          cards: [
            ArenaCard(
              label: 'A',
              spec: a,
              status: CardStatus.streaming,
              revealed: !battle,
            ),
            ArenaCard(
              label: 'B',
              spec: b,
              status: CardStatus.streaming,
              revealed: !battle,
            ),
          ],
        ),
      ],
    );
    await Future.wait([_fill(idx, 0, prompt), _fill(idx, 1, prompt)]);
  }

  /// Retry just one card (refresh button) — same concurrent rules.
  Future<void> retry(int roundIdx, int cardIdx) async {
    _patchCard(
      roundIdx,
      cardIdx,
      (c) => c.copyWith(status: CardStatus.streaming, text: ''),
    );
    await _fill(roundIdx, cardIdx, state.rounds[roundIdx].prompt);
  }

  Future<void> _fill(int roundIdx, int cardIdx, String prompt) async {
    final card = state.rounds[roundIdx].cards[cardIdx];
    final sw = Stopwatch()..start();
    try {
      final text = await _run(card.spec, prompt);
      _patchCard(
        roundIdx,
        cardIdx,
        (c) => c.copyWith(
          status: CardStatus.done,
          text: text,
          ms: sw.elapsedMilliseconds,
        ),
      );
    } catch (e) {
      _patchCard(
        roundIdx,
        cardIdx,
        (c) => c.copyWith(
          status: CardStatus.error,
          error: e is TimeoutException ? 'Timed out (30s)' : 'Failed: $e',
        ),
      );
    }
  }

  /// Vote: 0 = A, 1 = tie, 2 = B. Also reveals Battle-mode names and
  /// writes the tally row to Hive.
  Future<void> vote(int roundIdx, int vote) async {
    final r = state.rounds[roundIdx];
    if (r.vote >= 0) return; // one vote per round
    final cards = [for (final c in r.cards) c.copyWith(revealed: true)];
    final rounds = [...state.rounds];
    rounds[roundIdx] = ArenaRound(prompt: r.prompt, cards: cards, vote: vote);
    state = state.copyWith(rounds: rounds);
    await recordArenaVote(
      aId: r.cards[0].spec.id,
      bId: r.cards[1].spec.id,
      vote: vote,
    );
  }

  void _patchCard(int roundIdx, int cardIdx, ArenaCard Function(ArenaCard) fn) {
    if (roundIdx >= state.rounds.length) return;
    final r = state.rounds[roundIdx];
    if (cardIdx >= r.cards.length) return;
    final cards = [...r.cards];
    cards[cardIdx] = fn(cards[cardIdx]);
    final rounds = [...state.rounds];
    rounds[roundIdx] = ArenaRound(prompt: r.prompt, cards: cards, vote: r.vote);
    state = state.copyWith(rounds: rounds);
  }
}
