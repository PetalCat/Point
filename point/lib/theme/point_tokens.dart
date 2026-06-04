import 'package:flutter/material.dart';

/// Design tokens for the Point redesign (2026-06 handoff).
/// Default theme is dark + indigo accent. See the design README §4.
///
/// Read colors via `Theme.of(context).extension<PointColors>()!` — never
/// hardcode hex in widgets.
@immutable
class PointColors extends ThemeExtension<PointColors> {
  // Accent (electric indigo) + brand gradient stops.
  final Color accent; // #4d54f7
  final Color accent2; // #28c8e8 cyan (gradient mid)
  final Color accent3; // #a98bff violet (gradient end)
  final Color accentInk; // text/icon on accent

  // Surfaces (dark default).
  final Color bg; // phone canvas
  final Color bg2; // sheet background
  final Color surface; // cards
  final Color surface2; // inset rows / secondary buttons
  final Color surface3; // tertiary fills / off-switch track
  final Color hairline;
  final Color hairline2;

  // Text.
  final Color text;
  final Color textMuted;
  final Color textDim;

  // Status / semantic.
  final Color live; // green
  final Color idle; // amber
  final Color stale; // grey
  final Color danger;
  final Color tempShare; // orange

  const PointColors({
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.accentInk,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.hairline,
    required this.hairline2,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.live,
    required this.idle,
    required this.stale,
    required this.danger,
    required this.tempShare,
  });

  /// The 102° brand gradient used for the wordmark, progress fills, and accents.
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accent2, accent3],
        transform: const GradientRotation(102 * 3.1415926535 / 180),
      );

  /// Per-person marker colors (assigned per user).
  static const personColors = <Color>[
    Color(0xFF34D399), Color(0xFFFB923C), Color(0xFFF472B6), Color(0xFF22D3EE),
    Color(0xFFA78BFA), Color(0xFFFACC15), Color(0xFF38BDF8), Color(0xFFC084FC),
    Color(0xFFF59E0B), Color(0xFF2DD4BF), Color(0xFFFB7185), Color(0xFF60A5FA),
  ];

  static Color colorForUser(String userId) =>
      personColors[userId.hashCode.abs() % personColors.length];

  /// Battery color by charge level (0-100).
  Color batteryColor(int pct) {
    if (pct <= 15) return const Color(0xFFFF6A5A);
    if (pct <= 35) return idle;
    return live;
  }

  static const dark = PointColors(
    accent: Color(0xFF4D54F7),
    accent2: Color(0xFF28C8E8),
    accent3: Color(0xFFA98BFF),
    accentInk: Color(0xFFFFFFFF),
    bg: Color(0xFF000000),
    bg2: Color(0xFF07080D),
    surface: Color(0xFF0D0E15),
    surface2: Color(0xFF14161F),
    surface3: Color(0xFF1C1F2B),
    hairline: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    hairline2: Color(0x21FFFFFF), // rgba(255,255,255,0.13)
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF9A9DAC),
    textDim: Color(0xFF61646F),
    live: Color(0xFF27C66B),
    idle: Color(0xFFF5B53D),
    stale: Color(0xFF6B6F7D),
    danger: Color(0xFFFF5A5F),
    tempShare: Color(0xFFFB923C),
  );

  static const light = PointColors(
    accent: Color(0xFF4D54F7),
    accent2: Color(0xFF28C8E8),
    accent3: Color(0xFFA98BFF),
    accentInk: Color(0xFFFFFFFF),
    bg: Color(0xFFEEF1F6),
    bg2: Color(0xFFE6EAF1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF4F6FA),
    surface3: Color(0xFFE9EDF4),
    hairline: Color(0x170D1020), // rgba(13,16,32,0.09)
    hairline2: Color(0x240D1020), // rgba(13,16,32,0.14)
    text: Color(0xFF0C1020),
    textMuted: Color(0xFF5D626F),
    textDim: Color(0xFF9AA0AD),
    live: Color(0xFF27C66B),
    idle: Color(0xFFF5B53D),
    stale: Color(0xFF6B6F7D),
    danger: Color(0xFFFF5A5F),
    tempShare: Color(0xFFFB923C),
  );

  @override
  PointColors copyWith({
    Color? accent,
    Color? accent2,
    Color? accent3,
    Color? accentInk,
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? hairline,
    Color? hairline2,
    Color? text,
    Color? textMuted,
    Color? textDim,
    Color? live,
    Color? idle,
    Color? stale,
    Color? danger,
    Color? tempShare,
  }) {
    return PointColors(
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accent3: accent3 ?? this.accent3,
      accentInk: accentInk ?? this.accentInk,
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      hairline: hairline ?? this.hairline,
      hairline2: hairline2 ?? this.hairline2,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textDim: textDim ?? this.textDim,
      live: live ?? this.live,
      idle: idle ?? this.idle,
      stale: stale ?? this.stale,
      danger: danger ?? this.danger,
      tempShare: tempShare ?? this.tempShare,
    );
  }

  @override
  PointColors lerp(PointColors? other, double t) {
    if (other == null) return this;
    return PointColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accent3: Color.lerp(accent3, other.accent3, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairline2: Color.lerp(hairline2, other.hairline2, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      live: Color.lerp(live, other.live, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
      stale: Color.lerp(stale, other.stale, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      tempShare: Color.lerp(tempShare, other.tempShare, t)!,
    );
  }
}

/// Bridge brand colors for badges/chips/icons (design README §4).
class BridgeColors {
  static const point = Color(0xFF4D54F7);
  static const findmy = Color(0xFF32C759);
  static const gmaps = Color(0xFF1A73E8);
  static const life360 = Color(0xFF7C3AED);
  static const tile = Color(0xFF12A594);
  static const samsung = Color(0xFF1A4FD6); // SmartTag
  static const traccar = Color(0xFF2563EB);
  static const owntracks = Color(0xFF0F766E);

  static Color forId(String id) {
    switch (id) {
      case 'point':
        return point;
      case 'findmy':
        return findmy;
      case 'gmaps':
      case 'google':
        return gmaps;
      case 'life360':
        return life360;
      case 'tile':
        return tile;
      case 'samsung':
        return samsung;
      case 'traccar':
        return traccar;
      case 'owntracks':
        return owntracks;
      default:
        return point;
    }
  }
}

/// Radii / spacing tokens (regular density).
class PointRadius {
  static const card = 22.0;
  static const sm = 14.0; // buttons/inputs
  static const lg = 30.0; // sheets
  static const pill = 999.0;
}

class PointSpacing {
  static const pad = 18.0;
  static const rowPad = 15.0;
  static const gap = 12.0;
}
