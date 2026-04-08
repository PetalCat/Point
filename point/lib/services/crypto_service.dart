import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../src/rust/api/crypto.dart';
import 'api_service.dart';

/// Manages MLS encryption state for the current user.
/// Wraps the Rust PointCryptoHandle via flutter_rust_bridge.
class CryptoService {
  final ApiService _api;
  PointCryptoHandle? _crypto;
  String? _identity;

  // Maps server group IDs (strings) -> MLS group IDs (bytes)
  final Map<String, Uint8List> _groupIdMap = {};

  CryptoService(this._api);

  bool get isInitialized => _crypto != null;

  /// Initialize MLS crypto for this user identity and upload key packages.
  Future<void> init(String identity) async {
    _identity = identity;
    _crypto = await PointCryptoHandle.newInstance(identity: identity);
    debugPrint('[Crypto] MLS initialized for $identity');
    await _uploadKeyPackages();
  }

  /// Upload fresh key packages so others can add us to groups.
  Future<void> _uploadKeyPackages() async {
    if (_crypto == null) return;
    try {
      final kp = await _crypto!.generateKeyPackage();
      await _api.uploadKeyPackage(base64Encode(kp));
      debugPrint('[Crypto] Uploaded key package (${kp.length} bytes)');
    } catch (e) {
      debugPrint('[Crypto] Failed to upload key package: $e');
    }
  }

  // ============================================================
  // High-level orchestration — called by providers/screens
  // ============================================================

  /// Create an MLS group for a server group, then add all existing members.
  /// Called after creating a new server group.
  Future<void> setupNewGroup(String groupId, List<String> memberUserIds) async {
    if (!isInitialized) return;
    try {
      await createGroup(groupId);
      for (final memberId in memberUserIds) {
        await _addMemberByUserId(groupId, memberId);
      }
      debugPrint('[Crypto] Group $groupId fully set up with ${memberUserIds.length} members');
    } catch (e) {
      debugPrint('[Crypto] Failed to set up group $groupId: $e');
    }
  }

  /// Add a single member to an existing MLS group by fetching their key package.
  /// Called when a new member joins a group we own.
  Future<void> addMemberToGroup(String groupId, String memberId) async {
    if (!isInitialized || !hasGroup(groupId)) return;
    try {
      await _addMemberByUserId(groupId, memberId);
    } catch (e) {
      debugPrint('[Crypto] Failed to add $memberId to $groupId: $e');
    }
  }

  /// Fetch and process all pending MLS messages (Welcomes and Commits).
  /// Called on app startup after MLS init.
  Future<void> processPendingMessages() async {
    if (!isInitialized) return;
    try {
      final messages = await _api.fetchMlsMessages();
      for (final msg in messages) {
        final type = msg['message_type'] as String?;
        final groupId = msg['group_id'] as String?;
        final payload = msg['payload'] as String?;
        final msgId = msg['id'] as String?;

        if (type == null || groupId == null || payload == null || msgId == null) continue;

        try {
          final bytes = base64Decode(payload);
          if (type == 'welcome') {
            await processWelcome(groupId, Uint8List.fromList(bytes));
            debugPrint('[Crypto] Processed Welcome for group $groupId');
          } else if (type == 'commit') {
            await processCommit(groupId, Uint8List.fromList(bytes));
            debugPrint('[Crypto] Processed Commit for group $groupId');
          }
          await _api.ackMlsMessage(msgId);
        } catch (e) {
          debugPrint('[Crypto] Failed to process MLS message $msgId: $e');
        }
      }
    } catch (e) {
      debugPrint('[Crypto] Failed to fetch pending MLS messages: $e');
    }
  }

  /// Handle a real-time MLS message from WebSocket.
  Future<void> handleMlsWsMessage(Map<String, dynamic> msg) async {
    if (!isInitialized) return;
    final type = msg['message_type'] as String?;
    final groupId = msg['group_id'] as String?;
    final payload = msg['payload'] as String?;

    if (type == null || groupId == null || payload == null) return;

    try {
      final bytes = base64Decode(payload);
      if (type == 'welcome') {
        await processWelcome(groupId, Uint8List.fromList(bytes));
        debugPrint('[Crypto] Processed real-time Welcome for $groupId');
      } else if (type == 'commit') {
        await processCommit(groupId, Uint8List.fromList(bytes));
        debugPrint('[Crypto] Processed real-time Commit for $groupId');
      }
    } catch (e) {
      debugPrint('[Crypto] Failed to handle MLS WS message: $e');
    }
  }

  /// Set up a pairwise MLS group for direct user-to-user sharing.
  /// Uses a deterministic group ID so both sides resolve to the same group.
  Future<void> setupDirectShare(String myUserId, String otherUserId) async {
    if (!isInitialized) return;
    final pairId = _pairwiseGroupId(myUserId, otherUserId);
    if (hasGroup(pairId)) return; // already set up

    try {
      await createGroup(pairId);
      await _addMemberByUserId(pairId, otherUserId);
      debugPrint('[Crypto] Direct share MLS group set up: $pairId');
    } catch (e) {
      debugPrint('[Crypto] Failed to set up direct share $pairId: $e');
    }
  }

  /// Get the pairwise group ID for direct sharing encryption/decryption.
  String pairwiseGroupId(String userA, String userB) => _pairwiseGroupId(userA, userB);

  // ============================================================
  // Low-level MLS operations
  // ============================================================

  /// Create an MLS group for a server group/sharing session.
  Future<Uint8List> createGroup(String serverGroupId) async {
    final crypto = _requireCrypto();
    final gid = await crypto.createGroup(groupId: utf8.encode(serverGroupId));
    _groupIdMap[serverGroupId] = Uint8List.fromList(gid);
    debugPrint('[Crypto] Created MLS group for $serverGroupId');
    return Uint8List.fromList(gid);
  }

  /// Add a member to an MLS group. Returns welcome + commit messages.
  Future<BridgeAddMemberResult> addMember(
    String serverGroupId,
    Uint8List keyPackageBytes,
  ) async {
    final crypto = _requireCrypto();
    final gid = _requireGroupId(serverGroupId);
    final result = await crypto.addMember(
      groupId: gid.toList(),
      keyPackageBytes: keyPackageBytes.toList(),
    );
    debugPrint('[Crypto] Added member to $serverGroupId');
    return result;
  }

  /// Process a Welcome message to join an MLS group.
  Future<void> processWelcome(
    String serverGroupId,
    Uint8List welcomeBytes,
  ) async {
    final crypto = _requireCrypto();
    final gid = await crypto.processWelcome(welcomeBytes: welcomeBytes.toList());
    _groupIdMap[serverGroupId] = Uint8List.fromList(gid);
    debugPrint('[Crypto] Joined MLS group $serverGroupId via Welcome');
  }

  /// Process an MLS Commit message to advance group epoch.
  Future<void> processCommit(String serverGroupId, Uint8List commitBytes) async {
    final crypto = _requireCrypto();
    final gid = _groupIdMap[serverGroupId];
    if (gid == null) {
      debugPrint('[Crypto] No MLS group for $serverGroupId, skipping commit');
      return;
    }
    await crypto.processCommit(
      groupId: gid.toList(),
      commitBytes: commitBytes.toList(),
    );
  }

  /// Encrypt location data for a group. Returns base64-encoded ciphertext.
  /// Falls back to base64-encoded plaintext if MLS isn't ready yet —
  /// this ensures the app works immediately while key exchange completes.
  Future<String> encrypt(String serverGroupId, Map<String, dynamic> data) async {
    if (!isInitialized) {
      debugPrint('[Crypto] Not initialized — sending unencrypted for $serverGroupId');
      return base64Encode(utf8.encode(jsonEncode(data)));
    }
    final crypto = _requireCrypto();
    final gid = _groupIdMap[serverGroupId];
    if (gid == null) {
      debugPrint('[Crypto] No MLS group for $serverGroupId — sending unencrypted (key exchange pending)');
      return base64Encode(utf8.encode(jsonEncode(data)));
    }
    final plaintext = utf8.encode(jsonEncode(data));
    final ciphertext = await crypto.encrypt(
      groupId: gid.toList(),
      plaintext: plaintext,
    );
    return base64Encode(ciphertext);
  }

  /// Decrypt a base64-encoded blob. Returns the decoded JSON map.
  Future<Map<String, dynamic>> decrypt(
    String serverGroupId,
    String blob,
  ) async {
    final bytes = base64Decode(blob);

    if (!isInitialized) {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }

    final gid = _groupIdMap[serverGroupId];

    if (gid == null) {
      try {
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        debugPrint('[Crypto] Cannot decrypt blob for $serverGroupId: no MLS group and not plaintext');
        rethrow;
      }
    }

    try {
      final crypto = _requireCrypto();
      final plaintext = await crypto.decrypt(
        groupId: gid.toList(),
        ciphertext: bytes,
      );
      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (e) {
      // If MLS decrypt fails, try as plaintext (migration period)
      debugPrint('[Crypto] MLS decrypt failed, trying plaintext: $e');
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
  }

  /// Check if we have an MLS group for a server ID.
  bool hasGroup(String serverGroupId) => _groupIdMap.containsKey(serverGroupId);

  // ============================================================
  // Private helpers
  // ============================================================

  /// Fetch a user's key package from the server, add them to the MLS group,
  /// then send the Welcome and Commit via the server.
  Future<void> _addMemberByUserId(String groupId, String memberId) async {
    final keyPackages = await _api.fetchKeyPackages(memberId);
    if (keyPackages.isEmpty) {
      debugPrint('[Crypto] No key packages for $memberId — they may not have MLS set up');
      return;
    }

    final kpBytes = Uint8List.fromList(base64Decode(keyPackages.first));
    final result = await addMember(groupId, kpBytes);

    // Send Welcome to the new member
    await _api.sendMlsWelcome(
      memberId,
      groupId,
      base64Encode(result.welcome),
    );

    // Send Commit to existing members
    await _api.sendMlsCommit(groupId, base64Encode(result.commit));

    // Upload a fresh key package (the one used was consumed)
    await _uploadKeyPackages();
  }

  /// Deterministic pairwise group ID for direct sharing.
  /// Sorted so both users compute the same ID.
  String _pairwiseGroupId(String userA, String userB) {
    final sorted = [userA, userB]..sort();
    return 'dm:${sorted[0]}:${sorted[1]}';
  }

  PointCryptoHandle _requireCrypto() {
    if (_crypto == null) {
      throw StateError('CryptoService not initialized — call init() first');
    }
    return _crypto!;
  }

  Uint8List _requireGroupId(String serverGroupId) {
    final gid = _groupIdMap[serverGroupId];
    if (gid == null) {
      throw StateError('No MLS group for $serverGroupId — call createGroup() first');
    }
    return gid;
  }
}
