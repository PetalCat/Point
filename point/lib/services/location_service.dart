import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

  // ---- Accelerometer gate (Layer 1 — v3) ----------------------------------
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  int _motionCount = 0;  // consecutive frames with significant acceleration
  int _stillCount = 0;   // consecutive frames below threshold
  static const double _motionThreshold = 1.5; // m/s² above gravity noise
  static const int _motionFramesRequired = 5;  // ~500ms of sustained motion at 10Hz
  static const int _stillFramesRequired = 30;  // ~3s of stillness at 10Hz

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
    _stopAccelerometerWatch();
    _cancelAllTimers();
    _setActivity(LocationActivity.ghost);
  }

  /// Exit ghost mode. Returns to SLEEPING so triggers can wake naturally.
  void exitGhost() {
    if (_activity != LocationActivity.ghost) return;
    debugPrint('[Location] Exiting ghost mode');
    _setActivity(LocationActivity.sleeping);
    _startAccelerometerWatch();
    _startHeartbeat();
  }

  /// Called when the app comes to foreground / map becomes visible.
  void appOpened() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _isBackgrounded = false;

    // Restore full-speed tracking if we were throttled in background
    if (_activity == LocationActivity.active || _activity == LocationActivity.fast) {
      _stopAccelerometerWatch(); // GPS is running, no need for accel
      final interval = _activity == LocationActivity.fast
          ? const Duration(seconds: 2)
          : const Duration(seconds: 2);
      _startContinuousGps(interval);
      debugPrint('[Location] Foregrounded — restored 2s tracking');
    } else {
      wake(WakeReason.appOpen);
    }
  }

  /// Called when the app goes to background. Starts countdown to SLEEPING.
  bool _isBackgrounded = false;

  void appBackgrounded() {
    if (_activity == LocationActivity.ghost) return;
    _isBackgrounded = true;

    if (_activity == LocationActivity.active) {
      _startContinuousGps(const Duration(seconds: 5));
      debugPrint('[Location] Backgrounded moving (walk) — 5s');
    } else if (_activity == LocationActivity.fast) {
      _startContinuousGps(const Duration(seconds: 3));
      debugPrint('[Location] Backgrounded moving (drive) — 3s');
    } else {
      // Not moving — GPS off, accelerometer watches for motion
      _stopGps();
      _setActivity(LocationActivity.sleeping);
      _startAccelerometerWatch();
      _startHeartbeat();
      debugPrint('[Location] Backgrounded still — GPS off, accel watching');
    }
  }

  /// Clean up everything.
  void dispose() {
    _stopGps();
    _stopAccelerometerWatch();
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
    _stopAccelerometerWatch();
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
      return;
    }

    // App is in foreground — go straight to high-accuracy continuous tracking.
    // No waiting for movement detection. Battery saving is for background only.
    _stopAccelerometerWatch(); // GPS takes over
    _setActivity(LocationActivity.active);
    _startContinuousGps(const Duration(seconds: 2));
    _resetStillnessTimer();
    debugPrint('[Location] App open — continuous tracking at 2s');
  }

  /// Movement detected: start GPS at 10s -> first fix -> check speed ->
  /// enter ACTIVE (3-5s) or FAST (2s). Set up stillness timer.
  void _handleMovementWake() {
    _consecutiveFastFixes = 0;
    _consecutiveSlowFixes = 0;
    _rampDownTimer?.cancel();
    _stopAccelerometerWatch(); // GPS takes over motion detection

    // Go straight to full-speed tracking. No ramp.
    _setActivity(LocationActivity.active);
    _startContinuousGps(const Duration(seconds: 2));
    _resetStillnessTimer();
    debugPrint('[Location] Movement wake — 2s tracking');
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
  // Accelerometer gate (Layer 1 — v3)
  // =========================================================================

  /// Start listening to the accelerometer to detect motion while GPS is OFF.
  /// UserAccelerometerEvent already has gravity subtracted — readings near 0 = still.
  void _startAccelerometerWatch() {
    _accelSubscription?.cancel();
    _motionCount = 0;
    _stillCount = 0;
    _accelSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100), // 10Hz — ~5mW
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (magnitude > _motionThreshold) {
        _motionCount++;
        _stillCount = 0;
        if (_motionCount >= _motionFramesRequired) {
          // Sustained motion detected — wake GPS
          debugPrint('[Location] Accelerometer: sustained motion detected '
              '(${magnitude.toStringAsFixed(1)} m/s²) — waking GPS');
          _stopAccelerometerWatch();
          wake(WakeReason.movement);
        }
      } else {
        _stillCount++;
        _motionCount = 0;
      }
    });
    debugPrint('[Location] Accelerometer watch ON');
  }

  /// Stop the accelerometer listener. Called when GPS takes over motion detection.
  void _stopAccelerometerWatch() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _motionCount = 0;
    _stillCount = 0;
    debugPrint('[Location] Accelerometer watch OFF');
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

      // GPS proves movement — transition to ACTIVE if still sleeping/idle.
      // This is the primary movement detection (not accelerometer).
      if (_activity == LocationActivity.sleeping || _activity == LocationActivity.idle) {
        debugPrint('[Location] Movement detected via GPS — transitioning to ACTIVE at 2s');
        _setActivity(LocationActivity.active);
        _startContinuousGps(const Duration(seconds: 2));
      }
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
    // Background: detect stillness fast (30s). Foreground: 2 min grace.
    final timeout = _isBackgrounded
        ? const Duration(seconds: 30)
        : const Duration(minutes: 2);
    _stillnessTimer = Timer(timeout, _onStillnessDetected);
  }

  /// No movement detected. Kill GPS, enter sleeping.
  void _onStillnessDetected() {
    if (_activity != LocationActivity.active &&
        _activity != LocationActivity.fast) {
      return;
    }

    if (_isBackgrounded) {
      // Background: instant kill, heartbeat handles check-ins
      debugPrint('[Location] Background stillness — GPS off, accel watching');
      _stopGps();
      _setActivity(LocationActivity.sleeping);
      _startAccelerometerWatch();
      _startHeartbeat();
    } else {
      // Foreground: ramp down gracefully
      debugPrint('[Location] Foreground stillness — ramp down');
      _startContinuousGps(const Duration(seconds: 10));
      _rampDownTimer = Timer(const Duration(seconds: 30), () {
        debugPrint('[Location] Ramp-down complete — sleeping, accel watching');
        _stopGps();
        _setActivity(LocationActivity.sleeping);
        _startAccelerometerWatch();
        _startHeartbeat();
      });
    }
  }

  // =========================================================================
  // Heartbeat timer (30-minute recurring)
  // =========================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 20), (_) {
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
