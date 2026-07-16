import 'package:flutter_test/flutter_test.dart';
import 'package:point/models/location_update.dart';
import 'package:point/services/relay_buffer.dart';

LocationData _fix(int ts) => LocationData(
      lat: 38.6 + ts * 1e-4,
      lon: -90.2 + ts * 1e-4,
      accuracy: 5.0,
      speed: 1.0,
      heading: 0.0,
      battery: 80,
      charging: false,
      timestamp: ts,
    );

void main() {
  group('RelayBuffer batching', () {
    test('add below maxSize does not overflow-flush', () {
      final buf = RelayBuffer();
      var overflowed = false;
      for (var i = 0; i < RelayBuffer.maxSize - 1; i++) {
        buf.add(_fix(i), onOverflow: (_) => overflowed = true);
      }
      expect(overflowed, isFalse);
      expect(buf.length, RelayBuffer.maxSize - 1);
    });

    test('add at maxSize flushes via onOverflow and clears buffer', () {
      final buf = RelayBuffer();
      List<LocationData>? flushed;
      for (var i = 0; i < RelayBuffer.maxSize; i++) {
        buf.add(_fix(i), onOverflow: (batch) => flushed = batch);
      }
      expect(flushed, isNotNull);
      expect(flushed!.length, RelayBuffer.maxSize);
      expect(buf.isEmpty, isTrue, reason: 'overflow flush empties the buffer');
    });

    test('flush returns a copy and clears', () {
      final buf = RelayBuffer();
      buf.add(_fix(1));
      buf.add(_fix(2));
      final batch = buf.flush();
      expect(batch.length, 2);
      expect(buf.isEmpty, isTrue);
    });
  });

  group('RelayBuffer auto-flush lifecycle', () {
    test('isAutoFlushing reflects start/stop', () {
      final buf = RelayBuffer();
      expect(buf.isAutoFlushing, isFalse);
      buf.startAutoFlush(const Duration(seconds: 30), (_) {});
      expect(buf.isAutoFlushing, isTrue);
      buf.stopAutoFlush();
      expect(buf.isAutoFlushing, isFalse);
      buf.dispose();
    });

    test('startAutoFlush periodically flushes only when non-empty', () async {
      final buf = RelayBuffer();
      final batches = <List<LocationData>>[];
      buf.startAutoFlush(
        const Duration(milliseconds: 40),
        (batch) => batches.add(batch),
      );

      // Empty tick — should NOT flush.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, isEmpty, reason: 'no flush while buffer empty');

      // Buffer a fix, then let the next tick flush it.
      buf.add(_fix(1));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches.length, 1);
      expect(batches.first.length, 1);
      expect(buf.isEmpty, isTrue, reason: 'auto-flush drains the buffer');

      buf.dispose();
    });

    test('dispose stops the auto-flush timer', () async {
      final buf = RelayBuffer();
      final batches = <List<LocationData>>[];
      buf.startAutoFlush(
        const Duration(milliseconds: 30),
        (batch) => batches.add(batch),
      );
      buf.add(_fix(1));
      buf.dispose();
      expect(buf.isAutoFlushing, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, isEmpty, reason: 'no flush after dispose');
    });
  });
}
