import 'package:flutter/material.dart';

/// Central color palette for Receipts.
///
/// Dark-first design: deep neutral surfaces, one vivid cyan accent, and a
/// small set of semantic status colors (pass / warn / fail). Per-provider
/// tints live separately in [ProviderTints] so brand colors never leak into
/// the core scheme.
abstract final class AppColors {
  // ---- Dark scheme ----
  static const darkBg = Color(0xFF0C0E12);
  static const darkSurface = Color(0xFF14171C);
  static const darkSurfaceHigh = Color(0xFF1B1F27);
  static const darkBorder = Color(0xFF262C36);
  static const darkInk = Color(0xFFF2F4F7);
  static const darkInkMuted = Color(0xFF9AA4B2);

  // ---- Light scheme ----
  static const lightBg = Color(0xFFF5F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFEDF0F4);
  static const lightBorder = Color(0xFFDDE2E9);
  static const lightInk = Color(0xFF14181F);
  static const lightInkMuted = Color(0xFF5A6472);

  // ---- Shared ----
  /// The single vivid accent — electric cyan. Deliberately distinct from all
  /// three provider tints (orange / green / violet) so routing colors never
  /// collide with app chrome.
  static const accent = Color(0xFF4FD8E0);
  static const accentDeep = Color(0xFF0E9AA7); // accent variant for light mode

  // Status colors — verdict semantics, shared by both schemes.
  static const pass = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const fail = Color(0xFFFF6B6B);
}
