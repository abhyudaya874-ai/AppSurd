import 'package:flutter/material.dart';

/// ThemeExtension exposing a [MotionTokens]-style handle on motion constants
/// through `Theme.of`, matching the rule that tokens live in the theme layer.
/// The underlying values come from `AppMotion`; this exists so widgets can
/// also read them via theme lookup.
@immutable
class MotionTokens extends ThemeExtension<MotionTokens> {
  const MotionTokens({
    this.fast = const Duration(milliseconds: 150),
    this.base = const Duration(milliseconds: 260),
    this.slow = const Duration(milliseconds: 420),
    this.hero = const Duration(milliseconds: 520),
  });

  final Duration fast;
  final Duration base;
  final Duration slow;
  final Duration hero;

  @override
  MotionTokens copyWith({
    Duration? fast,
    Duration? base,
    Duration? slow,
    Duration? hero,
  }) {
    return MotionTokens(
      fast: fast ?? this.fast,
      base: base ?? this.base,
      slow: slow ?? this.slow,
      hero: hero ?? this.hero,
    );
  }

  /// Durations are discrete — snap at the midpoint instead of interpolating.
  @override
  MotionTokens lerp(MotionTokens? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Per-provider brand tints, used sparingly: pill glyph, source chips, and
/// the strength-slider gradient. Never used as general app chrome colors.
@immutable
class ProviderTints extends ThemeExtension<ProviderTints> {
  const ProviderTints({
    this.groq = const Color(0xFFF97316), // Groq orange
    this.nvidia = const Color(0xFF76B900), // NVIDIA green
    this.openrouter = const Color(0xFF8B5CF6), // OpenRouter violet
  });

  final Color groq;
  final Color nvidia;
  final Color openrouter;

  /// Tint for a provider id string ('groq' | 'nvidia' | 'openrouter').
  Color forId(String providerId) => switch (providerId) {
    'groq' => groq,
    'nvidia' => nvidia,
    'openrouter' => openrouter,
    _ => groq,
  };

  @override
  ProviderTints copyWith({Color? groq, Color? nvidia, Color? openrouter}) {
    return ProviderTints(
      groq: groq ?? this.groq,
      nvidia: nvidia ?? this.nvidia,
      openrouter: openrouter ?? this.openrouter,
    );
  }

  @override
  ProviderTints lerp(ProviderTints? other, double t) {
    if (other == null) return this;
    return ProviderTints(
      groq: Color.lerp(groq, other.groq, t)!,
      nvidia: Color.lerp(nvidia, other.nvidia, t)!,
      openrouter: Color.lerp(openrouter, other.openrouter, t)!,
    );
  }
}
