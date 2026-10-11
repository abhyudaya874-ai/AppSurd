import 'package:flutter/material.dart';

/// Typography for Receipts: Inter for UI/body text, Fraunces (serif) as the
/// display face for big headlines, Space Grotesk for mid-level headings and
/// the roast card. All three are bundled — no runtime fetching.
abstract final class AppTypography {
  static const _fallbacks = ['Inter'];

  /// Serif display — the Perplexity-style headline face.
  static TextStyle display(Color ink, {double size = 36}) => TextStyle(
    fontFamily: 'Fraunces',
    fontFamilyFallback: _fallbacks,
    fontSize: size,
    fontWeight: FontWeight.w600,
    height: 1.08,
    letterSpacing: -0.5,
    color: ink,
  );

  /// Space Grotesk for section titles and in-character moments.
  static TextStyle grotesk(Color ink) => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontFamilyFallback: _fallbacks,
    color: ink,
  );

  static TextStyle inter(Color ink) => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: _fallbacks,
    color: ink,
  );

  /// Builds the full [TextTheme] for a brightness.
  static TextTheme textTheme(Brightness brightness) {
    final Color ink = brightness == Brightness.dark
        ? const Color(0xFFECEEF0)
        : const Color(0xFF14181F);
    final body = inter(ink);
    final display = grotesk(ink);

    return TextTheme(
      // Serif takes the biggest slots — Perplexity-style headlines.
      displayLarge: AppTypography.display(ink, size: 40),
      displayMedium: AppTypography.display(ink, size: 36),
      headlineLarge: display.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: display.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: display.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 15, fontWeight: FontWeight.w400),
      bodyMedium: body.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: body.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
      labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: body.copyWith(fontSize: 10, fontWeight: FontWeight.w500),
    );
  }

  /// The small teal section label that sits above headlines ("TASKS", "ASK").
  static TextStyle sectionLabel(Color teal) => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: _fallbacks,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.2,
    color: teal,
  );
}
