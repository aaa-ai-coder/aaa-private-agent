/// Cloudflare Worker endpoints.
///
/// The Worker keeps the Supabase project awake (free tier pauses after ~1 week
/// of inactivity) and snapshots the whole database to R2 daily.
class CloudflareConfig {
  static const String keepaliveWorkerUrl =
      'https://aaa-supabase-keepalive.aaaai.workers.dev';
}
