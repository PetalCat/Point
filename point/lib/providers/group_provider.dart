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
