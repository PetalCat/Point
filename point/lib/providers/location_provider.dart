import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_update.dart';
import '../providers.dart';
import '../services/location_service.dart';
import '../services/native_geofence_service.dart';
import '../services/relay_buffer.dart';

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
  final bool? charging;
  final String? activity;
  final double? speed;
  final bool online;
  final String precision;

  PersonLocation({
    required this.userId,
    required this.lat,
    required this.lon,
    required this.sourceType,
    required this.timestamp,
    this.battery,
    this.charging,
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
    bool? charging,
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
      charging: charging ?? this.charging,
      activity: activity ?? this.activity,
      speed: speed ?? this.speed,
      online: online ?? this.online,
      precision: precision ?? this.precision,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId, 'lat': lat, 'lon': lon, 'sourceType': sourceType,
    'timestamp': timestamp, 'battery': battery, 'charging': charging, 'activity': activity,
    'speed': speed, 'precision': precision,
  };

  factory PersonLocation.fromJson(Map<String, dynamic> j) => PersonLocation(
    userId: j['userId'] ?? '',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    sourceType: j['sourceType'] ?? 'cached',
    timestamp: j['timestamp'] ?? 0,
    battery: j['battery'],
    charging: j['charging'],
    activity: j['activity'],
    speed: (j['speed'] as num?)?.toDouble(),
    online: false, // cached people are offline until confirmed
    precision: j['precision'] ?? 'exact',
  );
}

class LocationState {
  final Map<String, PersonLocation> people;
  final Map<String, List<TrailPoint>> trails;
  final Position? myPosition;
  final bool isGhostMode;
  final List<Map<String, dynamic>> places;
  final String? viewingUserId;
  final DateTime? lastLocationSent;
  final String? myUserId;
  final List<String> activeGroupIds;
  final List<String> activeUserIds;
  final Set<String> zoneConsentedUsers;
  final LocationActivity activity;
  final LearnedZone? currentZone;

  /// Derived: sharing is active when the activity state implies relay.
  bool get isSharing =>
      activity == LocationActivity.active ||
      activity == LocationActivity.fast;

  const LocationState({
    this.people = const {},
    this.trails = const {},
    this.myPosition,
    this.isGhostMode = false,
    this.places = const [],
    this.viewingUserId,
    this.lastLocationSent,
    this.myUserId,
    this.activeGroupIds = const [],
    this.activeUserIds = const [],
    this.zoneConsentedUsers = const {},
    this.activity = LocationActivity.sleeping,
    this.currentZone,
  });

  LocationState copyWith({
    Map<String, PersonLocation>? people,
    Map<String, List<TrailPoint>>? trails,
    Position? myPosition,
    bool? isGhostMode,
    List<Map<String, dynamic>>? places,
    String? viewingUserId,
    DateTime? lastLocationSent,
    String? myUserId,
    List<String>? activeGroupIds,
    List<String>? activeUserIds,
    Set<String>? zoneConsentedUsers,
    LocationActivity? activity,
    LearnedZone? currentZone,
    bool clearViewingUserId = false,
    bool clearMyPosition = false,
    bool clearCurrentZone = false,
  }) {
    return LocationState(
      people: people ?? this.people,
      trails: trails ?? this.trails,
      myPosition: clearMyPosition ? null : (myPosition ?? this.myPosition),
      isGhostMode: isGhostMode ?? this.isGhostMode,
      places: places ?? this.places,
      viewingUserId:
          clearViewingUserId ? null : (viewingUserId ?? this.viewingUserId),
      lastLocationSent: lastLocationSent ?? this.lastLocationSent,
      myUserId: myUserId ?? this.myUserId,
      activeGroupIds: activeGroupIds ?? this.activeGroupIds,
      activeUserIds: activeUserIds ?? this.activeUserIds,
      zoneConsentedUsers: zoneConsentedUsers ?? this.zoneConsentedUsers,
      activity: activity ?? this.activity,
      currentZone: clearCurrentZone ? null : (currentZone ?? this.currentZone),
    );
  }
}

class LocationNotifier extends Notifier<LocationState> {
  final Battery _battery = Battery();
  final Set<String> _insidePlaces = {};
  final Map<String, Set<String>> _personInsidePlaces = {};
  final Map<String, DateTime> _lastNudge = {};

  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<LocationActivity>? _activitySubscription;
  StreamSubscription<String>? _geofenceExitSubscription;
  Timer? _nudgeTimer;
  Timer? _relayTimer;
  Timer? _zoneCheckTimer;

  /// Last position captured from the GPS stream, used by the relay tick.
  Position? _lastPosition;

  /// Position that was last relayed to the server (for distance threshold).
  Position? _lastRelayedPosition;

  /// Minimum distance (meters) the device must move before relaying again.
  static const double _relayDistanceThreshold = 5.0;

  /// How often to check if we've left a learned zone while in-zone.
  /// Catches the case where the OS didn't fire the geofence exit or GPS was asleep.
  static const Duration _zoneCheckInterval = Duration(minutes: 10);

  /// Auto-flush interval for background batching.
  static const Duration _backgroundFlushInterval = Duration(seconds: 30);

  /// Whether the app is currently backgrounded.
  bool _isBackgrounded = false;

  /// Buffer for batching location fixes in background mode.
  late final RelayBuffer _relayBuffer;

  /// Zone learning service — detects and manages auto-learned places.
  late final ZoneLearningService _zoneLearningService;

  /// Native OS geofence service — survives app sleep/kill.
  late final NativeGeofenceService _nativeGeofenceService;

  /// Whether we were inside a learned zone on the previous fix (for enter/exit detection).
  bool _wasInZone = false;

  final _geofenceEventsController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get geofenceEvents =>
      _geofenceEventsController.stream;

  // ---------------------------------------------------------------------------
  // Build / lifecycle
  // ---------------------------------------------------------------------------

  @override
  LocationState build() {
    final wsService = ref.read(wsServiceProvider);
    final locationService = ref.read(locationServiceProvider);
    _relayBuffer = ref.read(relayBufferProvider);
    _zoneLearningService = ref.read(zoneLearningServiceProvider);
    _nativeGeofenceService = ref.read(nativeGeofenceServiceProvider);

    // Listen for WS messages (location broadcasts, presence, nudges).
    _wsSubscription = wsService.messages.listen(_handleWsMessage);

    // Listen for GPS positions — every fix updates the map immediately.
    _positionSubscription = locationService.positions.listen(_onPosition);

    // Listen for activity state changes — controls relay cadence.
    _activitySubscription =
        locationService.activityChanges.listen(_onActivityChange);

    // Listen for OS-level geofence exit events (survives app sleep/doze).
    _geofenceExitSubscription =
        _nativeGeofenceService.onZoneExit.listen(_onOsGeofenceExit);

    // Load cached state first so everyone appears immediately on launch.
    _loadCache();

    // Then fetch fresh own position.
    _fetchInitialPosition();

    ref.onDispose(() {
      _wsSubscription?.cancel();
      _positionSubscription?.cancel();
      _activitySubscription?.cancel();
      _geofenceExitSubscription?.cancel();
      _nudgeTimer?.cancel();
      _relayTimer?.cancel();
      _zoneCheckTimer?.cancel();
      _relayBuffer.dispose();
      _geofenceEventsController.close();
      _lastCacheSave = null; // force save on dispose
      _saveCache();
    });

    return const LocationState();
  }

  // ---------------------------------------------------------------------------
  // Position cache — instant load on app start
  // ---------------------------------------------------------------------------

  static const _cacheKey = 'location_cache';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      // Restore people
      final peopleJson = data['people'] as Map<String, dynamic>? ?? {};
      final people = <String, PersonLocation>{};
      for (final entry in peopleJson.entries) {
        people[entry.key] = PersonLocation.fromJson(entry.value);
      }

      // Restore own position
      final myLat = data['myLat'] as double?;
      final myLon = data['myLon'] as double?;

      if (people.isNotEmpty || myLat != null) {
        state = state.copyWith(
          people: people,
          myPosition: myLat != null && myLon != null
              ? Position(
                  latitude: myLat, longitude: myLon,
                  timestamp: DateTime.now(), accuracy: 0, altitude: 0,
                  altitudeAccuracy: 0, heading: 0, headingAccuracy: 0,
                  speed: 0, speedAccuracy: 0,
                )
              : null,
        );
        debugPrint('[Location] Loaded ${people.length} cached people');
      }
    } catch (e) {
      debugPrint('[Location] Cache load failed: $e');
    }
  }

  DateTime? _lastCacheSave;

  Future<void> _saveCache() async {
    // Debounce: save at most once per 30 seconds to avoid disk I/O lag
    final now = DateTime.now();
    if (_lastCacheSave != null && now.difference(_lastCacheSave!).inSeconds < 30) return;
    _lastCacheSave = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final peopleJson = <String, dynamic>{};
      for (final entry in state.people.entries) {
        peopleJson[entry.key] = entry.value.toJson();
      }
      final data = <String, dynamic>{
        'people': peopleJson,
        if (state.myPosition != null) 'myLat': state.myPosition!.latitude,
        if (state.myPosition != null) 'myLon': state.myPosition!.longitude,
      };
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[Location] Cache save failed: $e');
    }
  }

  Future<void> _fetchInitialPosition() async {
    final locationService = ref.read(locationServiceProvider);
    try {
      final granted = await locationService.requestPermission();
      if (!granted) return;
      final pos = await locationService.getCurrentPosition();
      if (pos != null) {
        _lastPosition = pos;
        state = state.copyWith(myPosition: pos);
        // Always relay initial position so others see us immediately
        _relayTick();
        debugPrint('[Location] Initial position relayed: ${pos.latitude.toStringAsFixed(4)},${pos.longitude.toStringAsFixed(4)}');

        // Re-establish zone state after app restart (e.g., update, reboot, OOM kill).
        // OS geofences survive app restarts but are cleared on reboot, so re-register.
        final zone = _zoneLearningService.getZoneAt(pos.latitude, pos.longitude);
        if (zone != null && zone.confidence >= 50) {
          debugPrint('[Zones] App restart inside "${zone.displayName}" — re-registering');
          _wasInZone = true;
          state = state.copyWith(currentZone: zone);
          _startZoneCheckTimer();
          _registerOsGeofence(zone);
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Position listener (every GPS fix — for smooth map rendering)
  // ---------------------------------------------------------------------------

  void _onPosition(Position position) {
    _lastPosition = position;
    debugPrint('[Location] Fix: ${position.latitude.toStringAsFixed(5)},${position.longitude.toStringAsFixed(5)} speed=${position.speed.toStringAsFixed(1)}');

    final ghostState = ref.read(ghostProvider);
    final globalGhost = state.isGhostMode || ghostState.isGhostActive;

    // In ghost mode: update own position for local map rendering only.
    if (globalGhost && !ghostState.isGhostedForGroup('__any__')) {
      // Per-group ghost only — still update local state below.
    } else if (state.isGhostMode ||
        ghostState.isGlobalGhostOn ||
        ghostState.hasActiveTimer) {
      state = state.copyWith(myPosition: position);
      return;
    }

    // Update own trail.
    final newTrails = Map<String, List<TrailPoint>>.from(state.trails);
    if (state.myUserId != null && state.myUserId!.isNotEmpty) {
      final trail = List<TrailPoint>.from(newTrails[state.myUserId!] ?? []);
      final ts = position.timestamp.millisecondsSinceEpoch ~/ 1000;
      trail.add(TrailPoint(position.latitude, position.longitude, ts));
      final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1800;
      trail.removeWhere((p) => p.timestamp < cutoff);
      newTrails[state.myUserId!] = trail;
    }

    state = state.copyWith(myPosition: position, trails: newTrails);

    // Feed position to zone learning service (dwell detection & zone refinement).
    _zoneLearningService.onPositionUpdate(position.latitude, position.longitude);

    // Check if we're inside a learned zone.
    // Entry uses base radius (isInside), exit uses 1.2x radius (isOutside)
    // to prevent flickering at the boundary.
    final zone = _zoneLearningService.getZoneAt(position.latitude, position.longitude);
    final nowInZone = zone != null && zone.confidence >= 50;

    if (nowInZone && !_wasInZone) {
      // Just entered a zone — relay zone center once, then suppress.
      debugPrint('[Zones] Entered "${zone!.displayName}" — relaying zone center, then suppressing');
      state = state.copyWith(currentZone: zone);
      _relayTick(); // one last relay with current position
      _wasInZone = true;
      _startZoneCheckTimer();
      _registerOsGeofence(zone);
    } else if (_wasInZone) {
      // Check exit with hysteresis — must be clearly outside (1.2x radius).
      final currentZone = state.currentZone;
      final leftZone = currentZone != null &&
          currentZone.isOutside(position.latitude, position.longitude);

      if (leftZone) {
        debugPrint('[Zones] Left zone (hysteresis) — waking GPS for departure relay');
        _handleZoneExit();
      } else {
        // Still inside zone (or within hysteresis band) — update state but don't relay.
        if (zone != null) state = state.copyWith(currentZone: zone);
      }
    }

    // In IDLE/SLEEPING: relay if position changed significantly (>10m)
    // This ensures contacts see your initial position even when you're not "active"
    // Skip if we're inside a learned zone (relay suppressed).
    if (!nowInZone &&
        (state.activity == LocationActivity.idle || state.activity == LocationActivity.sleeping)) {
      if (_shouldRelayPositionChange(position)) {
        _relayTick();
      }
    }

    // Evaluate geofences on every fix.
    _checkGeofences(position.latitude, position.longitude);
  }

  // ---------------------------------------------------------------------------
  // Activity change listener (controls relay timer)
  // ---------------------------------------------------------------------------

  void _onActivityChange(LocationActivity activity) {
    state = state.copyWith(activity: activity);
    _configureRelayTimer(activity);
  }

  void _configureRelayTimer(LocationActivity activity) {
    _relayTimer?.cancel();
    _relayTimer = null;

    switch (activity) {
      case LocationActivity.sleeping:
        // Flush any remaining buffered fixes before sleeping.
        if (_relayBuffer.isNotEmpty) {
          _flushBatch(_relayBuffer.flush());
        }
        _relayBuffer.stopAutoFlush();
        break;
      case LocationActivity.idle:
        // Relay once on entering idle (so server has current pos),
        // then relay on position changes only (no fixed timer)
        _relayTick();
        break;
      case LocationActivity.active:
        _relayTimer =
            Timer.periodic(const Duration(seconds: 3), (_) => _relayTick());
        break;
      case LocationActivity.fast:
        _relayTimer =
            Timer.periodic(const Duration(seconds: 5), (_) => _relayTick());
        break;
      case LocationActivity.ghost:
        // Relay blocked.
        break;
    }
  }

  bool _shouldRelayPositionChange(Position position) {
    if (_lastRelayedPosition == null) return true;
    // Relay if moved >10m since last relay
    final dlat = position.latitude - _lastRelayedPosition!.latitude;
    final dlon = position.longitude - _lastRelayedPosition!.longitude;
    // ~10m in degrees at mid-latitudes
    return (dlat * dlat + dlon * dlon) > 0.0001 * 0.0001;
  }

  // ---------------------------------------------------------------------------
  // Relay tick (sends encrypted position to server at activity-dependent rate)
  // ---------------------------------------------------------------------------

  /// Relay current position to all recipients.
  ///
  /// When [force] is true, bypasses zone suppression and distance checks.
  /// Used by the zone heartbeat to ensure contacts always see a fresh position.
  Future<void> _relayTick({bool force = false}) async {
    final position = _lastPosition;
    if (position == null) return;

    // Ghost mode blocks all relay.
    final ghostState = ref.read(ghostProvider);
    if (state.isGhostMode ||
        ghostState.isGlobalGhostOn ||
        ghostState.hasActiveTimer) {
      return;
    }

    // Zone suppression: if inside a learned zone with high confidence,
    // skip relay (server already has zone center from the entry relay).
    if (!force &&
        _wasInZone &&
        _zoneLearningService.shouldSuppressRelay(
            position.latitude, position.longitude)) {
      return;
    }

    // In active/fast: always relay (timer already gates the frequency).
    // In idle/sleeping: only relay on significant movement.
    if (!force &&
        state.activity != LocationActivity.active &&
        state.activity != LocationActivity.fast &&
        _lastRelayedPosition != null) {
      final dist = _haversineDistance(
        position.latitude,
        position.longitude,
        _lastRelayedPosition!.latitude,
        _lastRelayedPosition!.longitude,
      );
      if (dist < _relayDistanceThreshold) return;
    }

    _lastRelayedPosition = position;

    // Read battery level and charging state.
    int? batteryLevel;
    bool? isCharging;
    try {
      batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      isCharging = batteryState == BatteryState.charging ||
          batteryState == BatteryState.full;
    } catch (_) {}

    if (batteryLevel != null) {
      ref.read(ghostProvider.notifier).updateBattery(batteryLevel);
    }

    final locationData = LocationData(
      lat: position.latitude,
      lon: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      battery: batteryLevel,
      charging: isCharging,
      timestamp: position.timestamp.millisecondsSinceEpoch,
    );

    // Background mode: buffer fixes for batched send (fewer radio wakes).
    if (_isBackgrounded) {
      _relayBuffer.add(locationData, onOverflow: _flushBatch);
      return;
    }

    // Foreground mode: send immediately.
    _sendSingleFix(locationData);
  }

  /// Send a single location fix to all active recipients (foreground path).
  Future<void> _sendSingleFix(LocationData locationData) async {
    final ghostState = ref.read(ghostProvider);
    final locationJson = locationData.toJson();
    final cryptoService = ref.read(cryptoServiceProvider);
    final wsService = ref.read(wsServiceProvider);

    // Relay to active groups.
    for (final groupId in state.activeGroupIds) {
      if (ghostState.isGhostedForGroup(groupId)) continue;
      try {
        final blob = await cryptoService.encrypt(groupId, locationJson);
        wsService.sendLocationUpdate(
          recipientType: 'group',
          recipientId: groupId,
          encryptedBlob: blob,
          sourceType: 'gps',
          timestamp: locationData.timestamp,
        );
        state = state.copyWith(lastLocationSent: DateTime.now());
      } catch (e) {
        debugPrint('[Location] Encrypt failed for group $groupId: $e');
      }
    }

    // Relay to active users (direct shares).
    for (final userId in state.activeUserIds) {
      if (ghostState.isGhostedForGroup(userId)) continue;
      try {
        final encryptId = state.myUserId != null
            ? cryptoService.pairwiseGroupId(state.myUserId!, userId)
            : userId;
        final blob = await cryptoService.encrypt(encryptId, locationJson);
        if (blob == null) continue; // MLS not ready for this pair yet
        wsService.sendLocationUpdate(
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
  }

  /// Flush a batch of buffered fixes -- encrypt each individually and send as
  /// a single `location.batch_update` message per recipient.
  Future<void> _flushBatch(List<LocationData> batch) async {
    if (batch.isEmpty) return;

    final ghostState = ref.read(ghostProvider);
    if (state.isGhostMode ||
        ghostState.isGlobalGhostOn ||
        ghostState.hasActiveTimer) {
      return;
    }

    final cryptoService = ref.read(cryptoServiceProvider);
    final wsService = ref.read(wsServiceProvider);

    // Each fix is encrypted individually (MLS requires per-message encryption).
    for (final groupId in state.activeGroupIds) {
      if (ghostState.isGhostedForGroup(groupId)) continue;
      try {
        final blobs = <String>[];
        final timestamps = <int>[];
        for (final fix in batch) {
          final blob = await cryptoService.encrypt(groupId, fix.toJson());
          blobs.add(blob);
          timestamps.add(fix.timestamp);
        }
        wsService.sendBatchLocationUpdate(
          recipientType: 'group',
          recipientId: groupId,
          encryptedBlobs: blobs,
          sourceType: 'gps',
          timestamps: timestamps,
        );
        state = state.copyWith(lastLocationSent: DateTime.now());
      } catch (e) {
        debugPrint('[Location] Batch encrypt failed for group $groupId: $e');
      }
    }

    for (final userId in state.activeUserIds) {
      if (ghostState.isGhostedForGroup(userId)) continue;
      try {
        final encryptId = state.myUserId != null
            ? cryptoService.pairwiseGroupId(state.myUserId!, userId)
            : userId;
        final blobs = <String>[];
        final timestamps = <int>[];
        for (final fix in batch) {
          final blob = await cryptoService.encrypt(encryptId, fix.toJson());
          blobs.add(blob);
          timestamps.add(fix.timestamp);
        }
        wsService.sendBatchLocationUpdate(
          recipientType: 'user',
          recipientId: userId,
          encryptedBlobs: blobs,
          sourceType: 'gps',
          timestamps: timestamps,
        );
      } catch (e) {
        debugPrint('[Location] Batch encrypt failed for user $userId: $e');
      }
    }

    debugPrint('[Location] Flushed batch of ${batch.length} fixes');
  }

  // ---------------------------------------------------------------------------
  // Zone check heartbeat (10-min fallback for zone exit detection)
  // ---------------------------------------------------------------------------

  void _startZoneCheckTimer() {
    _zoneCheckTimer?.cancel();
    _zoneCheckTimer =
        Timer.periodic(_zoneCheckInterval, (_) => _zoneCheckTick());
    debugPrint(
        '[Zones] Zone check heartbeat started (${_zoneCheckInterval.inMinutes}min)');
  }

  void _stopZoneCheckTimer() {
    _zoneCheckTimer?.cancel();
    _zoneCheckTimer = null;
  }

  Future<void> _zoneCheckTick() async {
    if (!_wasInZone) return;

    final locationService = ref.read(locationServiceProvider);
    final pos = await locationService.getCurrentPosition();
    if (pos == null) return;

    debugPrint('[Zones] Zone check: '
        '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}');

    // Use hysteresis (1.2x radius) for exit — same as GPS-based detection.
    final currentZone = state.currentZone;
    final leftZone = currentZone != null &&
        currentZone.isOutside(pos.latitude, pos.longitude);

    _lastPosition = pos;
    state = state.copyWith(myPosition: pos);

    if (leftZone) {
      debugPrint('[Zones] Zone check detected exit');
      _handleZoneExit();
    } else {
      // Still in zone — force a relay so contacts see a fresh timestamp
      // instead of a stale position from hours ago.
      _relayTick(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Zone exit (shared by GPS-based detection, heartbeat, and OS geofence)
  // ---------------------------------------------------------------------------

  void _handleZoneExit() {
    state = state.copyWith(clearCurrentZone: true);
    _wasInZone = false;
    _stopZoneCheckTimer();
    _nativeGeofenceService.unregisterAll();
    final locationService = ref.read(locationServiceProvider);
    locationService.wake(WakeReason.movement);
    _relayTick(); // relay departure position
  }

  // ---------------------------------------------------------------------------
  // OS-level geofence (survives app sleep/kill via Android GeofencingClient)
  // ---------------------------------------------------------------------------

  void _registerOsGeofence(LearnedZone zone) {
    // Use 1.2x radius to match the exit hysteresis — the OS should fire
    // only after the user is clearly outside, not at the boundary.
    _nativeGeofenceService.registerZone(
      id: zone.id,
      lat: zone.lat,
      lon: zone.lon,
      radius: zone.radius * 1.2,
    );
  }

  void _onOsGeofenceExit(String zoneId) {
    if (!_wasInZone) return;
    debugPrint('[Zones] OS geofence exit for zone $zoneId — triggering exit');

    // Get a fresh fix and relay it.
    final locationService = ref.read(locationServiceProvider);
    locationService.getCurrentPosition().then((pos) {
      if (pos != null) {
        _lastPosition = pos;
        state = state.copyWith(myPosition: pos);
      }
      _handleZoneExit();
    });
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void setMyUserId(String id) {
    state = state.copyWith(myUserId: id);
  }

  /// Called when the app transitions between foreground and background.
  /// In background mode, location fixes are buffered and sent in batches
  /// every 30 seconds to reduce radio wakes and save battery.
  void setBackgrounded(bool backgrounded) {
    if (_isBackgrounded == backgrounded) return;
    _isBackgrounded = backgrounded;

    if (backgrounded) {
      // Entering background: start auto-flush timer.
      debugPrint('[Location] Entering background — starting batch relay (${_backgroundFlushInterval.inSeconds}s)');
      _relayBuffer.startAutoFlush(_backgroundFlushInterval, _flushBatch);
    } else {
      // Returning to foreground: flush any buffered fixes immediately and
      // switch back to direct relay.
      debugPrint('[Location] Returning to foreground — flushing buffer and resuming direct relay');
      _relayBuffer.stopAutoFlush();
      if (_relayBuffer.isNotEmpty) {
        _flushBatch(_relayBuffer.flush());
      }
    }
  }

  void setActiveGroups(List<String> groupIds) {
    state = state.copyWith(activeGroupIds: List.from(groupIds));
    _autoWake();
  }

  void setActiveUserIds(List<String> userIds) {
    state = state.copyWith(activeUserIds: List.from(userIds));
    _autoWake();
  }

  /// When active groups/users are set, wake the location service so GPS starts
  /// producing fixes (which flow through the position listener and get relayed
  /// on the activity-dependent timer).
  void _autoWake() {
    final locationService = ref.read(locationServiceProvider);
    locationService.hasActiveShares =
        state.activeGroupIds.isNotEmpty || state.activeUserIds.isNotEmpty;

    if (state.activeGroupIds.isNotEmpty || state.activeUserIds.isNotEmpty) {
      final locationService = ref.read(locationServiceProvider);
      locationService.wake(WakeReason.movement);
    }
  }

  void shareWithUser(String userId) {
    if (!state.activeUserIds.contains(userId)) {
      state = state.copyWith(activeUserIds: [...state.activeUserIds, userId]);
    }
  }

  void stopSharingWithUser(String userId) {
    state = state.copyWith(
      activeUserIds: state.activeUserIds.where((id) => id != userId).toList(),
    );
  }

  void setPlaces(List<Map<String, dynamic>> places) {
    state = state.copyWith(places: List.from(places));
  }

  /// Load all places (group + personal) and set them in state.
  Future<void> loadPlaces(List<String> groupIds) async {
    final api = ref.read(apiServiceProvider);
    final allPlaces = <Map<String, dynamic>>[];
    for (final gId in groupIds) {
      try {
        final places = await api.listPlaces(gId);
        allPlaces.addAll(places);
      } catch (_) {}
    }
    try {
      final personalPlaces = await api.listPersonalPlaces();
      allPlaces.addAll(personalPlaces);
    } catch (_) {}
    state = state.copyWith(places: List.from(allPlaces));
  }

  /// Fetch location history for a user.
  Future<List<Map<String, dynamic>>> getHistory(
    String userId, {
    int? since,
    int limit = 100,
  }) async {
    final api = ref.read(apiServiceProvider);
    return await api.getHistory(userId, since: since, limit: limit);
  }

  /// Create a group place (geofence).
  Future<Map<String, dynamic>> createPlace(
    String groupId,
    String name, {
    String geometryType = 'circle',
    double? lat,
    double? lon,
    double? radius,
    List<Map<String, double>>? polygonPoints,
  }) async {
    final api = ref.read(apiServiceProvider);
    return await api.createPlace(
      groupId,
      name,
      geometryType: geometryType,
      lat: lat,
      lon: lon,
      radius: radius,
      polygonPoints: polygonPoints,
    );
  }

  /// Create a personal place (geofence).
  Future<Map<String, dynamic>> createPersonalPlace(
    String name, {
    String geometryType = 'circle',
    double? lat,
    double? lon,
    double? radius,
    List<Map<String, double>>? polygonPoints,
  }) async {
    final api = ref.read(apiServiceProvider);
    return await api.createPersonalPlace(
      name,
      geometryType: geometryType,
      lat: lat,
      lon: lon,
      radius: radius,
      polygonPoints: polygonPoints,
    );
  }

  void setZoneConsentedUsers(List<String> userIds) {
    state = state.copyWith(zoneConsentedUsers: Set.from(userIds));
  }

  /// Load granted zone consents from the server.
  Future<void> loadZoneConsents() async {
    final api = ref.read(apiServiceProvider);
    final grantedConsents = await api.listGrantedZoneConsents();
    setZoneConsentedUsers(
      grantedConsents.map((c) => c['consenter_id'] as String).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Ghost mode
  // ---------------------------------------------------------------------------

  void toggleGhostMode() {
    final newGhostMode = !state.isGhostMode;
    state = state.copyWith(isGhostMode: newGhostMode);

    if (newGhostMode) {
      // Kill relay timer immediately — GHOST blocks all outbound.
      _relayTimer?.cancel();
      _relayTimer = null;
    } else {
      // Resuming from ghost — reconfigure relay based on current activity.
      _configureRelayTimer(state.activity);
    }
  }

  // ---------------------------------------------------------------------------
  // Viewing / nudge system
  // ---------------------------------------------------------------------------

  /// Start actively viewing a person.
  void startViewing(String userId) {
    state = state.copyWith(viewingUserId: userId);
    _nudgeTimer?.cancel();
    _sendNudge(userId);
    _scheduleNextNudge();
  }

  void stopViewing() {
    state = state.copyWith(clearViewingUserId: true);
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
  }

  void _sendNudge(String userId) {
    final wsService = ref.read(wsServiceProvider);
    final lastTime = _lastNudge[userId];
    if (lastTime != null &&
        DateTime.now().difference(lastTime).inSeconds < 15) {
      return;
    }
    wsService.requestFreshLocation(userId);
    _lastNudge[userId] = DateTime.now();
    debugPrint('[Location] Nudged $userId for fresh location');
  }

  void _scheduleNextNudge() {
    final viewingUserId = state.viewingUserId;
    if (viewingUserId == null) return;
    final person = state.people[viewingUserId];

    Duration interval;
    if (person == null) {
      interval = const Duration(seconds: 15);
    } else {
      final speed = person.speed ?? 0;
      final secSinceUpdate = DateTime.now().millisecondsSinceEpoch ~/ 1000 -
          (person.timestamp > 9999999999
              ? person.timestamp ~/ 1000
              : person.timestamp);

      if (speed > 1.0) {
        interval = const Duration(seconds: 15);
      } else if (secSinceUpdate < 120) {
        interval = const Duration(seconds: 45);
      } else {
        interval = const Duration(minutes: 2);
      }
    }

    _nudgeTimer = Timer(interval, () {
      if (state.viewingUserId == viewingUserId) {
        _sendNudge(viewingUserId);
        _scheduleNextNudge();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // WS message handling
  // ---------------------------------------------------------------------------

  void _handleWsMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    if (type == 'location.broadcast' || type == 'location.update') {
      _handleLocationBroadcast(message);
    } else if (type == 'presence.broadcast' || type == 'presence.update') {
      _handlePresenceBroadcast(message);
    } else if (type == 'location.nudge') {
      _handleNudge();
    }
  }

  void _handleNudge() {
    if (state.isGhostMode) return;

    final locationService = ref.read(locationServiceProvider);
    locationService.wake(WakeReason.nudge);
    debugPrint('[Location] Received nudge — waking for fresh fix');

    // Nudges must bypass zone suppression — someone is actively looking
    // at our position and wants a fresh fix, not a stale zone center.
    locationService.getCurrentPosition().then((pos) {
      if (pos != null) {
        _lastPosition = pos;
        state = state.copyWith(myPosition: pos);
        _relayTick(force: true);
      }
    });
  }

  void _handleLocationBroadcast(Map<String, dynamic> message) {
    final senderId = message['sender_id'] as String?;
    final blob = message['encrypted_blob'] as String?;
    final sourceType = message['source_type'] as String? ?? 'gps';
    final recipientType = message['recipient_type'] as String? ?? 'user';
    final recipientId = message['recipient_id'] as String? ?? senderId;

    if (senderId == null || blob == null) return;

    final cryptoService = ref.read(cryptoServiceProvider);
    String decryptId;
    if (recipientType == 'user' && state.myUserId != null) {
      decryptId = cryptoService.pairwiseGroupId(state.myUserId!, senderId);
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
    final cryptoService = ref.read(cryptoServiceProvider);
    try {
      final json = await cryptoService.decrypt(recipientId, blob);
      final data = LocationData.fromJson(json);

      final newPeople = Map<String, PersonLocation>.from(state.people);
      final newTrails = Map<String, List<TrailPoint>>.from(state.trails);

      final existing = newPeople[senderId];
      final precision =
          (message['precision'] as String?) ?? existing?.precision ?? 'exact';
      newPeople[senderId] = PersonLocation(
        userId: senderId,
        lat: data.lat,
        lon: data.lon,
        sourceType: sourceType,
        timestamp: data.timestamp,
        battery: data.battery ?? existing?.battery,
        charging: data.charging ?? existing?.charging,
        activity: data.activity ?? existing?.activity,
        speed: data.speed,
        online: true,
        precision: precision,
      );

      final trail = List<TrailPoint>.from(newTrails[senderId] ?? []);
      final tsSec = data.timestamp > 9999999999
          ? data.timestamp ~/ 1000
          : data.timestamp;
      trail.add(TrailPoint(data.lat, data.lon, tsSec));
      final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1800;
      trail.removeWhere((p) => p.timestamp < cutoff);
      newTrails[senderId] = trail;

      state = state.copyWith(people: newPeople, trails: newTrails);
      _saveCache(); // persist for instant next launch

      _checkPersonAgainstPersonalZones(senderId, data.lat, data.lon);
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

    final newPeople = Map<String, PersonLocation>.from(state.people);
    final existing = newPeople[senderId];
    if (existing != null) {
      newPeople[senderId] = existing.copyWith(
        battery: battery,
        activity: activity,
        online: online,
      );
    } else {
      newPeople[senderId] = PersonLocation(
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
    state = state.copyWith(people: newPeople);
  }

  // ---------------------------------------------------------------------------
  // Geofence evaluation
  // ---------------------------------------------------------------------------

  void _checkGeofences(double lat, double lon) {
    final wsService = ref.read(wsServiceProvider);
    for (final place in state.places) {
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
        wsService.send({
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
        wsService.send({
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
    if (!state.zoneConsentedUsers.contains(userId)) return;
    final wsService = ref.read(wsServiceProvider);

    for (final place in state.places) {
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
        wsService.send({
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
        wsService.send({
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

  // ---------------------------------------------------------------------------
  // Geo math helpers
  // ---------------------------------------------------------------------------

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

  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
