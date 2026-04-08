import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../theme.dart';
import '../../providers.dart';
import '../group_detail_screen.dart';

class SharingTab extends ConsumerStatefulWidget {
  const SharingTab({super.key, this.onSwitchToMap});

  /// Called when the user taps "Find on map" in the person sheet.
  final VoidCallback? onSwitchToMap;

  @override
  ConsumerState<SharingTab> createState() => _SharingTabState();
}

class _SharingTabState extends ConsumerState<SharingTab> {
  int _sharingFilter = 0; // 0=All, 1=People, 2=Groups, 3=Requests

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupProvider);
    final sharing = ref.watch(sharingProvider);
    final filterLabels = ['All', 'People', 'Groups', 'Requests'];

    return RefreshIndicator(
      color: PointColors.accent,
      onRefresh: () async {
        await ref.read(groupProvider.notifier).loadGroups();
        await ref.read(sharingProvider.notifier).loadAll();
      },
      child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        const SizedBox(height: 14),
        // Title row
        Row(
          children: [
            Text(
              'Sharing',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: context.primaryText,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _showAddShareDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: PointColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    const BoxShadow(
                      color: PointColors.accentGlow,
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  '+ Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Filter pills
        Row(
          children: List.generate(filterLabels.length, (i) {
            final active = _sharingFilter == i;
            final label = filterLabels[i];
            final badge = (i == 3 && sharing.pendingCount > 0)
                ? sharing.pendingCount
                : 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _sharingFilter = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: active ? PointColors.accent : context.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      if (active)
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      if (!active)
                        BoxShadow(
                          color: context.shadowClr,
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : context.secondaryText,
                        ),
                      ),
                      if (badge > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white.withValues(alpha: 0.3)
                                : PointColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$badge',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: active ? Colors.white : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        // Content
        if (_sharingFilter == 0 || _sharingFilter == 1) ...[
          // People section
          if (sharing.shares.isNotEmpty) ...[
            if (_sharingFilter == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  'PEOPLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: PointColors.textTertiary,
                  ),
                ),
              ),
            ...sharing.shares.map((s) => _buildPersonShareRow(s, sharing)),
          ],
          if (sharing.shares.isEmpty && _sharingFilter == 1)
            _buildEmptyState(Icons.person_outline, 'No people sharing yet'),
        ],
        if (_sharingFilter == 0 || _sharingFilter == 2) ...[
          // Groups section
          if (_sharingFilter == 0 && sharing.shares.isNotEmpty)
            const SizedBox(height: 10),
          if (groups.groups.isNotEmpty) ...[
            if (_sharingFilter == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  'GROUPS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: PointColors.textTertiary,
                  ),
                ),
              ),
            ...groups.groups.map((g) => _buildGroupCard(g, groups)),
          ],
          // Join by Code / New Group action row
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showJoinByCodeDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code,
                            size: 16,
                            color: Color(0xFF3F51FF),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Join by Code',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3F51FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _showCreateGroupDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 16, color: Color(0xFF3F51FF)),
                          SizedBox(width: 6),
                          Text(
                            'New Group',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3F51FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (groups.groups.isEmpty && _sharingFilter == 2)
            _buildEmptyState(Icons.group_outlined, 'No groups yet'),
        ],
        // Requests — show in All (filter 0) AND Requests (filter 3)
        if (_sharingFilter == 0 || _sharingFilter == 3) ...[
          if (sharing.incomingRequests.isNotEmpty) ...[
            if (_sharingFilter == 0 &&
                (sharing.shares.isNotEmpty || groups.groups.isNotEmpty))
              const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                'INCOMING REQUESTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: PointColors.textTertiary,
                ),
              ),
            ),
            ...sharing.incomingRequests.map(
              (r) => _buildIncomingRequestRow(r, sharing),
            ),
          ],
          if (sharing.outgoingRequests.isNotEmpty) ...[
            if (sharing.incomingRequests.isNotEmpty) const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                'SENT REQUESTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: PointColors.textTertiary,
                ),
              ),
            ),
            ...sharing.outgoingRequests.map((r) => _buildOutgoingRequestRow(r)),
          ],
          if (_sharingFilter == 3 &&
              sharing.incomingRequests.isEmpty &&
              sharing.outgoingRequests.isEmpty)
            _buildEmptyState(Icons.swap_horiz, 'No pending requests'),
        ],
        if (_sharingFilter == 0 &&
            sharing.shares.isEmpty &&
            groups.groups.isEmpty &&
            sharing.incomingRequests.isEmpty &&
            sharing.outgoingRequests.isEmpty)
          _buildEmptyState(Icons.share_outlined, 'No sharing yet'),
        const SizedBox(height: 40),
      ],
    ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.tertiaryText),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonShareRow(
    Map<String, dynamic> share,
    SharingState sharing,
  ) {
    final userId = share['user_id'] as String? ?? '';
    final name = userId.split('@').first;
    return GestureDetector(
      onTap: () => _showPersonSheet(userId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PointColors.colorForUser(userId),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: PointColors.colorForUser(
                      userId,
                    ).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.primaryText,
                    ),
                  ),
                  Text(
                    'Mutual sharing',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: PointColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonSheet(String userId) {
    final name = userId.split('@').first;
    final color = PointColors.colorForUser(userId);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              const SizedBox(height: 20),
              // Avatar + name
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                userId,
                style: const TextStyle(
                  fontSize: 12,
                  color: PointColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              _sheetAction(Icons.location_on, 'Find on map', () {
                Navigator.pop(ctx);
                widget.onSwitchToMap?.call();
              }),
              _sheetAction(
                Icons.notifications_outlined,
                'Notify when nearby',
                () {
                  Navigator.pop(ctx);
                  // Future: proximity alert setup
                },
              ),
              const SizedBox(height: 8),
              _sheetAction(Icons.remove_circle_outline, 'Stop sharing', () async {
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Stop sharing'),
                    content: Text('Stop sharing with $name?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Stop', style: TextStyle(color: PointColors.danger)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  Navigator.pop(ctx);
                  ref.read(sharingProvider.notifier).removeShare(userId);
                }
              }, danger: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? PointColors.danger : context.primaryText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: danger ? PointColors.danger.withValues(alpha: 0.1) : context.subtleBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequestRow(
    Map<String, dynamic> request,
    SharingState sharing,
  ) {
    final userId = request['from_user_id'] as String? ?? '';
    final requestId = request['id'] as String? ?? '';
    final name = userId.split('@').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PointColors.colorForUser(userId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.primaryText,
                  ),
                ),
                Text(
                  'wants to share with you',
                  style: TextStyle(fontSize: 11, color: context.secondaryText),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => ref.read(sharingProvider.notifier).rejectRequest(requestId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: context.subtleBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Reject',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: PointColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => ref.read(sharingProvider.notifier).acceptRequest(requestId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: PointColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Accept',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutgoingRequestRow(Map<String, dynamic> request) {
    final userId = request['to_user_id'] as String? ?? '';
    final name = userId.split('@').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PointColors.colorForUser(userId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.primaryText,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Pending',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFFFF9800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(dynamic g, GroupState groups) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: g.id)),
        );
        ref.read(groupProvider.notifier).loadGroups();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: PointColors.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        g.name[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.primaryText,
                          ),
                        ),
                        Text(
                          '${g.members.length} member${g.members.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    '\u203a',
                    style: TextStyle(
                      fontSize: 18,
                      color: PointColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: 26,
                child: Stack(
                  children: g.members
                      .take(6)
                      .toList()
                      .asMap()
                      .entries
                      .map<Widget>((entry) {
                        final m = entry.value;
                        final name = m.userId.split('@').first;
                        return Positioned(
                          left: entry.key * 18.0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: PointColors.colorForUser(m.userId),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.cardBg,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddShareDialog() {
    final controller = TextEditingController();
    final domain =
        ref.read(authProvider).userId?.split('@').last ?? 'point.local';
    var selectedDuration = -1; // -1 = permanent, 0+ = minutes

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.dividerClr,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share Location',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),

              // Username input
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'username or user@server',
                  suffixText: '@$domain',
                  suffixStyle: const TextStyle(
                    color: PointColors.textSecondary,
                    fontSize: 14,
                  ),
                  helperText: 'For other servers: user@theirserver.com',
                  helperStyle: TextStyle(
                    fontSize: 10,
                    color: context.tertiaryText,
                  ),
                  filled: true,
                  fillColor: context.subtleBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: PointColors.accent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Duration selector
              const Text(
                'Duration',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: PointColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _durationChip(
                    'Permanent',
                    -1,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '1 hour',
                    60,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '8 hours',
                    480,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    'Until midnight',
                    _minutesUntilMidnight(),
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '24 hours',
                    1440,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    var userId = controller.text.trim();
                    if (userId.isEmpty) return;
                    if (!userId.contains('@')) userId = '$userId@$domain';
                    Navigator.pop(ctx);

                    if (selectedDuration == -1) {
                      // Permanent share request
                      final success = await ref
                          .read(sharingProvider.notifier)
                          .sendRequest(userId);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Share request sent to ${userId.split('@').first}'
                                  : 'Failed to send request',
                            ),
                          ),
                        );
                      }
                    } else {
                      // Temp share
                      try {
                        await ref.read(apiServiceProvider).createTempShare(
                          userId,
                          selectedDuration,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Sharing with ${userId.split('@').first}',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PointColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    selectedDuration == -1
                        ? 'Send Share Request'
                        : 'Start Sharing',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationChip(
    String label,
    int value,
    int selected,
    ValueChanged<int> onSelect,
  ) {
    final active = value == selected;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? PointColors.accent : context.subtleBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  const BoxShadow(
                    color: PointColors.accentGlow,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : context.secondaryText,
          ),
        ),
      ),
    );
  }

  int _minutesUntilMidnight() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    return midnight.difference(now).inMinutes;
  }

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final group = await ref.read(groupProvider.notifier).createGroup(
                controller.text.trim(),
              );
              if (group != null && context.mounted) {
                ref.read(locationProvider.notifier).setActiveGroups(
                  ref
                      .read(groupProvider)
                      .groups
                      .map((g) => g.id)
                      .toList(),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinByCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter invite code'),
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(
            fontSize: 18,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref.read(apiServiceProvider).joinGroupByCode(code);
                await ref.read(groupProvider.notifier).loadGroups();
                ref.read(locationProvider.notifier).setActiveGroups(
                  ref
                      .read(groupProvider)
                      .groups
                      .map((g) => g.id)
                      .toList(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined group!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
