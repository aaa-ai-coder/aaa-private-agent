import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static String? _accountId;
  static String? _bucketName;
  static String? _accessKeyId;
  static String? _secretAccessKey;

  /// Initialize Cloudflare R2 S3 storage settings
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accountId = prefs.getString('r2_account_id');
    _bucketName = prefs.getString('r2_bucket_name');
    _accessKeyId = prefs.getString('r2_access_key');
    _secretAccessKey = prefs.getString('r2_secret_key');
  }

  static Future<void> saveConfig({
    required String accountId,
    required String bucketName,
    required String accessKeyId,
    required String secretAccessKey,
  }) async {
    _accountId = accountId.trim();
    _bucketName = bucketName.trim();
    _accessKeyId = accessKeyId.trim();
    _secretAccessKey = secretAccessKey.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('r2_account_id', _accountId!);
    await prefs.setString('r2_bucket_name', _bucketName!);
    await prefs.setString('r2_access_key', _accessKeyId!);
    await prefs.setString('r2_secret_key', _secretAccessKey!);
  }

  static bool get isConfigured =>
      _accountId != null &&
      _bucketName != null &&
      _accessKeyId != null &&
      _secretAccessKey != null &&
      _accountId!.isNotEmpty &&
      _bucketName!.isNotEmpty;

  /// Upload a file or screenshot to Cloudflare R2 (S3 compatible endpoint)
  static Future<String?> uploadFile({
    required File file,
    required String fileName,
    String folder = 'uploads',
  }) async {
    if (!isConfigured) return null;

    try {
      final endpoint = 'https://$_accountId.r2.cloudflarestorage.com/$_bucketName/$folder/$fileName';
      
      final bytes = await file.readAsBytes();
      
      // Cloudflare R2 S3 HTTP PUT upload
      final response = await http.put(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_accessKeyId', // Or AWS Signature V4 if required
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return endpoint;
      }
      return null;
    } catch (e) {
      print('Cloudflare R2 upload error: $e');
      return null;
    }
  }
}
