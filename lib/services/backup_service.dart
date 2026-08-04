import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'chat_history_service.dart';
import 'cloudflare_service.dart';
import 'firebase_service.dart';
import 'storage_service.dart';

/// Unified backup layer.
///
/// Data flow:
///  * Supabase (Postgres) is the primary database — the source of truth.
///  * Firebase (Firestore) mirrors chat sessions per user as a live backup.
///  * Cloudflare R2 / Supabase Storage / Firebase Storage hold a portable
///    JSON export of every chat session (heavy, immutable artifacts).
///  * The Cloudflare Worker snapshots the whole Supabase database to R2
///    once per day (see `workers/supabase-keepalive`).
class BackupService {
  /// Build a portable JSON export of all local chat sessions.
  static Future<String> exportChatsJson() async {
    final sessions = await ChatHistoryService.loadSessions();
    return jsonEncode({
      'app': 'AAA Private Agent',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    });
  }

  /// Backup now:
  ///  1. mirror every chat session to Firestore (Firebase backup layer),
  ///  2. upload a JSON export to R2 + Supabase Storage + Firebase Storage,
  ///  3. ask the Cloudflare Worker for an on-demand DB snapshot in R2.
  /// Returns a summary map of what succeeded.
  static Future<Map<String, dynamic>> backupNow({String? userId}) async {
    final results = <String, dynamic>{};

    // 1. Firestore mirror (Firebase = backup).
    if (userId != null && userId.isNotEmpty) {
      final sessions = await ChatHistoryService.loadSessions();
      results['firestore'] =
          await FirebaseService.backupChatsToFirestore(userId, sessions);
    } else {
      results['firestore'] = false;
    }

    // 2. Portable JSON export to the three file stores.
    final json = await exportChatsJson();
    final bytes = utf8.encode(json);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final fileName = 'chat-backup-$stamp.json';
    results['file'] = await StorageService.uploadBytes(
      bytes: bytes,
      fileName: fileName,
      folder: 'backups',
      contentType: 'application/json',
    );

    // 3. On-demand worker database snapshot to R2.
    results['db_snapshot'] = await CloudflareService.triggerBackup();

    developer.log('Backup done: $results', name: 'BackupService');
    return results;
  }

  /// Restore chat sessions from a portable JSON export (merges by session id).
  /// Returns the number of sessions restored.
  static Future<int> restoreFromJson(String jsonString) async {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final raw = decoded['sessions'] as List? ?? [];
    final sessions = raw
        .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final session in sessions) {
      await ChatHistoryService.saveSession(session);
    }
    return sessions.length;
  }

  /// Fetch the most recent chat backup JSON from Supabase Storage
  /// (`backups/` folder in the public `aaa-backups` bucket).
  static Future<String?> fetchLatestBackupJson() async {
    try {
      final client = SupabaseConfig.client;
      final folder = 'backups';
      final files = await client.storage
          .from('aaa-backups')
          .list(path: folder, searchOptions: const SearchOptions(limit: 100));
      files.sort((a, b) {
        final an = a.name;
        final bn = b.name;
        return bn.compareTo(an); // newest first
      });
      if (files.isEmpty) return null;
      final newest = files.first;
      final bytes =
          await client.storage.from('aaa-backups').download('$folder/${newest.name}');
      return utf8.decode(bytes);
    } catch (e) {
      developer.log('Fetch latest backup error: $e', name: 'BackupService');
      return null;
    }
  }

  /// Restore chat sessions from the newest cloud backup (Supabase Storage).
  static Future<int> restoreFromCloud() async {
    final json = await fetchLatestBackupJson();
    if (json == null) return -1;
    return restoreFromJson(json);
  }

  /// Whether automatic cloud backups are enabled.
  static Future<bool> autoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_backup_enabled') ?? true;
  }

  static Future<void> setAutoBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_backup_enabled', value);
  }

  /// Called after every chat save. If auto-backup is on, mirrors the latest
  /// sessions to Firestore (fire-and-forget).
  static Future<void> maybeAutoBackup(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    if (!await autoBackupEnabled()) return;
    final sessions = await ChatHistoryService.loadSessions();
    await FirebaseService.backupChatsToFirestore(userId, sessions);
  }
}
