import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<String?> uploadFile({
    required File file,
    required String fileName,
    String folder = 'uploads',
  }) async {
    if (!isConfigured) return null;

    try {
      final endpoint = 'https://$_accountId.r2.cloudflarestorage.com/$_bucketName/$folder/$fileName';
      final bytes = await file.readAsBytes();

      final response = await http.put(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_apiToken',
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