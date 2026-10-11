import 'model_catalog.dart';

/// HARD RULE: the app must never call a paid model. `assertFree` runs before
/// every request (wired into the router's execution path); a model that
/// fails the check is blocked before any bytes leave the device.
///
/// Free-ness is decided per provider:
///  - OpenRouter: live `/models` pricing must be 0 for prompt + completion,
///    and router/meta ids (openrouter/auto etc.) are excluded.
///  - NVIDIA: curated chat allowlist ∩ live /models.
///  - Groq: chat models on the free plan (speech/guard/tts excluded).
abstract final class FreeGuard {
  /// Throws [FreeGuardFailure] if [spec] is not a free model.
  static void assertFree(ModelSpec spec) {
    if (!spec.isFree) {
      throw FreeGuardFailure(spec.id);
    }
  }

  /// Decides freeness from a ModelSpec's stored reason — the guard trusts
  /// only evidence recorded at catalog-build time, never the display name.
  static bool evaluate({
    required String id,
    required AiProvider provider,
    required bool pricingIsZero,
    required bool onNimAllowlist,
    required bool isChatCapable,
  }) {
    // Meta/router ids are never allowed — they could proxy to paid models.
    if (id == 'openrouter/auto' || id.startsWith('openrouter/')) {
      return false;
    }
    switch (provider) {
      case AiProvider.openrouter:
        return pricingIsZero || id.endsWith(':free');
      case AiProvider.nvidia:
        // NIM serves its whole chat catalog on free-tier credits — the old
        // curated allowlist hid most of it from the picker.
        return isChatCapable;
      case AiProvider.groq:
        return isChatCapable;
    }
  }

  /// Groq ids we treat as non-chat (speech/vision-audio/guard).
  static bool groqIsChat(String id) => !RegExp(
    r'(whisper|tts|playai|guard|distil-whisper)',
    caseSensitive: false,
  ).hasMatch(id);

  /// NVIDIA ids we treat as non-chat (embedding / rerank / safety / retrieval).
  static bool nimIsChat(String id) => !RegExp(
    r'(embed|rerank|guard|retriev|baai/bge|nv-embed|llama-3.2-nv)',
    caseSensitive: false,
  ).hasMatch(id);

  /// NVIDIA curated chat allowlist — intersected with live /models.
  static const nimAllowlist = {
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-405b-instruct',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-90b-vision-instruct',
    'deepseek-ai/deepseek-r1',
    'qwen/qwen3-235b-a22b',
    'meta/llama-4-scout-17b-16e-instruct',
    'meta/llama-4-maverick-17b-128e-instruct',
    'moonshotai/kimi-k2-instruct',
    'microsoft/phi-4',
  };
}

class FreeGuardFailure implements Exception {
  const FreeGuardFailure(this.modelId);
  final String modelId;
  @override
  String toString() => 'FreeGuard: "$modelId" is not a free model.';
}
