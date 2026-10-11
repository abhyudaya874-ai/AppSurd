import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import 'model_selection.dart';

/// What the pill should display right now: the model the router would pick
/// for the current selection, or null when nothing can be routed (no keys).
final resolvedModelProvider = Provider<ModelSpec?>((ref) {
  final selection = ref.watch(modelSelectionProvider);
  final keys = ref.watch(configuredKeysProvider).value ?? const {};
  final alive = ref.watch(aliveModelsProvider).value ?? const {};
  final plan = const ModelRouter().plan(
    tier: selection.preset,
    keys: keys,
    aliveIds: alive,
    speed: selection.speed,
    customModelId: selection.customModelId,
  );
  return plan.candidates.isEmpty ? null : plan.primary;
});

/// Provider → ARGB tint (kept in sync with `ProviderTints`).
int providerTintValue(AiProvider p) => switch (p) {
      AiProvider.groq => 0xFFF97316,
      AiProvider.nvidia => 0xFF76B900,
      AiProvider.openrouter => 0xFF8B5CF6,
    };

/// Pretty fallback ramp when a tier has no routable model (no key configured).
const _fallbackTints = [0xFFF97316, 0xFF4FD8E0, 0xFF76B900, 0xFF8B5CF6];

int _tierTint(
  Tier tier,
  Map<AiProvider, String> keys,
  Map<AiProvider, Set<String>?> alive,
) {
  final primary = const ModelRouter()
      .plan(tier: tier, keys: keys, aliveIds: alive)
      .candidates
      .firstOrNull;
  return primary == null
      ? _fallbackTints[tier.index]
      : providerTintValue(primary.provider);
}

/// Provider tint for each tier — colors the slider gradient and detent dots,
/// so the fill visibly shifts hue as you drag from Swift to Deep.
final tierTintsProvider = Provider<List<int>>((ref) {
  final keys = ref.watch(configuredKeysProvider).value ?? const {};
  final alive = ref.watch(aliveModelsProvider).value ?? const {};
  return [for (final t in Tier.values) _tierTint(t, keys, alive)];
});
