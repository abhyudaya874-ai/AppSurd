import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Named page transitions so every screen shares the same motion language:
/// shared-axis (slide+fade) for forward navigation, fade-through for tab-style
/// switches. Plain [PageRouteBuilder] — no routing package.
abstract final class AppTransitions {
  /// Forward navigation: incoming page slides up slightly while fading in,
  /// outgoing fades — the Material "shared axis" feel.
  static PageRouteBuilder<T> sharedAxis<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: AppMotion.base,
      reverseTransitionDuration: AppMotion.base,
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.standard);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Tab-style switch: a clean cross-fade with no spatial motion.
  static PageRouteBuilder<T> fadeThrough<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: AppMotion.base,
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
}
