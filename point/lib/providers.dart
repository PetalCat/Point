import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/ws_service.dart';
import 'services/location_service.dart';
import 'services/crypto_service.dart';
import 'services/relay_buffer.dart';
import 'services/zone_learning_service.dart';
import 'providers/auth_provider.dart';
import 'providers/group_provider.dart';
import 'providers/sharing_provider.dart';
import 'providers/location_provider.dart';
import 'providers/ghost_provider.dart';
import 'providers/item_provider.dart';
import 'main.dart' show ThemeNotifier, ThemeModeState;

export 'providers/auth_provider.dart' show AuthState, AuthNotifier;
export 'providers/group_provider.dart' show GroupState, GroupNotifier;
export 'providers/sharing_provider.dart' show SharingState, SharingNotifier;
export 'providers/location_provider.dart' show LocationState, LocationNotifier, PersonLocation, TrailPoint;
export 'models/learned_zone.dart' show LearnedZone;
export 'services/zone_learning_service.dart' show ZoneLearningService;
export 'providers/ghost_provider.dart' show GhostState, GhostNotifier;
export 'providers/item_provider.dart' show ItemState, ItemNotifier;
export 'main.dart' show ThemeModeState, ThemeNotifier;

// Singleton services
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final wsServiceProvider = Provider<WsService>((ref) => WsService());
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService(ref.watch(apiServiceProvider)));
final relayBufferProvider = Provider<RelayBuffer>((ref) => RelayBuffer());
final zoneLearningServiceProvider = Provider<ZoneLearningService>((ref) => ZoneLearningService());

// Notifier providers
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
final groupProvider = NotifierProvider<GroupNotifier, GroupState>(GroupNotifier.new);
final sharingProvider = NotifierProvider<SharingNotifier, SharingState>(SharingNotifier.new);
final locationProvider = NotifierProvider<LocationNotifier, LocationState>(LocationNotifier.new);
final ghostProvider = NotifierProvider<GhostNotifier, GhostState>(GhostNotifier.new);
final itemProvider = NotifierProvider<ItemNotifier, ItemState>(ItemNotifier.new);
final themeProvider = NotifierProvider<ThemeNotifier, ThemeModeState>(ThemeNotifier.new);
