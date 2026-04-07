import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Background location tracking intervals.
enum TrackingMode {
  /// High frequency: 10s / 5m — active use, following someone
  realtime(intervalMs: 10000, distanceFilter: 5),
  /// Normal: 30s / 15m — default background sharing
  normal(intervalMs: 30000, distanceFilter: 15),
  /// Battery saver: 60s / 50m — low power mode
  batterySaver(intervalMs: 60000, distanceFilter: 50);

  final int intervalMs;
  final int distanceFilter;
  const TrackingMode({required this.intervalMs, required this.distanceFilter});
}

class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _controller = StreamController<Position>.broadcast();
  TrackingMode _currentMode = TrackingMode.normal;

  Stream<Position> get positions => _controller.stream;
  TrackingMode get currentMode => _currentMode;

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

  void startTracking({TrackingMode mode = TrackingMode.normal}) {
    _positionSubscription?.cancel();
    _currentMode = mode;

    final settings = _buildSettings(mode);
    debugPrint('[Location] Tracking started: ${mode.name} '
        '(${mode.intervalMs}ms / ${mode.distanceFilter}m)');

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) => _controller.add(position),
          onError: (e) => debugPrint('[Location] Stream error: $e'),
        );
  }

  /// Switch tracking mode without stopping the stream.
  void setMode(TrackingMode mode) {
    if (mode == _currentMode) return;
    startTracking(mode: mode);
  }

  LocationSettings _buildSettings(TrackingMode mode) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: mode.distanceFilter,
        intervalDuration: Duration(milliseconds: mode.intervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Point',
          notificationText: 'Sharing your location',
          enableWakeLock: true,
        ),
      );
    }

    // iOS / other platforms
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: mode.distanceFilter,
    );
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[Location] Tracking stopped');
  }

  void dispose() {
    stopTracking();
    _controller.close();
  }
}
