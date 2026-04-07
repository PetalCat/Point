import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/notification_service.dart';
import '../services/ws_service.dart';

class SharingProvider extends ChangeNotifier {
  final ApiService _api;
  CryptoService? _crypto;
  String? _myUserId;

  StreamSubscription? _wsSub;

  List<Map<String, dynamic>> _shares = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _outgoingRequests = [];
  List<Map<String, dynamic>> _incomingZoneConsents = [];
  bool _loading = false;

  List<Map<String, dynamic>> get shares => _shares;
  List<Map<String, dynamic>> get incomingRequests => _incomingRequests;
  List<Map<String, dynamic>> get outgoingRequests => _outgoingRequests;
  List<Map<String, dynamic>> get incomingZoneConsents => _incomingZoneConsents;
  int get pendingCount =>
      _incomingRequests.length + _incomingZoneConsents.length;
  bool get isLoading => _loading;

  SharingProvider(this._api);

  void setCryptoService(CryptoService crypto) {
    _crypto = crypto;
  }

  void setMyUserId(String userId) {
    _myUserId = userId;
  }

  /// Connect to WebSocket to listen for share events
  void listenToWs(WsService ws) {
    _wsSub?.cancel();
    _wsSub = ws.messages.listen(_handleWsMessage);
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'share.request' ||
        type == 'share.accepted' ||
        type == 'share.rejected') {
      // Auto-refresh when we get any share-related WS message
      loadAll();
    }
    if (type == 'share.request') {
      NotificationService.show(
        title: 'Share Request',
        body:
            '${msg['from_user_id']?.split('@').first} wants to share with you',
      );
    }
    // Zone consent WS events
    if (type == 'zone.consent_request' ||
        type == 'zone.consent_accepted' ||
        type == 'zone.consent_rejected') {
      loadAll();
    }
    if (type == 'zone.consent_request') {
      NotificationService.show(
        title: 'Zone Consent Request',
        body:
            '${msg['from_user_id']?.split('@').first} wants their zones to track your location',
      );
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      _shares = await _api.listShares();
      _incomingRequests = await _api.listIncomingRequests();
      _outgoingRequests = await _api.listOutgoingRequests();
      try {
        _incomingZoneConsents = await _api.listIncomingZoneConsents();
      } catch (_) {
        // Zone consent endpoint may not be available yet
      }
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> sendRequest(String toUserId) async {
    try {
      await _api.sendShareRequest(toUserId);
      await loadAll();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      // Find the request to get the other user's ID before accepting
      final request = _incomingRequests.firstWhere(
        (r) => r['id'] == requestId,
        orElse: () => <String, dynamic>{},
      );
      final otherUserId = request['from_user_id'] as String?;

      await _api.acceptRequest(requestId);
      await loadAll();

      // Set up MLS pairwise group for direct sharing
      if (_crypto != null && _myUserId != null && otherUserId != null) {
        try {
          await _crypto!.setupDirectShare(_myUserId!, otherUserId);
        } catch (e) {
          debugPrint('[Sharing] MLS direct share setup failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  Future<void> rejectRequest(String requestId) async {
    try {
      await _api.rejectRequest(requestId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  Future<void> acceptZoneConsent(String ownerId) async {
    try {
      await _api.acceptZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  Future<void> rejectZoneConsent(String ownerId) async {
    try {
      await _api.rejectZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  Future<void> revokeZoneConsent(String ownerId) async {
    try {
      await _api.revokeZoneConsent(ownerId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  Future<void> removeShare(String userId) async {
    try {
      await _api.removeShare(userId);
      await loadAll();
    } catch (e) {
      debugPrint('SharingProvider error: $e');
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
