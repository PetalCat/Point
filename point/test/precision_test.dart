import 'package:flutter_test/flutter_test.dart';
import 'package:point/models/location_update.dart';

void main() {
  // Exact coordinates that, if leaked to an approximate/city recipient, would
  // be a P0-05 privacy violation.
  final exact = LocationData(
    lat: 38.627003,
    lon: -90.199404,
    accuracy: 5.0,
    speed: 12.5,
    heading: 90.0,
    battery: 80,
    charging: false,
    timestamp: 1712345678,
  );

  group('LocationData.withPrecision', () {
    test('exact preserves full coordinates and motion', () {
      final r = exact.withPrecision('exact');
      expect(r.lat, exact.lat);
      expect(r.lon, exact.lon);
      expect(r.speed, exact.speed);
      expect(r.heading, exact.heading);
    });

    test('approximate snaps to ~550m grid and drops motion', () {
      final r = exact.withPrecision('approximate');
      // Snapped to 0.005 grid.
      expect((r.lat / 0.005).round() * 0.005, closeTo(r.lat, 1e-9));
      expect((r.lon / 0.005).round() * 0.005, closeTo(r.lon, 1e-9));
      // Must differ from exact (loses precision).
      expect(r.lat, isNot(exact.lat));
      // Motion fields stripped so movement can't be inferred.
      expect(r.speed, isNull);
      expect(r.heading, isNull);
      // Reduced position is within ~1km of the true position.
      expect((r.lat - exact.lat).abs(), lessThan(0.01));
      expect((r.lon - exact.lon).abs(), lessThan(0.01));
    });

    test('city snaps to ~11km grid and drops motion', () {
      final r = exact.withPrecision('city');
      expect((r.lat / 0.1).round() * 0.1, closeTo(r.lat, 1e-9));
      expect(r.speed, isNull);
      expect(r.heading, isNull);
      // Coarser than approximate.
      expect((r.lat - exact.lat).abs(), lessThan(0.2));
    });

    test('unknown precision falls back to exact (no accidental over-share)', () {
      // An unrecognized level must NOT silently expand precision beyond exact;
      // exact is the only "full detail" path and the safe default here.
      final r = exact.withPrecision('garbage');
      expect(r.lat, exact.lat);
      expect(r.lon, exact.lon);
    });

    test('approximate never round-trips back to exact coordinates', () {
      final approx = exact.withPrecision('approximate');
      // The whole point of P0-05: a recipient decrypting the approximate blob
      // cannot recover the exact coordinates.
      expect(approx.lat == exact.lat && approx.lon == exact.lon, isFalse);
    });
  });
}
