import 'dart:math' as math;

class LearnedZone {
  final String id;
  final double lat;
  final double lon;
  double radius; // starts 150m, shrinks to 50m with confidence
  int visitCount;
  int confidence; // 0-100
  DateTime lastVisit;
  String? userLabel; // null = anonymous "Zone 1"
  List<String> wifiBssids; // for future WiFi fingerprint

  LearnedZone({
    required this.id,
    required this.lat,
    required this.lon,
    this.radius = 150.0,
    this.visitCount = 0,
    this.confidence = 0,
    required this.lastVisit,
    this.userLabel,
    this.wifiBssids = const [],
  });

  /// Display name: user label or "Zone N" fallback.
  String get displayName => userLabel ?? 'Zone $id';

  /// Check if a GPS position is inside this zone using haversine distance.
  bool isInside(double lat, double lon) {
    return _haversineDistance(this.lat, this.lon, lat, lon) <= radius;
  }

  /// Check if a position is just outside the zone (for exit hysteresis).
  /// Uses 1.2x radius so we don't flip-flop at the boundary.
  bool isOutside(double lat, double lon) {
    return _haversineDistance(this.lat, this.lon, lat, lon) > radius * 1.2;
  }

  /// Recalculate confidence based on visit count and recency.
  /// Decays if not visited within 30 days.
  void updateConfidence() {
    final daysSinceVisit = DateTime.now().difference(lastVisit).inDays;
    final recencyFactor = daysSinceVisit <= 30
        ? 1.0
        : math.max(0.0, 1.0 - (daysSinceVisit - 30) / 60.0);
    confidence = (visitCount * 15 * recencyFactor).clamp(0, 100).toInt();
  }

  /// Shrink radius as confidence grows (150m -> 50m).
  void refineRadius() {
    // Linear interpolation: confidence 0 -> 150m, confidence 100 -> 50m
    radius = 150.0 - (confidence / 100.0) * 100.0;
    if (radius < 50.0) radius = 50.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lon': lon,
        'radius': radius,
        'visitCount': visitCount,
        'confidence': confidence,
        'lastVisit': lastVisit.toIso8601String(),
        'userLabel': userLabel,
        'wifiBssids': wifiBssids,
      };

  factory LearnedZone.fromJson(Map<String, dynamic> json) => LearnedZone(
        id: json['id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        radius: (json['radius'] as num?)?.toDouble() ?? 150.0,
        visitCount: json['visitCount'] as int? ?? 0,
        confidence: json['confidence'] as int? ?? 0,
        lastVisit: DateTime.tryParse(json['lastVisit'] as String? ?? '') ??
            DateTime.now(),
        userLabel: json['userLabel'] as String?,
        wifiBssids: (json['wifiBssids'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

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
