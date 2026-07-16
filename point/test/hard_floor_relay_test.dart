import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:point/providers.dart';
import 'package:point/services/api_service.dart';
import 'package:point/services/crypto_service.dart';
import 'package:point/services/location_service.dart';
import 'package:point/services/native_geofence_service.dart';
import 'package:point/services/ws_service.dart';

// ---------------------------------------------------------------------------
// The "owner at work all day" regression: while SLEEPING + backgrounded +
// inside a learned zone, the hard-floor relay is the ONLY buffer producer, and
// the batch flusher is stopped on the sleeping transition. If the hard-floor
// tick merely buffers, the fix is stranded — a contact's "last seen" never
// refreshes. This test asserts a relay actually LEAVES the device on a single
// hard-floor tick, and that it carries the masked zone center (not exact GPS).
// ---------------------------------------------------------------------------

Position _pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// WsService with a safe (no-socket) constructor; records every outbound send.
class _FakeWs extends WsService {
  final List<Map<String, dynamic>> sent = [];
  @override
  void send(Map<String, dynamic> message) => sent.add(message);
}

/// LocationService with all platform paths overridden; we drive its streams.
class _FakeLocationService extends LocationService {
  final _positions = StreamController<Position>.broadcast();
  final _activities = StreamController<LocationActivity>.broadcast();
  Position? current;

  @override
  Stream<Position> get positions => _positions.stream;
  @override
  Stream<LocationActivity> get activityChanges => _activities.stream;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Position?> getCurrentPosition() async => current;
  @override
  void wake(WakeReason reason) {}
  @override
  void appBackgrounded() {}
  @override
  void appOpened() {}

  void emitActivity(LocationActivity a) => _activities.add(a);
}

/// CryptoService that records the plaintext it was asked to encrypt so the
/// test can prove the relayed coordinates are the masked zone center.
class _FakeCrypto extends CryptoService {
  _FakeCrypto() : super(ApiService());
  final List<Map<String, dynamic>> encryptedPayloads = [];
  @override
  Future<String?> encrypt(String groupId, Map<String, dynamic> payload) async {
    encryptedPayloads.add(payload);
    return 'blob:${payload['lat']},${payload['lon']}';
  }
}

class _FakeZones extends ZoneLearningService {
  _FakeZones(this._zone);
  final LearnedZone _zone;
  @override
  LearnedZone? getZoneAt(double lat, double lon) => _zone;
  @override
  bool shouldSuppressRelay(double lat, double lon) => true;
  @override
  void onPositionUpdate(double lat, double lon) {}
}

class _FakeGeofence implements NativeGeofenceService {
  final _c = StreamController<String>.broadcast();
  @override
  Stream<String> get onZoneExit => _c.stream;
  @override
  Future<void> registerZone({
    required String id,
    required double lat,
    required double lon,
    required double radius,
  }) async {}
  @override
  Future<void> unregisterZone(String id) async {}
  @override
  Future<void> unregisterAll() async {}
  @override
  void dispose() => _c.close();
}

class _FakeGhost extends GhostNotifier {
  @override
  GhostState build() => const GhostState();
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'hard-floor relay leaves the device (immediate send) while sleeping + '
      'in-zone, carrying the masked zone center', () async {
    // Home/"work" zone centered here, confident enough to suppress + mask.
    final zone = LearnedZone(
      id: '1',
      lat: 38.6270,
      lon: -90.1994,
      radius: 60,
      confidence: 70,
      lastVisit: DateTime.now(),
    );
    final atCenter = _pos(zone.lat, zone.lon);

    final ws = _FakeWs();
    final loc = _FakeLocationService()..current = atCenter;
    final crypto = _FakeCrypto();

    final container = ProviderContainer(overrides: [
      wsServiceProvider.overrideWithValue(ws),
      locationServiceProvider.overrideWithValue(loc),
      cryptoServiceProvider.overrideWithValue(crypto),
      zoneLearningServiceProvider.overrideWithValue(_FakeZones(zone)),
      nativeGeofenceServiceProvider.overrideWithValue(_FakeGeofence()),
      ghostProvider.overrideWith(_FakeGhost.new),
    ]);
    // NB: intentionally not disposing the container — LocationNotifier's
    // onDispose calls _saveCache(), which reads `state` inside a dispose
    // life-cycle (forbidden under Riverpod 3). That's unrelated to what this
    // test exercises; the leaked 5-min timer is harmless for a plain test().

    final notifier = container.read(locationProvider.notifier);
    // Let build()/_fetchInitialPosition run — lands us inside the zone
    // (_wasInZone=true, currentZone set).
    await _settle();

    notifier.setMyUserId('me');
    // Background, then the sleeping transition stops the batch flusher —
    // exactly the state where a buffered hard-floor fix would be stranded.
    notifier.setBackgrounded(true);
    loc.emitActivity(LocationActivity.sleeping);
    await _settle();

    // Share with a group; activity stays sleeping (no movement).
    notifier.setActiveGroups(['g'], precision: {'g': 'exact'});
    await _settle();

    // Baseline: ignore any entry-relay traffic; measure only the hard-floor tick.
    ws.sent.clear();
    crypto.encryptedPayloads.clear();

    await notifier.debugRunHardFloorTick();
    await _settle();

    // MUST leave the device this interval — not sit in a stopped buffer.
    final updates =
        ws.sent.where((m) => m['type'] == 'location.update').toList();
    expect(updates, isNotEmpty,
        reason: 'hard-floor tick must send immediately, not buffer, while '
            'sleeping + in-zone');
    // And it must be a single immediate update, not a batched flush.
    expect(ws.sent.any((m) => m['type'] == 'location.batch_update'), isFalse);

    // Privacy: the relayed coordinates are the masked zone center, never the
    // exact fix.
    expect(crypto.encryptedPayloads, isNotEmpty);
    final payload = crypto.encryptedPayloads.last;
    expect(payload['lat'], closeTo(zone.lat, 1e-9));
    expect(payload['lon'], closeTo(zone.lon, 1e-9));
  });
}
