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

/// Extract display name from a user ID (local or federated).
/// "alice" → "alice"
/// "alice@point.petalcat.dev" → "alice"
String displayName(String userId) {
  return userId.split('@').first;
}

/// Extract the domain from a federated user ID, or null if local.
String? userDomain(String userId) {
  if (!userId.contains('@')) return null;
  final parts = userId.split('@');
  if (parts.length < 2 || !parts[1].contains('.')) return null;
  return parts[1];
}

/// Check if a user ID is federated (from a remote server).
bool isFederatedUser(String userId, {String? localDomain}) {
  final domain = userDomain(userId);
  if (domain == null) return false;
  if (localDomain != null) return domain != localDomain;
  return true;
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
