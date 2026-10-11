import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../model_picker/model_selection.dart';
import '../../core/ai/model_router.dart';

/// Resolved lineup: catalog models from the persisted id list that also have
/// a configured provider key (and are still alive where we probed /models).
final arenaLineupProvider = Provider<List<ModelSpec>>((ref) {
  final sel = ref.watch(modelSelectionProvider);
  final keys = ref.watch(configuredKeysProvider).value ?? const {};
  final alive = ref.watch(aliveModelsProvider).value;
  return [
    for (final id in sel.arenaLineup)
      ...kModelCatalog.where((m) =>
          m.id == id &&
          keys.containsKey(m.provider) &&
          (alive?[m.provider]?.contains(m.id) ?? true)),
  ];
});

/// Arena can run when on and ≥2 lineup ids are selected (keyed or not —
/// unkeyed judges become DNF cards, and Demo Mode turns an all-unkeyed
/// arena into the canned showcase outcome).
final arenaReadyProvider = Provider<bool>((ref) {
  final sel = ref.watch(modelSelectionProvider);
  return sel.arenaMode && sel.arenaLineup.length >= 2;
});

/// Default jury: one model per provider, best coverage of tiers.
List<String> defaultLineup() => [
      for (final p in AiProvider.values)
        if (kModelCatalog.where((m) => m.provider == p).isNotEmpty)
          kModelCatalog.firstWhere((m) => m.provider == p).id,
    ];
