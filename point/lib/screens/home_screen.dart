import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../config.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../providers/group_provider.dart';
import '../providers/item_provider.dart';
import '../providers/location_provider.dart';
import '../providers/sharing_provider.dart';
import '../services/api_service.dart';
import '../main.dart' show ThemeNotifier;
import '../providers/ghost_provider.dart';
import '../services/crypto_service.dart';
import '../screens/ghost_rules_screen.dart';
import '../widgets/ghost_bottom_sheet.dart';
import '../services/notification_service.dart';
import '../services/ws_service.dart';
import '../widgets/filter_bar.dart';
import '../widgets/map_view.dart';
import '../widgets/people_drawer.dart';
import 'group_detail_screen.dart';
import 'person_history_screen.dart';
import 'place_creation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterMode _filterMode = FilterMode.all;
  int _currentTab = 0;
  int _sharingFilter = 0; // 0=All, 1=People, 2=Groups, 3=Requests
  bool _showTrails = true;
  String? _selectedPersonId;
  final _mapKey = GlobalKey<MapViewState>();
  StreamSubscription<Map<String, dynamic>>? _geofenceSubscription;
  final List<Map<String, dynamic>> _recentGeofenceEvents = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServices());
  }

  Future<void> _initServices() async {
    final auth = context.read<AuthProvider>();
    final ws = context.read<WsService>();
    final groups = context.read<GroupProvider>();
    final location = context.read<LocationProvider>();

    if (auth.token != null) ws.connect(auth.token!);
    ws.sendPresence();
    location.setMyUserId(auth.userId ?? '');
    final ghostProvider = context.read<GhostProvider>();
    location.setGhostProvider(ghostProvider);
    ghostProvider.setApiService(context.read<ApiService>());

    // Initialize MLS encryption
    final crypto = context.read<CryptoService>();
    try {
      final domain = Uri.parse(AppConfig.serverUrl).host;
      final identity = '${auth.userId}@$domain';
      await crypto.init(identity);
    } catch (e) {
      debugPrint('MLS init: $e');
    }

    // Wire crypto into providers
    groups.setCryptoService(crypto);
    final sharing = context.read<SharingProvider>();
    sharing.setCryptoService(crypto);
    sharing.setMyUserId(auth.userId ?? '');

    // Listen for real-time MLS messages (Welcome/Commit)
    ws.messages.listen((msg) {
      if (msg['type'] == 'mls.message') {
        crypto.handleMlsWsMessage(msg);
      }
    });

    // Process any pending MLS messages (Welcomes from while we were offline)
    await crypto.processPendingMessages();

    // Register FCM token with server
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && context.mounted) {
        await context.read<ApiService>().registerFcmToken(fcmToken);
      }
    } catch (e) {
      debugPrint('FCM token registration: $e');
    }

    await groups.loadGroups();
    location.setActiveGroups(groups.groups.map((g) => g.id).toList());

    // Set up MLS encryption for all groups
    await groups.setupEncryptionForAllGroups(auth.userId ?? '');

    // Load places (geofences) for all groups + personal places
    if (context.mounted) {
      final api = context.read<ApiService>();
      final allPlaces = <Map<String, dynamic>>[];
      for (final g in groups.groups) {
        try {
          final places = await api.listPlaces(g.id);
          allPlaces.addAll(places);
        } catch (_) {
          // Skip groups where places can't be loaded
        }
      }
      try {
        final personalPlaces = await api.listPersonalPlaces();
        allPlaces.addAll(personalPlaces);
      } catch (_) {
        // Personal places endpoint may not be available yet
      }
      location.setPlaces(allPlaces);
    }

    // Listen for geofence enter/exit events
    _geofenceSubscription = location.geofenceEvents.listen((event) {
      if (mounted) {
        setState(() {
          _recentGeofenceEvents.insert(0, {
            ...event,
            'time': DateTime.now().toIso8601String(),
          });
          if (_recentGeofenceEvents.length > 50)
            _recentGeofenceEvents.removeLast();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${event['event'] == 'enter' ? 'Arrived at' : 'Left'} ${event['place_name']}',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      NotificationService.show(
        title: event['event'] == 'enter' ? 'Arrived' : 'Left',
        body:
            '${event['triggered_by']?.split('@').first ?? 'Someone'} ${event['event'] == 'enter' ? 'arrived at' : 'left'} ${event['place_name']}',
      );
    });

    if (context.mounted) context.read<ItemProvider>().loadItems();
    if (context.mounted) {
      final sharing = context.read<SharingProvider>();
      sharing.listenToWs(ws); // Auto-refresh on WS share events
      await sharing.loadAll();
      if (context.mounted) {
        final userIds = sharing.shares
            .map((s) => s['user_id'] as String)
            .toList();
        context.read<LocationProvider>().setActiveUserIds(userIds);
      }
    }

    // Load zone consents so personal zones only evaluate consented users
    if (context.mounted) {
      try {
        final api = context.read<ApiService>();
        final grantedConsents = await api.listGrantedZoneConsents();
        if (context.mounted) {
          context.read<LocationProvider>().setZoneConsentedUsers(
            grantedConsents.map((c) => c['consenter_id'] as String).toList(),
          );
        }
      } catch (e) {
        debugPrint('Zone consents load: $e');
      }
    }
  }

  @override
  void dispose() {
    _geofenceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentTab,
                children: [
                  _buildMapTab(),
                  _buildSharingTab(),
                  _buildInboxTab(),
                  _buildProfileTab(),
                ],
              ),
            ),
            _buildTabBar(),
          ],
        ),
      ),
    );
  }

  void _selectPerson(String userId) {
    setState(() => _selectedPersonId = userId);
    _mapKey.currentState?.followUser(userId);
  }

  void _deselectPerson() {
    setState(() => _selectedPersonId = null);
    _mapKey.currentState?.followUser(null);
  }

  Widget _buildPersonDetailInDrawer(
    String userId,
    ScrollController scrollController,
  ) {
    final locationProvider = context.watch<LocationProvider>();
    final person = locationProvider.people[userId];
    final myPos = locationProvider.myPosition;
    final name = userId.split('@').first;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = PointColors.colorForUser(userId);

    if (person == null) {
      // Person left or data unavailable — go back
      WidgetsBinding.instance.addPostFrameCallback((_) => _deselectPerson());
      return const SizedBox.shrink();
    }

    final isStale =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - person.timestamp) >
        7200;
    final speed = person.speed;
    final battery = person.battery;

    // Activity label
    String activityLabel;
    if (speed == null || speed < 0.5) {
      activityLabel = 'Stationary';
    } else if (speed < 2.0) {
      activityLabel = 'Walking';
    } else if (speed < 5.0) {
      activityLabel = 'Cycling';
    } else {
      activityLabel = 'Driving';
    }

    // Time ago
    final msAgo = DateTime.now().millisecondsSinceEpoch - person.timestamp;
    String timeAgo;
    if (msAgo < 60000) {
      timeAgo = 'just now';
    } else if (msAgo < 3600000) {
      timeAgo = '${msAgo ~/ 60000}m ago';
    } else if (msAgo < 86400000) {
      timeAgo = '${msAgo ~/ 3600000}h ago';
    } else {
      timeAgo = '${msAgo ~/ 86400000}d ago';
    }

    // Distance
    String distanceLabel = '--';
    if (myPos != null) {
      final meters = _haversine(
        myPos.latitude,
        myPos.longitude,
        person.lat,
        person.lon,
      );
      final miles = meters / 1609.344;
      if (miles < 0.1) {
        distanceLabel = '${meters.round()} ft';
      } else if (miles < 10) {
        distanceLabel = '${miles.toStringAsFixed(1)} mi';
      } else {
        distanceLabel = '${miles.round()} mi';
      }
    }

    // Speed label
    String speedLabel;
    if (speed == null || speed < 0.5) {
      speedLabel = '0 mph';
    } else {
      speedLabel = '${(speed * 2.237).round()} mph';
    }

    // Battery
    String batteryLabel = battery != null ? '$battery%' : '--';
    IconData batteryIcon;
    Color batteryColor;
    if (battery == null) {
      batteryIcon = Icons.battery_unknown;
      batteryColor = PointColors.textSecondary;
    } else if (battery > 50) {
      batteryIcon = Icons.battery_full;
      batteryColor = PointColors.online;
    } else if (battery > 20) {
      batteryIcon = Icons.battery_3_bar;
      batteryColor = const Color(0xFFFFAB00);
    } else {
      batteryIcon = Icons.battery_1_bar;
      batteryColor = PointColors.danger;
    }

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.dividerClr,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Back button + name
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _deselectPerson,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: context.subtleBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: context.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: context.primaryText,
                            ),
                          ),
                          Text(
                            '${person.online && !isStale ? "Online" : "Offline"}  \u00b7  $timeAgo',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Stats row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _drawerStatBox(
                      Icons.near_me_outlined,
                      color,
                      'Distance',
                      distanceLabel,
                    ),
                    const SizedBox(width: 8),
                    _drawerStatBox(Icons.speed, color, 'Speed', speedLabel),
                    const SizedBox(width: 8),
                    _drawerStatBox(
                      batteryIcon,
                      batteryColor,
                      'Battery',
                      batteryLabel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // View History button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonHistoryScreen(
                        userId: userId,
                        displayName: name,
                        userColor: PointColors.colorForUser(userId),
                      ),
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: context.subtleBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'View History',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PointColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Stop following button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: _deselectPerson,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: context.subtleBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Stop following',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Current status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: context.tertiaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.subtleBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            activityLabel == 'Stationary'
                                ? Icons.pause_circle_outline
                                : activityLabel == 'Walking'
                                ? Icons.directions_walk
                                : activityLabel == 'Cycling'
                                ? Icons.directions_bike
                                : Icons.directions_car,
                            size: 18,
                            color: color,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            activityLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.primaryText,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ],
    );
  }

  Widget _drawerStatBox(
    IconData icon,
    Color iconColor,
    String label,
    String value,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: context.subtleBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  String _ghostTimerText(GhostProvider ghost) {
    if (ghost.timerExpiry == null) return '';
    final diff = ghost.timerExpiry!.difference(DateTime.now());
    if (diff.isNegative) return '';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  // ==================== MAP TAB ====================
  Widget _buildMapTab() {
    final ghost = context.watch<GhostProvider>();
    final ghostMode = ghost.isGhostActive || context.watch<LocationProvider>().isGhostMode;

    // NORMAL MAP MODE
    return Stack(
      children: [
        Positioned.fill(
          child: MapView(
            key: _mapKey,
            onPersonTap: _selectPerson,
            showTrails: _showTrails,
            onLongPress: (pos) async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaceCreationScreen(initialPosition: pos),
                ),
              );
              if (result == true && mounted) {
                // Reload places
                final api = context.read<ApiService>();
                final groupProvider = context.read<GroupProvider>();
                final location = context.read<LocationProvider>();
                final allPlaces = <Map<String, dynamic>>[];
                for (final g in groupProvider.groups) {
                  try {
                    final places = await api.listPlaces(g.id);
                    allPlaces.addAll(places);
                  } catch (_) {}
                }
                try {
                  final personalPlaces = await api.listPersonalPlaces();
                  allPlaces.addAll(personalPlaces);
                } catch (_) {}
                location.setPlaces(allPlaces);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Place saved'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ),
        // Filter bar
        Positioned(
          top: 12,
          left: 14,
          child: Row(
            children: [
              ...FilterMode.values.map((mode) {
                final active = mode == _filterMode;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterMode = mode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: active ? PointColors.accent : context.cardBg,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          if (active)
                            const BoxShadow(
                              color: PointColors.accentGlow,
                              blurRadius: 14,
                              offset: Offset(0, 3),
                            ),
                          if (!active)
                            BoxShadow(
                              color: context.shadowClr,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Text(
                        mode.name[0].toUpperCase() + mode.name.substring(1),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : context.secondaryText,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // Connection state indicator
        Positioned(
          top: 52,
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: context.read<WsService>().connectionState,
              builder: (context, connected, _) {
                if (connected) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE53935).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Text(
                    '\u26A0 Disconnected \u2014 reconnecting...',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Ghost mode indicator — tappable
        if (ghostMode)
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => GhostBottomSheet.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '\u{1F47B} Ghost Mode',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (ghost.hasActiveTimer) ...[
                        const SizedBox(width: 6),
                        Text(
                          _ghostTimerText(ghost),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: PointColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Map controls — right side
        Positioned(
          top: 12,
          right: 14,
          child: Column(
            children: [
              GestureDetector(
                onTap: () => _mapKey.currentState?.fitAllMarkers(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: context.shadowClr,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.fit_screen_rounded,
                    size: 18,
                    color: context.secondaryText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Ghost mode button
              GestureDetector(
                onTap: () => GhostBottomSheet.show(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ghostMode ? PointColors.accent : context.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (ghostMode)
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      if (!ghostMode)
                        BoxShadow(
                          color: context.shadowClr,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Center(
                    child: Text('👻',
                        style: TextStyle(
                            fontSize: ghostMode ? 18 : 16)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showTrails = !_showTrails),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _showTrails ? PointColors.accent : context.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (_showTrails)
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      if (!_showTrails)
                        BoxShadow(
                          color: context.shadowClr,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Icon(
                    Icons.timeline,
                    size: 18,
                    color: _showTrails
                        ? Colors.white
                        : PointColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Drawer
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.06,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.06, 0.35, 0.85],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: context.shadowClr,
                  blurRadius: 30,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: _selectedPersonId != null
                ? _buildPersonDetailInDrawer(
                    _selectedPersonId!,
                    scrollController,
                  )
                : PeopleDrawer(
                    scrollController: scrollController,
                    filterMode: _filterMode,
                    onPersonTap: _selectPerson,
                  ),
          ),
        ),
      ],
    );
  }

  // ==================== SHARING TAB ====================
  Widget _buildSharingTab() {
    final groups = context.watch<GroupProvider>();
    final sharing = context.watch<SharingProvider>();
    final filterLabels = ['All', 'People', 'Groups', 'Requests'];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        const SizedBox(height: 14),
        // Title row
        Row(
          children: [
            Text(
              'Sharing',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: context.primaryText,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _showAddShareDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: PointColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    const BoxShadow(
                      color: PointColors.accentGlow,
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  '+ Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Filter pills
        Row(
          children: List.generate(filterLabels.length, (i) {
            final active = _sharingFilter == i;
            final label = filterLabels[i];
            final badge = (i == 3 && sharing.pendingCount > 0)
                ? sharing.pendingCount
                : 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _sharingFilter = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: active ? PointColors.accent : context.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      if (active)
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      if (!active)
                        BoxShadow(
                          color: context.shadowClr,
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : context.secondaryText,
                        ),
                      ),
                      if (badge > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white.withValues(alpha: 0.3)
                                : PointColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$badge',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: active ? Colors.white : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        // Content
        if (_sharingFilter == 0 || _sharingFilter == 1) ...[
          // People section
          if (sharing.shares.isNotEmpty) ...[
            if (_sharingFilter == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  'PEOPLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: PointColors.textTertiary,
                  ),
                ),
              ),
            ...sharing.shares.map((s) => _buildPersonShareRow(s, sharing)),
          ],
          if (sharing.shares.isEmpty && _sharingFilter == 1)
            _buildEmptyState(Icons.person_outline, 'No people sharing yet'),
        ],
        if (_sharingFilter == 0 || _sharingFilter == 2) ...[
          // Groups section
          if (_sharingFilter == 0 && sharing.shares.isNotEmpty)
            const SizedBox(height: 10),
          if (groups.groups.isNotEmpty) ...[
            if (_sharingFilter == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  'GROUPS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: PointColors.textTertiary,
                  ),
                ),
              ),
            ...groups.groups.map((g) => _buildGroupCard(g, groups)),
          ],
          // Join by Code / New Group action row
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showJoinByCodeDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code,
                            size: 16,
                            color: Color(0xFF3F51FF),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Join by Code',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3F51FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _showCreateGroupDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 16, color: Color(0xFF3F51FF)),
                          SizedBox(width: 6),
                          Text(
                            'New Group',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3F51FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (groups.groups.isEmpty && _sharingFilter == 2)
            _buildEmptyState(Icons.group_outlined, 'No groups yet'),
        ],
        // Requests — show in All (filter 0) AND Requests (filter 3)
        if (_sharingFilter == 0 || _sharingFilter == 3) ...[
          if (sharing.incomingRequests.isNotEmpty) ...[
            if (_sharingFilter == 0 &&
                (sharing.shares.isNotEmpty || groups.groups.isNotEmpty))
              const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                'INCOMING REQUESTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: PointColors.textTertiary,
                ),
              ),
            ),
            ...sharing.incomingRequests.map(
              (r) => _buildIncomingRequestRow(r, sharing),
            ),
          ],
          if (sharing.outgoingRequests.isNotEmpty) ...[
            if (sharing.incomingRequests.isNotEmpty) const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                'SENT REQUESTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: PointColors.textTertiary,
                ),
              ),
            ),
            ...sharing.outgoingRequests.map((r) => _buildOutgoingRequestRow(r)),
          ],
          if (_sharingFilter == 3 &&
              sharing.incomingRequests.isEmpty &&
              sharing.outgoingRequests.isEmpty)
            _buildEmptyState(Icons.swap_horiz, 'No pending requests'),
        ],
        if (_sharingFilter == 0 &&
            sharing.shares.isEmpty &&
            groups.groups.isEmpty &&
            sharing.incomingRequests.isEmpty &&
            sharing.outgoingRequests.isEmpty)
          _buildEmptyState(Icons.share_outlined, 'No sharing yet'),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.tertiaryText),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonShareRow(
    Map<String, dynamic> share,
    SharingProvider sharing,
  ) {
    final userId = share['user_id'] as String? ?? '';
    final name = userId.split('@').first;
    return GestureDetector(
      onTap: () => _showPersonSheet(userId, sharing),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PointColors.colorForUser(userId),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: PointColors.colorForUser(
                      userId,
                    ).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.primaryText,
                    ),
                  ),
                  Text(
                    'Mutual sharing',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: PointColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonSheet(String userId, SharingProvider sharing) {
    final name = userId.split('@').first;
    final color = PointColors.colorForUser(userId);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Avatar + name
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                userId,
                style: const TextStyle(
                  fontSize: 12,
                  color: PointColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              _sheetAction(Icons.location_on, 'Find on map', () {
                Navigator.pop(ctx);
                setState(() => _currentTab = 0); // Switch to map
              }),
              _sheetAction(
                Icons.notifications_outlined,
                'Notify when nearby',
                () {
                  Navigator.pop(ctx);
                  // Future: proximity alert setup
                },
              ),
              const SizedBox(height: 8),
              _sheetAction(Icons.remove_circle_outline, 'Stop sharing', () {
                Navigator.pop(ctx);
                sharing.removeShare(userId);
              }, danger: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? PointColors.danger : context.primaryText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFF5F5) : context.subtleBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequestRow(
    Map<String, dynamic> request,
    SharingProvider sharing,
  ) {
    final userId = request['from_user_id'] as String? ?? '';
    final requestId = request['id'] as String? ?? '';
    final name = userId.split('@').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PointColors.colorForUser(userId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.primaryText,
                  ),
                ),
                Text(
                  'wants to share with you',
                  style: TextStyle(fontSize: 11, color: context.secondaryText),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => sharing.rejectRequest(requestId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: PointColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Reject',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: PointColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => sharing.acceptRequest(requestId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: PointColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Accept',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutgoingRequestRow(Map<String, dynamic> request) {
    final userId = request['to_user_id'] as String? ?? '';
    final name = userId.split('@').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PointColors.colorForUser(userId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.primaryText,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Pending',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFFFF9800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(dynamic g, GroupProvider groups) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: g.id)),
        );
        groups.loadGroups();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: PointColors.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        g.name[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.primaryText,
                          ),
                        ),
                        Text(
                          '${g.members.length} member${g.members.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    '\u203a',
                    style: TextStyle(
                      fontSize: 18,
                      color: PointColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: 26,
                child: Stack(
                  children: g.members
                      .take(6)
                      .toList()
                      .asMap()
                      .entries
                      .map<Widget>((entry) {
                        final m = entry.value;
                        final name = m.userId.split('@').first;
                        return Positioned(
                          left: entry.key * 18.0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: PointColors.colorForUser(m.userId),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.cardBg,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddShareDialog() {
    final controller = TextEditingController();
    final domain =
        context.read<AuthProvider>().userId?.split('@').last ?? 'point.local';
    var selectedDuration = -1; // -1 = permanent, 0+ = minutes

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share Location',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),

              // Username input
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'username',
                  suffixText: '@$domain',
                  suffixStyle: const TextStyle(
                    color: PointColors.textSecondary,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: context.subtleBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: PointColors.accent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Duration selector
              const Text(
                'Duration',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: PointColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _durationChip(
                    'Permanent',
                    -1,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '1 hour',
                    60,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '8 hours',
                    480,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    'Until midnight',
                    _minutesUntilMidnight(),
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                  _durationChip(
                    '24 hours',
                    1440,
                    selectedDuration,
                    (v) => setSheetState(() => selectedDuration = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    var userId = controller.text.trim();
                    if (userId.isEmpty) return;
                    if (!userId.contains('@')) userId = '$userId@$domain';
                    Navigator.pop(ctx);

                    if (selectedDuration == -1) {
                      // Permanent share request
                      final success = await context
                          .read<SharingProvider>()
                          .sendRequest(userId);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Share request sent to ${userId.split('@').first}'
                                  : 'Failed to send request',
                            ),
                          ),
                        );
                      }
                    } else {
                      // Temp share
                      try {
                        await context.read<ApiService>().createTempShare(
                          userId,
                          selectedDuration,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Sharing with ${userId.split('@').first}',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PointColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    selectedDuration == -1
                        ? 'Send Share Request'
                        : 'Start Sharing',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationChip(
    String label,
    int value,
    int selected,
    ValueChanged<int> onSelect,
  ) {
    final active = value == selected;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? PointColors.accent : context.subtleBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  const BoxShadow(
                    color: PointColors.accentGlow,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : context.secondaryText,
          ),
        ),
      ),
    );
  }

  int _minutesUntilMidnight() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    return midnight.difference(now).inMinutes;
  }

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final group = await context.read<GroupProvider>().createGroup(
                controller.text.trim(),
              );
              if (group != null && context.mounted) {
                context.read<LocationProvider>().setActiveGroups(
                  context
                      .read<GroupProvider>()
                      .groups
                      .map((g) => g.id)
                      .toList(),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinByCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter invite code'),
          textCapitalization: TextCapitalization.none,
          style: const TextStyle(
            fontSize: 18,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await context.read<ApiService>().joinGroupByCode(code);
                await context.read<GroupProvider>().loadGroups();
                context.read<LocationProvider>().setActiveGroups(
                  context
                      .read<GroupProvider>()
                      .groups
                      .map((g) => g.id)
                      .toList(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined group!')),
                  );
                }
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  // ==================== INBOX TAB ====================
  int get _inboxItemCount {
    final sharing = context.read<SharingProvider>();
    final location = context.read<LocationProvider>();
    int count = sharing.incomingRequests.length + _recentGeofenceEvents.length;
    for (final person in location.people.values) {
      if (person.battery != null && person.battery! < 20 && person.online) {
        count++;
      }
    }
    return count;
  }

  Widget _buildInboxTab() {
    final sharing = context.watch<SharingProvider>();
    final location = context.watch<LocationProvider>();

    final items = <Widget>[];

    // Incoming share requests
    for (final req in sharing.incomingRequests) {
      items.add(
        _buildInboxItem(
          icon: Icons.person_add,
          iconBg: PointColors.accent,
          title:
              '${(req['from_user_id'] as String? ?? '').split('@').first} wants to share',
          subtitle: 'Share request',
          time: 'now',
          actions: [
            _inboxAction(
              'Accept',
              PointColors.accent,
              () => sharing.acceptRequest(req['id'] as String? ?? ''),
            ),
            _inboxAction(
              'Decline',
              PointColors.textSecondary,
              () => sharing.rejectRequest(req['id'] as String? ?? ''),
            ),
          ],
        ),
      );
    }

    // Geofence events
    for (final event in _recentGeofenceEvents) {
      items.add(
        _buildInboxItem(
          icon: event['event'] == 'enter'
              ? Icons.location_on
              : Icons.location_off,
          iconBg: event['event'] == 'enter'
              ? PointColors.online
              : PointColors.textSecondary,
          title:
              '${event['event'] == 'enter' ? 'Arrived at' : 'Left'} ${event['place_name']}',
          subtitle: event['triggered_by']?.split('@').first ?? 'You',
          time: _formatEventTime(event['time']),
        ),
      );
    }

    // Low battery warnings
    for (final person in location.people.values) {
      if (person.battery != null && person.battery! < 20 && person.online) {
        items.add(
          _buildInboxItem(
            icon: Icons.battery_alert,
            iconBg: PointColors.danger,
            title: '${person.userId.split('@').first}\'s battery is low',
            subtitle: '${person.battery}% remaining',
            time: 'now',
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        const SizedBox(height: 14),
        Text(
          'Inbox',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: context.primaryText,
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _buildEmptyState(Icons.inbox_outlined, 'No notifications yet')
        else
          ...items,
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildInboxItem({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String time,
    List<Widget>? actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: iconBg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.primaryText,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.tertiaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: context.secondaryText),
                ),
                if (actions != null && actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inboxAction(String label, Color color, VoidCallback onTap) {
    final isAccent = color == PointColors.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isAccent ? PointColors.accent : PointColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isAccent ? Colors.white : PointColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  String _formatEventTime(String? iso) {
    if (iso == null) return 'now';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'now';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ==================== PROFILE TAB ====================
  Widget _buildProfileTab() {
    final auth = context.watch<AuthProvider>();
    final groups = context.watch<GroupProvider>();
    final location = context.watch<LocationProvider>();
    final name = auth.displayName ?? 'User';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Profile card
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: PointColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        const BoxShadow(
                          color: PointColors.accentGlow,
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: context.primaryText,
                          ),
                        ),
                        Text(
                          auth.userId ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (auth.isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x143F51FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: PointColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Stats
              Row(
                children: [
                  _statBox('${groups.groups.length}', 'Groups'),
                  const SizedBox(width: 8),
                  _statBox('0', 'Bridges'),
                  const SizedBox(width: 8),
                  _statBoxAccent('📍', 'Sharing'),
                ],
              ),
            ],
          ),
        ),

        // Sharing controls
        Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              _toggleRow(
                '📍',
                'Location Sharing',
                'Sharing with ${groups.groups.length} groups',
                location.isSharing,
                onChanged: (val) {
                  if (val) {
                    location.startSharing();
                  } else {
                    location.stopSharing();
                  }
                },
              ),
              Divider(
                height: 1,
                color: context.dividerClr,
                indent: 16,
                endIndent: 16,
              ),
              Builder(builder: (context) {
                final ghost = context.watch<GhostProvider>();
                return Column(children: [
              _toggleRow(
                '👻',
                'Ghost Mode',
                ghost.activeRules.isEmpty
                    ? 'Tap to set up schedules & rules'
                    : '${ghost.activeRules.length} active rule${ghost.activeRules.length == 1 ? '' : 's'}',
                ghost.isGhostActive || location.isGhostMode,
                onChanged: (_) => GhostBottomSheet.show(context),
              ),
              // Ghost rules link
              Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: const SizedBox(width: 24),
                  title: Text('Edit Ghost Rules',
                      style: TextStyle(fontSize: 13, color: PointColors.accent, fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: context.secondaryText),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GhostRulesScreen())),
                ),
              ),
                ]); }),
            ],
          ),
        ),

        // Server
        _sectionLabel('Server'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              _infoRow(
                '🖥️',
                AppConfig.serverUrl.replaceAll('http://', ''),
                badge: 'CONNECTED',
                badgeColor: PointColors.online,
              ),
              _divider(),
              _actionRow('🔗', 'Generate Invite', onTap: _generateInvite),
            ],
          ),
        ),

        // App
        _sectionLabel('App'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Builder(
            builder: (context) {
              final themeNotifier = context.watch<ThemeNotifier>();
              final modeLabel = themeNotifier.mode == ThemeMode.dark
                  ? 'Dark'
                  : themeNotifier.mode == ThemeMode.light
                  ? 'Light'
                  : 'System';
              return Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      final next = themeNotifier.mode == ThemeMode.system
                          ? ThemeMode.light
                          : themeNotifier.mode == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.system;
                      themeNotifier.setMode(next);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: _settingRow('🌙', 'Dark Mode', modeLabel),
                  ),
                  _divider(),
                  _settingRow('📏', 'Units', 'Miles'),
                  _divider(),
                  _settingRow('🔔', 'Notifications', ''),
                  _divider(),
                  GestureDetector(
                    onTap: _showChangePasswordSheet,
                    behavior: HitTestBehavior.opaque,
                    child: _settingRow('🔑', 'Change Password', ''),
                  ),
                ],
              );
            },
          ),
        ),

        // Sign out
        GestureDetector(
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign Out?'),
                content: const Text('You will stop sharing your location.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Sign Out',
                      style: TextStyle(color: PointColors.danger),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              context.read<AuthProvider>().logout();
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 20, 14, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Sign Out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PointColors.danger,
                ),
              ),
            ),
          ),
        ),

        // Delete account
        GestureDetector(
          onTap: _showDeleteAccountDialog,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 30),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x0AFF3B30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Delete Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PointColors.danger,
                ),
              ),
            ),
          ),
        ),

        Center(
          child: Text(
            'Point v0.1.0',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.tertiaryText,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _statBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: context.subtleBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: context.primaryText,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: context.secondaryText,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBoxAccent(String icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x0A00E676),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: PointColors.online,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
    String icon,
    String title,
    String subtitle,
    bool value, {
    ValueChanged<bool>? onChanged,
  }) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged(!value) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.primaryText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: value ? PointColors.online : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(13),
                boxShadow: value
                    ? [BoxShadow(color: PointColors.onlineGlow, blurRadius: 8)]
                    : null,
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: context.tertiaryText,
        ),
      ),
    );
  }

  Widget _infoRow(
    String icon,
    String value, {
    String? badge,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.secondaryText,
            ),
          ),
          if (badge != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (badgeColor ?? PointColors.accent).withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: badgeColor ?? PointColors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(String icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.primaryText,
              ),
            ),
            const Spacer(),
            Text('›', style: TextStyle(color: context.tertiaryText)),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(String icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.primaryText,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(fontSize: 12, color: context.secondaryText),
            ),
          const SizedBox(width: 4),
          Text('›', style: TextStyle(color: context.tertiaryText)),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: context.dividerClr, indent: 16, endIndent: 16);

  void _showChangePasswordSheet() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: PointColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (newCtrl.text != confirmCtrl.text) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')),
                  );
                  return;
                }
                if (newCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('New password cannot be empty'),
                    ),
                  );
                  return;
                }
                try {
                  await context.read<ApiService>().changePassword(
                    currentCtrl.text,
                    newCtrl.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password changed')),
                    );
                } catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text(
                'Change Password',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action is permanent and cannot be undone. Enter your password to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (passwordCtrl.text.isEmpty) return;
              try {
                await context.read<ApiService>().deleteAccount(
                  passwordCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) context.read<AuthProvider>().logout();
              } catch (e) {
                if (ctx.mounted)
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: PointColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _generateInvite() async {
    try {
      final result = await context.read<ApiService>().createInvite(maxUses: 10);
      final code = result['code'];
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Invite Code'),
            content: SelectableText(
              code ?? '',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ==================== TAB BAR ====================
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        boxShadow: [
          BoxShadow(
            color: context.shadowClr,
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _tabItem(0, Icons.location_on_outlined, Icons.location_on, 'Map'),
              _tabItem(1, Icons.share_outlined, Icons.share, 'Sharing'),
              _tabItem(
                2,
                Icons.inbox_outlined,
                Icons.inbox,
                'Inbox',
                badge: _inboxItemCount,
              ),
              _tabItem(3, Icons.settings_outlined, Icons.settings, 'Me'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    int badge = 0,
  }) {
    final active = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active)
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: PointColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            if (!active) const SizedBox(height: 5),
            const SizedBox(height: 2),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  active ? activeIcon : icon,
                  size: 24,
                  color: active ? PointColors.accent : context.tertiaryText,
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: PointColors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 14,
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? PointColors.accent : context.tertiaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
