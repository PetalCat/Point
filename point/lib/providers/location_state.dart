import 'package:geolocator/geolocator.dart';

import '../models/learned_zone.dart';
import '../services/location_service.dart';

class TrailPoint {
  final double lat;
  final double lon;
  final int timestamp;
  TrailPoint(this.lat, this.lon, this.timestamp);
}

class PersonLocation {
  final String userId;
  final double lat;
  final double lon;
  final String sourceType;
  final int timestamp;
  final int? battery;
  final bool? charging;
  final String? activity;
  final double? speed;
  final bool online;
  final String precision;

  PersonLocation({
    required this.userId,
    required this.lat,
    required this.lon,
    required this.sourceType,
    required this.timestamp,
    this.battery,
    this.charging,
    this.activity,
    this.speed,
    this.online = true,
    this.precision = 'exact',
  });

  PersonLocation copyWith({
    double? lat,
    double? lon,
    String? sourceType,
    int? timestamp,
    int? battery,
    bool? charging,
    String? activity,
    double? speed,
    bool? online,
    String? precision,
  }) {
    return PersonLocation(
      userId: userId,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      sourceType: sourceType ?? this.sourceType,
      timestamp: timestamp ?? this.timestamp,
      battery: battery ?? this.battery,
      charging: charging ?? this.charging,
      activity: activity ?? this.activity,
      speed: speed ?? this.speed,
      online: online ?? this.online,
      precision: precision ?? this.precision,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId, 'lat': lat, 'lon': lon, 'sourceType': sourceType,
    'timestamp': timestamp, 'battery': battery, 'charging': charging, 'activity': activity,
    'speed': speed, 'precision': precision,
  };

  factory PersonLocation.fromJson(Map<String, dynamic> j) => PersonLocation(
    userId: j['userId'] ?? '',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    sourceType: j['sourceType'] ?? 'cached',
    timestamp: j['timestamp'] ?? 0,
    battery: j['battery'],
    charging: j['charging'],
    activity: j['activity'],
    speed: (j['speed'] as num?)?.toDouble(),
    online: false,
    precision: j['precision'] ?? 'exact',
  );
}

class LocationState {
  final Map<String, PersonLocation> people;
  final Map<String, List<TrailPoint>> trails;
  final Position? myPosition;
  final bool isGhostMode;
  final List<Map<String, dynamic>> places;
  final String? viewingUserId;
  final DateTime? lastLocationSent;
  final String? myUserId;
  final List<String> activeGroupIds;
  final List<String> activeUserIds;
  final Set<String> zoneConsentedUsers;
  final LocationActivity activity;
  final LearnedZone? currentZone;
  final bool permissionDenied;

  /// Derived: sharing is active when the activity state implies relay.
  bool get isSharing =>
      activity == LocationActivity.active ||
      activity == LocationActivity.fast;

  const LocationState({
    this.people = const {},
    this.trails = const {},
    this.myPosition,
    this.isGhostMode = false,
    this.places = const [],
    this.viewingUserId,
    this.lastLocationSent,
    this.myUserId,
    this.activeGroupIds = const [],
    this.activeUserIds = const [],
    this.zoneConsentedUsers = const {},
    this.activity = LocationActivity.sleeping,
    this.currentZone,
    this.permissionDenied = false,
  });

  LocationState copyWith({
    Map<String, PersonLocation>? people,
    Map<String, List<TrailPoint>>? trails,
    Position? myPosition,
    bool? isGhostMode,
    List<Map<String, dynamic>>? places,
    String? viewingUserId,
    DateTime? lastLocationSent,
    String? myUserId,
    List<String>? activeGroupIds,
    List<String>? activeUserIds,
    Set<String>? zoneConsentedUsers,
    LocationActivity? activity,
    LearnedZone? currentZone,
    bool? permissionDenied,
    bool clearViewingUserId = false,
    bool clearMyPosition = false,
    bool clearCurrentZone = false,
  }) {
    return LocationState(
      people: people ?? this.people,
      trails: trails ?? this.trails,
      myPosition: clearMyPosition ? null : (myPosition ?? this.myPosition),
      isGhostMode: isGhostMode ?? this.isGhostMode,
      places: places ?? this.places,
      viewingUserId:
          clearViewingUserId ? null : (viewingUserId ?? this.viewingUserId),
      lastLocationSent: lastLocationSent ?? this.lastLocationSent,
      myUserId: myUserId ?? this.myUserId,
      activeGroupIds: activeGroupIds ?? this.activeGroupIds,
      activeUserIds: activeUserIds ?? this.activeUserIds,
      zoneConsentedUsers: zoneConsentedUsers ?? this.zoneConsentedUsers,
      activity: activity ?? this.activity,
      currentZone: clearCurrentZone ? null : (currentZone ?? this.currentZone),
      permissionDenied: permissionDenied ?? this.permissionDenied,
    );
  }
}
