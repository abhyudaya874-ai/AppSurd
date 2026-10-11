/// The model catalog is config, not code: every selectable model is one const
/// entry here. IDs are verified against each provider's `GET /models` at
/// runtime — catalog entries that no longer exist are dropped automatically,
/// so a stale ID never becomes a broken call.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import 'api_key_store.dart';
import 'brand_resolver.dart';
import 'free_guard.dart';
import 'strength_estimator.dart';

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
    this.isFree = true, // seed catalog is curated free-tier
    this.freeReason = 'curated free tier',
    this.brand,
    this.contextK = 0,
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

  /// Computed at catalog-build time — FreeGuard trusts this, not the name.
  final bool isFree;

  /// Why we think it's free ("OpenRouter pricing = 0", "NIM allowlist"…).
  final String freeReason;

  /// Model-maker brand key for the logo resolver ('meta','qwen'…).
  final String? brand;

  /// Advertised context window in K tokens (0 = unknown).
  final int contextK;
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

// ---------------------------------------------------------------------------
// Dynamic catalog (phase 2a): live /models ∩ free-only filtering, cached.
// Seed catalog remains as the offline/first-boot fallback.
// ---------------------------------------------------------------------------

/// Which surface a model list is for: `task` = curated seed list only
/// (composer, create-task, verification, arena jury), `ask` = every free
/// model the providers expose. Keeps Task pickers compact and Ask rich.
enum ModelScope { task, ask }

/// The dependable, curated pool used by the router for proof verification
/// and task surfaces — the seed catalog (alive-filtered when probed).
/// Wrapped in AsyncData so scoped pickers can treat both providers as
/// `AsyncValue<List<ModelSpec>>` and share one `.when` path.
final curatedCatalogProvider = Provider<AsyncValue<List<ModelSpec>>>(
  (ref) => const AsyncData(kModelCatalog),
);

/// Result of building the catalog — the list plus which models are free.
final liveCatalogProvider =
    AsyncNotifierProvider<CatalogNotifier, List<ModelSpec>>(
      CatalogNotifier.new,
    );

class CatalogNotifier extends AsyncNotifier<List<ModelSpec>> {
  static const _box = 'receipts_settings';
  static const _key = 'live_models_v1';

  @override
  Future<List<ModelSpec>> build() => load();

  /// Pull each configured provider's /models, keep only free chat models,
  /// cache the raw payload for offline rebuilds.
  Future<List<ModelSpec>> load() async {
    final keys = await ref.read(configuredKeysProvider.future);
    final all = <ModelSpec>[];
    final cached = <String, dynamic>{};
    for (final provider in AiProvider.values) {
      final key = keys[provider];
      final hasKey = key != null && key.isNotEmpty;
      // OpenRouter's /models is public — fetch it with no key. NIM also
      // answers keyless (rate-limited); try it and fall back to the user's
      // key. Groq needs a key — without one its seed models show locked.
      final keylessOk =
          provider == AiProvider.openrouter || provider == AiProvider.nvidia;
      if (!hasKey && !keylessOk) {
        all.addAll(kModelCatalog.where((m) => m.provider == provider));
        continue;
      }
      try {
        final dio = Dio(
          BaseOptions(
            baseUrl: provider.baseUrl,
            headers: {
              if (hasKey) 'Authorization': 'Bearer $key',
              ...provider.extraHeaders,
            },
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        final res = await dio.get<Map<String, dynamic>>('/models');
        cached[provider.id] = res.data;
        all.addAll(_parse(provider, res.data ?? const {}));
      } on DioException {
        // Offline/error → cached payload, else the seed catalog slice.
        final box = await Hive.openBox(_box);
        final raw = box.get('$_key.${provider.id}');
        if (raw is Map) {
          all.addAll(_parse(provider, Map<String, dynamic>.from(raw)));
        } else {
          all.addAll(kModelCatalog.where((m) => m.provider == provider));
        }
      }
    }
    if (cached.isNotEmpty) {
      final box = await Hive.openBox(_box);
      for (final e in cached.entries) {
        await box.put('$_key.${e.key}', e.value);
      }
    }
    if (all.isEmpty) return List.of(kModelCatalog);
    // Live + seed lists can overlap — dedupe by id, first wins.
    final seen = <String>{};
    return _withStrength([
      for (final m in all)
        if (seen.add(m.id)) m,
    ]);
  }

  /// Builds ModelSpecs from a provider's /models payload — free-only.
  List<ModelSpec> _parse(AiProvider provider, Map<String, dynamic> data) {
    final out = <ModelSpec>[];
    final list = data['data'];
    if (list is! List) return out;
    for (final raw in list) {
      if (raw is! Map) continue;
      final id = raw['id'] as String? ?? '';
      if (id.isEmpty) continue;

      final pricing = raw['pricing'] as Map?;
      final promptZero = (pricing?['prompt'] as num?)?.toDouble() == 0;
      final completionZero = (pricing?['completion'] as num?)?.toDouble() == 0;
      final arch = raw['architecture'] as Map?;
      final modalities = (arch?['input_modalities'] as List? ?? const [])
          .cast<String>();
      final supported = (raw['supported_parameters'] as List? ?? const [])
          .cast<String>();
      final context = (raw['context_length'] as num?)?.toInt() ?? 0;

      final vision =
          modalities.contains('image') ||
          RegExp(r'vision|\bvl\b|llava|scout|maverick|gemma-3|llama-4')
              .hasMatch(id);
      final reasoning =
          supported.contains('reasoning') ||
          RegExp(r'r1|gpt-oss|qwq|thinking').hasMatch(id);

      final isChat = switch (provider) {
        AiProvider.groq => FreeGuard.groqIsChat(id),
        AiProvider.nvidia => FreeGuard.nimIsChat(id),
        _ => true,
      };
      final isFree = FreeGuard.evaluate(
        id: id,
        provider: provider,
        pricingIsZero: promptZero && completionZero,
        onNimAllowlist: FreeGuard.nimAllowlist.contains(id),
        isChatCapable: isChat,
      );
      if (!isFree) continue;

      out.add(
        ModelSpec(
          id: id,
          provider: provider,
          displayName: _prettyName(id, raw),
          tier: Tier.swift, // reassigned from quartiles below
          strength: 0,
          supportsVision: vision,
          supportsReasoning: reasoning,
          isFree: true,
          freeReason: switch (provider) {
            AiProvider.openrouter => 'OpenRouter pricing = 0',
            AiProvider.nvidia => 'NIM free catalog allowlist',
            AiProvider.groq => 'Groq free plan',
          },
          brand: BrandResolver.fromModel(id, provider),
          contextK: context ~/ 1000,
          blurb: _blurb(vision, reasoning, context),
        ),
      );
    }
    return out;
  }

  /// Strength-normalize across the set, then bucket into quartile tiers.
  static List<ModelSpec> _withStrength(List<ModelSpec> models) {
    final strength = StrengthEstimator.normalized(models);
    final sorted = models.toList()
      ..sort((a, b) => (strength[a.id] ?? 0).compareTo(strength[b.id] ?? 0));
    final n = sorted.length;
    return [
      for (var i = 0; i < n; i++)
        ModelSpec(
          id: sorted[i].id,
          provider: sorted[i].provider,
          displayName: sorted[i].displayName,
          tier: Tier.values[(i * 4 ~/ n).clamp(0, 3)],
          strength: strength[sorted[i].id] ?? 0,
          supportsVision: sorted[i].supportsVision,
          supportsReasoning: sorted[i].supportsReasoning,
          isFree: true,
          freeReason: sorted[i].freeReason,
          brand: sorted[i].brand,
          contextK: sorted[i].contextK,
          blurb: sorted[i].blurb,
        ),
    ];
  }

  static String _prettyName(String id, Map raw) {
    final name = raw['name'] as String?;
    if (name != null && name.length > 2 && name.length < 60) {
      return name;
    }
    final base = id.split('/').last.split(':').first;
    return base
        .replaceAll(RegExp(r'[-_]'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String _blurb(bool vision, bool reasoning, int ctx) => [
    if (reasoning) 'reasoning',
    if (vision) 'vision',
    if (ctx >= 128000) 'long context',
    if (!reasoning && !vision && ctx < 128000) 'chat',
  ].join(' · ');
}
