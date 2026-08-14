import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'app_log_service.dart';
import 'hive_service.dart';

/// Automatic cloud backup for every API key plus the active provider/model.
///
/// Users bring their own Supabase project (project URL + anon key) and a
/// private passcode. All keys are serialized into one JSON payload and upserted
/// into a `nova_key_backup` table (columns: passcode text pk, payload text,
/// updated_at timestamptz). Restore pulls the row back and rewrites Hive.
///
/// The payload is base64-encoded, not encrypted, so protect your anon key and
/// use a strong passcode; it is opaque to anyone without the URL + key.
class KeyBackupService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();

  static const String backupUrlKey = 'backup_supabase_url';
  static const String backupAnonKey = 'backup_supabase_anon_key';
  static const String backupPasscode = 'backup_supabase_passcode';

  /// Reactive flag so the UI can observe configuration changes.
  final RxBool configured = false.obs;

  bool get _isConfigured {
    final url = _hive.getSetting<String>(backupUrlKey) ?? '';
    final key = _hive.getSetting<String>(backupAnonKey) ?? '';
    final pass = _hive.getSetting<String>(backupPasscode) ?? '';
    return url.isNotEmpty && key.isNotEmpty && pass.isNotEmpty;
  }

  bool get isConfigured => configured.value;

  @override
  void onInit() {
    super.onInit();
    configured.value = _isConfigured;
  }

  String get providerLabel {
    if (!configured.value) return 'Not configured';
    return 'Automatic cloud backup ON';
  }

  Future<void> configure({
    required String url,
    required String anonKey,
    required String passcode,
  }) async {
    await _hive.setSetting(backupUrlKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
    await _hive.setSetting(backupAnonKey, anonKey.trim());
    await _hive.setSetting(backupPasscode, passcode.trim());
    configured.value = true;
    await syncNow();
  }

  Future<void> clear() async {
    await _hive.setSetting(backupUrlKey, '');
    await _hive.setSetting(backupAnonKey, '');
    await _hive.setSetting(backupPasscode, '');
    configured.value = false;
  }

  Map<String, String> _collectKeys() {
    final keys = <String, String>{};
    for (final key in [
      AppConstants.keyOpenaiKey,
      AppConstants.keyAnthropicKey,
      AppConstants.keyGoogleKey,
      AppConstants.keyKimiKey,
      AppConstants.keyStabilityKey,
      AppConstants.keyNvidiaKey,
      AppConstants.keyOpenRouterKey,
      AppConstants.keyDeepSeekKey,
      AppConstants.keyCustomCloudKey,
    ]) {
      final value = _hive.getSetting<String>(key) ?? '';
      if (value.isNotEmpty) keys[key] = value;
    }
    return keys;
  }

  Map<String, String> _collectSettings() {
    String setting(String key, {String fallback = ''}) {
      final value = _hive.getSetting<String>(key, defaultValue: fallback);
      return value ?? fallback;
    }

    return {
      AppConstants.keyCloudProvider:
          setting(AppConstants.keyCloudProvider, fallback: 'freeai'),
      AppConstants.keyFreeAiModel:
          setting(AppConstants.keyFreeAiModel, fallback: 'openai-fast'),
      AppConstants.keyOpenaiModel: setting(AppConstants.keyOpenaiModel),
      AppConstants.keyAnthropicModel: setting(AppConstants.keyAnthropicModel),
      AppConstants.keyGoogleModel: setting(AppConstants.keyGoogleModel),
      AppConstants.keyKimiModel: setting(AppConstants.keyKimiModel),
      AppConstants.keyStabilityModel: setting(AppConstants.keyStabilityModel),
      AppConstants.keyNvidiaModel: setting(AppConstants.keyNvidiaModel),
      AppConstants.keyOpenRouterModel: setting(AppConstants.keyOpenRouterModel),
      AppConstants.keyDeepSeekModel: setting(AppConstants.keyDeepSeekModel),
      AppConstants.keyCustomCloudModel: setting(AppConstants.keyCustomCloudModel),
      AppConstants.keyCustomCloudName: setting(AppConstants.keyCustomCloudName),
      AppConstants.keyCustomCloudBaseUrl:
          setting(AppConstants.keyCustomCloudBaseUrl),
    };
  }

  /// Silent, safe to call repeatedly. No-ops when not configured, never throws.
  Future<void> syncNow() async {
    if (!_isConfigured) return;
    try {
      final baseUrl = _hive.getSetting<String>(backupUrlKey) ?? '';
      final anonKey = _hive.getSetting<String>(backupAnonKey) ?? '';
      final passcode = _hive.getSetting<String>(backupPasscode) ?? '';

      final payload = base64Url.encode(utf8.encode(jsonEncode({
        'keys': _collectKeys(),
        'settings': _collectSettings(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      })));

      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('$baseUrl/rest/v1/nova_key_backup?on_conflict=passcode'),
          headers: {
            'apikey': anonKey,
            'Authorization': 'Bearer $anonKey',
            'Content-Type': 'application/json',
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'passcode': passcode,
            'payload': payload,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        if (response.statusCode >= 300) {
          Get.find<AppLogService>().error(
              'Key backup upload failed (${response.statusCode})',
              details: response.body);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      Get.find<AppLogService>().error('Key backup error', details: e);
    }
  }

  /// Pulls the stored payload and rewrites Hive. Returns true on success.
  Future<bool> restore() async {
    if (!_isConfigured) return false;
    try {
      final baseUrl = _hive.getSetting<String>(backupUrlKey) ?? '';
      final anonKey = _hive.getSetting<String>(backupAnonKey) ?? '';
      final passcode = _hive.getSetting<String>(backupPasscode) ?? '';

      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(
              '$baseUrl/rest/v1/nova_key_backup?passcode=eq.$passcode&select=payload'),
          headers: {
            'apikey': anonKey,
            'Authorization': 'Bearer $anonKey',
          },
        );
        if (response.statusCode == 200) {
          final rows = jsonDecode(response.body) as List;
          if (rows.isEmpty) return false;
          final encoded = (rows.first as Map)['payload'] as String?;
          if (encoded == null || encoded.isEmpty) return false;
          final data = jsonDecode(utf8.decode(base64Url.decode(encoded)));
          final keys =
              (data['keys'] as Map?)?.cast<String, String>() ?? const {};
          final settings =
              (data['settings'] as Map?)?.cast<String, String>() ?? const {};
          for (final entry in keys.entries) {
            await _hive.setSetting(entry.key, entry.value);
          }
          for (final entry in settings.entries) {
            await _hive.setSetting(entry.key, entry.value);
          }
          return true;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      Get.find<AppLogService>().error('Key restore error', details: e);
    }
    return false;
  }
}
