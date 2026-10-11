import 'model_catalog.dart';

/// Maps model ids to brand keys — prefixes/keywords → logo asset name.
/// Unknown ⇒ null → the UI shows a monogram (never a wrong logo).
abstract final class BrandResolver {
  static const _rules = [
    // Specific makers first — 'nvidia/llama-nemotron' is NVIDIA, not Meta.
    (r'nemotron|nvidia/', 'nvidia'),
    (r'meta[-_/]?llama|llama-', 'meta'),
    (r'^llama', 'meta'),
    (r'qwen', 'qwen'),
    (r'deepseek', 'deepseek'),
    (r'mistral|mixtral|codestral', 'mistral'),
    (r'gemma|google', 'gemma'),
    (r'gpt-oss|openai/', 'openai'),
    (r'nemotron|nvidia/', 'nvidia'),
    (r'kimi|moonshot', 'moonshot'),
    (r'glm|chatglm|zhipu|z\.ai', 'zhipu'),
    (r'phi-|microsoft', 'microsoft'),
  ];

  /// Model-maker brand for [id]; falls back to provider logos for 'provider'.
  static String? fromModel(String id, AiProvider provider) {
    final lower = id.toLowerCase();
    for (final (pattern, brand) in _rules) {
      if (RegExp(pattern).hasMatch(lower)) return brand;
    }
    return null;
  }

  /// Provider brand (serving platform).
  static String forProvider(AiProvider p) => switch (p) {
    AiProvider.groq => 'groq',
    AiProvider.nvidia => 'nvidia',
    AiProvider.openrouter => 'openrouter',
  };
}
