import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'providers.dart';
import 'providers/ghost_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

import 'config.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
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

// Handle background FCM messages (only when Firebase is enabled).
// Runs in a separate isolate with no provider access, so it does only
// isolate-safe work: surface user-visible geofence/share alerts as local
// notifications. Privacy-sensitive content is never carried in the push —
// these are wake/notify signals only (P1-12).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  final type = data['type'] as String?;
  if (type == 'place.triggered') {
    await NotificationService.init();
    final name = data['place_name'] as String? ?? 'a place';
    final event = data['event'] as String?;
    final who = (data['user_id'] as String?)?.split('@').first ?? 'Someone';
    await NotificationService.show(
      title: event == 'enter' ? 'Arrived' : 'Left',
      body: '$who ${event == 'enter' ? 'arrived at' : 'left'} $name',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;
  try {
    if (defaultTargetPlatform != TargetPlatform.iOS) await RustLib.init();
    await AppConfig.load();
    await NotificationService.init();
    await GhostNotifier.initBackground();

    // Only init Firebase if enabled and the platform has a config.
    // iOS/macOS have no GoogleService-Info.plist yet, so skip there.
    final firebaseSupported = defaultTargetPlatform == TargetPlatform.android;
    if (AppConfig.isFirebaseEnabled && firebaseSupported) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e, st) {
    startupError = '$e\n\n$st';
  }

  runApp(ProviderScope(child: startupError != null
      ? _StartupErrorApp(error: startupError!)
      : const PointApp()));
}

class _StartupErrorApp extends StatelessWidget {
  final String error;
  const _StartupErrorApp({required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'STARTUP CRASH\n\n$error',
            style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
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
    return auth.isLoggedIn ? const HomeScreen() : const OnboardingScreen();
  }
}
