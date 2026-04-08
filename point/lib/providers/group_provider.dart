import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/group.dart';
import '../providers.dart';

class GroupState {
  final List<Group> groups;
  final String? selectedGroupId;

  const GroupState({
    this.groups = const [],
    this.selectedGroupId,
  });

  GroupState copyWith({
    List<Group>? groups,
    String? selectedGroupId,
    bool clearSelectedGroupId = false,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      selectedGroupId: clearSelectedGroupId ? null : (selectedGroupId ?? this.selectedGroupId),
    );
  }

  Group? get selectedGroup =>
      groups.where((g) => g.id == selectedGroupId).firstOrNull;
}

class GroupNotifier extends Notifier<GroupState> {
  @override
  GroupState build() {
    return const GroupState();
  }

  Future<void> loadGroups() async {
    final api = ref.read(apiServiceProvider);
    try {
      final groups = await api.listGroups();
      var selectedId = state.selectedGroupId;
      if (selectedId == null && groups.isNotEmpty) {
        selectedId = groups.first.id;
      }
      state = state.copyWith(groups: groups, selectedGroupId: selectedId);
    } catch (e) {
      debugPrint('GroupNotifier error: $e');
    }
  }

  Future<void> setupEncryptionForAllGroups(String myUserId) async {
    final crypto = ref.read(cryptoServiceProvider);
    if (!crypto.isInitialized) return;
    for (final group in state.groups) {
      if (crypto.hasGroup(group.id)) continue;
      try {
        if (group.ownerId == myUserId) {
          final memberIds = group.members
              .where((m) => m.userId != myUserId)
              .map((m) => m.userId)
              .toList();
          await crypto.setupNewGroup(group.id, memberIds);
        }
      } catch (e) {
        debugPrint('[Groups] MLS setup failed for ${group.id}: $e');
      }
    }
  }

  void selectGroup(String? id) {
    if (id == null) {
      state = state.copyWith(clearSelectedGroupId: true);
    } else {
      state = state.copyWith(selectedGroupId: id);
    }
  }

  Future<Group?> createGroup(String name) async {
    final api = ref.read(apiServiceProvider);
    final crypto = ref.read(cryptoServiceProvider);
    try {
      final group = await api.createGroup(name);
      state = state.copyWith(groups: [...state.groups, group]);

      if (crypto.isInitialized) {
        try {
          await crypto.createGroup(group.id);
        } catch (e) {
          debugPrint('[Groups] MLS group creation failed: $e');
        }
      }

      return group;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateMySettings(
    String groupId, {
    String? precision,
    bool? sharing,
    String? scheduleType,
  }) async {
    final api = ref.read(apiServiceProvider);
    await api.updateMyGroupSettings(
      groupId,
      precision: precision,
      sharing: sharing,
      scheduleType: scheduleType,
    );
    await loadGroups();
  }

  Future<void> updateGroupSettings(
    String groupId, {
    String? name,
    bool? membersCanInvite,
  }) async {
    final api = ref.read(apiServiceProvider);
    await api.updateGroupSettings(
      groupId,
      name: name,
      membersCanInvite: membersCanInvite,
    );
    await loadGroups();
  }

  Future<void> deleteGroup(String groupId) async {
    final api = ref.read(apiServiceProvider);
    await api.deleteGroup(groupId);
    await loadGroups();
  }

  Future<void> updateMemberRole(
    String groupId,
    String memberId,
    String role,
  ) async {
    final api = ref.read(apiServiceProvider);
    await api.updateMemberRole(groupId, memberId, role);
    await loadGroups();
  }

  Future<void> removeMember(String groupId, String memberId) async {
    final api = ref.read(apiServiceProvider);
    await api.removeMember(groupId, memberId);
    await loadGroups();
  }

  Future<Map<String, dynamic>> createGroupInvite(String groupId) async {
    final api = ref.read(apiServiceProvider);
    return await api.createGroupInvite(groupId);
  }

  Future<Map<String, dynamic>> joinGroupByCode(String code) async {
    final api = ref.read(apiServiceProvider);
    final result = await api.joinGroupByCode(code);
    await loadGroups();
    return result;
  }

  Future<void> leaveGroup(String groupId) async {
    final auth = ref.read(authProvider);
    if (auth.userId == null) return;
    await removeMember(groupId, auth.userId!);
  }

  Future<bool> addMember(String groupId, String userId, {String? role}) async {
    final api = ref.read(apiServiceProvider);
    final crypto = ref.read(cryptoServiceProvider);
    try {
      await api.addMember(groupId, userId, role: role);

      if (crypto.hasGroup(groupId)) {
        try {
          await crypto.addMemberToGroup(groupId, userId);
        } catch (e) {
          debugPrint('[Groups] MLS add member failed: $e');
        }
      }

      await loadGroups();
      return true;
    } catch (_) {
      return false;
    }
  }
}
