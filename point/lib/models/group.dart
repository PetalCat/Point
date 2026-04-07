class Group {
  final String id;
  final String name;
  final String ownerId;
  final bool membersCanInvite;
  final List<GroupMember> members;

  Group({
    required this.id,
    required this.name,
    required this.ownerId,
    this.membersCanInvite = false,
    required this.members,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'],
    name: json['name'],
    ownerId: json['owner_id'],
    membersCanInvite: json['members_can_invite'] ?? false,
    members: (json['members'] as List)
        .map((m) => GroupMember.fromJson(m))
        .toList(),
  );
}

class GroupMember {
  final String userId;
  final String role;
  final String precision;
  final bool sharing;
  final String scheduleType;

  GroupMember({
    required this.userId,
    required this.role,
    required this.precision,
    this.sharing = true,
    this.scheduleType = 'always',
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    userId: json['user_id'],
    role: json['role'],
    precision: json['precision'] ?? 'exact',
    sharing: json['sharing'] ?? true,
    scheduleType: json['schedule_type'] ?? 'always',
  );
}
