/// Spacing scale — every gap, padding and margin in the app is a multiple of
/// [unit], so screens stay rhythmically consistent and free of magic numbers.
abstract final class AppSpacing {
  static const double unit = 16;

  static const double xxs = unit * 0.25; // 4
  static const double xs = unit * 0.5; // 8
  static const double sm = unit * 0.75; // 12
  static const double md = unit; // 16
  static const double lg = unit * 1.5; // 24
  static const double xl = unit * 2; // 32
  static const double xxl = unit * 3; // 48

  /// Widest content column — keeps lists readable on tablets / wide web.
  static const double contentMaxWidth = 720;
}
