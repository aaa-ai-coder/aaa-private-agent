import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/credentials.dart';
import '../config/supabase_config.dart';
import 'firebase_service.dart';

/// Triple-redundant Storage Service: Cloudflare R2 + Supabase Storage + Firebase Storage.
/// R2 uses the account owner's Cloudflare credentials (from the gitignored
/// `config/credentials.dart`, overridable per-device via Settings → Storage).
/// Supabase and Firebase backups work out of the box when those SDKs are configured.
class StorageService {
  static String _accountId = AppCredentials.r2AccountId;
  static String _bucketName = AppCredentials.r2BucketName;
  static String _authEmail = AppCredentials.r2AuthEmail;
  static String _globalKey = AppCredentials.r2GlobalKey;
  static String _apiToken = AppCredentials.r2ApiToken;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accountId = prefs.getString('r2_account_id') ?? AppCredentials.r2AccountId;
    _bucketName = prefs.getString('r2_bucket_name') ?? AppCredentials.r2BucketName;
    _authEmail = prefs.getString('r2_auth_email') ?? AppCredentials.r2AuthEmail;
    _globalKey = prefs.getString('r2_global_key') ?? AppCredentials.r2GlobalKey;
    _apiToken = prefs.getString('r2_api_token') ?? AppCredentials.r2ApiToken;
  }

  static Future<void> saveConfig({
    required String accountId,
    required String bucketName,
    required String apiToken,
    String authEmail = '',
  }) async {
    _accountId = accountId.trim();
    _bucketName = bucketName.trim();
    _globalKey = apiToken.trim();
    _apiToken = apiToken.trim();
    if (authEmail.trim().isNotEmpty) _authEmail = authEmail.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('r2_account_id', _accountId);
    await prefs.setString('r2_bucket_name', _bucketName);
    await prefs.setString('r2_auth_email', _authEmail);
    await prefs.setString('r2_global_key', _globalKey);
    await prefs.setString('r2_api_token', _apiToken);
  }

  /// Whether Cloudflare R2 credentials have been provided by the user.
  static bool get isConfigured =>
      _accountId.isNotEmpty &&
      _bucketName.isNotEmpty &&
      (_apiToken.isNotEmpty ||
          (_authEmail.isNotEmpty && _globalKey.isNotEmpty));

  static String get accountId => _accountId;
  static String get bucketName => _bucketName;
  static String get authEmail => _authEmail;
  static String get apiToken => _apiToken;

  static String get _baseEndpoint =>
      'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_bucketName/objects';

  static Map<String, String> get _authHeaders => _apiToken.isNotEmpty
      ? {'Authorization': 'Bearer $_apiToken'}
      : {
          'X-Auth-Email': _authEmail,
          'X-Auth-Key': _globalKey,
        };

  /// Upload a file simultaneously to Cloudflare R2, Supabase Storage, and Firebase Storage.
  /// Returns the primary public URL on success.
  static Future<String?> uploadFile({
    required File file,
    required String fileName,
    String folder = 'uploads',
  }) async {
    try {
      final bytes = await file.readAsBytes();
      return uploadBytes(
        bytes: bytes,
        fileName: fileName,
        folder: folder,
      );
    } catch (e) {
      developer.log('File read error during upload: $e', name: 'StorageService');
      return null;
    }
  }

  /// Upload raw bytes simultaneously to Cloudflare R2, Supabase Storage, and Firebase Storage.
  static Future<String?> uploadBytes({
    required List<int> bytes,
    required String fileName,
    String folder = 'uploads',
    String? contentType,
  }) async {
    final path = '$folder/$fileName';
    String? publicUrl;

    // 1. Upload to Cloudflare R2
    try {
      final endpoint = '$_baseEndpoint/$path';
      final response = await http.put(
        Uri.parse(endpoint),
        headers: {
          ..._authHeaders,
          'Content-Type': contentType ?? 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        publicUrl = 'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_bucketName/objects/$path';
        developer.log('Cloudflare R2 upload success: $path', name: 'StorageService');
      }
    } catch (e) {
      developer.log('Cloudflare R2 upload error: $e', name: 'StorageService');
    }

    // 2. Auto Backup to Supabase Storage ('aaa-backups' bucket)
    try {
      final uint8Bytes = Uint8List.fromList(bytes);
      final supabasePath = '$folder/$fileName';
      await SupabaseConfig.client.storage.from('aaa-backups').uploadBinary(
            supabasePath,
            uint8Bytes,
            fileOptions: FileOptions(
              contentType: contentType ?? 'application/octet-stream',
              upsert: true,
            ),
          );
      final supabaseUrl = SupabaseConfig.client.storage
          .from('aaa-backups')
          .getPublicUrl(supabasePath);
      publicUrl ??= supabaseUrl;
      developer.log('Supabase Storage backup success: $supabasePath', name: 'StorageService');
    } catch (e) {
      developer.log('Supabase Storage backup error: $e', name: 'StorageService');
    }

    // 3. Auto Backup to Firebase Storage
    try {
      final fbUrl = await FirebaseService.uploadBytesToStorage(
        bytes: bytes,
        path: path,
        contentType: contentType,
      );
      if (fbUrl != null) {
        publicUrl ??= fbUrl;
        developer.log('Firebase Storage backup success: $path', name: 'StorageService');
      }
    } catch (e) {
      developer.log('Firebase Storage backup error: $e', name: 'StorageService');
    }

    return publicUrl;
  }

  /// Delete a file from Cloudflare R2, Supabase Storage, and Firebase Storage.
  static Future<bool> deleteFile(String path) async {
    bool success = false;

    // Delete from Cloudflare R2
    try {
      final endpoint = '$_baseEndpoint/$path';
      final response = await http.delete(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        success = true;
      }
    } catch (e) {
      developer.log('Cloudflare R2 delete error: $e', name: 'StorageService');
    }

    // Delete from Supabase Storage
    try {
      await SupabaseConfig.client.storage.from('aaa-backups').remove([path]);
      success = true;
    } catch (e) {
      developer.log('Supabase Storage delete error: $e', name: 'StorageService');
    }

    // Delete from Firebase Storage
    try {
      await FirebaseService.deleteFromStorage(path);
      success = true;
    } catch (e) {
      developer.log('Firebase Storage delete error: $e', name: 'StorageService');
    }

    return success;
  }

  /// List files in Cloudflare R2 or Supabase Storage.
  static Future<List<String>> listFiles(String prefix) async {
    final keys = <String>[];

    // Try Cloudflare R2 list
    try {
      final endpoint =
          'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_bucketName/objects?prefix=$prefix';
      final response = await http.get(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['result'] is List) {
          for (final item in json['result']) {
            if (item['key'] != null) {
              keys.add(item['key'].toString());
            }
          }
        }
      }
    } catch (e) {
      developer.log('Cloudflare R2 list error: $e', name: 'StorageService');
    }

    // Fallback/Merge Supabase Storage
    if (keys.isEmpty) {
      try {
        final objects = await SupabaseConfig.client.storage
            .from('aaa-backups')
            .list(path: prefix);
        for (final obj in objects) {
          keys.add('${prefix.isEmpty ? '' : '$prefix/'}${obj.name}');
        }
      } catch (e) {
        developer.log('Supabase Storage list error: $e', name: 'StorageService');
      }
    }

    return keys;
  }

  /// Get public URL.
  static String getPublicUrl(String path) {
    return 'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_bucketName/objects/$path';
  }
}

