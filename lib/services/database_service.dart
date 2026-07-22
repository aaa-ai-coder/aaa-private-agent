import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/chat_message.dart';
import '../models/saved_skill.dart';

class DatabaseService {
  static SupabaseClient get _db => SupabaseConfig.client;

  // ─── Chat Sessions ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSessions(
    String userId,
  ) async {
    final data = await _db
        .from('chat_sessions')
        .select('id, title, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return data;
  }

  static Future<String> createSession(
    String userId,
    String title,
  ) async {
    final data = await _db.from('chat_sessions').insert({
      'user_id': userId,
      'title': title,
    }).select('id').single();
    return data['id'] as String;
  }

  static Future<void> updateSessionTitle(
    String sessionId,
    String title,
  ) async {
    await _db.from('chat_sessions').update({
      'title': title,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  static Future<void> deleteSession(String sessionId) async {
    await _db.from('chat_sessions').delete().eq('id', sessionId);
  }

  // ─── Chat Messages ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMessages(
    String sessionId,
  ) async {
    return await _db
        .from('chat_messages')
        .select('role, content, action_result, created_at')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
  }

  static Future<void> saveMessage({
    required String sessionId,
    required String userId,
    required String role,
    required String content,
    Map<String, dynamic>? actionResult,
  }) async {
    await _db.from('chat_messages').insert({
      'session_id': sessionId,
      'user_id': userId,
      'role': role,
      'content': content,
      'action_result': actionResult != null
          ? jsonEncode(actionResult)
          : null,
    });
  }

  static Future<void> saveMessagesBulk({
    required String sessionId,
    required String userId,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (messages.isEmpty) return;
    await _db.from('chat_messages').insert(
      messages.map((m) => {
        'session_id': sessionId,
        'user_id': userId,
        'role': m['role'],
        'content': m['content'],
        'action_result': m['action_result'],
      }).toList(),
    );
  }

  // ─── Saved Skills ───────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSkills(String userId) async {
    return await _db
        .from('saved_skills')
        .select('*')
        .eq('user_id', userId)
        .order('last_used', ascending: false);
  }

  static Future<void> saveSkill({
    required String userId,
    required String task,
    required List<String> taskKeywords,
    required List<Map<String, dynamic>> steps,
  }) async {
    await _db.from('saved_skills').insert({
      'user_id': userId,
      'task': task,
      'task_keywords': taskKeywords,
      'steps': steps,
      'last_used': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> updateSkillSuccess(String skillId) async {
    final skill = await _db
        .from('saved_skills')
        .select('success_count, last_used')
        .eq('id', skillId)
        .single();
    int count = (skill['success_count'] as int?) ?? 0;
    await _db.from('saved_skills').update({
      'success_count': count + 1,
      'last_used': DateTime.now().toIso8601String(),
    }).eq('id', skillId);
  }

  static Future<void> updateSkillFailure(String skillId) async {
    final skill = await _db
        .from('saved_skills')
        .select('fail_count')
        .eq('id', skillId)
        .single();
    int count = (skill['fail_count'] as int?) ?? 0;
    await _db.from('saved_skills').update({
      'fail_count': count + 1,
    }).eq('id', skillId);
  }

  // ─── Task History ───────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getTaskHistory(
    String userId,
  ) async {
    return await _db
        .from('task_history')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  static Future<void> logTask({
    required String userId,
    required String goal,
    required String status,
    int totalTokens = 0,
    int stepsTaken = 0,
    List<String>? trace,
  }) async {
    await _db.from('task_history').insert({
      'user_id': userId,
      'goal': goal,
      'status': status,
      'total_tokens': totalTokens,
      'steps_taken': stepsTaken,
      'trace': trace != null ? jsonEncode(trace) : null,
    });
  }

  static Future<void> clearTaskHistory(String userId) async {
    await _db.from('task_history').delete().eq('user_id', userId);
  }

  // ─── User Settings ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getSettings(String userId) async {
    final data = await _db
        .from('user_settings')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle();
    return data;
  }

  static Future<void> saveSettings({
    required String userId,
    required Map<String, dynamic> settings,
  }) async {
    final existing = await _db
        .from('user_settings')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _db.from('user_settings').update({
        ...settings,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);
    } else {
      await _db.from('user_settings').insert({
        'user_id': userId,
        ...settings,
      });
    }
  }

  // ─── Profile ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    return await _db
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();
  }
}
