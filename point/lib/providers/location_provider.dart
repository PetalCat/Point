import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_update.dart';
import '../providers/ghost_provider.dart';
import '../services/crypto_service.dart';
import '../services/location_service.dart';
import '../services/ws_service.dart';

class TrailPoint {
  final double lat;
  final double lon;
  final int timestamp;
  TrailPoint(this.lat, this.lon, this.timestamp);
}

class PersonLocation {
  final String userId;
  final double lat;
  final double lon;
  final String sourceType;
  final int timestamp;
  final int? battery;
  final String? activity;
  final double? speed; // meters per second
  final bool online;
  final String precision; // 'exact', 'approximate', or 'city'

  PersonLocation({
    required this.userId,
    required this.lat,
    required this.lon,
    required this.sourceType,
    required this.timestamp,
    this.battery,
    this.activity,
    this.speed,
    this.online = true,
    this.precision = 'exact',
  });

  PersonLocation copyWith({
    double? lat,
    double? lon,
    String? sourceType,
    int? timestamp,
    int? battery,
    String? activity,
    double? speed,
    bool? online,
    String? precision,
  }) {
    return PersonLocation(
      userId: userId,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      sourceType: sourceType ?? this.sourceType,
      timestamp: timestamp ?? this.timestamp,
      battery: battery ?? this.battery,
      activity: activity ?? this.activity,
      speed: speed ?? this.speed,
      online: online ?? this.online,
      precision: precision ?? this.precision,
    );
  }
}

class LocationProvider extends ChangeNotifier {
  final WsService _wsService;
  final LocationService _locationService;
  final CryptoService _cryptoService;
  GhostProvider? _ghostProvider;
  final Battery _battery = Battery();

  final Map<String, PersonLocation> _people = {};
  final Map<String, List<TrailPoint>> _trails = {};
  String? _myUserId;
  Position? _myPosition;
  bool _isSharing = false;
  bool _ghostMode = false;
  List<String> _activeGroupIds = [];
  List<String> _activeUserIds = []; // direct person-to-person sharing
  List<Map<String, dynamic>> _places = [];
  final Set<String> _insidePlaces = {};
  // Track per-person per-place state for personal zones: personId -> set of placeIds
  final Map<String, Set<String>> _personInsidePlaces = {};
  // Only evaluate personal zones for users who have explicitly consented
  Set<String> _zoneConsentedUsers = {};

  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // Nudge system — request fresh location when actively viewing someone
  String? _viewingUserId;
  Timer? _nudgeTimer;
  final Map<String, DateTime> _lastNudge = {};
  DateTime? _lastLocationSent;

  final _geofenceEventsController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get geofenceEvents =>
      _geofenceEventsController.stream;

  Map<String, PersonLocation> get people => Map.unmodifiable(_people);
  Map<String, List<TrailPoint>> get trails => Map.unmodifiable(_trails);
  List<Map<String, dynamic>> get places => List.unmodifiable(_places);
  Position? get myPosition => _myPosition;
  bool get isSharing => _isSharing;
  DateTime? get lastLocationSent => _lastLocationSent;
  bool get isGhostMode => _ghostMode;

  void setMyUserId(String id) {
    _myUserId = id;
  }

  void setGhostProvider(GhostProvider gp) {
    _ghostProvider = gp;
  }

  LocationProvider(this._wsService, this._locationService, this._cryptoService) {
    _wsSubscription = _wsService.messages.listen(_handleWsMessage);
    _fetchInitialPosition();
  }

  Future<void> _fetchInitialPosition() async {
    try {
      final granted = await _locationService.requestPermission();
      if (!granted) return;
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        _myPosition = pos;
        notifyListeners();
      }
    } catch (_) {
      // Geolocation not available (e.g. web without HTTPS)
    }
  }

  void setActiveGroups(List<String> groupIds) {
    _activeGroupIds = List.from(groupIds);
  }

  void setActiveUserIds(List<String> userIds) {
    _activeUserIds = List.from(userIds);
  }

  void shareWithUser(String userId) {
    if (!_activeUserIds.contains(userId)) {
      _activeUserIds.add(userId);
    }
  }

  void stopSharingWithUser(String userId) {
    _activeUserIds.remove(userId);
  }

  void setPlaces(List<Map<String, dynamic>> places) {
    _places = List.from(places);
  }

  /// Start actively viewing a person — triggers nudge for fresh location.
  /// Continues nudging periodically while viewing, slowing down if they're still.
  void startViewing(String userId) {
    _viewingUserId = userId;
    _nudgeTimer?.cancel();
    // Send initial nudge
    _sendNudge(userId);
    // Schedule recurring nudges
    _scheduleNextNudge();
  }

  /// Stop viewing — cancel nudge timer.
  void stopViewing() {
    _viewingUserId = null;
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
  }

  void _sendNudge(String userId) {
    // Debounce: min 15 seconds between nudges to the same person
    final lastTime = _lastNudge[userId];
    if (lastTime != null && DateTime.now().difference(lastTime).inSeconds < 15) {
      return;
    }
    _wsService.requestFreshLocation(userId);
    _lastNudge[userId] = DateTime.now();
    debugPrint('[Location] Nudged $userId for fresh location');
  }

  void _scheduleNextNudge() {
    if (_viewingUserId == null) return;
    final userId = _viewingUserId!;
    final person = _people[userId];

    // Adaptive interval based on whether the person is moving
    Duration interval;
    if (person == null) {
      interval = const Duration(seconds: 15); // unknown state, nudge soon
    } else {
      final speed = person.speed ?? 0;
      final secSinceUpdate = DateTime.now().millisecondsSinceEpoch ~/ 1000 -
          (person.timestamp > 9999999999 ? person.timestamp ~/ 1000 : person.timestamp);

      if (speed > 1.0) {
        // Moving — nudge every 15s
        interval = const Duration(seconds: 15);
      } else if (secSinceUpdate < 120) {
        // Recently updated but still — nudge every 45s
        interval = const Duration(seconds: 45);
      } else {
        // Stale and still — nudge every 2 min
        interval = const Duration(minutes: 2);
      }
    }

    _nudgeTimer = Timer(interval, () {
      if (_viewingUserId == userId) {
        _sendNudge(userId);
        _scheduleNextNudge(); // reschedule
      }
    });
  }

  void setZoneConsentedUsers(List<String> userIds) {
    _zoneConsentedUsers = Set.from(userIds);
  }

  TrackingMode get trackingMode => _locationService.currentMode;

  Future<void> startSharing({TrackingMode mode = TrackingMode.adaptive}) async {
    try {
      final granted = await _locationService.requestPermission();
      if (!granted) return;

      _locationService.startTracking(mode: mode);
      _positionSubscription = _locationService.positions.listen(_onPosition);
      _isSharing = true;
      notifyListeners();
    } catch (_) {
      // Geolocation not available
    }
  }

  /// Switch tracking frequency (e.g. when following someone → realtime).
  void setTrackingMode(TrackingMode mode) {
    _locationService.setMode(mode);
    notifyListeners();
  }

  void stopSharing() {
    _locationService.stopTracking();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isSharing = false;
    _ghostMode = false;
    notifyListeners();
  }

  void toggleGhostMode() {
    _ghostMode = !_ghostMode;
    if (_ghostMode) {
      // Stop the location subscription but keep _isSharing true so it auto-resumes
      _locationService.stopTracking();
      _positionSubscription?.cancel();
      _positionSubscription = null;
    } else if (_isSharing) {
      // Resume with current tracking mode
      _locationService.startTracking(mode: _locationService.currentMode);
      _positionSubscription = _locationService.positions.listen(_onPosition);
    }
    notifyListeners();
  }

  void _onPosition(Position position) async {
    // Global ghost — stop all sharing
    final gp = _ghostProvider;
    final globalGhost = _ghostMode || (gp != null && gp.isGhostActive);
    if (globalGhost && gp != null && !gp.isGhostedForGroup('__any__')) {
      // Per-group ghost only — we still update position but skip ghosted groups below
    } else if (_ghostMode || (gp != null && gp.isGlobalGhostOn) || (gp != null && gp.hasActiveTimer)) {
      // Fully ghosted — don't send anything but still track our own position
      _myPosition = position;
      notifyListeners();
      return;
    }

    _myPosition = position;

    // Add own position to trail
    if (_myUserId != null && _myUserId!.isNotEmpty) {
      final trail = _trails.putIfAbsent(_myUserId!, () => []);
      final ts = position.timestamp.millisecondsSinceEpoch ~/ 1000;
      trail.add(TrailPoint(position.latitude, position.longitude, ts));
      final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1800;
      trail.removeWhere((p) => p.timestamp < cutoff);
    }

    notifyListeners();

    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      // Battery info unavailable on some platforms
    }

    // Feed battery to ghost provider for battery rules
    if (batteryLevel != null) {
      gp?.updateBattery(batteryLevel);
    }

    final locationData = LocationData(
      lat: position.latitude,
      lon: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      battery: batteryLevel,
      timestamp: position.timestamp.millisecondsSinceEpoch,
    );

    final locationJson = locationData.toJson();

    for (final groupId in _activeGroupIds) {
      // Per-group ghost check — skip groups that are ghosted by rules
      if (gp != null && gp.isGhostedForGroup(groupId)) {
        continue;
      }
      try {
        final blob = await _cryptoService.encrypt(groupId, locationJson);
        _wsService.sendLocationUpdate(
          recipientType: 'group',
          recipientId: groupId,
          encryptedBlob: blob,
          sourceType: 'gps',
          timestamp: locationData.timestamp,
        );
        _lastLocationSent = DateTime.now();
      } catch (e) {
        debugPrint('[Location] Encrypt failed for group $groupId: $e');
      }
    }

    for (final userId in _activeUserIds) {
      // Per-user ghost check via pairwise group
      if (gp != null && gp.isGhostedForGroup(userId)) {
        continue;
      }
      try {
        // Use pairwise MLS group ID for direct sharing encryption
        final encryptId = _myUserId != null
            ? _cryptoService.pairwiseGroupId(_myUserId!, userId)
            : userId;
        final blob = await _cryptoService.encrypt(encryptId, locationJson);
        _wsService.sendLocationUpdate(
          recipientType: 'user',
          recipientId: userId,
          encryptedBlob: blob,
          sourceType: 'gps',
          timestamp: locationData.timestamp,
        );
      } catch (e) {
        debugPrint('[Location] Encrypt failed for user $userId: $e');
      }
    }

    // Client-side geofence evaluation
    _checkGeofences(position.latitude, position.longitude);
  }

  void _checkGeofences(double lat, double lon) {
    for (final place in _places) {
      final placeId = place['id'] as String;
      final placeName = place['name'] as String? ?? '';
      final geometryType = place['geometry_type'] as String? ?? 'circle';

      final wasInside = _insidePlaces.contains(placeId);
      bool isInside;

      if (geometryType == 'polygon') {
        final points = place['polygon_points'] as List<dynamic>?;
        if (points == null || points.length < 3) continue;
        isInside = _isInsidePolygon(lat, lon, points);
      } else {
        final placeLat = (place['lat'] as num).toDouble();
        final placeLon = (place['lon'] as num).toDouble();
        final radius = (place['radius'] as num).toDouble();
        final distance = _haversineDistance(lat, lon, placeLat, placeLon);
        isInside = distance <= radius;
      }

      if (isInside && !wasInside) {
        _insidePlaces.add(placeId);
        _wsService.send({
          'type': 'place.triggered',
          'place_id': placeId,
          'place_name': placeName,
          'event': 'enter',
        });
        _geofenceEventsController.add({
          'event': 'enter',
          'place_name': placeName,
          'place_id': placeId,
        });
      } else if (!isInside && wasInside) {
        _insidePlaces.remove(placeId);
        _wsService.send({
          'type': 'place.triggered',
          'place_id': placeId,
          'place_name': placeName,
          'event': 'exit',
        });
        _geofenceEventsController.add({
          'event': 'exit',
          'place_name': placeName,
          'place_id': placeId,
        });
      }
    }
  }

  void _checkPersonAgainstPersonalZones(String userId, double lat, double lon) {
    // Only evaluate personal zones for users who have explicitly consented
    if (!_zoneConsentedUsers.contains(userId)) return;

    for (final place in _places) {
      if (place['is_personal'] != true) continue;
      final placeId = place['id'] as String;
      final placeName = place['name'] as String? ?? '';
      final geometryType = place['geometry_type'] as String? ?? 'circle';

      final personPlaces = _personInsidePlaces.putIfAbsent(userId, () => {});
      final wasInside = personPlaces.contains(placeId);
      bool isInside;

      if (geometryType == 'polygon') {
        final points = place['polygon_points'] as List<dynamic>?;
        if (points == null || points.length < 3) continue;
        isInside = _isInsidePolygon(lat, lon, points);
      } else {
        final placeLat = (place['lat'] as num).toDouble();
        final placeLon = (place['lon'] as num).toDouble();
        final radius = (place['radius'] as num).toDouble();
        final distance = _haversineDistance(lat, lon, placeLat, placeLon);
        isInside = distance <= radius;
      }

      if (isInside && !wasInside) {
        personPlaces.add(placeId);
        _wsService.send({
          'type': 'place.triggered',
          'place_id': placeId,
          'place_name': placeName,
          'event': 'enter',
          'triggered_by': userId,
        });
        _geofenceEventsController.add({
          'event': 'enter',
          'place_name': placeName,
          'place_id': placeId,
          'triggered_by': userId,
        });
      } else if (!isInside && wasInside) {
        personPlaces.remove(placeId);
        _wsService.send({
          'type': 'place.triggered',
          'place_id': placeId,
          'place_name': placeName,
          'event': 'exit',
          'triggered_by': userId,
        });
        _geofenceEventsController.add({
          'event': 'exit',
          'place_name': placeName,
          'place_id': placeId,
          'triggered_by': userId,
        });
      }
    }
  }

  /// Ray-casting point-in-polygon test.
  static bool _isInsidePolygon(double lat, double lon, List<dynamic> points) {
    int crossings = 0;
    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final aLat = (a['lat'] as num).toDouble();
      final aLon = (a['lon'] as num).toDouble();
      final bLat = (b['lat'] as num).toDouble();
      final bLon = (b['lon'] as num).toDouble();

      if ((aLon <= lon && bLon > lon) || (bLon <= lon && aLon > lon)) {
        final t = (lon - aLon) / (bLon - aLon);
        if (lat < aLat + t * (bLat - aLat)) {
          crossings++;
        }
      }
    }
    return crossings % 2 == 1;
  }

  /// Haversine distance in meters between two lat/lon points.
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  void _handleWsMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    if (type == 'location.broadcast' || type == 'location.update') {
      _handleLocationBroadcast(message);
    } else if (type == 'presence.broadcast' || type == 'presence.update') {
      _handlePresenceBroadcast(message);
    } else if (type == 'location.nudge') {
      // Someone is viewing us — send a fresh position immediately
      _handleNudge();
    }
  }

  /// Respond to a nudge by sending our current position immediately.
  void _handleNudge() {
    if (_myPosition != null && _isSharing && !_ghostMode) {
      debugPrint('[Location] Received nudge — sending fresh position');
      _onPosition(_myPosition!);
    }
  }

  void _handleLocationBroadcast(Map<String, dynamic> message) {
    final senderId = message['sender_id'] as String?;
    final blob = message['encrypted_blob'] as String?;
    final sourceType = message['source_type'] as String? ?? 'gps';
    final recipientType = message['recipient_type'] as String? ?? 'user';
    final recipientId = message['recipient_id'] as String? ?? senderId;

    if (senderId == null || blob == null) return;

    // For direct shares, use pairwise MLS group ID for decryption
    String decryptId;
    if (recipientType == 'user' && _myUserId != null) {
      decryptId = _cryptoService.pairwiseGroupId(_myUserId!, senderId);
    } else {
      decryptId = recipientId!;
    }

    _decryptAndProcessLocation(senderId, blob, sourceType, decryptId, message);
  }

  Future<void> _decryptAndProcessLocation(
    String senderId,
    String blob,
    String sourceType,
    String recipientId,
    Map<String, dynamic> message,
  ) async {
    try {
      final json = await _cryptoService.decrypt(recipientId, blob);
      final data = LocationData.fromJson(json);

      final existing = _people[senderId];
      final precision =
          (message['precision'] as String?) ?? existing?.precision ?? 'exact';
      _people[senderId] = PersonLocation(
        userId: senderId,
        lat: data.lat,
        lon: data.lon,
        sourceType: sourceType,
        timestamp: data.timestamp,
        battery: data.battery ?? existing?.battery,
        activity: data.activity ?? existing?.activity,
        speed: data.speed,
        online: true,
        precision: precision,
      );

      // Append to trail (normalize timestamp to seconds)
      final trail = _trails.putIfAbsent(senderId, () => []);
      final tsSec = data.timestamp > 9999999999
          ? data.timestamp ~/ 1000
          : data.timestamp;
      trail.add(TrailPoint(data.lat, data.lon, tsSec));
      final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1800;
      trail.removeWhere((p) => p.timestamp < cutoff);

      // Check if this person entered/exited any of our personal zones
      _checkPersonAgainstPersonalZones(senderId, data.lat, data.lon);

      notifyListeners();
    } catch (_) {
      // Ignore malformed location data
    }
  }

  void _handlePresenceBroadcast(Map<String, dynamic> message) {
    final senderId = (message['sender_id'] ?? message['user_id']) as String?;
    if (senderId == null) return;

    final battery = message['battery'] as int?;
    final activity = message['activity'] as String?;
    final online = message['online'] as bool? ?? true;

    final existing = _people[senderId];
    if (existing != null) {
      _people[senderId] = existing.copyWith(
        battery: battery,
        activity: activity,
        online: online,
      );
    } else {
      _people[senderId] = PersonLocation(
        userId: senderId,
        lat: 0,
        lon: 0,
        sourceType: 'unknown',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        battery: battery,
        activity: activity,
        online: online,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _positionSubscription?.cancel();
    _geofenceEventsController.close();
    super.dispose();
  }
}
