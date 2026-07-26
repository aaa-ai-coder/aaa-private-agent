import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Dual storage service supporting Cloudflare R2 + Firebase Storage.
/// R2 is primary for heavy data (screenshots, recordings, backups).
class StorageService {
  static String? _accountId;
  static String? _bucketName;
  static String? _apiToken;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accountId = prefs.getString('r2_account_id');
    _bucketName = prefs.getString('r2_bucket_name');
    _apiToken = prefs.getString('r2_api_token');
  }

  static Future<void> saveConfig({
    required String accountId,
    required String bucketName,
    required String apiToken,
  }) async {
    _accountId = accountId.trim();
    _bucketName = bucketName.trim();
    _apiToken = apiToken.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('r2_account_id', _accountId!);
    await prefs.setString('r2_bucket_name', _bucketName!);
    await prefs.setString('r2_api_token', _apiToken!);
  }

  static bool get isConfigured =>
      _accountId != null &&
      _bucketName != null &&
      _apiToken != null &&
      _accountId!.isNotEmpty &&
      _bucketName!.isNotEmpty;

  static String get _baseEndpoint =>
      'https://$_accountId.r2.cloudflarestorage.com/$_bucketName';

  static Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_apiToken',
      };

  /// Upload a file to Cloudflare R2.
  /// Returns the public URL on success, null on failure.
  static Future<String?> uploadFile({
    required File file,
    required String fileName,
    String folder = 'uploads',
  }) async {
    if (!isConfigured) return null;

    try {
      final path = '$folder/$fileName';
      final endpoint = '$_baseEndpoint/$path';
      final bytes = await file.readAsBytes();

      final response = await http.put(
        Uri.parse(endpoint),
        headers: {
          ..._authHeaders,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return _publicUrl(path);
      }
      return null;
    } catch (e) {
      print('Cloudflare R2 upload error: $e');
      return null;
    }
  }

  /// Upload raw bytes to Cloudflare R2.
  static Future<String?> uploadBytes({
    required List<int> bytes,
    required String fileName,
    String folder = 'uploads',
    String? contentType,
  }) async {
    if (!isConfigured) return null;

    try {
      final path = '$folder/$fileName';
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
        return _publicUrl(path);
      }
      return null;
    } catch (e) {
      print('Cloudflare R2 upload error: $e');
      return null;
    }
  }

  /// Download a file from Cloudflare R2.
  /// Returns the file bytes on success, null on failure.
  static Future<List<int>?> downloadFile(String path) async {
    if (!isConfigured) return null;

    try {
      final endpoint = '$_baseEndpoint/$path';
      final response = await http.get(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Cloudflare R2 download error: $e');
      return null;
    }
  }

  /// Delete a file from Cloudflare R2.
  static Future<bool> deleteFile(String path) async {
    if (!isConfigured) return false;

    try {
      final endpoint = '$_baseEndpoint/$path';
      final response = await http.delete(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Cloudflare R2 delete error: $e');
      return false;
    }
  }

  /// List files in a folder prefix (R2 doesn't have native list via S3 API
  /// with just Bearer token — this is a best-effort listing using delimiter).
  /// Returns list of object keys.
  static Future<List<String>> listFiles(String prefix) async {
    if (!isConfigured) return [];

    try {
      // R2 S3-compatible list objects v2
      final endpoint =
          '$_baseEndpoint?list-type=2&prefix=$prefix&delimiter=/';
      final response = await http.get(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final body = response.body;
        final keys = <String>[];

        // Parse XML response for Key and CommonPrefixes
        final keyRegex = RegExp(r'<Key>([^<]+)</Key>');
        for (final match in keyRegex.allMatches(body)) {
          keys.add(match.group(1)!);
        }

        // Also include CommonPrefixes (subfolders)
        final prefixRegex = RegExp(r'<CommonPrefixes>.*?<Prefix>([^<]+)</Prefix>.*?</CommonPrefixes>', dotAll: true);
        for (final match in prefixRegex.allMatches(body)) {
          keys.add(match.group(1)!);
        }

        return keys;
      }
      return [];
    } catch (e) {
      print('Cloudflare R2 list error: $e');
      return [];
    }
  }

  /// Check if a file exists in R2.
  static Future<bool> fileExists(String path) async {
    if (!isConfigured) return false;

    try {
      final endpoint = '$_baseEndpoint/$path';
      final response = await http.head(
        Uri.parse(endpoint),
        headers: _authHeaders,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get the public URL for a file (readable via R2 public bucket setting).
  static String _publicUrl(String path) {
    return 'https://$_accountId.r2.cloudflarestorage.com/$_bucketName/$path';
  }

  /// Get a shareable signed URL (R2 public bucket URL).
  static String getPublicUrl(String path) {
    return _publicUrl(path);
  }
}
