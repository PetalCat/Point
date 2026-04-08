import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ghost_rule.dart';
import '../models/group.dart';
import '../providers.dart';
import '../screens/ghost_rules_screen.dart';
import '../theme.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  Group? _group;
  String? _myRole;
  GroupMember? _myMembership;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final groups = ref.read(groupProvider.notifier);
    await groups.loadGroups();
    final auth = ref.read(authProvider);

    final g = ref.read(groupProvider).groups.where((g) => g.id == widget.groupId).firstOrNull;
    if (g != null && mounted) {
      setState(() {
        _group = g;
        _myMembership = g.members
            .where((m) => m.userId == auth.userId)
            .firstOrNull;
        _myRole = _myMembership?.role;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  bool get _isAdmin => _myRole == 'admin';
  bool get _isOwner => _group?.ownerId == ref.read(authProvider).userId;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found')),
      );
    }

    final group = _group!;
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: context.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF3F51FF),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: _handleMenuAction,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Group Settings'),
                ),
                if (_isOwner)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete Group',
                      style: TextStyle(color: Color(0xFFE85D5D)),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          // Your Sharing section
          const SizedBox(height: 8),
          const Text(
            'Your Sharing',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3F51FF),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Sharing toggle
                _settingRow(
                  'Share Location',
                  trailing: Switch.adaptive(
                    value: _myMembership?.sharing ?? true,
                    activeColor: const Color(0xFF3F51FF),
                    onChanged: (v) => _updateMySetting(sharing: v),
                  ),
                ),
                const Divider(height: 24),
                // Precision
                _settingRow('Precision', trailing: _precisionDropdown()),
                const Divider(height: 24),
                // Schedule
                _settingRow(
                  'Schedule',
                  subtitle: _myMembership?.scheduleType == 'always'
                      ? 'Always sharing'
                      : 'Custom schedule',
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
              ],
            ),
          ),

          // Ghost visibility section
          const SizedBox(height: 24),
          _buildGhostSection(),

          // Members section
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Members (${group.members.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_isAdmin || group.membersCanInvite) ...[
                GestureDetector(
                  onTap: _showInviteSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F51FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '+ Invite',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: group.members.asMap().entries.map((entry) {
                final i = entry.key;
                final m = entry.value;
                final name = m.userId.split('@').first;
                final isMe = m.userId == auth.userId;
                final isMemberOwner = m.userId == group.ownerId;

                return Column(
                  children: [
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: Colors.black.withValues(alpha: 0.04),
                        indent: 60,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _colorForUser(m.userId),
                            child: Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isMe ? '$name (you)' : name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isMe
                                            ? const Color(0xFF999999)
                                            : const Color(0xFF3F51FF),
                                      ),
                                    ),
                                    if (isMemberOwner) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.subtleBg,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'owner',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: context.midGrey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      m.sharing
                                          ? Icons.location_on
                                          : Icons.location_off,
                                      size: 12,
                                      color: m.sharing
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFFCCCCCC),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      m.sharing ? m.precision : 'not sharing',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF999999),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Role badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: context.subtleBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              m.role,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: context.midGrey,
                              ),
                            ),
                          ),
                          // Admin actions
                          if (_isAdmin && !isMe && !isMemberOwner)
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                size: 18,
                                color: Color(0xFFCCCCCC),
                              ),
                              onSelected: (action) =>
                                  _handleMemberAction(action, m),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'role',
                                  child: Text(
                                    m.role == 'admin'
                                        ? 'Make Member'
                                        : 'Make Admin',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(color: Color(0xFFE85D5D)),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          // Leave group
          const SizedBox(height: 24),
          if (!_isOwner)
            GestureDetector(
              onTap: _leaveGroup,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.inputBorder),
                ),
                child: const Center(
                  child: Text(
                    'Leave Group',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE85D5D),
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _settingRow(
    String title, {
    String? subtitle,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3F51FF),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF999999),
                  ),
                ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildGhostSection() {
    final ghost = ref.watch(ghostProvider);
    final groupId = widget.groupId;
    final isGhosted = ghost.isGhostedForGroup(groupId);
    final rulesForGroup = ghost.rulesForGroup(groupId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('👻 ', style: TextStyle(fontSize: 14)),
            Text(
              'Ghost Visibility',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isGhosted ? PointColors.accent : context.primaryText,
              ),
            ),
            const Spacer(),
            if (isGhosted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: PointColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('GHOSTED',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: PointColors.accent)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('VISIBLE',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF22C55E))),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rulesForGroup.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No ghost rules affect this group',
                    style: TextStyle(fontSize: 13, color: context.secondaryText),
                  ),
                )
              else
                ...rulesForGroup.map((rule) => _ghostRuleRow(rule)),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GhostRulesScreen())),
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('Edit Ghost Rules',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    foregroundColor: PointColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: PointColors.accent.withValues(alpha: 0.15)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ghostRuleRow(GhostRule rule) {
    final isActive = rule.isActiveNow();
    final color = _ghostRuleColor(rule.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4, height: 32,
            decoration: BoxDecoration(
              color: isActive ? color : context.dividerClr,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.name,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: context.primaryText)),
                Text(rule.summary,
                    style: TextStyle(fontSize: 11, color: context.secondaryText)),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('ON',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
            ),
          const SizedBox(width: 4),
          Switch.adaptive(
            value: rule.enabled,
            activeColor: color,
            onChanged: (_) => ref.read(ghostProvider.notifier).toggleRule(rule.id),
          ),
        ],
      ),
    );
  }

  Color _ghostRuleColor(GhostRuleType type) {
    switch (type) {
      case GhostRuleType.schedule: return PointColors.accent;
      case GhostRuleType.location: return const Color(0xFF00FF88);
      case GhostRuleType.battery: return const Color(0xFFFFB700);
      case GhostRuleType.timer: return const Color(0xFFFF3B8B);
    }
  }

  Widget _precisionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.subtleBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: _myMembership?.precision ?? 'exact',
        underline: const SizedBox.shrink(),
        isDense: true,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3F51FF),
        ),
        items: const [
          DropdownMenuItem(value: 'exact', child: Text('Exact')),
          DropdownMenuItem(value: 'approximate', child: Text('Approximate')),
          DropdownMenuItem(value: 'city', child: Text('City')),
        ],
        onChanged: (v) => _updateMySetting(precision: v),
      ),
    );
  }

  Future<void> _updateMySetting({
    String? precision,
    bool? sharing,
    String? scheduleType,
  }) async {
    try {
      await ref.read(apiServiceProvider).updateMyGroupSettings(
        widget.groupId,
        precision: precision,
        sharing: sharing,
        scheduleType: scheduleType,
      );
      await _loadGroup();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'rename':
        final controller = TextEditingController(text: _group?.name);
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rename Group'),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (result != null && result.isNotEmpty) {
          await ref.read(apiServiceProvider).updateGroupSettings(
            widget.groupId,
            name: result,
          );
          await _loadGroup();
        }
        break;
      case 'settings':
        _showGroupSettingsSheet();
        break;
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Group?'),
            content: const Text(
              'This cannot be undone. All members will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFE85D5D)),
                ),
              ),
            ],
          ),
        );
        if (confirm == true && mounted) {
          await ref.read(apiServiceProvider).deleteGroup(widget.groupId);
          await ref.read(groupProvider.notifier).loadGroups();
          if (mounted) Navigator.pop(context);
        }
        break;
    }
  }

  void _showGroupSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Group Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Members can invite',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _group?.membersCanInvite ?? false,
                    activeColor: const Color(0xFF3F51FF),
                    onChanged: (v) async {
                      Navigator.pop(ctx);
                      await ref.read(apiServiceProvider).updateGroupSettings(
                        widget.groupId,
                        membersCanInvite: v,
                      );
                      await _loadGroup();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMemberAction(String action, GroupMember member) async {
    switch (action) {
      case 'role':
        final newRole = member.role == 'admin' ? 'member' : 'admin';
        await ref.read(apiServiceProvider).updateMemberRole(
          widget.groupId,
          member.userId,
          newRole,
        );
        await _loadGroup();
        break;
      case 'remove':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Remove ${member.userId.split('@').first}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Color(0xFFE85D5D)),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await ref.read(apiServiceProvider).removeMember(
            widget.groupId,
            member.userId,
          );
          await _loadGroup();
        }
        break;
    }
  }

  void _showInviteSheet() async {
    try {
      final result = await ref.read(apiServiceProvider).createGroupInvite(
        widget.groupId,
      );
      final code = result['code'] as String;
      final url = result['url'] as String? ?? 'point://join?code=$code';
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Group Invite',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                QrImageView(
                  data: url,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Invite Code',
                  style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Color(0xFF3F51FF),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap code to copy',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text(
                      'Share Invite',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      Share.share(
                        'Join my group on Point! Use code: $code\n$url',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Leave',
              style: TextStyle(color: Color(0xFFE85D5D)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final auth = ref.read(authProvider);
      await ref.read(apiServiceProvider).removeMember(
        widget.groupId,
        auth.userId!,
      );
      await ref.read(groupProvider.notifier).loadGroups();
      if (mounted) Navigator.pop(context);
    }
  }

  Color _colorForUser(String userId) {
    const colors = [
      Color(0xFFE85D5D),
      Color(0xFF4A9E6B),
      Color(0xFFC49A5A),
      Color(0xFF7A8AAB),
      Color(0xFF9B6B9E),
      Color(0xFF5A8AAB),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }
}
