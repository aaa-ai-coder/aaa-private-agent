/// EXAMPLE credentials file.
///
/// Copy this file to `lib/config/credentials.dart` and fill in your real
/// values. `credentials.dart` is gitignored and NEVER committed to the repo,
/// so your secrets stay safe even if this project is public.
class AppCredentials {
  /// Cloudflare R2 (used by StorageService for cloud file storage).
  static const String r2AccountId = 'your_cloudflare_account_id';
  static const String r2BucketName = 'aaa-r2';
  static const String r2AuthEmail = 'your_cloudflare_email';
  static const String r2GlobalKey = 'your_cloudflare_api_key';

  /// Optional Cloudflare API token (bearer). Preferred over the email/global
  /// key pair when set — only one auth method is required.
  static const String r2ApiToken = 'your_cloudflare_api_token';

  /// Supabase management-API personal access token. Only used for privileged
  /// admin operations against api.supabase.com (NOT a PostgREST client key).
  /// The app's normal client flows use the public anon key in
  /// `supabase_config.dart`.
  static const String supabaseManagementToken = '';
}
