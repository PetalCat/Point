import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'providers.dart';
import 'providers/ghost_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

import 'config.dart';
import 'services/notification_service.dart';
import 'src/rust/frb_generated.dart';

class ThemeModeState {
  final ThemeMode mode;
  const ThemeModeState({this.mode = ThemeMode.system});
  ThemeModeState copyWith({ThemeMode? mode}) {
    return ThemeModeState(mode: mode ?? this.mode);
  }
}

class ThemeNotifier extends Notifier<ThemeModeState> {
  @override
  ThemeModeState build() {
    _load();
    return const ThemeModeState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode') ?? 'system';
    final mode = saved == 'dark' ? ThemeMode.dark : saved == 'light' ? ThemeMode.light : ThemeMode.system;
    state = state.copyWith(mode: mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
  }
}

// Handle background FCM messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppConfig.load();
  await NotificationService.init();
  await GhostNotifier.initBackground();

  // FCM setup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission(alert: true, badge: true, sound: true);
  final fcmToken = await fcm.getToken();
  if (fcmToken != null) {
    debugPrint('FCM Token: $fcmToken');
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

  runApp(const ProviderScope(child: PointApp()));
}

class PointApp extends ConsumerWidget {
  const PointApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeState = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Point',
      debugShowCheckedModeBanner: false,
      theme: PointTheme.light(),
      darkTheme: PointTheme.dark(),
      themeMode: themeModeState.mode,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
