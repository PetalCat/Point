import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../config.dart';
import '../theme.dart';
import '../providers.dart';
import '../widgets/ghost_bottom_sheet.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../widgets/filter_bar.dart';
import '../widgets/map_view.dart';
import '../widgets/people_drawer.dart';
import 'person_history_screen.dart';
import 'place_creation_screen.dart';
import 'tabs/inbox_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/sharing_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  FilterMode _filterMode = FilterMode.all;
  int _currentTab = 0;
  bool _showTrails = true;
  bool _servicesReady = false;
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
    final auth = ref.read(authProvider);
    final ws = ref.read(wsServiceProvider);
    final groupNotifier = ref.read(groupProvider.notifier);
    final locationNotifier = ref.read(locationProvider.notifier);

    if (auth.token != null) ws.connect(auth.token!);
    ws.sendPresence();
    locationNotifier.setMyUserId(auth.userId ?? '');

    // Ghost provider reads apiService via ref internally

    // Initialize MLS encryption
    final crypto = ref.read(cryptoServiceProvider);
    try {
      // userId already includes @domain from registration
      final identity = auth.userId ?? '';
      await crypto.init(identity);
    } catch (e) {
      debugPrint('MLS init: $e');
    }

    // Listen for real-time MLS messages (Welcome/Commit)
    ws.messages.listen((msg) {
      if (msg['type'] == 'mls.message') {
        crypto.handleMlsWsMessage(msg);
      }
    });

    // Process any pending MLS messages
    await crypto.processPendingMessages();

    // Initialize push notifications (Firebase, UnifiedPush, or disabled)
    try {
      await PushService.init(
        onTokenReceived: (token) async {
          await ref.read(authProvider.notifier).registerFcmToken(token);
        },
      );
    } catch (e) {
      debugPrint('Push init: $e');
    }

    await groupNotifier.loadGroups();
    final groups = ref.read(groupProvider);
    locationNotifier.setActiveGroups(groups.groups.map((g) => g.id).toList());

    // Set up MLS encryption for all groups
    await groupNotifier.setupEncryptionForAllGroups(auth.userId ?? '');

    // Load places (geofences)
    if (mounted) {
      await locationNotifier.loadPlaces(groups.groups.map((g) => g.id).toList());
    }

    // Listen for geofence enter/exit events
    _geofenceSubscription = locationNotifier.geofenceEvents.listen((event) {
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

    if (mounted) ref.read(itemProvider.notifier).loadItems();
    if (mounted) {
      final sharingNotifier = ref.read(sharingProvider.notifier);
      sharingNotifier.setMyUserId(auth.userId ?? '');
      sharingNotifier.listenToWs(ws);
      await sharingNotifier.loadAll();
      if (mounted) {
        final shares = ref.read(sharingProvider).shares;
        final userIds = shares.map((s) => s['user_id'] as String).toList();
        locationNotifier.setActiveUserIds(userIds);
      }
    }

    // Load zone consents
    if (mounted) {
      try {
        await locationNotifier.loadZoneConsents();
      } catch (e) {
        debugPrint('Zone consents load: $e');
      }
    }

    if (mounted) setState(() => _servicesReady = true);
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
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _currentTab,
                    children: [
                      _buildMapTab(),
                      SharingTab(onSwitchToMap: () => setState(() => _currentTab = 0)),
                      InboxTab(recentGeofenceEvents: _recentGeofenceEvents),
                      const ProfileTab(),
                    ],
                  ),
                ),
                _buildTabBar(),
              ],
            ),
            if (!_servicesReady)
              Positioned.fill(
                child: Container(
                  color: context.pageBg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/icon/app_icon.png', width: 80, height: 80),
                        const SizedBox(height: 20),
                        const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: PointColors.accent),
                        ),
                        const SizedBox(height: 12),
                        Text('Setting up encryption...',
                            style: TextStyle(fontSize: 13, color: context.secondaryText)),
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
    final loc = ref.watch(locationProvider);
    final person = loc.people[userId];
    final myPos = loc.myPosition;
    final name = userId.split('@').first;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = PointColors.colorForUser(userId);

    if (person == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _deselectPerson());
      return const SizedBox.shrink();
    }

    final isStale =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - person.timestamp) >
        7200;
    final speed = person.speed;
    final battery = person.battery;

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

    String distanceLabel = '--';
    if (myPos != null) {
      final meters = _haversine(
        myPos.latitude, myPos.longitude, person.lat, person.lon,
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

    String speedLabel;
    if (speed == null || speed < 0.5) {
      speedLabel = '0 mph';
    } else {
      speedLabel = '${(speed * 2.237).round()} mph';
    }

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
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: context.dividerClr,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _deselectPerson,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: context.subtleBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.arrow_back_ios_new, size: 14, color: context.secondaryText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Center(child: Text(initial, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.primaryText)),
                          Text('${person.online && !isStale ? "Online" : "Offline"}  \u00b7  $timeAgo',
                              style: TextStyle(fontSize: 11, color: context.secondaryText)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _drawerStatBox(Icons.near_me_outlined, color, 'Distance', distanceLabel),
                    const SizedBox(width: 8),
                    _drawerStatBox(Icons.speed, color, 'Speed', speedLabel),
                    const SizedBox(width: 8),
                    _drawerStatBox(batteryIcon, batteryColor, 'Battery', batteryLabel),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PersonHistoryScreen(userId: userId, displayName: name, userColor: PointColors.colorForUser(userId)),
                    )),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: context.subtleBg, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('View History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: PointColors.accent))),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _deselectPerson,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(color: context.subtleBg, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: Text('Stop following', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.secondaryText))),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: context.tertiaryText)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: context.subtleBg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(
                            activityLabel == 'Stationary' ? Icons.pause_circle_outline
                                : activityLabel == 'Walking' ? Icons.directions_walk
                                : activityLabel == 'Cycling' ? Icons.directions_bike
                                : Icons.directions_car,
                            size: 18, color: color,
                          ),
                          const SizedBox(width: 10),
                          Text(activityLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.primaryText)),
                          const Spacer(),
                          Text(timeAgo, style: TextStyle(fontSize: 11, color: context.secondaryText)),
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

  Widget _drawerStatBox(IconData icon, Color iconColor, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(color: context.subtleBg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.primaryText)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: context.secondaryText)),
          ],
        ),
      ),
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  String _ghostTimerText(GhostState ghost) {
    if (ghost.timerExpiry == null) return '';
    final diff = ghost.timerExpiry!.difference(DateTime.now());
    if (diff.isNegative) return '';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  Widget _buildMapTab() {
    final ghost = ref.watch(ghostProvider);
    final loc = ref.watch(locationProvider);
    final ghostMode = ghost.isGhostActive || loc.isGhostMode;

    return Stack(
      children: [
        Positioned.fill(
          child: MapView(
            key: _mapKey,
            onPersonTap: _selectPerson,
            showTrails: _showTrails,
            onLongPress: (pos) async {
              final result = await Navigator.push<bool>(
                context, MaterialPageRoute(builder: (_) => PlaceCreationScreen(initialPosition: pos)),
              );
              if (result == true && mounted) {
                final groups = ref.read(groupProvider);
                await ref.read(locationProvider.notifier).loadPlaces(
                  groups.groups.map((g) => g.id).toList(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Place saved'), behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  );
                }
              }
            },
          ),
        ),
        Positioned(
          top: 12, left: 14,
          child: Row(
            children: [
              ...FilterMode.values.map((mode) {
                final active = mode == _filterMode;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                    onTap: () => setState(() => _filterMode = mode),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? PointColors.accent : context.cardBg,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          if (active) const BoxShadow(color: PointColors.accentGlow, blurRadius: 14, offset: Offset(0, 3)),
                          if (!active) BoxShadow(color: context.shadowClr, blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Text(
                        mode.name[0].toUpperCase() + mode.name.substring(1),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: active ? Colors.white : context.secondaryText),
                      ),
                    ),
                  ),
                  ),
                );
              }),
            ],
          ),
        ),
        if (ghostMode)
          Positioned(
            top: 56, left: 0, right: 0,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                onTap: () => GhostBottomSheet.show(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('\u{1F47B} Ghost Mode', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      if (ghost.hasActiveTimer) ...[
                        const SizedBox(width: 6),
                        Text(_ghostTimerText(ghost), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: PointColors.accent)),
                      ],
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        Positioned(
          top: 12, right: 14,
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _mapKey.currentState?.fitAllMarkers(),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 8, offset: const Offset(0, 2))]),
                    child: Icon(Icons.fit_screen_rounded, size: 18, color: context.secondaryText),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => GhostBottomSheet.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: ghostMode ? PointColors.accent : context.cardBg, borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        if (ghostMode) const BoxShadow(color: PointColors.accentGlow, blurRadius: 10, offset: Offset(0, 2)),
                        if (!ghostMode) BoxShadow(color: context.shadowClr, blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Center(child: Icon(Icons.visibility_off_rounded, size: ghostMode ? 18 : 16, color: ghostMode ? Colors.white : context.secondaryText)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _showTrails = !_showTrails),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _showTrails ? PointColors.accent : context.cardBg, borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        if (_showTrails) const BoxShadow(color: PointColors.accentGlow, blurRadius: 10, offset: Offset(0, 2)),
                        if (!_showTrails) BoxShadow(color: context.shadowClr, blurRadius: 8, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Icon(Icons.timeline, size: 18, color: _showTrails ? Colors.white : PointColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: ref.read(wsServiceProvider).connectionState,
          builder: (context, connected, _) {
            if (connected) return const SizedBox.shrink();
            return Positioned(
              top: 56, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: PointColors.danger.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)),
                      SizedBox(width: 6),
                      Text('Reconnecting...', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.35, minChildSize: 0.12, maxChildSize: 0.85,
          snap: true, snapSizes: const [0.12, 0.35, 0.85],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 30, offset: const Offset(0, -8))],
            ),
            child: _selectedPersonId != null
                ? _buildPersonDetailInDrawer(_selectedPersonId!, scrollController)
                : PeopleDrawer(scrollController: scrollController, filterMode: _filterMode, onPersonTap: _selectPerson),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        boxShadow: [BoxShadow(color: context.shadowClr, blurRadius: 8, offset: const Offset(0, -1))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _tabItem(0, Icons.location_on_outlined, Icons.location_on, 'Map'),
              _tabItem(1, Icons.share_outlined, Icons.share, 'Sharing'),
              _tabItem(2, Icons.inbox_outlined, Icons.inbox, 'Inbox',
                  badge: InboxTab(recentGeofenceEvents: _recentGeofenceEvents).itemCount(ref)),
              _tabItem(3, Icons.settings_outlined, Icons.settings, 'Me'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(int index, IconData icon, IconData activeIcon, String label, {int badge = 0}) {
    final active = _currentTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentTab = index);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) Container(width: 5, height: 5, decoration: const BoxDecoration(color: PointColors.accent, shape: BoxShape.circle)),
            if (!active) const SizedBox(height: 5),
            const SizedBox(height: 2),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, size: 24, color: active ? PointColors.accent : context.tertiaryText),
                if (badge > 0)
                  Positioned(
                    right: -6, top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: PointColors.danger, borderRadius: BorderRadius.circular(8)),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                      child: Text('$badge', textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: active ? PointColors.accent : context.tertiaryText)),
          ],
        ),
      ),
    );
  }
}
