import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/sharing_provider.dart';

class InboxTab extends StatelessWidget {
  const InboxTab({super.key, required this.recentGeofenceEvents});

  final List<Map<String, dynamic>> recentGeofenceEvents;

  int itemCount(BuildContext context) {
    final sharing = context.read<SharingProvider>();
    final location = context.read<LocationProvider>();
    int count = sharing.incomingRequests.length + recentGeofenceEvents.length;
    for (final person in location.people.values) {
      if (person.battery != null && person.battery! < 20 && person.online) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final sharing = context.watch<SharingProvider>();
    final location = context.watch<LocationProvider>();

    final items = <Widget>[];

    // Incoming share requests
    for (final req in sharing.incomingRequests) {
      items.add(
        _buildInboxItem(
          context,
          icon: Icons.person_add,
          iconBg: PointColors.accent,
          title:
              '${(req['from_user_id'] as String? ?? '').split('@').first} wants to share',
          subtitle: 'Share request',
          time: 'now',
          actions: [
            _inboxAction(
              context,
              'Accept',
              PointColors.accent,
              () => sharing.acceptRequest(req['id'] as String? ?? ''),
            ),
            _inboxAction(
              context,
              'Decline',
              PointColors.textSecondary,
              () => sharing.rejectRequest(req['id'] as String? ?? ''),
            ),
          ],
        ),
      );
    }

    // Geofence events
    for (final event in recentGeofenceEvents) {
      items.add(
        _buildInboxItem(
          context,
          icon: event['event'] == 'enter'
              ? Icons.location_on
              : Icons.location_off,
          iconBg: event['event'] == 'enter'
              ? PointColors.online
              : PointColors.textSecondary,
          title:
              '${event['event'] == 'enter' ? 'Arrived at' : 'Left'} ${event['place_name']}',
          subtitle: event['triggered_by']?.split('@').first ?? 'You',
          time: _formatEventTime(event['time']),
        ),
      );
    }

    // Low battery warnings
    for (final person in location.people.values) {
      if (person.battery != null && person.battery! < 20 && person.online) {
        items.add(
          _buildInboxItem(
            context,
            icon: Icons.battery_alert,
            iconBg: PointColors.danger,
            title: '${person.userId.split('@').first}\'s battery is low',
            subtitle: '${person.battery}% remaining',
            time: 'now',
          ),
        );
      }
    }

    return RefreshIndicator(
      color: PointColors.accent,
      onRefresh: () => sharing.loadAll(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          const SizedBox(height: 14),
          Text(
            'Inbox',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: context.primaryText,
            ),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            _buildEmptyState(context, Icons.inbox_outlined, 'No notifications yet')
          else
            ...items,
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, IconData icon, String message) {
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

  Widget _buildInboxItem(
    BuildContext context, {
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String time,
    List<Widget>? actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: iconBg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.primaryText,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.tertiaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: context.secondaryText),
                ),
                if (actions != null && actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxAction(
      BuildContext context, String label, Color color, VoidCallback onTap) {
    final isAccent = color == PointColors.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isAccent ? PointColors.accent : context.subtleBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isAccent ? Colors.white : PointColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  String _formatEventTime(String? iso) {
    if (iso == null) return 'now';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
