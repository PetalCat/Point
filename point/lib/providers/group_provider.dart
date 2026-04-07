import 'package:flutter/foundation.dart';
import '../models/group.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

class GroupProvider extends ChangeNotifier {
  final ApiService _api;
  CryptoService? _crypto;
  List<Group> _groups = [];
  String? _selectedGroupId;

  List<Group> get groups => _groups;
  String? get selectedGroupId => _selectedGroupId;
  Group? get selectedGroup =>
      _groups.where((g) => g.id == _selectedGroupId).firstOrNull;

  GroupProvider(this._api);

  void setCryptoService(CryptoService crypto) {
    _crypto = crypto;
  }

  Future<void> loadGroups() async {
    try {
      _groups = await _api.listGroups();
      if (_selectedGroupId == null && _groups.isNotEmpty) {
        _selectedGroupId = _groups.first.id;
      }
    } catch (e) {
      debugPrint('GroupProvider error: $e');
    }
    notifyListeners();
  }

  /// Set up MLS encryption for all loaded groups.
  /// For groups we created (admin), create the MLS group if not already set up.
  /// For groups we joined, we should have received a Welcome already.
  Future<void> setupEncryptionForAllGroups(String myUserId) async {
    if (_crypto == null || !_crypto!.isInitialized) return;
    for (final group in _groups) {
      if (_crypto!.hasGroup(group.id)) continue;

      // Check if we're the admin (creator) — if so, create the MLS group
      // and add existing members
      try {
        // Try to create the MLS group — if we're not the first member,
        // we should receive a Welcome instead (which processPendingMessages handles)
        if (group.ownerId == myUserId) {
          final memberIds = group.members
              .where((m) => m.userId != myUserId)
              .map((m) => m.userId)
              .toList();
          await _crypto!.setupNewGroup(group.id, memberIds);
        }
      } catch (e) {
        debugPrint('[Groups] MLS setup failed for ${group.id}: $e');
      }
    }
  }

  void selectGroup(String? id) {
    _selectedGroupId = id;
    notifyListeners();
  }

  Future<Group?> createGroup(String name) async {
    try {
      final group = await _api.createGroup(name);
      _groups.add(group);
      notifyListeners();

      // Create MLS group — we're the only member initially
      if (_crypto != null && _crypto!.isInitialized) {
        try {
          await _crypto!.createGroup(group.id);
        } catch (e) {
          debugPrint('[Groups] MLS group creation failed: $e');
        }
      }

      return group;
    } catch (_) {
      return null;
    }
  }

  /// Add a member to a group and set up MLS key exchange.
  Future<bool> addMember(String groupId, String userId, {String? role}) async {
    try {
      await _api.addMember(groupId, userId, role: role);

      // MLS key exchange — fetch their key package, add to group, send Welcome
      if (_crypto != null && _crypto!.hasGroup(groupId)) {
        try {
          await _crypto!.addMemberToGroup(groupId, userId);
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
