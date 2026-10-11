import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:receipts/core/ai/model_catalog.dart';
import 'package:receipts/features/arena/arena_models.dart';
import 'package:receipts/features/arena/arena_service.dart';
import 'package:receipts/features/verification/verdict_model.dart';
import 'package:receipts/features/arena/arena_chat_state.dart';
import 'package:receipts/features/model_picker/model_selection.dart';
import 'package:receipts/core/ai/api_key_store.dart';

JudgeResult _j(ModelSpec m, VerdictKind k, double conf) => JudgeResult(
  model: m,
  latencyMs: 100,
  verdict: Verdict(
    kind: k,
    confidence: conf,
    summary: 's',
    checks: const [],
    claims: const [],
  ),
);

void main() {
  setUpAll(() => Hive.init('/tmp/arena_test_hive'));

  test('aggregation: weighted vote + strict tie + strictness floor', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(arenaServiceProvider);

    // Reach _aggregate via a canned run — demo mode off, but we can call the
    // extension indirectly through run() only with a real task. Instead test
    // the public surface: make lineup models and check the outcome object.
    final groq = kModelCatalog.firstWhere((m) => m.provider.id == 'groq');
    final nv = kModelCatalog.firstWhere((m) => m.provider.id == 'nvidia');
    final or1 = kModelCatalog.firstWhere((m) => m.provider.id == 'openrouter');

    // 2 pass vs 1 fail, but fail has huge confidence → still loses the vote
    // (fail score 0.99 < pass 1.6).
    var out = svc.testAggregateForTest([
      _j(groq, VerdictKind.pass, 0.8),
      _j(nv, VerdictKind.pass, 0.8),
      _j(or1, VerdictKind.fail, 0.99),
    ], Strictness.fair);
    expect(out.consensus, VerdictKind.pass);
    expect(out.dissenters.single.model.provider.id, 'openrouter');
    expect(out.agreement, closeTo(2 / 3, 0.01));
    expect(out.strictest!.verdict!.kind, VerdictKind.fail);

    // Tied scores: strictest verdict wins the tie.
    out = svc.testAggregateForTest([
      _j(groq, VerdictKind.pass, 0.9),
      _j(nv, VerdictKind.fail, 0.9),
    ], Strictness.fair);
    expect(out.consensus, VerdictKind.fail);

    // Strictness floor: pass consensus at 0.6 avg under Strict (0.8) → partial.
    out = svc.testAggregateForTest([
      _j(groq, VerdictKind.pass, 0.6),
      _j(nv, VerdictKind.pass, 0.6),
    ], Strictness.strict);
    expect(out.consensus, VerdictKind.partial);

    // All judges dead → forced fail, agreement 0.
    out = svc.testAggregateForTest([
      JudgeResult(model: groq, latencyMs: 0, error: 'timeout'),
      JudgeResult(model: nv, latencyMs: 0, error: 'timeout'),
    ], Strictness.fair);
    expect(out.consensus, VerdictKind.fail);
    expect(out.agreement, 0);
  });

  arenaChatTests();
}

// ---------------------------------------------------------------------------
// Rev 4 — side-by-side arena chat: concurrency + Elo.
// ---------------------------------------------------------------------------

class _NoKeys extends ConfiguredKeys {
  @override
  Future<Map<AiProvider, String>> build() async => const {};
}

ProviderContainer _arenaContainer() => ProviderContainer(
  overrides: [
    configuredKeysProvider.overrideWith(_NoKeys.new),
    modelSelectionProvider.overrideWith(ModelSelectionNotifier.new),
  ],
);

void arenaChatTests() {
  test('fan-out: one failing model does not block the other card', () async {
    final c = _arenaContainer();
    addTearDown(c.dispose);
    final n = c.read(arenaChatProvider.notifier);
    n.runnerForTest = (spec, prompt) async {
      if (spec == c.read(arenaChatProvider).specA) {
        throw Exception('model A blew up');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 'B says hi';
    };
    await n.send('test prompt');
    final r = c.read(arenaChatProvider).rounds.single;
    expect(r.cards[0].status, CardStatus.error);
    expect(r.cards[1].status, CardStatus.done);
    expect(r.cards[1].text, 'B says hi');
  });

  test(
    'Elo: win increments winner, tie half-points both, one vote/round',
    () async {
      final c = _arenaContainer();
      addTearDown(c.dispose);
      final n = c.read(arenaChatProvider.notifier);
      n.runnerForTest = (spec, prompt) async => 'ok';
      // The arena box persists on disk between test runs — reset the tally.
      await (await Hive.openBox('receipts_arena')).clear();
      await n.send('p');
      final r = c.read(arenaChatProvider).rounds.single;
      await n.vote(0, 0); // A wins
      await n.vote(0, 2); // ignored — already voted
      final scores = await arenaScores();
      expect(scores[r.cards[0].spec.id], [1, 0]);
      expect(scores[r.cards[1].spec.id], [0, 1]);
      expect(c.read(arenaChatProvider).rounds.single.vote, 0);
    },
  );
}
