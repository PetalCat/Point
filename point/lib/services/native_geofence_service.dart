import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wraps OS-level geofence APIs (Android GeofencingClient) via platform channels.
///
/// Registered geofences survive app sleep and doze mode because they're managed
/// by the OS, not by Dart timers. When the OS detects a zone exit, it fires
/// the [onZoneExit] stream — even if the app was in deep sleep.
class NativeGeofenceService {
  static const _channel = MethodChannel('dev.petalcat.point/geofence');
  static const _eventChannel =
      EventChannel('dev.petalcat.point/geofence_events');

  StreamSubscription<dynamic>? _eventSubscription;
  final _exitController = StreamController<String>.broadcast();

  /// Fires the zone ID when the OS detects exit from a registered geofence.
  Stream<String> get onZoneExit => _exitController.stream;

  NativeGeofenceService() {
    _eventSubscription =
        _eventChannel.receiveBroadcastStream().listen((event) {
      final data = Map<String, dynamic>.from(event as Map);
      if (data['transition'] == 'exit') {
        final zoneId = data['zoneId'] as String;
        debugPrint('[Geofence] OS exit event for zone $zoneId');
        _exitController.add(zoneId);
      }
    }, onError: (e) {
      // Platform channel not available (e.g., running on unsupported platform).
      debugPrint('[Geofence] Event channel error: $e');
    });
  }

  /// Register a circular geofence with the OS. Only EXIT transitions are monitored.
  Future<void> registerZone({
    required String id,
    required double lat,
    required double lon,
    required double radius,
  }) async {
    try {
      await _channel.invokeMethod('registerGeofence', {
        'id': id,
        'lat': lat,
        'lon': lon,
        'radius': radius,
      });
      debugPrint(
          '[Geofence] Registered OS geofence: zone $id (${radius.toStringAsFixed(0)}m)');
    } catch (e) {
      debugPrint('[Geofence] Failed to register: $e');
    }
  }

  /// Remove a previously registered geofence.
  Future<void> unregisterZone(String id) async {
    try {
      await _channel.invokeMethod('unregisterGeofence', {'id': id});
      debugPrint('[Geofence] Unregistered OS geofence: zone $id');
    } catch (e) {
      debugPrint('[Geofence] Failed to unregister: $e');
    }
  }

  /// Remove all registered geofences.
  Future<void> unregisterAll() async {
    try {
      await _channel.invokeMethod('unregisterAll');
    } catch (e) {
      debugPrint('[Geofence] Failed to unregister all: $e');
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _exitController.close();
  }
}
