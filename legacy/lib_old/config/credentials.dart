/// Local credentials file — GITIGNORED, never commit.
///
/// Populated from the account credentials provided by the project owner.
/// All values here are scrubbed placeholders — the real values live only in
/// GitHub Actions secrets and are substituted at CI build time.
class AppCredentials {
  /// Cloudflare R2 (used by StorageService for cloud file storage).
  /// Bearer API token is preferred when set; the email/global key pair is the
  /// fallback for accounts that only expose a legacy global API key.
  static const String r2AccountId = 'your_cloudflare_account_id';
  static const String r2BucketName = 'aaa-r2';
  static const String r2AuthEmail = 'your_cloudflare_email';
  static const String r2GlobalKey = 'your_cloudflare_api_key';
  static const String r2ApiToken = 'your_cloudflare_api_token';

  /// Supabase management-API personal access token. Only used for privileged
  /// admin operations against api.supabase.com (NOT a PostgREST client key).
  /// The app's normal client flows use the public anon key in
  /// `supabase_config.dart`.
  static const String supabaseManagementToken = 'your_supabase_management_token';
}
