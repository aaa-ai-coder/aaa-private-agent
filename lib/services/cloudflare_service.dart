import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../config/cloudflare_config.dart';

/// Client for the AAA Supabase keep-alive + backup Worker.
///
/// The Worker (deployed on Cloudflare) pings the Supabase project every
/// 5 minutes so the free-tier database never sleeps, and snapshots all
/// tables to the R2 bucket (`db-backup/YYYY-MM-DD.json`) once per day.
class CloudflareService {
  static const String _baseUrl = CloudflareConfig.keepaliveWorkerUrl;

  /// Wake the Supabase project and keep its inactivity timer reset.
  /// Fire-and-forget; safe to call on every app launch.
  static Future<bool> pingKeepalive() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/'))
          .timeout(const Duration(seconds: 12));
      final ok = res.statusCode == 200;
      if (!ok) {
        developer.log(
          'Keepalive ping HTTP ${res.statusCode}',
          name: 'CloudflareService',
        );
      }
      return ok;
    } catch (e) {
      developer.log('Keepalive ping error: $e', name: 'CloudflareService');
      return false;
    }
  }

  /// Trigger an on-demand full database backup to R2.
  /// Returns the resulting backup key (e.g. `db-backup/2026-08-04.json`).
  static Future<String?> triggerBackup() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/backup?force=1'))
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return json['ok'] == true ? json['key'] as String? : null;
    } catch (e) {
      developer.log('Trigger backup error: $e', name: 'CloudflareService');
      return null;
    }
  }

  /// Ask the Worker for its latest status.
  static Future<Map<String, dynamic>?> status() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      developer.log('Worker status error: $e', name: 'CloudflareService');
      return null;
    }
  }
}
