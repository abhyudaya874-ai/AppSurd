import 'model_catalog.dart';

/// Explainable, single-file strength estimate for free models — no provider
/// returns one, so we compute it from the id: parsed parameter count +
/// reasoning/vision bonuses + long-context bonus − small-model penalties.
/// Normalized 0..1 across the available set.
abstract final class StrengthEstimator {
  /// Manual overrides for known models (0..1 raw before normalization).
  static const _overrides = {
    'deepseek-r1': 0.95,
    'qwen3-235b': 0.9,
    'gpt-oss-120b': 0.7,
    'llama-4-scout': 0.5,
    'llama-3.1-8b-instant': 0.12,
  };

  /// Raw (un-normalized) score for one model id.
  static double raw(String id, {bool reasoning = false, bool vision = false}) {
    for (final k in _overrides.keys) {
      if (id.contains(k)) return _overrides[k]!;
    }
    double s = 0.45; // unknown → middle default
    // Parameter count parsed from the id ("8b", "70b", "235b", "1.5b").
    final m = RegExp(r'(\d+(?:\.\d+)?)[bB](?:[_-]|$|[^a-z])').firstMatch(id);
    if (m != null) {
      final b = double.parse(m.group(1)!);
      s = (b <= 4
          ? 0.15
          : b <= 12
          ? 0.3
          : b <= 32
          ? 0.5
          : b <= 100
          ? 0.7
          : 0.85);
    }
    if (reasoning) s += 0.12;
    if (vision) s += 0.05;
    if (RegExp(r'(mini|small|flash|lite|instant|nano|micro)').hasMatch(id)) {
      s -= 0.15;
    }
    return s.clamp(0.0, 1.0);
  }

  /// Normalize raw scores to 0..1 across the set (min/max anchored).
  static Map<String, double> normalized(Iterable<ModelSpec> models) {
    final raws = {
      for (final m in models)
        m.id: raw(
          m.id,
          reasoning: m.supportsReasoning,
          vision: m.supportsVision,
        ),
    };
    if (raws.isEmpty) return const {};
    final lo = raws.values.reduce((a, b) => a < b ? a : b);
    final hi = raws.values.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    return {for (final e in raws.entries) e.key: (e.value - lo) / span};
  }
}
