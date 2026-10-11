/// The model catalog is config, not code: every selectable model is one const
/// entry here. IDs are verified against each provider's `GET /models` at
/// runtime — catalog entries that no longer exist are dropped automatically,
/// so a stale ID never becomes a broken call.
library;

/// AI providers — all OpenAI-compatible.
enum AiProvider {
  groq('groq', 'Groq', 'https://api.groq.com/openai/v1'),
  nvidia('nvidia', 'NVIDIA', 'https://integrate.api.nvidia.com/v1'),
  openrouter('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1');

  const AiProvider(this.id, this.label, this.baseUrl);

  /// Stable id used in keys, logs, and ProviderTints.forId.
  final String id;
  final String label;
  final String baseUrl;

  /// Extra headers a provider wants (OpenRouter asks for referer + title).
  Map<String, String> get extraHeaders => switch (this) {
        AiProvider.openrouter => {
            'HTTP-Referer': 'https://receipts.app',
            'X-Title': 'Receipts',
          },
        _ => const {},
      };
}

/// Slider presets — coarse "how much brain do I need" choices that map onto
/// whatever real models are currently alive per provider.
enum Tier {
  swift('Swift', 'fastest, cheapest — quick checks'),
  balanced('Balanced', 'everyday verification'),
  smart('Smart', 'harder judgement, better reasoning'),
  deep('Deep', 'reasoning models, slowest but most careful');

  const Tier(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// One selectable model.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.tier,
    required this.strength,
    this.supportsVision = false,
    this.supportsReasoning = false,
    required this.blurb,
  });

  /// Provider-side model id sent in the API request.
  final String id;
  final AiProvider provider;
  final String displayName;
  final Tier tier;

  /// 0..1 — used to order options inside a tier and color the slider.
  final double strength;
  final bool supportsVision;
  final bool supportsReasoning;

  /// One-line "what this is for" shown under the pill when expanded.
  final String blurb;
}

/// Seed catalog. Prefer low-cost/free models — the demo runs on real keys.
const List<ModelSpec> kModelCatalog = [
  // ---- Swift: smallest fast models, Groq preferred for latency ----
  ModelSpec(
    id: 'llama-3.1-8b-instant',
    provider: AiProvider.groq,
    displayName: 'Llama 8B Instant',
    tier: Tier.swift,
    strength: 0.10,
    blurb: 'fastest sanity checks, near-zero latency',
  ),
  ModelSpec(
    id: 'meta/llama-3.1-8b-instruct',
    provider: AiProvider.nvidia,
    displayName: 'Llama 8B',
    tier: Tier.swift,
    strength: 0.08,
    blurb: 'lightweight checks on NIM',
  ),
  ModelSpec(
    id: 'meta-llama/llama-3.1-8b-instruct',
    provider: AiProvider.openrouter,
    displayName: 'Llama 8B (OR)',
    tier: Tier.swift,
    strength: 0.07,
    blurb: 'budget quick checks via OpenRouter',
  ),

  // ---- Balanced: ~70B general-purpose ----
  ModelSpec(
    id: 'llama-3.3-70b-versatile',
    provider: AiProvider.groq,
    displayName: 'Llama 70B',
    tier: Tier.balanced,
    strength: 0.40,
    blurb: 'for balanced everyday tasks',
  ),
  ModelSpec(
    id: 'meta/llama-3.3-70b-instruct',
    provider: AiProvider.nvidia,
    displayName: 'Llama 70B (NIM)',
    tier: Tier.balanced,
    strength: 0.42,
    blurb: 'the same 70B class, routed via NIM',
  ),
  ModelSpec(
    id: 'meta-llama/llama-3.3-70b-instruct',
    provider: AiProvider.openrouter,
    displayName: 'Llama 70B (OR)',
    tier: Tier.balanced,
    strength: 0.38,
    blurb: '70B via OpenRouter as a fallback lane',
  ),

  // ---- Vision-capable (evidence screenshots) ----
  ModelSpec(
    id: 'meta-llama/llama-4-scout-17b-16e-instruct',
    provider: AiProvider.groq,
    displayName: 'Llama 4 Scout',
    tier: Tier.balanced,
    strength: 0.45,
    supportsVision: true,
    blurb: 'reads screenshots — image evidence',
  ),
  ModelSpec(
    id: 'meta/llama-3.2-90b-vision-instruct',
    provider: AiProvider.nvidia,
    displayName: 'Llama 90B Vision',
    tier: Tier.smart,
    strength: 0.62,
    supportsVision: true,
    blurb: 'bigger eyes for dense screenshots',
  ),
  ModelSpec(
    id: 'qwen/qwen2.5-vl-72b-instruct',
    provider: AiProvider.openrouter,
    displayName: 'Qwen 2.5 VL',
    tier: Tier.smart,
    strength: 0.60,
    supportsVision: true,
    blurb: 'strong vision model via OpenRouter',
  ),

  // ---- Smart: strongest non-reasoning ----
  ModelSpec(
    id: 'openai/gpt-oss-120b',
    provider: AiProvider.groq,
    displayName: 'GPT-OSS 120B',
    tier: Tier.smart,
    strength: 0.66,
    supportsReasoning: true,
    blurb: 'big open model, still Groq-fast',
  ),
  ModelSpec(
    id: 'meta/llama-3.1-405b-instruct',
    provider: AiProvider.nvidia,
    displayName: 'Llama 405B',
    tier: Tier.smart,
    strength: 0.70,
    blurb: 'the heavyweight for careful calls',
  ),

  // ---- Deep: reasoning-first models ----
  ModelSpec(
    id: 'deepseek-ai/deepseek-r1',
    provider: AiProvider.nvidia,
    displayName: 'DeepSeek R1',
    tier: Tier.deep,
    strength: 0.90,
    supportsReasoning: true,
    blurb: 'thinks before it judges',
  ),
  ModelSpec(
    id: 'deepseek/deepseek-r1',
    provider: AiProvider.openrouter,
    displayName: 'DeepSeek R1 (OR)',
    tier: Tier.deep,
    strength: 0.88,
    supportsReasoning: true,
    blurb: 'reasoning via OpenRouter',
  ),
  ModelSpec(
    id: 'qwen/qwen3-235b-a22b',
    provider: AiProvider.nvidia,
    displayName: 'Qwen3 235B',
    tier: Tier.deep,
    strength: 0.85,
    supportsReasoning: true,
    blurb: 'mixture-of-experts deep check',
  ),
];
