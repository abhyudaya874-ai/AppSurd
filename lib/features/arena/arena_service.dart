import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/ai/prompts.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_model.dart';
import '../verification/evidence_prep.dart';
import '../verification/verdict_model.dart';
import 'arena_models.dart';
import '../../core/ai/free_guard.dart';

/// Per-judge progress for the jury bar + cards.
sealed class ArenaEvent {
  const ArenaEvent();
}

class JudgeStarted extends ArenaEvent {
  const JudgeStarted(this.model);
  final ModelSpec model;
}

class JudgeDone extends ArenaEvent {
  const JudgeDone(this.result);
  final JudgeResult result;
}

class ArenaDone extends ArenaEvent {
  const ArenaDone(this.outcome);
  final ArenaOutcome outcome;
}

/// One call per lineup model, run concurrently, aggregated in code.
class ArenaService {
  ArenaService(this._ref);
  final Ref _ref;

  /// Fans the SAME prepared evidence out to every judge and aggregates the
  /// verdicts: confidence-weighted vote, ties go to the stricter verdict,
  /// code-side rules (dead link ⇒ fail, strictness floor) applied after.
  Stream<ArenaEvent> run(
    Task task,
    EvidenceAttempt attempt,
    List<ModelSpec> lineup,
    Strictness strictness,
  ) async* {
    final keys = await _ref.read(configuredKeysProvider.future);

    // Demo Mode safety: no usable keys → canned outcome with one clear
    // dissenter, still running through the real UI + real aggregation.
    // Labelled "[Demo data]" on every judge summary.
    final demo = _ref.read(demoModeProvider);
    final anyKeyForLineup =
        lineup.any((m) => keys.containsKey(m.provider));
    if (demo && !anyKeyForLineup) {
      yield* _canned(lineup);
      return;
    }
    final prep = await prepareEvidence(attempt);

    // Judges that can't read images are skipped (not failed) on screenshots.
    final judges = lineup
        .where((m) => !prep.needsVision || m.supportsVision)
        .toList();
    final blind = lineup
        .where((m) => prep.needsVision && !m.supportsVision)
        .toList();
    for (final m in blind) {
      yield JudgeDone(JudgeResult(
          model: m, latencyMs: 0, error: "Can't see images"));
    }

    if (prep.fetchFailed) {
      // Dead evidence ⇒ forced fail, same rule as single mode.
      final fail = Verdict(
        kind: VerdictKind.fail,
        confidence: 1,
        summary: 'The evidence link could not be fetched.',
        checks: const [
          VerdictCheck(label: 'Evidence link reachable', ok: false),
        ],
        claims: const [],
        roast: 'That link doesn\'t even open. Bold strategy.',
      );
      yield ArenaDone(ArenaOutcome(
        results: [
          for (final m in lineup)
            JudgeResult(model: m, latencyMs: 0, verdict: fail),
        ],
        consensus: VerdictKind.fail,
        agreement: 1,
        dissenters: const [],
        strictest: null,
        consensusVerdict: fail,
      ));
      return;
    }

    // Fan out concurrently — one call per judge, each 30s / ≤600 tokens.
    // Free tiers: cap at 3 judges, stagger starts ~150ms to spread quota.
    final capped = judges.take(3).toList();
    final futures = <String, Future<JudgeResult>>{};
    for (var i = 0; i < capped.length; i++) {
      final m = capped[i];
      futures[m.id] = _staggeredJudge(i, task, attempt, prep, m,
          keys[m.provider], strictness);
    }
    final judges2 = capped;
    final results = <JudgeResult>[];
    for (final m in judges2) {
      yield JudgeStarted(m);
    }
    for (final entry in futures.entries) {
      final r = await entry.value;
      results.add(r);
      yield JudgeDone(r);
    }
    if (results.where((r) => r.finished).isEmpty) {
      // ALL judges failed — one retry round, then give up.
      for (final m in judges2) {
        yield JudgeStarted(m);
      }
      for (final m in judges2) {
        final r = await _judge(
            task, attempt, prep, m, keys[m.provider], strictness);
        results.add(r);
        yield JudgeDone(r);
      }
    }

    yield ArenaDone(_aggregate(results, strictness));
  }

  /// Staggered start for free-tier rate limits (~150ms per judge).
  Future<JudgeResult> _staggeredJudge(
    int i,
    Task task,
    EvidenceAttempt attempt,
    PreparedEvidence prep,
    ModelSpec m,
    String? key,
    Strictness s,
  ) async {
    if (i > 0) {
      await Future<void>.delayed(Duration(milliseconds: 150 * i));
    }
    return _judge(task, attempt, prep, m, key, s);
  }

  /// Calls one judge model directly (no tier routing — arena picks models).
  Future<JudgeResult> _judge(
    Task task,
    EvidenceAttempt attempt,
    PreparedEvidence prep,
    ModelSpec model,
    String? key,
    Strictness strictness,
  ) async {
    if (key == null) {
      return JudgeResult(
          model: model, latencyMs: 0, error: 'No API key');
    }
    final sw = Stopwatch()..start();
    try {
      FreeGuard.assertFree(model); // free-only, even for judges
      final client = OpenAiCompatClient(
        baseUrl: model.provider.baseUrl,
        apiKey: key,
        extraHeaders: model.provider.extraHeaders,
      );
      final userText = verifierUser(
        taskTitle: task.title,
        taskProofHint: task.description,
        evidenceType: attempt.type.name,
        evidenceText: prep.evidenceText,
        sourceTexts: evidenceSourceTexts(prep),
      );
      final raw = await client.complete(
        model: model.id,
        jsonMode: true,
        maxTokens: 600,
        messages: [
          const ChatMessage(role: 'system', content: verifierSystem),
          ChatMessage(
              role: 'user',
              content: prep.imageB64 == null
                  ? userText
                  : [
                      {'type': 'text', 'text': userText},
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url': 'data:image/jpeg;base64,${prep.imageB64}'
                        },
                      },
                    ]),
        ],
      ).timeout(const Duration(seconds: 30));
      return JudgeResult(
        model: model,
        latencyMs: sw.elapsedMilliseconds,
        verdict: Verdict.parse(raw),
      );
    } catch (e) {
      return JudgeResult(
          model: model,
          latencyMs: sw.elapsedMilliseconds,
          error: e.runtimeType.toString().replaceAll('Exception', ''));
    }
  }

  /// Aggregation — in code, never delegated. Confidence-weighted vote per
  /// verdict kind; ties resolve to the stricter verdict; strictness sets the
  /// pass floor on the consensus confidence.
  ArenaOutcome _aggregate(List<JudgeResult> results, Strictness strictness) {
    final finished = results.where((r) => r.finished).toList();
    if (finished.isEmpty) {
      const fail = Verdict(
        kind: VerdictKind.fail,
        confidence: 0,
        summary: 'Every judge failed to return a verdict.',
        checks: [],
        claims: [],
      );
      return ArenaOutcome(
          results: results,
          consensus: VerdictKind.fail,
          agreement: 0,
          dissenters: const [],
          strictest: null,
          consensusVerdict: fail);
    }

    // Confidence-weighted vote: kind → sum of confidences voting for it.
    final scores = <VerdictKind, double>{};
    for (final r in finished) {
      final k = r.verdict!.kind;
      scores[k] = (scores[k] ?? 0) + r.verdict!.confidence;
    }
    // Strictness order for ties: fail < partial < pass means fail is strictest.
    const strictnessOrder = {
      VerdictKind.fail: 0,
      VerdictKind.partial: 1,
      VerdictKind.pass: 2,
    };
    var winner = scores.entries.reduce((a, b) {
      if (a.value != b.value) return a.value > b.value ? a : b;
      return strictnessOrder[a.key]! < strictnessOrder[b.key]! ? a : b;
    }).key;

    // Strictness floor: consensus "pass" needs average confidence ≥ threshold.
    if (winner == VerdictKind.pass) {
      final passers =
          finished.where((r) => r.verdict!.kind == VerdictKind.pass);
      final avg = passers.fold<double>(
              0, (s, r) => s + r.verdict!.confidence) /
          passers.length;
      if (avg < strictness.passThreshold) winner = VerdictKind.partial;
    }

    // After a strictness-floor downgrade, no judge may have actually voted
    // for the winner kind — treat the pass-voters as the consensus group.
    var inConsensus =
        finished.where((r) => r.verdict!.kind == winner).toList();
    final effectiveWinner =
        inConsensus.isEmpty ? VerdictKind.pass : winner;
    if (inConsensus.isEmpty) {
      inConsensus = finished
          .where((r) => r.verdict!.kind == VerdictKind.pass)
          .toList();
    }
    final dissenters = finished
        .where((r) => r.verdict!.kind != effectiveWinner)
        .toList();
    final agreement = inConsensus.length / finished.length;

    // Strictest judge = harshest vote; highest confidence breaks ties.
    JudgeResult? strictest;
    for (final r in finished) {
      if (strictest == null ||
          strictnessOrder[r.verdict!.kind]! <
              strictnessOrder[strictest.verdict!.kind]! ||
          (r.verdict!.kind == strictest.verdict!.kind &&
              r.verdict!.confidence > strictest.verdict!.confidence)) {
        strictest = r;
      }
    }

    // The consensus verdict object = a consensus judge's own verdict, with
    // the strictest judge's roast/challenge overlaid for non-passes. When the
    // winner kind was code-downgraded, override the kind on that verdict.
    var consensusVerdict = inConsensus
        .reduce((a, b) =>
            a.verdict!.confidence > b.verdict!.confidence ? a : b)
        .verdict!;
    if (effectiveWinner != winner) {
      consensusVerdict = consensusVerdict.copyWith(kind: winner);
    }
    if (winner != VerdictKind.pass && strictest?.verdict != null) {
      consensusVerdict = consensusVerdict.copyWith(
        roast: strictest!.verdict!.roast ?? consensusVerdict.roast,
        challenge:
            strictest.verdict!.challenge ?? consensusVerdict.challenge,
      );
    }
    return ArenaOutcome(
      results: results,
      consensus: winner,
      agreement: agreement,
      dissenters: dissenters,
      strictest: strictest,
      consensusVerdict: consensusVerdict,
    );
  }
}

final arenaServiceProvider =
    Provider<ArenaService>((ref) => ArenaService(ref));

extension ArenaServiceTesting on ArenaService {
  /// Test seam for the aggregation — exercised directly so the vote math,
  /// tie rules and strictness floor get real coverage without network.
  ArenaOutcome testAggregateForTest(
          List<JudgeResult> results, Strictness s) =>
      _aggregate(results, s);
}

extension _CannedArena on ArenaService {
  /// Canned demo outcome — every judge "returns" with staged latencies, one
  /// clear dissenter, all labelled "[Demo data]". Real aggregation runs on
  /// these results, so the split/consensus logic is genuinely exercised.
  Stream<ArenaEvent> _canned(List<ModelSpec> lineup) async* {
    for (final m in lineup) {
      yield JudgeStarted(m);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final results = <JudgeResult>[];
    for (var i = 0; i < lineup.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // Middle judge dissents to 'partial' — split decision on screen.
      final dissent = i == 1 && lineup.length > 2;
      final v = Verdict(
        kind: dissent ? VerdictKind.partial : VerdictKind.pass,
        confidence: dissent ? 0.61 : 0.85 - i * 0.03,
        summary: dissent
            ? '[Demo data] The evidence is thin on specifics — the page loads but nothing proves YOUR work.'
            : '[Demo data] The link resolves, content matches the task claim, deliverable looks real.',
        checks: const [
          VerdictCheck(label: 'Link fetched 2xx', ok: true),
          VerdictCheck(label: 'Matches the task', ok: true),
        ],
        claims: const [
          VerdictClaim(text: 'Task deliverable present', sourceIndex: 0),
        ],
        roast: dissent
            ? 'This evidence is giving "I swear I did it" energy.'
            : null,
      );
      final r = JudgeResult(model: lineup[i], latencyMs: 650 + i * 240, verdict: v);
      results.add(r);
      yield JudgeDone(r);
    }
    // Reach the real aggregation via the private method (same file).
    yield ArenaDone((this)._aggregate(results, Strictness.fair));
  }
}
