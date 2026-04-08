import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/ghost_rule.dart';
import '../providers.dart';
import '../screens/ghost_rules_screen.dart';
import '../theme.dart';

class GhostBottomSheet extends ConsumerWidget {
  const GhostBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const GhostBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ghost = ref.watch(ghostProvider);
    final isActive = ghost.isGhostActive;

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.dividerClr,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header with toggle
          Row(
            children: [
              Icon(Icons.visibility_off_rounded, size: 28, color: context.primaryText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ghost Mode',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800, color: context.primaryText)),
                    Text(
                      isActive ? 'You are invisible' : 'You are visible',
                      style: TextStyle(fontSize: 12, color: context.secondaryText),
                    ),
                  ],
                ),
              ),
              Switch(
                value: ghost.isGlobalGhostOn,
                onChanged: (_) => ref.read(ghostProvider.notifier).toggleGlobalGhost(),
                activeColor: PointColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick timers
          Text('GHOST FOR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: context.secondaryText,
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              _timerChip(context, ref, ghost, Text('1h', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.primaryText)), const Duration(hours: 1)),
              const SizedBox(width: 6),
              _timerChip(context, ref, ghost, Text('4h', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.primaryText)), const Duration(hours: 4)),
              const SizedBox(width: 6),
              _timerChip(context, ref, ghost, Icon(Icons.dark_mode_rounded, size: 18, color: context.primaryText), const Duration(hours: 8), label: 'Tonight'),
              const SizedBox(width: 6),
              _timerChip(context, ref, ghost, Icon(Icons.calendar_today_rounded, size: 18, color: context.primaryText), const Duration(hours: 24), label: 'Tomorrow'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _timerChip(context, ref, ghost, Icon(Icons.all_inclusive_rounded, size: 18, color: context.primaryText), Duration.zero, label: 'Indefinite', indefinite: true),
              const SizedBox(width: 6),
              if (ghost.hasActiveTimer)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                    onTap: () => ref.read(ghostProvider.notifier).clearTimer(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: PointColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PointColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: const Center(
                        child: Text('Cancel Timer',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: PointColors.danger)),
                      ),
                    ),
                  ),
                  ),
                ),
            ],
          ),

          if (ghost.hasActiveTimer) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: PointColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: PointColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Ghost expires in ${_timerRemaining(ghost.timerExpiry!)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: PointColors.accent),
                  ),
                ],
              ),
            ),
          ],

          // Active rules summary
          if (ghost.activeRules.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: context.secondaryText),
                const SizedBox(width: 6),
                Text('ACTIVE RULES',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: context.secondaryText)),
              ],
            ),
            const SizedBox(height: 8),
            ...ghost.activeRules.take(3).map((r) => _activeRulePill(context, r)),
            if (ghost.rules.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${ghost.rules.length - 3} more rules',
                  style: TextStyle(fontSize: 11, color: context.secondaryText),
                ),
              ),
          ],

          // Edit rules link
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GhostRulesScreen()));
              },
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Edit Ghost Rules',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: PointColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: PointColors.accent.withValues(alpha: 0.2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerChip(BuildContext context, WidgetRef ref, GhostState ghost, Widget display,
      Duration duration, {String? label, bool indefinite = false}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: () {
          if (indefinite) {
            if (!ghost.isGlobalGhostOn) ref.read(ghostProvider.notifier).toggleGlobalGhost();
          } else {
            ref.read(ghostProvider.notifier).setGhostTimer(duration);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: context.subtleBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.dividerClr),
          ),
          child: Column(
            children: [
              display,
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(label,
                      style: TextStyle(fontSize: 9, color: context.secondaryText)),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _activeRulePill(BuildContext context, GhostRule rule) {
    final color = _colorForType(rule.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(rule.name,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.primaryText)),
          ),
          Text(rule.summary,
              style: TextStyle(fontSize: 10, color: context.secondaryText)),
        ],
      ),
    );
  }

  Color _colorForType(GhostRuleType type) {
    switch (type) {
      case GhostRuleType.schedule:
        return PointColors.accent;
      case GhostRuleType.location:
        return const Color(0xFF00FF88);
      case GhostRuleType.battery:
        return const Color(0xFFFFB700);
      case GhostRuleType.timer:
        return const Color(0xFFFF3B8B);
    }
  }

  String _timerRemaining(DateTime expiry) {
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}
