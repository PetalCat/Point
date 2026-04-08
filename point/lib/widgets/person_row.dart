import 'package:flutter/material.dart';
import '../providers/location_provider.dart';
import '../theme.dart';
import '../utils.dart' as utils;

class PersonRow extends StatelessWidget {
  final PersonLocation person;

  const PersonRow({super.key, required this.person});

  Color get _color => PointColors.colorForUser(person.userId);
  String get _name => utils.displayName(person.userId);
  String? get _domain => utils.userDomain(person.userId);
  bool get _isFederated => _domain != null;
  String get _initial => _name.isNotEmpty ? _name[0].toUpperCase() : '?';
  int get _secAgo => utils.secondsAgo(person.timestamp);
  bool get _isStale => _secAgo > 2 * 60 * 60;

  String? get _speedLabel {
    final speed = person.speed;
    if (speed == null || speed < 0.5) return null;
    final mph = (speed * 2.237).round();
    final activity = speed < 2.0
        ? 'walking'
        : speed < 5.0
        ? 'cycling'
        : 'driving';
    return '$activity \u00b7 $mph mph';
  }

  String get _timeAgo => utils.formatTimeAgo(_secAgo);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _isStale ? 0.35 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _color.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  if (person.online)
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: PointColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.cardBg, width: 2),
                          boxShadow: [
                            const BoxShadow(
                              color: PointColors.onlineGlow,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: context.primaryText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isFederated) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _domain!,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00D4FF),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 5),
                      _badge(),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _speedLabel ??
                        person.activity ??
                        (person.online ? 'online' : 'offline'),
                    style: TextStyle(
                      fontSize: 10,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            // Distance / time / battery
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeAgo,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.tertiaryText,
                  ),
                ),
                if (person.battery != null) ...[
                  const SizedBox(height: 2),
                  _batteryIndicator(person.battery!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _batteryIndicator(int level) {
    final Color color;
    final IconData icon;
    if (level > 50) {
      color = PointColors.online;
      icon = Icons.battery_full;
    } else if (level > 20) {
      color = const Color(0xFFFFAB00);
      icon = Icons.battery_3_bar;
    } else {
      color = PointColors.danger;
      icon = Icons.battery_1_bar;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          '$level%',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _badge() {
    final src = person.sourceType.toLowerCase();
    final (label, color) = switch (src) {
      String s when s.contains('e2e') || s == 'gps' => (
        'E2E',
        PointColors.online,
      ),
      String s when s.contains('federated') => (
        'FED',
        const Color(0xFF00D4FF),
      ),
      String s when s.contains('find') || s.contains('apple') => (
        'FIND MY',
        PointColors.findMy,
      ),
      String s when s.contains('google') => ('GOOGLE', PointColors.google),
      _ => ('', Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
