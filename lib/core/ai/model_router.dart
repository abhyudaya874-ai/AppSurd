import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_failure.dart';
import 'api_key_store.dart';
import 'model_catalog.dart';
import 'openai_compat_client.dart';

/// How strongly the router should bias toward low latency.
enum SpeedPref { normal, fast }

/// The plan the router produces: an ordered candidate list plus flags the UI
/// surfaces as small chips ("switched for vision", "rerouted via X").
class RoutePlan {
  const RoutePlan({
    required this.candidates,
    this.visionSwappedTo,
  });

  /// Ordered models to try — index 0 is the primary pick.
  final List<ModelSpec> candidates;

  /// Set when image evidence forced a swap to a vision-capable model.
  final ModelSpec? visionSwappedTo;

  ModelSpec get primary => candidates.first;
}

/// Result of executing a plan: which model actually answered and whether the
/// call had to fall back off the primary provider.
class RouteOutcome<T> {
  const RouteOutcome({required this.used, required this.value, this.reroutedFrom});

  final ModelSpec used;
  final T value;

  /// Non-null when the primary candidate failed and a fallback answered.
  final AiProvider? reroutedFrom;
}

/// Stateless picker: turns (tier, keys, alive ids, evidence flags) into an
/// ordered candidate list. Kept pure so it stays explainable in Q&A.
class ModelRouter {
  const ModelRouter();

  /// Catalog entries whose provider reported them alive via GET /models.
  /// A provider whose fetch failed is left unfiltered — a transient error
  /// shouldn't remove models that are probably fine.
  List<ModelSpec> _alive(Map<AiProvider, Set<String>?> aliveIds) {
    return kModelCatalog.where((m) {
      final alive = aliveIds[m.provider];
      return alive == null || alive.contains(m.id);
    }).toList();
  }

  /// Ordered candidates for [tier], best first. Only providers with a
  /// configured key are considered. [SpeedPref.fast] biases Groq first.
  List<ModelSpec> _tierCandidates(
    Tier tier,
    Map<AiProvider, String> keys,
    Map<AiProvider, Set<String>?> aliveIds,
    SpeedPref speed,
  ) {
    final pool = _alive(aliveIds)
        .where((m) => m.tier == tier && keys.containsKey(m.provider))
        .toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    if (speed == SpeedPref.fast) {
      pool.sort((a, b) {
        if (a.provider == b.provider) return 0;
        return a.provider == AiProvider.groq ? -1 : 1;
      });
    }
    return pool;
  }

  /// Builds the candidate list: primary pick in [tier], then the rest of that
  /// tier, then each lower tier, then higher tiers as a last resort.
  RoutePlan plan({
    required Tier tier,
    required Map<AiProvider, String> keys,
    Map<AiProvider, Set<String>?> aliveIds = const {},
    bool needsVision = false,
    SpeedPref speed = SpeedPref.normal,
    String? customModelId,
  }) {
    final alive = _alive(aliveIds);
    final candidates = <ModelSpec>[];

    if (customModelId != null) {
      final custom = alive.where((m) => m.id == customModelId).firstOrNull;
      if (custom != null && keys.containsKey(custom.provider)) {
        candidates.add(custom);
        candidates.addAll(
          _tierCandidates(custom.tier, keys, aliveIds, speed)
              .where((m) => m != custom),
        );
      }
    } else {
      candidates.addAll(_tierCandidates(tier, keys, aliveIds, speed));
    }

    // Lower tiers, then higher tiers — "drop a tier" on failure.
    final tiers = Tier.values;
    final start = candidates.isNotEmpty ? candidates.first.tier.index : tier.index;
    for (var i = start - 1; i >= 0; i--) {
      candidates.addAll(_tierCandidates(tiers[i], keys, aliveIds, speed)
          .where((m) => !candidates.contains(m)));
    }
    for (var i = start + 1; i < tiers.length; i++) {
      candidates.addAll(_tierCandidates(tiers[i], keys, aliveIds, speed)
          .where((m) => !candidates.contains(m)));
    }

    // Vision swap: image evidence on a blind model jumps to the nearest
    // vision-capable candidate instead of failing.
    ModelSpec? visionSwap;
    if (needsVision && candidates.isNotEmpty && !candidates.first.supportsVision) {
      final idx = candidates.indexWhere((m) => m.supportsVision);
      if (idx >= 0) {
        visionSwap = candidates.removeAt(idx);
        candidates.insert(0, visionSwap);
      }
    }

    return RoutePlan(candidates: candidates, visionSwappedTo: visionSwap);
  }

  /// Runs [call] against candidates in order. On rate-limit/server/network
  /// failures it advances to the next candidate — the "rerouted via X" chip in
  /// the UI is built from [RouteOutcome.reroutedFrom].
  Future<RouteOutcome<T>> execute<T>(
    RoutePlan plan,
    Future<T> Function(OpenAiCompatClient client, ModelSpec model) call,
    Map<AiProvider, String> keys,
  ) async {
    if (plan.candidates.isEmpty) {
      throw const AuthFailure('No provider key configured for any model.');
    }
    AiFailure? lastError;
    for (var i = 0; i < plan.candidates.length; i++) {
      final spec = plan.candidates[i];
      final key = keys[spec.provider];
      if (key == null) continue;
      final client = OpenAiCompatClient(
        baseUrl: spec.provider.baseUrl,
        apiKey: key,
        extraHeaders: spec.provider.extraHeaders,
      );
      try {
        final value = await call(client, spec);
        debugPrint('[router] ${spec.provider.id}/${spec.id} answered');
        return RouteOutcome(
          used: spec,
          value: value,
          reroutedFrom: i == 0 ? null : plan.candidates.first.provider,
        );
      } on AiFailure catch (e) {
        debugPrint('[router] ${spec.id} failed (${e.runtimeType}), falling back');
        lastError = e;
        // Auth failures don't benefit from retrying a sibling provider with a
        // different key — but a 429/5xx/timeout does.
        if (e is AuthFailure) continue;
      }
    }
    throw lastError ?? const BadResponseFailure('All providers failed.');
  }
}

/// Riverpod glue: which catalog entries are confirmed alive per provider.
/// Fetched once per app run; Settings "Refresh models" invalidates it.
final aliveModelsProvider =
    FutureProvider<Map<AiProvider, Set<String>?>>((ref) async {
  final keys = await ref.watch(configuredKeysProvider.future);
  final out = <AiProvider, Set<String>?>{};
  for (final entry in keys.entries) {
    try {
      final client = OpenAiCompatClient(
        baseUrl: entry.key.baseUrl,
        apiKey: entry.value,
        extraHeaders: entry.key.extraHeaders,
      );
      out[entry.key] = await client.listModelIds();
    } on AiFailure {
      out[entry.key] = null; // unfiltered fallback
    }
  }
  return out;
});

final modelRouterProvider = Provider<ModelRouter>((ref) => const ModelRouter());
