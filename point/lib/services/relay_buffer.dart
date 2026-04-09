import 'dart:async';

import '../models/location_update.dart';

/// Buffers location fixes for batched relay in background mode.
///
/// In foreground mode the caller sends fixes directly (no buffering).
/// In background mode fixes accumulate and auto-flush every [interval],
/// or when the buffer reaches [maxSize].
class RelayBuffer {
  final List<LocationData> _buffer = [];
  Timer? _autoFlushTimer;

  /// Hard cap — auto-flush regardless of timer when exceeded.
  static const int maxSize = 20;

  int get length => _buffer.length;
  bool get isEmpty => _buffer.isEmpty;
  bool get isNotEmpty => _buffer.isNotEmpty;

  /// Add a fix to the buffer. If [maxSize] is reached, fires [onOverflow].
  void add(LocationData fix, {void Function(List<LocationData> batch)? onOverflow}) {
    _buffer.add(fix);
    if (_buffer.length >= maxSize && onOverflow != null) {
      onOverflow(flush());
    }
  }

  /// Take all buffered fixes and clear.
  List<LocationData> flush() {
    final batch = List<LocationData>.from(_buffer);
    _buffer.clear();
    return batch;
  }

  /// Start auto-flush timer for background mode.
  void startAutoFlush(
    Duration interval,
    void Function(List<LocationData> batch) onFlush,
  ) {
    _autoFlushTimer?.cancel();
    _autoFlushTimer = Timer.periodic(interval, (_) {
      if (_buffer.isNotEmpty) {
        onFlush(flush());
      }
    });
  }

  void stopAutoFlush() {
    _autoFlushTimer?.cancel();
    _autoFlushTimer = null;
  }

  void dispose() {
    stopAutoFlush();
    _buffer.clear();
  }
}
