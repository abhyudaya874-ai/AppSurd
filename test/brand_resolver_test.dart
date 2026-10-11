import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipts/core/ai/brand_resolver.dart';
import 'package:receipts/core/ai/model_catalog.dart';

/// Model-id → logo resolution: creators' marks win over the serving
/// provider; every referenced asset must exist.
void main() {
  test('~25 model ids resolve to the expected brand asset', () {
    const cases = {
      'meta/llama-3.3-70b-instruct': 'meta',
      'llama-3.1-8b-instant': 'meta',
      'nvidia/llama-3.1-nemotron-70b': 'nvidia',
      'nemotron-nano-9b': 'nvidia',
      'deepseek-ai/deepseek-r1': 'deepseek',
      'deepseek/deepseek-r1:free': 'deepseek',
      'qwen/qwen3-235b-a22b': 'qwen',
      'qwen3-32b': 'qwen',
      'mistralai/mistral-small:free': 'mistral',
      'google/gemma-3-27b-it:free': 'gemma',
      'google/gemini-2.0-flash-exp:free': 'gemma',
      'openai/gpt-oss-120b': 'openai',
      'openai/o4-mini': 'openai',
      'moonshotai/kimi-k2:free': 'moonshot',
      'z-ai/glm-4.5-air:free': 'zhipu',
      'microsoft/phi-4': 'microsoft',
      'microsoft/phi-3-mini': 'microsoft',
      'anthropic/claude-3.5-haiku:free': 'anthropic',
      'x-ai/grok-4-fast:free': 'xai',
      'cohere/command-r-plus:free': 'cohere',
      'minimax/minimax-m2:free': 'minimax',
      'ai21/jamba-large-1.7': 'ai21',
      'tencent/hunyuan-a13b:free': 'tencent',
      'nousresearch/hermes-3:free': 'nousresearch',
      'liquid/lfm-40b': 'liquid',
      'meta-llama/llama-4-scout': 'meta',
      'moonshotai/kimi-k2-instruct': 'moonshot',
    };
    for (final e in cases.entries) {
      expect(
        BrandResolver.fromModel(e.key, AiProvider.openrouter),
        e.value,
        reason: '${e.key} should resolve to ${e.value}',
      );
      expect(
        File('assets/logos/${e.value}.svg').existsSync(),
        isTrue,
        reason: 'assets/logos/${e.value}.svg must exist',
      );
    }
  });

  test('unknown brands return null — never a wrong logo', () {
    expect(BrandResolver.fromModel('acme/mystery-7b', AiProvider.groq), isNull);
    expect(BrandResolver.forProvider(AiProvider.groq), 'groq');
    expect(BrandResolver.forProvider(AiProvider.nvidia), 'nvidia');
    expect(BrandResolver.forProvider(AiProvider.openrouter), 'openrouter');
  });
}
