import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/location_provider.dart';
import '../theme.dart';

class PersonDetailSheet extends StatefulWidget {
  final String userId;
  final PersonLocation person;
  final ScrollController scrollController;
  final double? myLat;
  final double? myLon;

  const PersonDetailSheet({
    super.key,
    required this.userId,
    required this.person,
    required this.scrollController,
    this.myLat,
    this.myLon,
  });

  @override
  State<PersonDetailSheet> createState() => _PersonDetailSheetState();
}

class _PersonDetailSheetState extends State<PersonDetailSheet> {
  Color get _color => PointColors.colorForUser(widget.userId);
  String get _name => widget.userId.split('@').first;
  String get _initial => _name.isNotEmpty ? _name[0].toUpperCase() : '?';

  String get _activityLabel {
    final speed = widget.person.speed;
    if (speed == null || speed < 0.5) return 'Stationary';
    if (speed < 2.0) return 'Walking';
    if (speed < 5.0) return 'Cycling';
    return 'Driving';
  }

  String get _timeAgo {
    final ms = DateTime.now().millisecondsSinceEpoch - widget.person.timestamp;
    if (ms < 60000) return 'just now';
    if (ms < 3600000) return '${ms ~/ 60000}m ago';
    if (ms < 86400000) return '${ms ~/ 3600000}h ago';
    return '${ms ~/ 86400000}d ago';
  }

  String get _distanceLabel {
    if (widget.myLat == null || widget.myLon == null) return '--';
    final meters = _haversine(
      widget.myLat!,
      widget.myLon!,
      widget.person.lat,
      widget.person.lon,
    );
    final miles = meters / 1609.344;
    if (miles < 0.1) return '${(meters).round()} ft';
    if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
    return '${miles.round()} mi';
  }

  String get _speedLabel {
    final speed = widget.person.speed;
    if (speed == null || speed < 0.5) return '0 mph';
    final mph = (speed * 2.237).round();
    return '$mph mph';
  }

  String get _batteryLabel {
    final battery = widget.person.battery;
    if (battery == null) return '--';
    return '$battery%';
  }

  IconData get _batteryIcon {
    final battery = widget.person.battery;
    if (battery == null) return Icons.battery_unknown;
    if (battery > 50) return Icons.battery_full;
    if (battery > 20) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }

  Color get _batteryColor {
    final battery = widget.person.battery;
    if (battery == null) return PointColors.textSecondary;
    if (battery > 50) return PointColors.online;
    if (battery > 20) return const Color(0xFFFFAB00);
    return PointColors.danger;
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: context.dividerClr,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header: avatar + name + subtitle
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _color.withValues(alpha: 0.25),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _initial,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_activityLabel  \u00b7  $_timeAgo',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Stats row
        Row(
          children: [
            _StatBox(
              icon: Icons.near_me_outlined,
              iconColor: _color,
              label: 'Distance',
              value: _distanceLabel,
            ),
            const SizedBox(width: 8),
            _StatBox(
              icon: Icons.speed,
              iconColor: _color,
              label: 'Speed',
              value: _speedLabel,
            ),
            const SizedBox(width: 8),
            _StatBox(
              icon: _batteryIcon,
              iconColor: _batteryColor,
              label: 'Battery',
              value: _batteryLabel,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // TODAY label
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'TODAY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: PointColors.textTertiary,
            ),
          ),
        ),

        // Timeline placeholder
        _buildTimeline(),
      ],
    );
  }

  Widget _buildTimeline() {
    // For now, show the current known location as a single timeline entry
    final time = DateTime.fromMillisecondsSinceEpoch(widget.person.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        _TimelineEntry(
          color: _color,
          time: timeStr,
          title: _activityLabel,
          subtitle:
              '${widget.person.lat.toStringAsFixed(4)}, ${widget.person.lon.toStringAsFixed(4)}',
          isFirst: true,
          isLast: true,
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatBox({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: context.subtleBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Color color;
  final String time;
  final String title;
  final String subtitle;
  final bool isFirst;
  final bool isLast;

  const _TimelineEntry({
    required this.color,
    required this.time,
    required this.title,
    required this.subtitle,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time
          SizedBox(
            width: 44,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: PointColors.textSecondary,
              ),
            ),
          ),
          // Dot + line
          SizedBox(
            width: 24,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(
                    child: Container(width: 1.5, color: context.dividerClr),
                  ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isFirst ? 1.0 : 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1.5, color: context.dividerClr),
                  ),
                if (isLast) const Expanded(child: SizedBox()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PointColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
