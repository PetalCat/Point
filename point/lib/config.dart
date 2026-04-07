import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static String serverUrl = '';
  static String wsUrl = '';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString('server_url') ?? '';
    wsUrl = serverUrl.isNotEmpty
        ? '${serverUrl.replaceFirst('http', 'ws')}/ws'
        : '';
  }

  static Future<void> setServerUrl(String url) async {
    var cleaned = url.trim();
    if (!cleaned.startsWith('http')) cleaned = 'http://\$cleaned';
    if (cleaned.endsWith('/'))
      cleaned = cleaned.substring(0, cleaned.length - 1);
    serverUrl = cleaned;
    wsUrl = '${cleaned.replaceFirst('http', 'ws')}/ws';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', serverUrl);
  }

  static bool get isConfigured => serverUrl.isNotEmpty;
}
