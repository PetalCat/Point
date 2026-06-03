class LocationData {
  final double lat;
  final double lon;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? battery;
  final bool? charging;
  final String? activity;
  final int timestamp;

  LocationData({
    required this.lat,
    required this.lon,
    this.accuracy,
    this.speed,
    this.heading,
    this.battery,
    this.charging,
    this.activity,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
    'battery': battery,
    'charging': charging,
    'activity': activity,
    'timestamp': timestamp,
  };

  /// Return a copy with coordinates reduced to the given precision level.
  /// Precision is applied BEFORE encryption so a recipient configured for
  /// approximate/city can never decrypt exact coordinates (P0-05).
  ///
  /// - exact: full coordinates, accuracy/speed/heading preserved
  /// - approximate: snapped to a ~550m grid, motion fields dropped
  /// - city: snapped to a ~11km grid, motion fields dropped
  LocationData withPrecision(String precision) {
    switch (precision) {
      case 'approximate':
        return _snapped(0.005); // ~550m
      case 'city':
        return _snapped(0.1); // ~11km
      case 'exact':
      default:
        return this;
    }
  }

  LocationData _snapped(double grid) {
    // Snap to the center of the grid cell to avoid leaking sub-grid position.
    double snap(double v) => (v / grid).round() * grid;
    return LocationData(
      lat: snap(lat),
      lon: snap(lon),
      accuracy: grid * 111000, // report coarse accuracy in meters
      speed: null,
      heading: null,
      battery: battery,
      charging: charging,
      activity: activity,
      timestamp: timestamp,
    );
  }

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    speed: (json['speed'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
    battery: json['battery'] as int?,
    charging: json['charging'] as bool?,
    activity: json['activity'] as String?,
    timestamp: json['timestamp'] as int,
  );
}
