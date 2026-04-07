import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ghost_rule.dart';
import '../providers/ghost_provider.dart';
import '../providers/group_provider.dart';
import '../theme.dart';

class GhostRulesScreen extends StatelessWidget {
  const GhostRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ghost = context.watch<GhostProvider>();
    final groups = context.watch<GroupProvider>().groups;

    return Scaffold(
      backgroundColor: context.pageBg,
      appBar: AppBar(
        backgroundColor: context.pageBg,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const Text('👻 ', style: TextStyle(fontSize: 20)),
            Text('Ghost Rules',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: context.primaryText)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Active status
          _buildStatusCard(context, ghost),
          const SizedBox(height: 20),

          // Weekly schedule section
          _sectionHeader(context, 'Schedules', Icons.calendar_today_rounded),
          const SizedBox(height: 8),
          ..._buildScheduleRules(context, ghost),

          const SizedBox(height: 20),

          // Smart rules section
          _sectionHeader(context, 'Smart Rules', Icons.auto_awesome_rounded),
          const SizedBox(height: 8),
          ..._buildSmartRules(context, ghost),

          const SizedBox(height: 16),

          // Add rule button
          _buildAddRuleButton(context, groups),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, GhostProvider ghost) {
    final active = ghost.activeRules;
    final isActive = ghost.isGhostActive;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? PointColors.accent.withValues(alpha: 0.1)
            : context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? PointColors.accent.withValues(alpha: 0.3)
              : context.dividerClr,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? PointColors.accent.withValues(alpha: 0.2)
                  : context.subtleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(isActive ? '👻' : '👁️', style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Ghost Mode Active' : 'Visible',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: context.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? '${active.length} rule${active.length == 1 ? '' : 's'} active'
                      : 'No rules active right now',
                  style: TextStyle(fontSize: 12, color: context.secondaryText),
                ),
              ],
            ),
          ),
          if (ghost.hasActiveTimer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: PointColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _timerRemaining(ghost.timerExpiry!),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: PointColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildScheduleRules(BuildContext context, GhostProvider ghost) {
    final schedules = ghost.rules.where((r) => r.type == GhostRuleType.schedule).toList();
    if (schedules.isEmpty) {
      return [
        _emptyState(context, 'No schedules yet', 'Add recurring ghost windows'),
      ];
    }
    return schedules.map((r) => _ruleCard(context, ghost, r, Icons.schedule_rounded)).toList();
  }

  List<Widget> _buildSmartRules(BuildContext context, GhostProvider ghost) {
    final smart = ghost.rules.where((r) => r.type != GhostRuleType.schedule).toList();
    if (smart.isEmpty) {
      return [
        _emptyState(context, 'No smart rules', 'Ghost based on location, battery, etc.'),
      ];
    }
    return smart.map((r) {
      IconData icon;
      switch (r.type) {
        case GhostRuleType.location:
          icon = Icons.location_on_rounded;
        case GhostRuleType.battery:
          icon = Icons.battery_alert_rounded;
        default:
          icon = Icons.auto_awesome_rounded;
      }
      return _ruleCard(context, ghost, r, icon);
    }).toList();
  }

  Widget _ruleCard(BuildContext context, GhostProvider ghost, GhostRule rule, IconData icon) {
    final isActive = rule.isActiveNow();
    final color = _colorForType(rule.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.4) : context.dividerClr,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editRule(context, rule),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Left color bar
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: rule.enabled ? color : context.dividerClr,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                // Icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: context.primaryText,
                          )),
                      const SizedBox(height: 2),
                      Text(rule.summary,
                          style: TextStyle(fontSize: 11, color: context.secondaryText)),
                      if (rule.target == GhostTarget.specific && rule.targetGroupIds != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${rule.targetGroupIds!.length} group${rule.targetGroupIds!.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Active badge
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('ACTIVE',
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w800, color: color)),
                  ),
                // Toggle
                Switch(
                  value: rule.enabled,
                  onChanged: (_) => ghost.toggleRule(rule.id),
                  activeColor: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.secondaryText),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: context.secondaryText,
            )),
      ],
    );
  }

  Widget _emptyState(BuildContext context, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: context.dividerClr, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: context.secondaryText)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: context.tertiaryText)),
        ],
      ),
    );
  }

  Widget _buildAddRuleButton(BuildContext context, List groups) {
    return FilledButton.icon(
      onPressed: () => _showAddRuleSheet(context),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add Rule', style: TextStyle(fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: PointColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showAddRuleSheet(BuildContext context) {
    final ghost = context.read<GhostProvider>();
    final groups = context.read<GroupProvider>().groups;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Rule',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: context.primaryText)),
            const SizedBox(height: 16),
            _addRuleOption(ctx, '📅', 'Schedule', 'Ghost on specific days & times', () {
              Navigator.pop(ctx);
              _createScheduleRule(context, ghost, groups);
            }),
            _addRuleOption(ctx, '📍', 'Location', 'Ghost when at a place', () {
              Navigator.pop(ctx);
              _createLocationRule(context, ghost);
            }),
            _addRuleOption(ctx, '🪫', 'Low Battery', 'Ghost when battery is low', () {
              Navigator.pop(ctx);
              _createBatteryRule(context, ghost);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _addRuleOption(BuildContext ctx, String emoji, String title, String desc, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Text(emoji, style: const TextStyle(fontSize: 24)),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w700, color: ctx.primaryText)),
        subtitle: Text(desc,
            style: TextStyle(fontSize: 12, color: ctx.secondaryText)),
        trailing: Icon(Icons.chevron_right_rounded, color: ctx.secondaryText),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _createScheduleRule(BuildContext context, GhostProvider ghost, List groups) {
    ghost.addRule(GhostRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Work Hours',
      type: GhostRuleType.schedule,
      days: [0, 1, 2, 3, 4], // Mon-Fri
      startMinute: 9 * 60, // 9 AM
      endMinute: 17 * 60, // 5 PM
    ));
  }

  void _createLocationRule(BuildContext context, GhostProvider ghost) {
    ghost.addRule(GhostRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'At Home',
      type: GhostRuleType.location,
      placeName: 'Home',
      target: GhostTarget.all,
      exceptGroupIds: [],
    ));
  }

  void _createBatteryRule(BuildContext context, GhostProvider ghost) {
    ghost.addRule(GhostRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Low Battery',
      type: GhostRuleType.battery,
      batteryThreshold: 15,
    ));
  }

  void _editRule(BuildContext context, GhostRule rule) {
    // TODO: full rule editor
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
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}
