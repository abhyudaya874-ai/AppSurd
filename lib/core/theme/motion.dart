import 'package:flutter/material.dart';

/// Motion tokens for the whole app. Durations and curves are named here once
/// so every animation feels related; widgets must never hardcode a Duration.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration hero = Duration(milliseconds: 520);

  /// Default entrance/exit ease.
  static const Curve standard = Curves.easeOutCubic;

  /// Big morphs and shared-element moves.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Gentle bounce for snap-backs (slider thumb, swipe dismissal).
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 26,
  );

  /// Returns [duration] normally, or zero when the OS asks us to reduce motion
  /// (accessibility setting). All animated widgets should route through this.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
