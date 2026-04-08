import 'package:shared_preferences/shared_preferences.dart';
import 'models/map_provider.dart';

class AppConfig {
  static String serverUrl = '';
  static String wsUrl = '';
  static MapProviderType mapProvider = MapProviderType.google;
  static String? mapboxToken;
  static String? selfHostedTileUrl;
  static String? selfHostedToken;

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

  static bool get isConfigured => serverUrl.isNotEmpty;
}
