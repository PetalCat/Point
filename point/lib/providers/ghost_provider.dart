import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/ghost_rule.dart';
import '../providers.dart';
import '../services/api_service.dart';

const _bgTaskEvaluate = 'ghost_evaluate';
const _bgTaskTransition = 'ghost_transition';

/// Background callback -- must be top-level.
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

      final token = prefs.getString('auth_token');
      final serverUrl = prefs.getString('server_url');
      if (token != null && serverUrl != null && serverUrl.isNotEmpty) {
        try {
          final api = ApiService()..setToken(token);
          await api.setGhostFlag(anyActive);
        } catch (_) {}
      }

      await prefs.setBool('ghost_active_bg', anyActive);
    } catch (e) {
      debugPrint('[Ghost BG] Error: $e');
    }
    return true;
  });
}

class GhostState {
  final List<GhostRule> rules;
  final DateTime? timerExpiry;
  final bool globalGhost;
  final Set<String> ghostedGroupIds;
  final int? currentBattery;
  final String? currentPlaceId;

  const GhostState({
    this.rules = const [],
    this.timerExpiry,
    this.globalGhost = false,
    this.ghostedGroupIds = const {},
    this.currentBattery,
    this.currentPlaceId,
  });

  bool get hasActiveTimer => timerExpiry != null && timerExpiry!.isAfter(DateTime.now());
  bool get isGlobalGhostOn => globalGhost;

  bool get isGhostActive {
    if (globalGhost) return true;
    if (hasActiveTimer) return true;
    return ghostedGroupIds.isNotEmpty;
  }

  List<GhostRule> get activeRules {
    return rules.where((r) => r.enabled && r.isActiveNow(
      currentBattery: currentBattery,
      currentPlaceId: currentPlaceId,
    )).toList();
  }

  bool isGhostedForGroup(String groupId) {
    if (globalGhost) return true;
    if (hasActiveTimer) return true;
    if (ghostedGroupIds.contains('__all__')) {
      for (final rule in rules) {
        if (!rule.enabled) continue;
        if (!rule.isActiveNow(currentBattery: currentBattery, currentPlaceId: currentPlaceId)) continue;
        if (rule.exceptGroupIds != null && rule.exceptGroupIds!.contains(groupId)) {
          return false;
        }
      }
      return true;
    }
    return ghostedGroupIds.contains(groupId);
  }

  List<GhostRule> rulesForGroup(String groupId) {
    return rules.where((r) => r.enabled && r.affectsGroup(groupId)).toList();
  }

  GhostState copyWith({
    List<GhostRule>? rules,
    DateTime? timerExpiry,
    bool? globalGhost,
    Set<String>? ghostedGroupIds,
    int? currentBattery,
    String? currentPlaceId,
    bool clearTimerExpiry = false,
    bool clearCurrentPlaceId = false,
  }) {
    return GhostState(
      rules: rules ?? this.rules,
      timerExpiry: clearTimerExpiry ? null : (timerExpiry ?? this.timerExpiry),
      globalGhost: globalGhost ?? this.globalGhost,
      ghostedGroupIds: ghostedGroupIds ?? this.ghostedGroupIds,
      currentBattery: currentBattery ?? this.currentBattery,
      currentPlaceId: clearCurrentPlaceId ? null : (currentPlaceId ?? this.currentPlaceId),
    );
  }
}

class GhostNotifier extends Notifier<GhostState> {
  Timer? _evaluationTimer;

  @override
  GhostState build() {
    _evaluationTimer = Timer.periodic(const Duration(minutes: 1), (_) => evaluate());
    ref.onDispose(() {
      _evaluationTimer?.cancel();
    });
    _load();
    return const GhostState();
  }

  // ============================================================
  // Manual controls
  // ============================================================

  void toggleGlobalGhost() {
    final newGlobal = !state.globalGhost;
    state = state.copyWith(
      globalGhost: newGlobal,
      clearTimerExpiry: !newGlobal ? true : false,
    );
    _syncServerGhostFlag();
  }

  void setGhostTimer(Duration duration) {
    state = state.copyWith(timerExpiry: DateTime.now().add(duration));
    _syncServerGhostFlag();
    _scheduleTimerExpiry(duration);
  }

  void clearTimer() {
    state = state.copyWith(clearTimerExpiry: true);
    _syncServerGhostFlag();
  }

  void updateBattery(int level) {
    state = state.copyWith(currentBattery: level);
    evaluate();
  }

  void updateCurrentPlace(String? placeId) {
    if (placeId == null) {
      state = state.copyWith(clearCurrentPlaceId: true);
    } else {
      state = state.copyWith(currentPlaceId: placeId);
    }
    evaluate();
  }

  // ============================================================
  // Rule CRUD
  // ============================================================

  void addRule(GhostRule rule) {
    state = state.copyWith(rules: [...state.rules, rule]);
    evaluate();
    _save();
    _scheduleNextTransition();
  }

  void updateRule(GhostRule updated) {
    final rules = [...state.rules];
    final idx = rules.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      rules[idx] = updated;
      state = state.copyWith(rules: rules);
      evaluate();
      _save();
      _scheduleNextTransition();
    }
  }

  void removeRule(String ruleId) {
    state = state.copyWith(
      rules: state.rules.where((r) => r.id != ruleId).toList(),
    );
    evaluate();
    _save();
    _scheduleNextTransition();
  }

  void toggleRule(String ruleId) {
    final rules = [...state.rules];
    final idx = rules.indexWhere((r) => r.id == ruleId);
    if (idx != -1) {
      rules[idx] = rules[idx].copyWith(enabled: !rules[idx].enabled);
      state = state.copyWith(rules: rules);
      evaluate();
      _save();
      _scheduleNextTransition();
    }
  }

  // ============================================================
  // Evaluation
  // ============================================================

  void evaluate() {
    final ghostedGroupIds = <String>{};

    for (final rule in state.rules) {
      if (!rule.enabled) continue;
      if (!rule.isActiveNow(
        currentBattery: state.currentBattery,
        currentPlaceId: state.currentPlaceId,
      )) continue;

      if (rule.target == GhostTarget.all) {
        ghostedGroupIds.add('__all__');
      } else if (rule.targetGroupIds != null) {
        ghostedGroupIds.addAll(rule.targetGroupIds!);
      }
    }

    DateTime? timerExpiry = state.timerExpiry;
    if (timerExpiry != null && timerExpiry.isBefore(DateTime.now())) {
      timerExpiry = null;
    }

    final wasPreviouslyActive = state.isGhostActive;
    state = state.copyWith(
      ghostedGroupIds: ghostedGroupIds,
      timerExpiry: timerExpiry,
      clearTimerExpiry: timerExpiry == null && state.timerExpiry != null,
    );

    if (state.isGhostActive != wasPreviouslyActive) {
      _syncServerGhostFlag();
    }
  }

  // ============================================================
  // Server safety net
  // ============================================================

  Future<void> _syncServerGhostFlag() async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.setGhostFlag(state.isGhostActive);
    } catch (e) {
      debugPrint('[Ghost] Failed to sync server ghost flag: $e');
    }
  }

  // ============================================================
  // Background scheduling
  // ============================================================

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

  void _scheduleTimerExpiry(Duration duration) {
    Workmanager().registerOneOffTask(
      'ghost_timer_expiry',
      _bgTaskTransition,
      initialDelay: duration,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Duration? _findNextTransitionDelay() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final weekday = now.weekday - 1;
    Duration? shortest;

    for (final rule in state.rules) {
      if (!rule.enabled || rule.type != GhostRuleType.schedule) continue;
      if (rule.days == null || rule.startMinute == null || rule.endMinute == null) continue;

      for (final day in rule.days!) {
        int daysAhead = day - weekday;
        if (daysAhead < 0) daysAhead += 7;

        int targetMinutes = rule.startMinute!;
        int minutesUntil = (daysAhead * 24 * 60) + (targetMinutes - nowMinutes);
        if (minutesUntil <= 0) minutesUntil += 7 * 24 * 60;
        final startDelay = Duration(minutes: minutesUntil);
        if (shortest == null || startDelay < shortest) shortest = startDelay;

        targetMinutes = rule.endMinute!;
        minutesUntil = (daysAhead * 24 * 60) + (targetMinutes - nowMinutes);
        if (minutesUntil <= 0) minutesUntil += 7 * 24 * 60;
        final endDelay = Duration(minutes: minutesUntil);
        if (endDelay < shortest) shortest = endDelay;
      }
    }

    return shortest;
  }

  /// Initialize WorkManager for background ghost evaluation.
  static Future<void> initBackground() async {
    await Workmanager().initialize(ghostBackgroundCallback);
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
    final json = state.rules.map((r) => r.toJson()).toList();
    await prefs.setString('ghost_rules', jsonEncode(json));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('ghost_rules');
    if (str != null) {
      try {
        final list = jsonDecode(str) as List;
        final rules = list.map((j) => GhostRule.fromJson(j)).toList();
        state = state.copyWith(rules: rules);
        evaluate();
      } catch (e) {
        debugPrint('[Ghost] Failed to load rules: $e');
      }
    }
    final bgGhost = prefs.getBool('ghost_active_bg') ?? false;
    if (bgGhost && !state.isGhostActive) {
      evaluate();
    }
  }
}
