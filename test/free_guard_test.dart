import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/core/ai/brand_resolver.dart';
import 'package:receipts/core/ai/free_guard.dart';
import 'package:receipts/core/ai/model_catalog.dart';
import 'package:receipts/core/ai/strength_estimator.dart';

void main() {
  group('FreeGuard', () {
    test('accepts zero-priced OpenRouter :free model', () {
      expect(
        FreeGuard.evaluate(
          id: 'meta-llama/llama-3.3-70b:free',
          provider: AiProvider.openrouter,
          pricingIsZero: true,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isTrue,
      );
    });
    test('rejects paid OpenRouter model (pricing > 0, no :free)', () {
      expect(
        FreeGuard.evaluate(
          id: 'openai/gpt-4o',
          provider: AiProvider.openrouter,
          pricingIsZero: false,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isFalse,
      );
      expect(
        FreeGuard.evaluate(
          id: 'openai/gpt-4o',
          provider: AiProvider.openrouter,
          pricingIsZero: false,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isFalse,
      );
    });
    test('rejects router/meta ids that could proxy to paid', () {
      expect(
        FreeGuard.evaluate(
          id: 'openrouter/auto',
          provider: AiProvider.openrouter,
          pricingIsZero: true,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isFalse,
      );
    });
    test('NVIDIA needs allowlist + chat', () {
      expect(
        FreeGuard.evaluate(
          id: 'meta/llama-3.3-70b-instruct',
          provider: AiProvider.nvidia,
          pricingIsZero: false,
          onNimAllowlist: true,
          isChatCapable: true,
        ),
        isTrue,
      );
      expect(
        FreeGuard.evaluate(
          id: 'unlisted/model',
          provider: AiProvider.nvidia,
          pricingIsZero: false,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isFalse,
      );
    });
    test('Groq rejects speech/guard models', () {
      expect(
        FreeGuard.evaluate(
          id: 'whisper-large-v3',
          provider: AiProvider.groq,
          pricingIsZero: false,
          onNimAllowlist: false,
          isChatCapable: false,
        ),
        isFalse,
      );
      expect(
        FreeGuard.evaluate(
          id: 'llama-3.3-70b-versatile',
          provider: AiProvider.groq,
          pricingIsZero: false,
          onNimAllowlist: false,
          isChatCapable: true,
        ),
        isTrue,
      );
    });
    test('assertFree throws on a paid model — the call is blocked', () {
      const paid = ModelSpec(
        id: 'openai/gpt-4o',
        provider: AiProvider.openrouter,
        displayName: 'GPT-4o',
        tier: Tier.smart,
        strength: 0.9,
        isFree: false,
        blurb: '',
      );
      expect(
        () => FreeGuard.assertFree(paid),
        throwsA(isA<FreeGuardFailure>()),
      );
      const free = ModelSpec(
        id: 'x/y:free',
        provider: AiProvider.openrouter,
        displayName: 'y',
        tier: Tier.swift,
        strength: 0.1,
        isFree: true,
        blurb: '',
      );
      expect(() => FreeGuard.assertFree(free), returnsNormally);
    });
  });

  group('BrandResolver — 15 ids', () {
    test('maps prefixes/keywords to brands', () {
      final cases = {
        'meta-llama/llama-3.3-70b': 'meta',
        'llama-3.1-8b-instant': 'meta',
        'qwen/qwen3-235b-a22b': 'qwen',
        'deepseek/deepseek-r1': 'deepseek',
        'mistralai/mistral-small': 'mistral',
        'google/gemma-3-27b': 'gemma',
        'openai/gpt-oss-120b': 'openai',
        'nvidia/llama-nemotron': 'nvidia',
        'moonshotai/kimi-k2': 'moonshot',
        'z-ai/glm-4.6': 'zhipu',
        'microsoft/phi-4': 'microsoft',
        'tng/deepseek-r1t-chimera': 'deepseek',
        'qwen2.5-vl-72b-instruct': 'qwen',
        'google/gemma-2-9b': 'gemma',
        'someone/unknown-model': null,
      };
      for (final e in cases.entries) {
        expect(
          BrandResolver.fromModel(e.key, AiProvider.openrouter),
          e.value,
          reason: e.key,
        );
      }
    });
  });

  group('StrengthEstimator', () {
    test('orders param counts; reasoning > plain; mini < mid', () {
      expect(
        StrengthEstimator.raw('x-120b'),
        greaterThan(StrengthEstimator.raw('x-8b')),
      );
      expect(
        StrengthEstimator.raw('x-8b', reasoning: true),
        greaterThan(StrengthEstimator.raw('x-8b')),
      );
      expect(
        StrengthEstimator.raw('x-70b-mini'),
        lessThan(StrengthEstimator.raw('x-70b')),
      );
    });
  });
}
