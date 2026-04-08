import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers.dart';
import '../services/notification_service.dart';
import '../services/ws_service.dart';

class SharingState {
  final List<Map<String, dynamic>> shares;
  final List<Map<String, dynamic>> incomingRequests;
  final List<Map<String, dynamic>> outgoingRequests;
  final List<Map<String, dynamic>> incomingZoneConsents;
  final bool loading;
  final String? myUserId;

  const SharingState({
    this.shares = const [],
    this.incomingRequests = const [],
    this.outgoingRequests = const [],
    this.incomingZoneConsents = const [],
    this.loading = false,
    this.myUserId,
  });

  int get pendingCount => incomingRequests.length + incomingZoneConsents.length;

  SharingState copyWith({
    List<Map<String, dynamic>>? shares,
    List<Map<String, dynamic>>? incomingRequests,
    List<Map<String, dynamic>>? outgoingRequests,
    List<Map<String, dynamic>>? incomingZoneConsents,
    bool? loading,
    String? myUserId,
  }) {
    return SharingState(
      shares: shares ?? this.shares,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      outgoingRequests: outgoingRequests ?? this.outgoingRequests,
      incomingZoneConsents: incomingZoneConsents ?? this.incomingZoneConsents,
      loading: loading ?? this.loading,
      myUserId: myUserId ?? this.myUserId,
    );
  }
}

class SharingNotifier extends Notifier<SharingState> {
  StreamSubscription? _wsSub;

  @override
  SharingState build() {
    ref.onDispose(() {
      _wsSub?.cancel();
    });
    return const SharingState();
  }

  void setMyUserId(String userId) {
    state = state.copyWith(myUserId: userId);
  }

  void listenToWs(WsService ws) {
    _wsSub?.cancel();
    _wsSub = ws.messages.listen(_handleWsMessage);
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'share.request' ||
        type == 'share.accepted' ||
        type == 'share.rejected') {
      loadAll();
    }
    if (type == 'share.request') {
      final fromId = msg['from_user_id'] as String? ?? '';
      final displayName = msg['display_name'] as String? ?? fromId.split('@').first;
      final isFederated = fromId.contains('@') && fromId.split('@').length > 1 && fromId.split('@')[1].contains('.');
      NotificationService.show(
        title: 'Share Request',
        body: isFederated
            ? '$displayName (${fromId.split('@').last}) wants to share'
            : '$displayName wants to share with you',
      );
    }
    if (type == 'zone.consent_request' ||
        type == 'zone.consent_accepted' ||
        type == 'zone.consent_rejected') {
      loadAll();
    }
    if (type == 'zone.consent_request') {
      final fromId = msg['from_user_id'] as String? ?? '';
      final displayName = msg['display_name'] as String? ?? fromId.split('@').first;
      NotificationService.show(
        title: 'Zone Consent Request',
        body: '$displayName wants their zones to track your location',
      );
    }
  }

  Future<void> loadAll() async {
    final api = ref.read(apiServiceProvider);
    state = state.copyWith(loading: true);
    try {
      final shares = await api.listShares();
      final incoming = await api.listIncomingRequests();
      final outgoing = await api.listOutgoingRequests();
      List<Map<String, dynamic>> zoneConsents = [];
      try {
        zoneConsents = await api.listIncomingZoneConsents();
      } catch (_) {}
      state = state.copyWith(
        shares: shares,
        incomingRequests: incoming,
        outgoingRequests: outgoing,
        incomingZoneConsents: zoneConsents,
        loading: false,
      );
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
      state = state.copyWith(loading: false);
    }
  }

  Future<bool> sendRequest(String toUserId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.sendShareRequest(toUserId);
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> acceptRequest(String requestId) async {
    final api = ref.read(apiServiceProvider);
    final crypto = ref.read(cryptoServiceProvider);
    try {
      final request = state.incomingRequests.firstWhere(
        (r) => r['id'] == requestId,
        orElse: () => <String, dynamic>{},
      );
      final otherUserId = request['from_user_id'] as String?;

      await api.acceptRequest(requestId);

      if (otherUserId != null && otherUserId.contains('@') && state.myUserId != null) {
        try {
          await api.sendFederated(otherUserId, 'share.accept', {});
        } catch (e) {
          debugPrint('[Sharing] Federation accept notify failed: $e');
        }
      }

      await loadAll();

      if (state.myUserId != null && otherUserId != null) {
        try {
          await crypto.setupDirectShare(state.myUserId!, otherUserId);
        } catch (e) {
          debugPrint('[Sharing] MLS direct share setup failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<void> rejectRequest(String requestId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.rejectRequest(requestId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<void> acceptZoneConsent(String ownerId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.acceptZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<void> rejectZoneConsent(String ownerId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.rejectZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<void> revokeZoneConsent(String ownerId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.revokeZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<void> removeShare(String userId) async {
    final api = ref.read(apiServiceProvider);
    try {
      await api.removeShare(userId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingNotifier error: $e');
    }
  }

  Future<Map<String, dynamic>> createTempShare(
    String toUserId,
    int durationMinutes, {
    String precision = 'exact',
  }) async {
    final api = ref.read(apiServiceProvider);
    return await api.createTempShare(toUserId, durationMinutes, precision: precision);
  }
}
