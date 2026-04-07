/// A ghost rule that can be time-based, location-based, or condition-based.
class GhostRule {
  final String id;
  final String name;
  final GhostRuleType type;
  final bool enabled;

  // Time-based
  final List<int>? days; // 0=Mon, 6=Sun
  final int? startMinute; // minutes from midnight
  final int? endMinute;

  // Location-based
  final String? placeId;
  final String? placeName;

  // Battery-based
  final int? batteryThreshold;

  // Targeting
  final GhostTarget target;
  final List<String>? targetGroupIds; // null = all groups
  final List<String>? exceptGroupIds; // groups excluded from ghost

  GhostRule({
    required this.id,
    required this.name,
    required this.type,
    this.enabled = true,
    this.days,
    this.startMinute,
    this.endMinute,
    this.placeId,
    this.placeName,
    this.batteryThreshold,
    this.target = GhostTarget.all,
    this.targetGroupIds,
    this.exceptGroupIds,
  });

  GhostRule copyWith({
    String? name,
    bool? enabled,
    List<int>? days,
    int? startMinute,
    int? endMinute,
    String? placeId,
    String? placeName,
    int? batteryThreshold,
    GhostTarget? target,
    List<String>? targetGroupIds,
    List<String>? exceptGroupIds,
  }) {
    return GhostRule(
      id: id,
      name: name ?? this.name,
      type: type,
      enabled: enabled ?? this.enabled,
      days: days ?? this.days,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      placeId: placeId ?? this.placeId,
      placeName: placeName ?? this.placeName,
      batteryThreshold: batteryThreshold ?? this.batteryThreshold,
      target: target ?? this.target,
      targetGroupIds: targetGroupIds ?? this.targetGroupIds,
      exceptGroupIds: exceptGroupIds ?? this.exceptGroupIds,
    );
  }

  /// Human-readable summary of when this rule is active.
  String get summary {
    switch (type) {
      case GhostRuleType.schedule:
        final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final dayStr = days != null && days!.isNotEmpty
            ? (days!.length == 7
                ? 'Every day'
                : days!.length == 5 && !days!.contains(5) && !days!.contains(6)
                    ? 'Weekdays'
                    : days!.length == 2 && days!.contains(5) && days!.contains(6)
                        ? 'Weekends'
                        : days!.map((d) => dayNames[d]).join(', '))
            : 'No days';
        if (startMinute != null && endMinute != null) {
          return '$dayStr ${_formatMinutes(startMinute!)}–${_formatMinutes(endMinute!)}';
        }
        return '$dayStr all day';
      case GhostRuleType.location:
        return 'At ${placeName ?? 'location'}';
      case GhostRuleType.battery:
        return 'Battery below ${batteryThreshold ?? 15}%';
      case GhostRuleType.timer:
        return 'Manual timer';
    }
  }

  /// Check if this rule is currently active based on time/conditions.
  bool isActiveNow({int? currentBattery, String? currentPlaceId}) {
    if (!enabled) return false;

    final now = DateTime.now();

    switch (type) {
      case GhostRuleType.schedule:
        if (days == null || days!.isEmpty) return false;
        final weekday = now.weekday - 1; // Dart: 1=Mon, we want 0=Mon
        if (!days!.contains(weekday)) return false;
        if (startMinute != null && endMinute != null) {
          final nowMinutes = now.hour * 60 + now.minute;
          if (startMinute! <= endMinute!) {
            return nowMinutes >= startMinute! && nowMinutes < endMinute!;
          } else {
            // Overnight: e.g. 22:00 - 07:00
            return nowMinutes >= startMinute! || nowMinutes < endMinute!;
          }
        }
        return true; // all day

      case GhostRuleType.location:
        return placeId != null && placeId == currentPlaceId;

      case GhostRuleType.battery:
        return currentBattery != null &&
            batteryThreshold != null &&
            currentBattery <= batteryThreshold!;

      case GhostRuleType.timer:
        return true; // managed externally
    }
  }

  /// Check if this rule affects a specific group.
  bool affectsGroup(String groupId) {
    if (exceptGroupIds != null && exceptGroupIds!.contains(groupId)) return false;
    if (target == GhostTarget.all) return true;
    if (target == GhostTarget.specific) {
      return targetGroupIds != null && targetGroupIds!.contains(groupId);
    }
    return false;
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return m == 0 ? '$hour $period' : '$hour:${m.toString().padLeft(2, '0')} $period';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'enabled': enabled,
    'days': days,
    'start_minute': startMinute,
    'end_minute': endMinute,
    'place_id': placeId,
    'place_name': placeName,
    'battery_threshold': batteryThreshold,
    'target': target.name,
    'target_group_ids': targetGroupIds,
    'except_group_ids': exceptGroupIds,
  };

  factory GhostRule.fromJson(Map<String, dynamic> json) => GhostRule(
    id: json['id'],
    name: json['name'],
    type: GhostRuleType.values.byName(json['type']),
    enabled: json['enabled'] ?? true,
    days: (json['days'] as List?)?.cast<int>(),
    startMinute: json['start_minute'],
    endMinute: json['end_minute'],
    placeId: json['place_id'],
    placeName: json['place_name'],
    batteryThreshold: json['battery_threshold'],
    target: GhostTarget.values.byName(json['target'] ?? 'all'),
    targetGroupIds: (json['target_group_ids'] as List?)?.cast<String>(),
    exceptGroupIds: (json['except_group_ids'] as List?)?.cast<String>(),
  );
}

enum GhostRuleType { schedule, location, battery, timer }
enum GhostTarget { all, specific }
