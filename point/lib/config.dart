import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static String serverUrl = '';
  static String wsUrl = '';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString('server_url') ?? '';
    wsUrl = _buildWsUrl(serverUrl);
  }

  static Future<void> setServerUrl(String url) async {
    serverUrl = _normalizeUrl(url);
    wsUrl = _buildWsUrl(serverUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', serverUrl);
  }

  static String _normalizeUrl(String url) {
    var cleaned = url.trim();
    // Strip any existing protocol to avoid double-protocol
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://'), '');
    // Remove trailing slashes and paths
    cleaned = cleaned.replaceFirst(RegExp(r'/+$'), '');
    // Add protocol — default to https, allow http for local IPs
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
