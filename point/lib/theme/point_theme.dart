import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'point_tokens.dart';

/// Typography roles (design README §4):
/// - display: Gabarito (headings, titles, numbers; 700-900)
/// - ui:      Hanken Grotesk (body/UI; 400-800)
/// - mono:    DM Mono (codes, countdowns, coordinates)
class PointType {
  static TextStyle display({
    double size = 22,
    FontWeight weight = FontWeight.w800,
    double letterSpacing = -0.025 * 22,
    Color? color,
  }) =>
      GoogleFonts.gabarito(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color,
        height: 1.05,
      );

  static TextStyle ui({
    double size = 13.5,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double height = 1.3,
  }) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle mono({
    double size = 12.5,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      GoogleFonts.dmMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Named scale shortcuts from the design.
  static TextStyle tabTitle(Color c) =>
      display(size: 30, weight: FontWeight.w800, letterSpacing: -0.025 * 30, color: c);
  static TextStyle sheetTitle(Color c) =>
      display(size: 22, weight: FontWeight.w800, letterSpacing: -0.025 * 22, color: c);
  static TextStyle cardHeading(Color c) =>
      display(size: 18, weight: FontWeight.w800, letterSpacing: -0.01 * 18, color: c);
  static TextStyle rowName(Color c) =>
      ui(size: 15.5, weight: FontWeight.w700, letterSpacing: -0.155, color: c);
  static TextStyle rowSub(Color c) => ui(size: 13, weight: FontWeight.w500, color: c);
  static TextStyle secLabel(Color c) => ui(
        size: 12.5,
        weight: FontWeight.w700,
        letterSpacing: 0.5,
        color: c,
      );
  static TextStyle eyebrow(Color c) => ui(
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1.54,
        color: c,
      );
  static TextStyle tabLabel(Color c) =>
      ui(size: 10.5, weight: FontWeight.w600, color: c);
}

class PointTheme {
  static ThemeData _build(PointColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      surface: c.surface,
      primary: c.accent,
    );
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      extensions: [c],
      textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
        bodyColor: c.text,
        displayColor: c.text,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bg2,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(PointRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      splashColor: c.accent.withValues(alpha: 0.08),
      highlightColor: c.accent.withValues(alpha: 0.04),
    );
  }

  static ThemeData dark() => _build(PointColors.dark, Brightness.dark);
  static ThemeData light() => _build(PointColors.light, Brightness.light);
}

/// Convenience accessor.
extension PointColorsX on BuildContext {
  PointColors get pc => Theme.of(this).extension<PointColors>() ?? PointColors.dark;
}
