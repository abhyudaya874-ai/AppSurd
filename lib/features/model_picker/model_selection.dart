import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';

/// Reasoning effort levels — mapped to `reasoning_effort` where supported.
enum ReasoningLevel { low, medium, high }

/// Immutable selection state for the pill: preset tier OR a custom model,
/// plus reasoning effort and speed preference. Persisted to Hive so the pill
/// survives restarts.
class ModelSelection {
  const ModelSelection({
    this.preset = Tier.balanced,
    this.customModelId,
    this.reasoning = ReasoningLevel.medium,
    this.speed = SpeedPref.normal,
  });

  final Tier preset;
  final String? customModelId;
  final ReasoningLevel reasoning;
  final SpeedPref speed;

  ModelSelection copyWith({
    Tier? preset,
    String? Function()? customModelId,
    ReasoningLevel? reasoning,
    SpeedPref? speed,
  }) {
    return ModelSelection(
      preset: preset ?? this.preset,
      customModelId:
          customModelId != null ? customModelId() : this.customModelId,
      reasoning: reasoning ?? this.reasoning,
      speed: speed ?? this.speed,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.index,
        'customModelId': customModelId,
        'reasoning': reasoning.index,
        'speed': speed.index,
      };

  factory ModelSelection.fromJson(Map<String, dynamic> json) => ModelSelection(
        preset: Tier.values[(json['preset'] as num?)?.toInt() ?? 1],
        customModelId: json['customModelId'] as String?,
        reasoning:
            ReasoningLevel.values[(json['reasoning'] as num?)?.toInt() ?? 1],
        speed: SpeedPref.values[(json['speed'] as num?)?.toInt() ?? 0],
      );
}

/// Riverpod source of truth for the pill's state.
final modelSelectionProvider =
    NotifierProvider<ModelSelectionNotifier, ModelSelection>(
        ModelSelectionNotifier.new);

/// Persists the selection into the `settings` Hive box on every change.
class ModelSelectionNotifier extends Notifier<ModelSelection> {
  static const _boxName = 'receipts_settings';
  static const _key = 'modelSelection';

  @override
  ModelSelection build() {
    _load();
    return const ModelSelection();
  }

  Future<Box> _box() => Hive.openBox(_boxName);

  Future<void> _load() async {
    final box = await _box();
    final raw = box.get(_key);
    if (raw is Map) {
      state = ModelSelection.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _persist() async {
    final box = await _box();
    await box.put(_key, state.toJson());
  }

  /// Preset changes clear any custom pick — the slider owns routing again.
  void setPreset(Tier tier) {
    state = state.copyWith(preset: tier, customModelId: () => null);
    _persist();
  }

  void setCustomModel(String? id) {
    state = state.copyWith(customModelId: () => id);
    _persist();
  }

  void setReasoning(ReasoningLevel level) {
    state = state.copyWith(reasoning: level);
    _persist();
  }

  void setSpeed(SpeedPref pref) {
    state = state.copyWith(speed: pref);
    _persist();
  }
}
