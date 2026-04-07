class LocationData {
  final double lat;
  final double lon;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? battery;
  final String? activity;
  final int timestamp;

  LocationData({
    required this.lat,
    required this.lon,
    this.accuracy,
    this.speed,
    this.heading,
    this.battery,
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
    'activity': activity,
    'timestamp': timestamp,
  };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    speed: (json['speed'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
    battery: json['battery'] as int?,
    activity: json['activity'] as String?,
    timestamp: json['timestamp'] as int,
  );
}
