import 'package:flutter/material.dart';

class PointColors {
  // Brand
  static const accent = Color(0xFF3F51FF);
  static const accentGlow = Color(0x4D3F51FF); // 30% opacity

  // Status
  static const online = Color(0xFF00E676);
  static const onlineGlow = Color(0x8000E676);
  static const danger = Color(0xFFFF3B30);

  // People colors — each person gets one
  static const List<Color> personColors = [
    Color(0xFF3F51FF), // blue
    Color(0xFFFF2D78), // pink
    Color(0xFFFF8C00), // orange
    Color(0xFF00BCD4), // cyan
    Color(0xFF00C853), // green
    Color(0xFF6C5CE7), // purple
    Color(0xFFFFAB00), // yellow
    Color(0xFFFF5722), // deep orange
  ];

  // Bridge colors
  static const findMy = Color(0xFFFF3B30);
  static const google = Color(0xFF4285F4);
  static const life360 = Color(0xFF6C5CE7);

  // Surfaces
  static const background = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF4F4F4);
  static const divider = Color(0x08000000);

  // Text
  static const textPrimary = Color(0xFF000000);
  static const textSecondary = Color(0x40000000); // 25%
  static const textTertiary = Color(0x1A000000); // 10%

  // Dark mode surfaces
  static const darkBackground = Color(0xFF0F0F14);
  static const darkSurface = Color(0xFF1A1A22);
  static const darkSurfaceAlt = Color(0xFF252530);
  static const darkDivider = Color(0x15FFFFFF);
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0x66FFFFFF);
  static const darkTextTertiary = Color(0x33FFFFFF);

  static Color colorForUser(String userId) {
    return personColors[userId.hashCode.abs() % personColors.length];
  }
}

class PointTheme {
  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: PointColors.accent,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: PointColors.background,
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: PointColors.accent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: PointColors.darkBackground,
      cardColor: PointColors.darkSurface,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PointColors.darkSurface,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: PointColors.darkSurface,
      ),
      useMaterial3: true,
    );
  }
}

/// Theme-aware color helpers — use these instead of hardcoded colors.
extension PointThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get pageBg => Theme.of(this).scaffoldBackgroundColor;
  Color get cardBg => isDark ? PointColors.darkSurface : Colors.white;
  Color get primaryText => isDark ? Colors.white : Colors.black;
  Color get secondaryText =>
      isDark ? PointColors.darkTextSecondary : PointColors.textSecondary;
  Color get tertiaryText =>
      isDark ? PointColors.darkTextTertiary : PointColors.textTertiary;
  Color get subtleBg =>
      isDark ? PointColors.darkSurfaceAlt : const Color(0xFFF5F5F5);
  Color get dividerClr =>
      isDark ? PointColors.darkDivider : PointColors.divider;
  Color get inputBorder =>
      isDark ? const Color(0xFF2A2A35) : const Color(0xFFE5E5E5);
  Color get hintText =>
      isDark ? const Color(0xFF666680) : const Color(0xFFBBBBBB);
  Color get midGrey =>
      isDark ? const Color(0xFF888899) : const Color(0xFF999999);

  /// Shadow color — returns transparent in dark mode since shadows are invisible on dark bg.
  Color get shadowClr =>
      isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04);
}
