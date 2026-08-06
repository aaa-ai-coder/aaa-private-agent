import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import 'action_handler.dart';
import 'ai_service.dart';
import 'notification_service.dart';

/// A task scheduled to run at a specific time, optionally repeating.
class ScheduledTask {
  final String id;
  final String label;
  final String actionType;
  final Map<String, dynamic> params;
  DateTime scheduledAt;
  final int repeatMinutes; // 0 = run once

  ScheduledTask({
    required this.id,
    required this.label,
    required this.actionType,
    required this.params,
    required this.scheduledAt,
    this.repeatMinutes = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'actionType': actionType,
        'params': params,
        'scheduledAt': scheduledAt.toIso8601String(),
        'repeatMinutes': repeatMinutes,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Task',
        actionType: json['actionType'] as String,
        params: (json['params'] as Map<String, dynamic>? ?? {}),
        scheduledAt: DateTime.parse(json['scheduledAt'] as String),
        repeatMinutes: (json['repeatMinutes'] as num?)?.toInt() ?? 0,
      );
}

/// Persists scheduled tasks in SharedPreferences and fires them through the
/// ActionHandler at their due time. Re-arms repeating tasks automatically and
/// re-loads all tasks whenever the app starts.
class SchedulerService {
  SchedulerService._();
  static final SchedulerService instance = SchedulerService._();

  final List<ScheduledTask> _tasks = [];
  final List<Timer> _timers = [];
  final ActionHandler _actionHandler = ActionHandler();

  static const String _prefsKey = 'scheduled_tasks';

  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  Future<void> initialize() async {
    _cancelAll();
    _tasks.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          if (item is Map) {
            _tasks.add(
              ScheduledTask.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
    } catch (_) {
      // Corrupt schedule data: ignore and start fresh.
    }
    _armAll();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_tasks.map((t) => t.toJson()).toList()),
    );
  }

  void _cancelAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  Future<ScheduledTask> addTask({
    required String label,
    required String actionType,
    required Map<String, dynamic> params,
    required DateTime scheduledAt,
    int repeatMinutes = 0,
  }) async {
    final task = ScheduledTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      actionType: actionType,
      params: params,
      scheduledAt: scheduledAt,
      repeatMinutes: repeatMinutes,
    );
    _tasks.add(task);
    await _persist();
    _arm(task);
    return task;
  }

  void _arm(ScheduledTask task) {
    final delay = task.scheduledAt.difference(DateTime.now());
    final duration = delay.isNegative ? Duration.zero : delay;
    _timers.add(Timer(duration, () => _fire(task)));
  }

  void _armAll() {
    for (final t in _tasks) {
      _arm(t);
    }
    // Tasks that became due while the app was closed fire immediately.
    for (final t in List<ScheduledTask>.from(_tasks)) {
      if (!t.scheduledAt.isAfter(DateTime.now())) {
        _fire(t);
      }
    }
  }

  Future<void> _fire(ScheduledTask task) async {
    final action = AgentAction(
      action: task.actionType,
      params: task.params,
      response: task.label,
    );
    AgentActionResult? result;
    try {
      result = await _actionHandler.execute(
        action,
        aiService: AiService.instance,
      );
    } catch (e) {
      result = AgentActionResult(
        actionType: task.actionType,
        success: false,
        details: 'Error: $e',
      );
    }
    try {
      await NotificationService().showTaskCompleteNotification(
        'Scheduled: ${task.label}',
        result.success
            ? (result.details ?? 'Completed.')
            : 'Failed: ${result.details ?? 'Unknown error'}',
      );
    } catch (_) {}

    if (task.repeatMinutes > 0) {
      task.scheduledAt = task.scheduledAt.add(
        Duration(minutes: task.repeatMinutes),
      );
      while (!task.scheduledAt.isAfter(DateTime.now())) {
        task.scheduledAt = task.scheduledAt.add(
          Duration(minutes: task.repeatMinutes),
        );
      }
      await _persist();
      _arm(task);
    } else {
      _tasks.remove(task);
      await _persist();
    }
  }

  Future<void> cancel(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    _cancelAll();
    _armAll();
    await _persist();
  }

  Future<void> clearAll() async {
    _tasks.clear();
    _cancelAll();
    await _persist();
  }

  void dispose() => _cancelAll();
}
