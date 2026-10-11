import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for Receipts: Inter for UI/body text, Space Grotesk as the
/// characterful display face (headings, verdicts, roast card).
abstract final class AppTypography {
  /// Builds the full [TextTheme] for a brightness, using Google Fonts.
  static TextTheme textTheme(Brightness brightness) {
    final Color ink = brightness == Brightness.dark
        ? const Color(0xFFF2F4F7)
        : const Color(0xFF14181F);
    final body = GoogleFonts.inter(color: ink);
    final display = GoogleFonts.spaceGrotesk(color: ink);

    return TextTheme(
      displayLarge: display.copyWith(fontSize: 40, fontWeight: FontWeight.w700),
      displayMedium: display.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
      headlineLarge: display.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
      headlineMedium: display.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      titleLarge: display.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: body.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: body.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge: body.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: body.copyWith(fontSize: 10, fontWeight: FontWeight.w500),
    );
  }
}
