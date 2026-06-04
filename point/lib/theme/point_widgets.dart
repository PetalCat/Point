import 'package:flutter/material.dart';

import 'point_theme.dart';
import 'point_tokens.dart';

/// Brand wordmark with the 102° gradient (ShaderMask).
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    return ShaderMask(
      shaderCallback: (bounds) => pc.brandGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// A card surface with the standard radius + hairline border.
class PointCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  const PointCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.radius = PointRadius.card,
  });

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    final body = Container(
      padding: padding ?? const EdgeInsets.all(PointSpacing.pad),
      decoration: BoxDecoration(
        color: color ?? pc.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: pc.hairline),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: body,
      ),
    );
  }
}

/// Avatar with initials, optional status dot and bridge badge.
class PointAvatar extends StatelessWidget {
  final String label; // initials
  final Color color;
  final double size;
  final Color? statusColor; // null = no dot
  final Widget? badge; // bridge badge overlay (bottom-right)
  final bool ring; // accent ring (selected)
  final bool dashed; // ghosted look

  const PointAvatar({
    super.key,
    required this.label,
    required this.color,
    this.size = 44,
    this.statusColor,
    this.badge,
    this.ring = false,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Opacity(
              opacity: dashed ? 0.55 : 1,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: dashed ? 0.35 : 1),
                  shape: BoxShape.circle,
                  border: ring
                      ? Border.all(color: pc.accent, width: 2.5)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: PointType.display(
                    size: size * 0.36,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
          if (statusColor != null)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: pc.bg, width: 2.5),
                ),
              ),
            ),
          if (badge != null)
            Positioned(right: -2, bottom: -2, child: badge!),
        ],
      ),
    );
  }
}

/// Small platform chip: colored dot-icon + short name.
class BridgeChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const BridgeChip({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PointRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.cell_tower_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: PointType.ui(size: 11, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Stadium pill (selectable chip or static tag).
class PointChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const PointChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PointRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? pc.accent : pc.surface2,
            borderRadius: BorderRadius.circular(PointRadius.pill),
            border: Border.all(color: selected ? pc.accent : pc.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? pc.accentInk : pc.textMuted),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: PointType.ui(
                  size: 13,
                  weight: FontWeight.w700,
                  color: selected ? pc.accentInk : pc.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS-style segmented control (e.g. People | Groups & rules).
class PointSegment extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const PointSegment({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: pc.surface2,
        borderRadius: BorderRadius.circular(PointRadius.sm),
      ),
      child: LayoutBuilder(builder: (context, cons) {
        final w = (cons.maxWidth - 8) / labels.length;
        return Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + 2 * index / (labels.length - 1).clamp(1, 99), 0),
              child: Container(
                width: w,
                height: 36,
                decoration: BoxDecoration(
                  color: pc.accent,
                  borderRadius: BorderRadius.circular(PointRadius.sm - 4),
                ),
              ),
            ),
            Row(
              children: List.generate(labels.length, (i) {
                final sel = i == index;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: PointType.ui(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: sel ? pc.accentInk : pc.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      }),
    );
  }
}

/// Mono countdown pill (clock + remaining).
class CountdownPill extends StatelessWidget {
  final String text;
  const CountdownPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pc.tempShare.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(PointRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 11, color: pc.tempShare),
          const SizedBox(width: 4),
          Text(text, style: PointType.mono(size: 11.5, color: pc.tempShare)),
        ],
      ),
    );
  }
}

/// Battery glyph with true fill width and threshold color.
class BatteryGlyph extends StatelessWidget {
  final int pct;
  final bool charging;
  const BatteryGlyph({super.key, required this.pct, this.charging = false});

  @override
  Widget build(BuildContext context) {
    final pc = context.pc;
    final col = pc.batteryColor(pct);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              width: 22,
              height: 11,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: pc.textDim, width: 1.2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(1.5),
              child: Container(
                width: (22 - 3) * (pct / 100).clamp(0.05, 1),
                height: 8,
                decoration: BoxDecoration(
                  color: col,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
        Text(
          charging ? '$pct%⚡' : '$pct%',
          style: PointType.ui(size: 12, weight: FontWeight.w700, color: col),
        ),
      ],
    );
  }
}

/// Status dot helper.
Color statusColorFor(BuildContext context, String status) {
  final pc = context.pc;
  switch (status) {
    case 'live':
      return pc.live;
    case 'idle':
      return pc.idle;
    default:
      return pc.stale;
  }
}
