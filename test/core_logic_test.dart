// Unit tests for the pure-logic core: verdict parsing (defensive JSON) and
// the model router's tier/fallback/vision behaviour. No UI, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/core/ai/model_catalog.dart';
import 'package:receipts/core/ai/model_router.dart';
import 'package:receipts/features/verification/verdict_model.dart';
import 'package:receipts/features/accountability/roast_bank.dart';

void main() {
  group('Verdict.parse', () {
    test('parses clean JSON', () {
      final v = Verdict.parse(
        '{"verdict":"pass","confidence":0.9,"summary":"ok","checks":[],"claims":[]}',
      );
      expect(v.kind, VerdictKind.pass);
      expect(v.confidence, 0.9);
    });

    test('downgrades low-confidence pass to partial (code-enforced)', () {
      final v = Verdict.parse(
        '{"verdict":"pass","confidence":0.4,"summary":"meh","checks":[],"claims":[]}',
      );
      expect(v.kind, VerdictKind.partial);
    });

    test('extracts JSON from prose wrapper', () {
      final v = Verdict.parse(
        'Here is my verdict: {"verdict":"fail","confidence":0.9,"summary":"x","checks":[],"claims":[]} hope that helps',
      );
      expect(v.kind, VerdictKind.fail);
    });

    test('survives total garbage', () {
      final v = Verdict.parse('not json at all');
      expect(v.kind, VerdictKind.partial);
    });
  });

  group('ModelRouter.plan', () {
    final keys = {'groq': 'k', 'nvidia': 'k', 'openrouter': 'k'}.map(
      (k, v) => MapEntry(AiProvider.values.firstWhere((p) => p.id == k), v),
    );

    test('picks highest-strength keyed model in tier', () {
      final plan = const ModelRouter().plan(tier: Tier.balanced, keys: keys);
      expect(plan.primary.tier, Tier.balanced);
      expect(keys.containsKey(plan.primary.provider), isTrue);
    });

    test('empty candidates when no keys', () {
      final plan = const ModelRouter().plan(tier: Tier.swift, keys: const {});
      expect(plan.candidates, isEmpty);
    });

    test('vision swap promotes a vision-capable model first', () {
      // Deep tier's primary (DeepSeek R1) has no vision — image evidence
      // must pull a vision-capable model to the front.
      final plan = const ModelRouter().plan(
        tier: Tier.deep,
        keys: keys,
        needsVision: true,
      );
      expect(plan.primary.supportsVision, isTrue);
      expect(plan.visionSwappedTo, isNotNull);
    });

    test('fallbacks include other tiers', () {
      final plan = const ModelRouter().plan(tier: Tier.smart, keys: keys);
      expect(plan.candidates.length, greaterThan(1));
      expect(plan.candidates.any((m) => m.tier == Tier.balanced), isTrue);
    });
  });

  test('RoastBank never repeats back-to-back', () {
    final a = RoastBank.pick();
    final b = RoastBank.pick();
    expect(a == b, isFalse);
  });
}
