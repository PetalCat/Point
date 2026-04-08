import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ---------------------------------------------------------------------------
// v1 compat — kept so LocationProvider and MapView compile without changes.
// These map onto the new activity states internally.
// ---------------------------------------------------------------------------
enum TrackingMode {
  adaptive(distanceFilter: 0, intervalMs: 1000),
  realtime(distanceFilter: 0, intervalMs: 1000),
  batterySaver(distanceFilter: 50, intervalMs: 120000);

  final int distanceFilter;
  final int intervalMs;
  const TrackingMode({required this.distanceFilter, required this.intervalMs});
}

// ---------------------------------------------------------------------------
// v2 — Event-driven activity state machine
// ---------------------------------------------------------------------------

/// Activity states for the location state machine.
enum LocationActivity { sleeping, idle, active, fast, ghost }

/// What caused the GPS to turn on.
enum WakeReason { appOpen, movement, nudge, heartbeat, geofence }

/// Adaptive, event-driven location service.
///
/// GPS hardware stays OFF unless a specific trigger demands a fix.
/// The service manages an activity state machine:
///   SLEEPING -> IDLE -> ACTIVE <-> FAST -> SLEEPING
///   Any -> GHOST (immediate kill)
///
/// The service does NOT handle relay (sending to server) or rendering.
/// It emits positions on [positions] and state changes on [activityChanges].
class LocationService {
  // ---- State ---------------------------------------------------------------
  LocationActivity _activity = LocationActivity.sleeping;
  Position? _lastPosition;
  DateTime? _lastMovementTime;
  DateTime? _lastRelayTime;

  // Speed detection counters
  int _consecutiveFastFixes = 0;
  int _consecutiveSlowFixes = 0;

  // Ramp-down timer for stillness detection
  Timer? _rampDownTimer;

  // ---- Streams -------------------------------------------------------------
  final _positionController = StreamController<Position>.broadcast();
  final _activityController = StreamController<LocationActivity>.broadcast();

  Stream<Position> get positions => _positionController.stream;
  Stream<LocationActivity> get activityChanges => _activityController.stream;
  LocationActivity get currentActivity => _activity;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastMovementTime => _lastMovementTime;
  DateTime? get lastRelayTime => _lastRelayTime;

  // ---- GPS subscription & timers -------------------------------------------
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _stillnessTimer;
  Timer? _heartbeatTimer;
  Timer? _backgroundTimer; // countdown to SLEEPING after app backgrounds

  // ---- Current GPS interval tracking ---------------------------------------
  Duration _currentInterval = const Duration(seconds: 5);

  // =========================================================================
  // Public API — v2
  // =========================================================================

  /// Request location permission from the OS.
  Future<bool> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// One-shot current position (does not change activity state).
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Primary wake trigger. Turns GPS on for the appropriate duration/mode.
  void wake(WakeReason reason) {
    if (_activity == LocationActivity.ghost) {
      debugPrint('[Location] wake($reason) ignored — ghost mode active');
      return;
    }

    debugPrint('[Location] wake($reason) in state ${_activity.name}');

    switch (reason) {
      case WakeReason.appOpen:
        _handleAppOpenWake();
      case WakeReason.movement:
        _handleMovementWake();
      case WakeReason.nudge:
        _handleNudgeWake();
      case WakeReason.heartbeat:
        _handleHeartbeatWake();
      case WakeReason.geofence:
        _handleNudgeWake(); // same as nudge — one-shot fix, emit, done
    }
  }

  /// Enter ghost mode. Immediately kills GPS, cancels all timers.
  void enterGhost() {
    debugPrint('[Location] Entering ghost mode');
    _stopGps();
    _cancelAllTimers();
    _setActivity(LocationActivity.ghost);
  }

  /// Exit ghost mode. Returns to SLEEPING so triggers can wake naturally.
  void exitGhost() {
    if (_activity != LocationActivity.ghost) return;
    debugPrint('[Location] Exiting ghost mode');
    _setActivity(LocationActivity.sleeping);
    _startHeartbeat();
  }

  /// Called when the app comes to foreground / map becomes visible.
  void appOpened() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    wake(WakeReason.appOpen);
  }

  /// Called when the app goes to background. Starts countdown to SLEEPING.
  void appBackgrounded() {
    if (_activity == LocationActivity.ghost) return;

    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(const Duration(minutes: 2), () {
      debugPrint('[Location] Background timeout — entering SLEEPING');
      if (_activity == LocationActivity.idle) {
        _setActivity(LocationActivity.sleeping);
      } else if (_activity == LocationActivity.active ||
          _activity == LocationActivity.fast) {
        // If actively moving while backgrounded, keep tracking but at reduced
        // rate. The stillness timer will eventually shut it down.
        debugPrint('[Location] Still moving in background — keeping GPS');
      }
    });
  }

  /// Clean up everything.
  void dispose() {
    _stopGps();
    _cancelAllTimers();
    _positionController.close();
    _activityController.close();
  }

  // =========================================================================
  // v1 compatibility shims
  // =========================================================================

  /// v1 compat: maps to currentActivity translated to TrackingMode.
  TrackingMode get currentMode {
    switch (_activity) {
      case LocationActivity.fast:
        return TrackingMode.realtime;
      case LocationActivity.active:
        return TrackingMode.adaptive;
      case LocationActivity.sleeping:
      case LocationActivity.idle:
      case LocationActivity.ghost:
        return TrackingMode.adaptive;
    }
  }

  /// v1 compat: true when SLEEPING or IDLE (no active movement).
  bool get isStill =>
      _activity == LocationActivity.sleeping ||
      _activity == LocationActivity.idle;

  /// v1 compat: starts continuous tracking. Maps to wake(movement).
  void startTracking({TrackingMode mode = TrackingMode.adaptive}) {
    if (_activity == LocationActivity.ghost) return;
    wake(WakeReason.movement);
  }

  /// v1 compat: sets tracking mode. Maps to activity transitions.
  void setMode(TrackingMode mode) {
    if (_activity == LocationActivity.ghost) return;
    switch (mode) {
      case TrackingMode.realtime:
        if (_activity != LocationActivity.fast) {
          _startContinuousGps(const Duration(seconds: 2));
          _setActivity(LocationActivity.fast);
        }
      case TrackingMode.adaptive:
        if (_activity == LocationActivity.fast) {
          _startContinuousGps(const Duration(seconds: 5));
          _setActivity(LocationActivity.active);
        } else if (_activity == LocationActivity.sleeping ||
            _activity == LocationActivity.idle) {
          wake(WakeReason.movement);
        }
      case TrackingMode.batterySaver:
        _startContinuousGps(const Duration(seconds: 30));
        _setActivity(LocationActivity.active);
    }
  }

  /// v1 compat: stops tracking entirely. Enters SLEEPING.
  void stopTracking() {
    _stopGps();
    _cancelAllTimers();
    if (_activity != LocationActivity.ghost) {
      _setActivity(LocationActivity.sleeping);
    }
    debugPrint('[Location] Tracking stopped');
  }

  // =========================================================================
  // Wake handlers
  // =========================================================================

  /// App opened: one-shot fix -> IDLE -> show cached.
  void _handleAppOpenWake() async {
    if (_activity == LocationActivity.active ||
        _activity == LocationActivity.fast) {
      // Already actively tracking — don't downgrade.
      return;
    }

    final pos = await getCurrentPosition();
    if (pos != null) {
      _lastPosition = pos;
      _positionController.add(pos);
    }
    _setActivity(LocationActivity.idle);
    _startHeartbeat();
  }

  /// Movement detected: start GPS at 10s -> first fix -> check speed ->
  /// enter ACTIVE (3-5s) or FAST (2s). Set up stillness timer.
  void _handleMovementWake() {
    _consecutiveFastFixes = 0;
    _consecutiveSlowFixes = 0;
    _rampDownTimer?.cancel();

    // Start at 10s interval, will ramp up after first fixes
    _startContinuousGps(const Duration(seconds: 10));
    if (_activity != LocationActivity.active &&
        _activity != LocationActivity.fast) {
      _setActivity(LocationActivity.active);
    }
    _resetStillnessTimer();
    _startHeartbeat();
  }

  /// Nudge: one-shot fix -> emit -> don't change state.
  void _handleNudgeWake() async {
    final pos = await getCurrentPosition();
    if (pos != null) {
      _lastPosition = pos;
      _positionController.add(pos);
    }
    // Activity state unchanged — if SLEEPING, stay SLEEPING.
  }

  /// Heartbeat: one-shot fix -> relay only if moved >50m since last relay.
  void _handleHeartbeatWake() async {
    final pos = await getCurrentPosition();
    if (pos == null) return;

    final shouldEmit = _lastPosition == null ||
        _haversineDistance(
              pos.latitude,
              pos.longitude,
              _lastPosition!.latitude,
              _lastPosition!.longitude,
            ) >
            50.0;

    _lastPosition = pos;

    if (shouldEmit) {
      _lastRelayTime = DateTime.now();
      _positionController.add(pos);
      debugPrint('[Location] Heartbeat: moved >50m, emitting position');
    } else {
      debugPrint('[Location] Heartbeat: still within 50m, skipping relay');
    }
    // Stay in current state (usually SLEEPING).
  }

  // =========================================================================
  // GPS management
  // =========================================================================

  void _startContinuousGps(Duration interval) {
    _gpsSubscription?.cancel();
    _currentInterval = interval;

    final settings = _buildSettings(interval);
    debugPrint('[Location] GPS ON: interval=${interval.inMilliseconds}ms, '
        'state=${_activity.name}');

    _gpsSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onGpsFix,
      onError: (e) => debugPrint('[Location] GPS stream error: $e'),
    );
  }

  void _stopGps() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    debugPrint('[Location] GPS OFF');
  }

  LocationSettings _buildSettings(Duration interval) {
    if (Platform.isAndroid) {
      // Only show foreground notification for ACTIVE/FAST
      final showNotification = _activity == LocationActivity.active ||
          _activity == LocationActivity.fast;

      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _activity == LocationActivity.fast ? 10 : 0,
        intervalDuration: interval,
        foregroundNotificationConfig: showNotification
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Point',
                notificationText: 'Sharing your location',
                enableWakeLock: true,
              )
            : null,
      );
    }

    // iOS / other
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _activity == LocationActivity.fast ? 10 : 0,
    );
  }

  // =========================================================================
  // Position processing
  // =========================================================================

  void _onGpsFix(Position position) {
    if (_activity == LocationActivity.ghost) return;

    final prevPosition = _lastPosition;
    _lastPosition = position;
    _positionController.add(position);

    // Check if actually moved (>5m)
    final moved = prevPosition == null ||
        _haversineDistance(
              position.latitude,
              position.longitude,
              prevPosition.latitude,
              prevPosition.longitude,
            ) >
            5.0;

    if (moved) {
      _lastMovementTime = DateTime.now();
      _rampDownTimer?.cancel();
      _resetStillnessTimer();
    }

    // Speed-based state transitions
    _processSpeedTransitions(position);

    // Ramp up from initial 10s to target interval after first fixes
    _maybeRampUpInterval();
  }

  /// Transition between ACTIVE <-> FAST based on speed.
  void _processSpeedTransitions(Position position) {
    final speed = position.speed;

    if (_activity == LocationActivity.active) {
      // ACTIVE -> FAST: speed >5 m/s for 3 consecutive fixes
      if (speed > 5.0) {
        _consecutiveFastFixes++;
        _consecutiveSlowFixes = 0;
        if (_consecutiveFastFixes >= 3) {
          debugPrint('[Location] Speed sustained >5 m/s — entering FAST');
          _setActivity(LocationActivity.fast);
          _startContinuousGps(const Duration(seconds: 2));
          _consecutiveFastFixes = 0;
        }
      } else {
        _consecutiveFastFixes = 0;
      }
    } else if (_activity == LocationActivity.fast) {
      // FAST -> ACTIVE: speed <2 m/s for 5 consecutive fixes
      if (speed < 2.0) {
        _consecutiveSlowFixes++;
        _consecutiveFastFixes = 0;
        if (_consecutiveSlowFixes >= 5) {
          debugPrint('[Location] Speed dropped <2 m/s — entering ACTIVE');
          _setActivity(LocationActivity.active);
          _startContinuousGps(const Duration(seconds: 5));
          _consecutiveSlowFixes = 0;
        }
      } else {
        _consecutiveSlowFixes = 0;
      }
    }
  }

  /// After first few fixes at 10s, ramp up to the target interval for the
  /// current activity state.
  void _maybeRampUpInterval() {
    if (_currentInterval.inSeconds <= 5) return; // already at target

    final targetInterval = _activity == LocationActivity.fast
        ? const Duration(seconds: 2)
        : const Duration(seconds: 5);

    if (_currentInterval > targetInterval) {
      // Step down: 10s -> 5s (or 2s for fast)
      debugPrint('[Location] Ramping up: ${_currentInterval.inSeconds}s -> '
          '${targetInterval.inSeconds}s');
      _startContinuousGps(targetInterval);
    }
  }

  // =========================================================================
  // Stillness detection
  // =========================================================================

  void _resetStillnessTimer() {
    _stillnessTimer?.cancel();
    _stillnessTimer = Timer(const Duration(minutes: 2), _onStillnessDetected);
  }

  /// No movement >5m for 2 minutes. Ramp down: 3s->10s->30s->off.
  void _onStillnessDetected() {
    if (_activity != LocationActivity.active &&
        _activity != LocationActivity.fast) {
      return;
    }

    debugPrint('[Location] Stillness detected — starting ramp-down');
    _startContinuousGps(const Duration(seconds: 10));

    _rampDownTimer = Timer(const Duration(seconds: 30), () {
      _startContinuousGps(const Duration(seconds: 30));
      debugPrint('[Location] Ramp-down stage 2: 30s interval');

      _rampDownTimer = Timer(const Duration(seconds: 60), () {
        debugPrint('[Location] Ramp-down complete — entering SLEEPING');
        _stopGps();
        _setActivity(LocationActivity.sleeping);
      });
    });
  }

  // =========================================================================
  // Heartbeat timer (30-minute recurring)
  // =========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (_activity == LocationActivity.sleeping ||
          _activity == LocationActivity.idle) {
        wake(WakeReason.heartbeat);
      }
      // If ACTIVE/FAST, GPS is already running — no heartbeat needed.
    });
  }

  // =========================================================================
  // Internal helpers
  // =========================================================================

  void _setActivity(LocationActivity next) {
    if (_activity == next) return;
    final prev = _activity;
    _activity = next;
    _activityController.add(next);
    debugPrint('[Location] State: ${prev.name} -> ${next.name}');
  }

  void _cancelAllTimers() {
    _stillnessTimer?.cancel();
    _stillnessTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _rampDownTimer?.cancel();
    _rampDownTimer = null;
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
