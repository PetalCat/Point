import 'dart:math';

double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const r = 3959.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

String formatTimeAgo(int secondsAgo) {
  if (secondsAgo < 60) return 'now';
  if (secondsAgo < 3600) return '${secondsAgo ~/ 60}m ago';
  if (secondsAgo < 86400) return '${secondsAgo ~/ 3600}h ago';
  return '${secondsAgo ~/ 86400}d ago';
}

String? speedLabel(double? speedMps) {
  if (speedMps == null || speedMps < 0.5) return null;
  final mph = (speedMps * 2.237).round();
  final activity = speedMps < 2.0
      ? 'walking'
      : speedMps < 5.0
      ? 'cycling'
      : 'driving';
  return '$activity \u00b7 $mph mph';
}
