# Supabase Keep-Alive & Backup Worker

Deployed at `https://aaa-supabase-keepalive.aaaai.workers.dev`.

## What it does

1. **Keep-alive** — every 5 minutes pings the Supabase project
   (`/auth/v1/health`). The free tier pauses a project after ~1 week without
   any API request; this resets the timer so the database never sleeps.
2. **Daily DB snapshot** — once per day exports every table through the REST
   API (service_role) and stores it in the `aaa-r2` bucket as
   `db-backup/YYYY-MM-DD.json` (a logical backup of all chat data).
3. **Automated retention cleanup** — once per day deletes `db-backup/`
   snapshots older than `BACKUP_RETENTION_DAYS` (default 30) so the bucket
   never grows without bound.

## Routes

- `GET /` — keepalive ping (the app calls this on startup).
- `GET /backup` — on-demand full backup (`?force=1` to overwrite today's file).
- `GET /cleanup` — delete expired snapshots. `?dryRun=1` previews without
  deleting; `?days=N` overrides the retention window for this run.
- `GET /health` — liveness probe.

## Deploy

```bash
cd workers/supabase-keepalive
export CLOUDFLARE_API_KEY=...   # Global API key
export CLOUDFLARE_EMAIL=...     # Cloudflare account email

# One-time: the service_role key is never stored in the repo
cat /path/to/service_role | npx wrangler secret put SUPABASE_SERVICE_ROLE

npx wrangler deploy
```

Cron, R2 bucket binding, and non-secret vars (anon key, table list) live in
`wrangler.toml`. The worker requires the R2 binding `BACKUPS` → `aaa-r2` and
the `SUPABASE_SERVICE_ROLE` secret.
