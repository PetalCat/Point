import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'providers/auth_provider.dart';
import 'providers/ghost_provider.dart' show GhostProvider;
import 'providers/group_provider.dart';
import 'providers/item_provider.dart';
import 'providers/location_provider.dart';
import 'providers/sharing_provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/ws_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

import 'config.dart';
import 'services/crypto_service.dart';
import 'src/rust/frb_generated.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeNotifier() { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode') ?? 'system';
    _mode = saved == 'dark' ? ThemeMode.dark : saved == 'light' ? ThemeMode.light : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
    notifyListeners();
  }
}

// Handle background FCM messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Wake-up push — the app will connect WS and process events when opened
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppConfig.load();
  await NotificationService.init();
  await GhostProvider.initBackground();

  // FCM setup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);
  final fcmToken = await fcm.getToken();
  if (fcmToken != null) {
    debugPrint('FCM Token: $fcmToken');
    // Token will be sent to server after login (in home_screen initServices)
  }

  // Handle foreground FCM messages
  FirebaseMessaging.onMessage.listen((message) {
    if (message.notification != null) {
      NotificationService.show(
        title: message.notification!.title ?? 'Point',
        body: message.notification!.body ?? '',
      );
    }
  });

  runApp(const PointApp());
}

class PointApp extends StatelessWidget {
  const PointApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    final authService = AuthService();
    final wsService = WsService();
    final locationService = LocationService();
    final cryptoService = CryptoService(apiService);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => GhostProvider()),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService, authService)),
        ChangeNotifierProvider(create: (_) => GroupProvider(apiService)),
        ChangeNotifierProvider(create: (_) => ItemProvider(apiService)),
        ChangeNotifierProvider(create: (_) => SharingProvider(apiService)),
        ChangeNotifierProvider(
            create: (_) => LocationProvider(wsService, locationService, cryptoService)),
        Provider.value(value: wsService),
        Provider.value(value: apiService),
        Provider.value(value: cryptoService),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) => MaterialApp(
          title: 'Point',
          debugShowCheckedModeBanner: false,
          theme: PointTheme.light(),
          darkTheme: PointTheme.dark(),
          themeMode: themeNotifier.mode,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
