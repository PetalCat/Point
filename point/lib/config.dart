import 'package:shared_preferences/shared_preferences.dart';
import 'models/map_provider.dart';

enum PushProvider {
  firebase('Firebase (Google)', 'Push notifications via Google. Works out of the box.'),
  unified('UnifiedPush', 'Self-hostable push via ntfy, gotify, etc. No Google.'),
  none('Disabled', 'No push notifications. App checks for updates when opened.');

  final String label;
  final String description;
  const PushProvider(this.label, this.description);
}

class AppConfig {
  static String serverUrl = '';
  static String wsUrl = '';
  static MapProviderType mapProvider = MapProviderType.google;
  static String? mapboxToken;
  static String? selfHostedTileUrl;
  static String? selfHostedToken;
  static PushProvider pushProvider = PushProvider.firebase;
  static String? unifiedPushEndpoint;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString('server_url') ?? '';
    wsUrl = _buildWsUrl(serverUrl);

    final mapStr = prefs.getString('map_provider') ?? 'google';
    mapProvider = MapProviderType.values.firstWhere(
      (e) => e.name == mapStr,
      orElse: () => MapProviderType.google,
    );
    mapboxToken = prefs.getString('mapbox_token');
    selfHostedTileUrl = prefs.getString('self_hosted_tile_url');
    selfHostedToken = prefs.getString('self_hosted_token');
    final pushStr = prefs.getString('push_provider') ?? 'firebase';
    pushProvider = PushProvider.values.firstWhere(
      (e) => e.name == pushStr, orElse: () => PushProvider.firebase);
    unifiedPushEndpoint = prefs.getString('unified_push_endpoint');
  }

  static Future<void> setServerUrl(String url) async {
    serverUrl = _normalizeUrl(url);
    wsUrl = _buildWsUrl(serverUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', serverUrl);
  }

  static Future<void> setMapProvider(MapProviderType provider, {String? token, String? tileUrl, String? selfToken}) async {
    mapProvider = provider;
    if (provider == MapProviderType.mapbox) mapboxToken = token ?? mapboxToken;
    if (provider == MapProviderType.selfHosted) {
      selfHostedTileUrl = tileUrl ?? selfHostedTileUrl;
      selfHostedToken = selfToken ?? token ?? selfHostedToken;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('map_provider', provider.name);
    if (token != null && provider == MapProviderType.mapbox) await prefs.setString('mapbox_token', token);
    if (tileUrl != null) await prefs.setString('self_hosted_tile_url', tileUrl);
    if (selfToken != null || (token != null && provider == MapProviderType.selfHosted)) {
      await prefs.setString('self_hosted_token', selfToken ?? token!);
    }
  }

  static String _normalizeUrl(String url) {
    var cleaned = url.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'/+$'), '');
    final isLocal = cleaned.startsWith('localhost') ||
        cleaned.startsWith('127.') ||
        cleaned.startsWith('10.') ||
        cleaned.startsWith('192.168.');
    return '${isLocal ? 'http' : 'https'}://$cleaned';
  }

  static String _buildWsUrl(String httpUrl) {
    if (httpUrl.isEmpty) return '';
    return '${httpUrl.replaceFirst('http', 'ws')}/ws';
  }

  static Future<void> setPushProvider(PushProvider provider, {String? endpoint}) async {
    pushProvider = provider;
    unifiedPushEndpoint = endpoint ?? unifiedPushEndpoint;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('push_provider', provider.name);
    if (endpoint != null) await prefs.setString('unified_push_endpoint', endpoint);
  }

  static bool get isFirebaseEnabled => pushProvider == PushProvider.firebase;

  static bool get isConfigured => serverUrl.isNotEmpty;
}
