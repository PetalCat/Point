import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/learned_zone.dart';

/// Tracks dwell events at GPS positions and promotes recurring dwells into
/// [LearnedZone]s. Zones are LOCAL ONLY and never sent to the server.
class ZoneLearningService {
  List<LearnedZone> _zones = [];
  List<_DwellEvent> _dwellEvents = [];

  /// Where the current dwell started (null if moving).
  double? _dwellStartLat;
  double? _dwellStartLon;
  DateTime? _dwellStartTime;

  /// Meters — positions within this radius count as "same spot".
  static const double _dwellRadius = 100.0;

  /// Minimum time to stay in one spot before recording a dwell.
  static const Duration _dwellMinDuration = Duration(minutes: 30);

  /// Number of dwell events at a cluster before it becomes a zone.
  static const int _promotionThreshold = 3;

  /// Minimum confidence for a zone to suppress relay.
  static const int _suppressionConfidence = 50;

  static const String _zonesKey = 'learned_zones';
  static const String _dwellsKey = 'learned_dwells';

  List<LearnedZone> get zones => List.unmodifiable(_zones);

  int _nextZoneId = 1;

  // ---------------------------------------------------------------------------
  // Position updates — called on every GPS fix
  // ---------------------------------------------------------------------------

  /// Called on every GPS fix. Detects dwells, records events, promotes to zones.
  void onPositionUpdate(double lat, double lon) {
    // Feed existing zones: if inside a zone, bump its visit stats.
    final zone = getZoneAt(lat, lon);
    if (zone != null) {
      _touchZone(zone);
    }

    // Dwell tracking
    if (_dwellStartLat == null) {
      // Start a new potential dwell.
      _dwellStartLat = lat;
      _dwellStartLon = lon;
      _dwellStartTime = DateTime.now();
      return;
    }

    final distFromStart =
        _haversineDistance(_dwellStartLat!, _dwellStartLon!, lat, lon);

    if (distFromStart <= _dwellRadius) {
      // Still near the dwell start — check if duration threshold is met.
      final elapsed = DateTime.now().difference(_dwellStartTime!);
      if (elapsed >= _dwellMinDuration) {
        _recordDwellEvent(_dwellStartLat!, _dwellStartLon!);
        // Reset so we don't keep recording the same dwell every fix.
        _dwellStartLat = lat;
        _dwellStartLon = lon;
        _dwellStartTime = DateTime.now();
      }
    } else {
      // Moved away — reset dwell tracking.
      _dwellStartLat = lat;
      _dwellStartLon = lon;
      _dwellStartTime = DateTime.now();
    }
  }

  // ---------------------------------------------------------------------------
  // Dwell event recording & zone promotion
  // ---------------------------------------------------------------------------

  void _recordDwellEvent(double lat, double lon) {
    final event = _DwellEvent(lat: lat, lon: lon, time: DateTime.now());
    _dwellEvents.add(event);
    debugPrint('[Zones] Dwell recorded at ${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}');

    // Check if this dwell is near an existing zone — if so, just refine it.
    for (final zone in _zones) {
      if (zone.isInside(lat, lon)) {
        zone.visitCount++;
        zone.lastVisit = DateTime.now();
        zone.updateConfidence();
        zone.refineRadius();
        debugPrint('[Zones] Refined "${zone.displayName}" — visits=${zone.visitCount} conf=${zone.confidence}');
        _saveSoon();
        return;
      }
    }

    // Count dwells near this location.
    final nearby = _dwellEvents.where((e) {
      return _haversineDistance(e.lat, e.lon, lat, lon) <= _dwellRadius;
    }).toList();

    if (nearby.length >= _promotionThreshold) {
      _promoteToZone(nearby);
    }
  }

  void _promoteToZone(List<_DwellEvent> cluster) {
    // Centroid of the cluster.
    double sumLat = 0, sumLon = 0;
    for (final e in cluster) {
      sumLat += e.lat;
      sumLon += e.lon;
    }
    final centerLat = sumLat / cluster.length;
    final centerLon = sumLon / cluster.length;

    // Don't create a zone if one already covers this centroid.
    if (getZoneAt(centerLat, centerLon) != null) return;

    final zone = LearnedZone(
      id: '${_nextZoneId++}',
      lat: centerLat,
      lon: centerLon,
      radius: 150.0,
      visitCount: cluster.length,
      lastVisit: DateTime.now(),
    );
    zone.updateConfidence();
    zone.refineRadius();
    _zones.add(zone);

    // Remove the dwell events that formed this zone (they're now baked in).
    for (final e in cluster) {
      _dwellEvents.remove(e);
    }

    debugPrint('[Zones] NEW zone "${zone.displayName}" at ${centerLat.toStringAsFixed(5)},${centerLon.toStringAsFixed(5)} r=${zone.radius.toStringAsFixed(0)}m');
    _saveSoon();
  }

  void _touchZone(LearnedZone zone) {
    // Only count a "visit" if last visit was >1 hour ago (avoid inflating from
    // continuous GPS fixes while sitting at the zone).
    if (DateTime.now().difference(zone.lastVisit).inMinutes > 60) {
      zone.visitCount++;
      zone.updateConfidence();
      zone.refineRadius();
      debugPrint('[Zones] Visit to "${zone.displayName}" — visits=${zone.visitCount} conf=${zone.confidence}');
    }
    zone.lastVisit = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns the zone the position is inside, or null.
  LearnedZone? getZoneAt(double lat, double lon) {
    for (final zone in _zones) {
      if (zone.isInside(lat, lon)) return zone;
    }
    return null;
  }

  /// Whether a position is inside a zone with enough confidence to suppress relay.
  bool shouldSuppressRelay(double lat, double lon) {
    final zone = getZoneAt(lat, lon);
    return zone != null && zone.confidence >= _suppressionConfidence;
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  void deleteZone(String id) {
    _zones.removeWhere((z) => z.id == id);
    _saveSoon();
  }

  void labelZone(String id, String label) {
    final zone = _zones.where((z) => z.id == id).firstOrNull;
    if (zone != null) {
      zone.userLabel = label;
      _saveSoon();
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence (SharedPreferences JSON)
  // ---------------------------------------------------------------------------

  bool _saveScheduled = false;

  void _saveSoon() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future.delayed(const Duration(seconds: 2), () {
      _saveScheduled = false;
      save();
    });
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final zonesJson = _zones.map((z) => z.toJson()).toList();
      await prefs.setString(_zonesKey, jsonEncode(zonesJson));

      final dwellsJson = _dwellEvents.map((d) => d.toJson()).toList();
      await prefs.setString(_dwellsKey, jsonEncode(dwellsJson));

      debugPrint('[Zones] Saved ${_zones.length} zones, ${_dwellEvents.length} pending dwells');
    } catch (e) {
      debugPrint('[Zones] Save failed: $e');
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final zonesRaw = prefs.getString(_zonesKey);
      if (zonesRaw != null) {
        final list = jsonDecode(zonesRaw) as List<dynamic>;
        _zones = list
            .map((e) => LearnedZone.fromJson(e as Map<String, dynamic>))
            .toList();

        // Recalculate confidence (accounts for time decay since last run).
        for (final zone in _zones) {
          zone.updateConfidence();
        }

        // Track next ID.
        for (final zone in _zones) {
          final parsed = int.tryParse(zone.id);
          if (parsed != null && parsed >= _nextZoneId) {
            _nextZoneId = parsed + 1;
          }
        }
      }

      final dwellsRaw = prefs.getString(_dwellsKey);
      if (dwellsRaw != null) {
        final list = jsonDecode(dwellsRaw) as List<dynamic>;
        _dwellEvents = list
            .map((e) => _DwellEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[Zones] Loaded ${_zones.length} zones, ${_dwellEvents.length} pending dwells');
    } catch (e) {
      debugPrint('[Zones] Load failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Haversine helper
  // ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Internal dwell event — not exposed outside this file
// ---------------------------------------------------------------------------

class _DwellEvent {
  final double lat;
  final double lon;
  final DateTime time;

  _DwellEvent({required this.lat, required this.lon, required this.time});

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'time': time.toIso8601String(),
      };

  factory _DwellEvent.fromJson(Map<String, dynamic> json) => _DwellEvent(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      );
}
