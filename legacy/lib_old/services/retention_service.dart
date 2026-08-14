import 'dart:async';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import 'chat_history_service.dart';
import 'cloudflare_service.dart';
import 'database_service.dart';
import 'firebase_service.dart';

/// Automated data lifecycle: prunes chat history and cloud backups older than
/// the configured retention window so storage never grows without bound.
///
/// Runs automatically on app start and when a user signs in. Everything is
/// best-effort and fire-and-forget — offline devices simply skip cloud steps.
class RetentionService {
  static const String retentionDaysKey = 'chat_retention_days';

  /// Current chat retention window in days. `<= 0` means keep everything.
  static Future<int> getRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(retentionDaysKey) ?? 30;
  }

  static Future<void> setRetentionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(retentionDaysKey, days);
    // Apply the new policy immediately.
    unawaited(pruneExpiredChats());
  }

  /// Delete chat sessions (local, Supabase and Firestore mirror) that are
  /// older than the retention window. Returns a per-layer removal summary.
  static Future<Map<String, dynamic>> pruneExpiredChats() async {
    final days = await getRetentionDays();
    final results = <String, dynamic>{'retentionDays': days};
    if (days <= 0) return results;

    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));

    results['local'] = await ChatHistoryService.deleteSessionsOlderThan(cutoff);

    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId != null) {
      results['supabase'] = await DatabaseService.pruneOldChats(userId, cutoff);
      results['firestore'] =
          await FirebaseService.pruneOldChatSessions(userId, cutoff);
    }

    developer.log('Retention prune done: $results', name: 'RetentionService');
    return results;
  }

  /// One-shot automated cleanup: prune expired chat history everywhere and ask
  /// the Cloudflare Worker to drop R2 DB snapshots past their retention window.
  static Future<void> runAutomatedCleanup() async {
    try {
      await pruneExpiredChats();
    } catch (e) {
      developer.log('Automated chat prune error: $e', name: 'RetentionService');
    }
    // Best-effort R2 snapshot retention handled server-side by the Worker.
    try {
      await CloudflareService.triggerCleanup();
    } catch (e) {
      developer.log('Automated R2 cleanup error: $e', name: 'RetentionService');
    }
  }
}
