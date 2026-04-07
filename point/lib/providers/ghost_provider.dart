import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/ghost_rule.dart';
import '../services/api_service.dart';

const _bgTaskEvaluate = 'ghost_evaluate';
const _bgTaskTransition = 'ghost_transition';

/// Background callback — must be top-level.
@pragma('vm:entry-point')
void ghostBackgroundCallback() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('ghost_rules');
    if (str == null) return true;

    try {
      final list = jsonDecode(str) as List;
      final rules = list.map((j) => GhostRule.fromJson(j)).toList();
      final anyActive = rules.any((r) => r.enabled && r.isActiveNow());

      // Update the server ghost flag as a safety net
      final token = prefs.getString('auth_token');
      final serverUrl = prefs.getString('server_url');
      if (token != null && serverUrl != null && serverUrl.isNotEmpty) {
        try {
          final api = ApiService()..setToken(token);
          await api.setGhostFlag(anyActive);
        } catch (_) {}
      }

      // Store current ghost state so the app reads it on resume
      await prefs.setBool('ghost_active_bg', anyActive);
    } catch (e) {
      debugPrint('[Ghost BG] Error: $e');
    }
    return true;
  });
}

class GhostProvider extends ChangeNotifier {
  List<GhostRule> _rules = [];
  DateTime? _timerExpiry;
  Timer? _evaluationTimer;
  int? _currentBattery;
  String? _currentPlaceId;
  ApiService? _api;

  final Set<String> _ghostedGroupIds = {};
  bool _globalGhost = false;

  List<GhostRule> get rules => List.unmodifiable(_rules);
  DateTime? get timerExpiry => _timerExpiry;
  bool get hasActiveTimer => _timerExpiry != null && _timerExpiry!.isAfter(DateTime.now());
  bool get isGlobalGhostOn => _globalGhost;

  GhostProvider() {
    _load();
    _evaluationTimer = Timer.periodic(const Duration(minutes: 1), (_) => evaluate());
  }

  void setApiService(ApiService api) {
    _api = api;
  }

  /// Check if ghost is active for a specific group right now.
  bool isGhostedForGroup(String groupId) {
    if (_globalGhost) return true;
    if (hasActiveTimer) return true;
    if (_ghostedGroupIds.contains('__all__')) {
      // Check exceptions
      for (final rule in _rules) {
        if (!rule.enabled) continue;
        if (!rule.isActiveNow(currentBattery: _currentBattery, currentPlaceId: _currentPlaceId)) continue;
        if (rule.exceptGroupIds != null && rule.exceptGroupIds!.contains(groupId)) {
          return false;
        }
      }
      return true;
    }
    return _ghostedGroupIds.contains(groupId);
  }

  bool get isGhostActive {
    if (_globalGhost) return true;
    if (hasActiveTimer) return true;
    return _ghostedGroupIds.isNotEmpty;
  }

  List<GhostRule> rulesForGroup(String groupId) {
    return _rules.where((r) => r.enabled && r.affectsGroup(groupId)).toList();
  }

  List<GhostRule> get activeRules {
    return _rules.where((r) => r.enabled && r.isActiveNow(
      currentBattery: _currentBattery,
      currentPlaceId: _currentPlaceId,
    )).toList();
  }

  // ============================================================
  // Manual controls
  // ============================================================

  void toggleGlobalGhost() {
    _globalGhost = !_globalGhost;
    if (!_globalGhost) _timerExpiry = null;
    _syncServerGhostFlag();
    notifyListeners();
  }

  void setGhostTimer(Duration duration) {
    _timerExpiry = DateTime.now().add(duration);
    _syncServerGhostFlag();
    _scheduleTimerExpiry(duration);
    notifyListeners();
  }

  void clearTimer() {
    _timerExpiry = null;
    _syncServerGhostFlag();
    notifyListeners();
  }

  void updateBattery(int level) {
    _currentBattery = level;
    evaluate();
  }

  void updateCurrentPlace(String? placeId) {
    _currentPlaceId = placeId;
    evaluate();
  }

  // ============================================================
  // Rule CRUD
  // ============================================================

  void addRule(GhostRule rule) {
    _rules.add(rule);
    evaluate();
    _save();
    _scheduleNextTransition();
  }

  void updateRule(GhostRule updated) {
    final idx = _rules.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      _rules[idx] = updated;
      evaluate();
      _save();
      _scheduleNextTransition();
    }
  }

  void removeRule(String ruleId) {
    _rules.removeWhere((r) => r.id == ruleId);
    evaluate();
    _save();
    _scheduleNextTransition();
  }

  void toggleRule(String ruleId) {
    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx != -1) {
      _rules[idx] = _rules[idx].copyWith(enabled: !_rules[idx].enabled);
      evaluate();
      _save();
      _scheduleNextTransition();
    }
  }

  // ============================================================
  // Evaluation
  // ============================================================

  void evaluate() {
    final wasPreviouslyActive = isGhostActive;
    _ghostedGroupIds.clear();

    for (final rule in _rules) {
      if (!rule.enabled) continue;
      if (!rule.isActiveNow(
        currentBattery: _currentBattery,
        currentPlaceId: _currentPlaceId,
      )) continue;

      if (rule.target == GhostTarget.all) {
        _ghostedGroupIds.add('__all__');
      } else if (rule.targetGroupIds != null) {
        _ghostedGroupIds.addAll(rule.targetGroupIds!);
      }
    }

    if (_timerExpiry != null && _timerExpiry!.isBefore(DateTime.now())) {
      _timerExpiry = null;
    }

    // If ghost state changed, update the server safety net
    if (isGhostActive != wasPreviouslyActive) {
      _syncServerGhostFlag();
    }

    notifyListeners();
  }

  // ============================================================
  // Server safety net — coarse "globally ghosted" flag
  // ============================================================

  Future<void> _syncServerGhostFlag() async {
    if (_api == null) return;
    try {
      await _api!.setGhostFlag(isGhostActive);
    } catch (e) {
      debugPrint('[Ghost] Failed to sync server ghost flag: $e');
    }
  }

  // ============================================================
  // Background scheduling
  // ============================================================

  /// Schedule a background task for the next ghost rule transition.
  void _scheduleNextTransition() {
    final nextTransition = _findNextTransitionDelay();
    if (nextTransition == null) return;

    Workmanager().registerOneOffTask(
      _bgTaskTransition,
      _bgTaskTransition,
      initialDelay: nextTransition,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    debugPrint('[Ghost] Scheduled background transition in ${nextTransition.inMinutes}m');
  }

  /// Schedule background task when a quick timer expires.
  void _scheduleTimerExpiry(Duration duration) {
    Workmanager().registerOneOffTask(
      'ghost_timer_expiry',
      _bgTaskTransition,
      initialDelay: duration,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Find the delay until the next schedule rule activates or deactivates.
  Duration? _findNextTransitionDelay() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final weekday = now.weekday - 1;
    Duration? shortest;

    for (final rule in _rules) {
      if (!rule.enabled || rule.type != GhostRuleType.schedule) continue;
      if (rule.days == null || rule.startMinute == null || rule.endMinute == null) continue;

      for (final day in rule.days!) {
        int daysAhead = day - weekday;
        if (daysAhead < 0) daysAhead += 7;

        // Check start transition
        int targetMinutes = rule.startMinute!;
        int minutesUntil = (daysAhead * 24 * 60) + (targetMinutes - nowMinutes);
        if (minutesUntil <= 0) minutesUntil += 7 * 24 * 60;
        final startDelay = Duration(minutes: minutesUntil);
        if (shortest == null || startDelay < shortest) shortest = startDelay;

        // Check end transition
        targetMinutes = rule.endMinute!;
        minutesUntil = (daysAhead * 24 * 60) + (targetMinutes - nowMinutes);
        if (minutesUntil <= 0) minutesUntil += 7 * 24 * 60;
        final endDelay = Duration(minutes: minutesUntil);
        if (endDelay < shortest!) shortest = endDelay;
      }
    }

    return shortest;
  }

  /// Initialize WorkManager for background ghost evaluation.
  static Future<void> initBackground() async {
    await Workmanager().initialize(ghostBackgroundCallback);
    // Periodic fallback — every 15 minutes, evaluate ghost rules
    await Workmanager().registerPeriodicTask(
      _bgTaskEvaluate,
      _bgTaskEvaluate,
      frequency: const Duration(minutes: 15),
    );
  }

  // ============================================================
  // Persistence
  // ============================================================

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = _rules.map((r) => r.toJson()).toList();
    await prefs.setString('ghost_rules', jsonEncode(json));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('ghost_rules');
    if (str != null) {
      try {
        final list = jsonDecode(str) as List;
        _rules = list.map((j) => GhostRule.fromJson(j)).toList();
        evaluate();
      } catch (e) {
        debugPrint('[Ghost] Failed to load rules: $e');
      }
    }
    // Check if background worker set ghost state while we were dead
    final bgGhost = prefs.getBool('ghost_active_bg') ?? false;
    if (bgGhost && !isGhostActive) {
      evaluate(); // re-evaluate with fresh time
    }
  }

  @override
  void dispose() {
    _evaluationTimer?.cancel();
    super.dispose();
  }
}
