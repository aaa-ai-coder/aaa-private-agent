// AAA Private Agent — Supabase keepalive + backup + cleanup worker.
//
// Responsibilities:
//  1. Every 5 minutes, ping the Supabase project so the free tier never
//     pauses the database (auth/v1/health is enough to reset the timer).
//  2. Once per day, export every table via the REST API (service_role) and
//     snapshot it as JSON into the R2 bucket under db-backup/YYYY-MM-DD.json.
//  3. Once per day, delete db-backup/ snapshots older than the retention
//     window (BACKUP_RETENTION_DAYS, default 30) so the bucket never grows
//     without bound.
//
// HTTP routes:
//  GET /              keepalive ping (also used by the app on startup)
//  GET /backup        on-demand full backup (force=1 to override today's file)
//  GET /cleanup       delete expired snapshots (dryRun=1 to preview,
//                     days=N to override the retention window)
//  GET /health        liveness probe

const BUCKET_KEY_PREFIX = 'db-backup/';
const DEFAULT_RETENTION_DAYS = 30;

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runKeepalive(env));

    // Once per day: only attempt when no snapshot exists for today.
    ctx.waitUntil(
      runBackup(env, { force: false }).catch((e) =>
        console.error('scheduled backup failed:', String(e)),
      ),
    );

    // Once per day: drop expired snapshots from R2.
    ctx.waitUntil(
      runCleanup(env).catch((e) =>
        console.error('scheduled cleanup failed:', String(e)),
      ),
    );
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === '/health') {
        return json({
          ok: true,
          service: 'supabase-keepalive',
          time: new Date().toISOString(),
        });
      }

      if (path === '/backup') {
        const force = url.searchParams.get('force') === '1';
        return json(await runBackup(env, { force }));
      }

      if (path === '/cleanup') {
        const dryRun = url.searchParams.get('dryRun') === '1';
        const daysRaw = url.searchParams.get('days');
        const days = daysRaw ? Number(daysRaw) : NaN;
        return json(await runCleanup(env, { dryRun, days }));
      }

      // Default route: keepalive ping (wakes a paused project).
      return json(await runKeepalive(env));
    } catch (e) {
      console.error('worker error:', String(e));
      return json({ ok: false, error: String(e) }, 500);
    }
  },
};

async function runKeepalive(env) {
  const started = Date.now();
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/health`, {
    headers: { apikey: env.SUPABASE_ANON_KEY },
  });
  return {
    ok: res.ok,
    http: res.status,
    latencyMs: Date.now() - started,
    time: new Date().toISOString(),
  };
}

async function runBackup(env, { force }) {
  const today = new Date().toISOString().slice(0, 10);
  const key = `${BUCKET_KEY_PREFIX}${today}.json`;

  if (!force) {
    const existing = await env.BACKUPS.head(key);
    if (existing) {
      return { ok: true, skipped: true, key, size: existing.size };
    }
  }

  const tables = env.BACKUP_TABLES.split(',').map((t) => t.trim()).filter(Boolean);
  const data = {};

  for (const table of tables) {
    data[table] = await fetchAllRows(env, table);
  }

  const payload = JSON.stringify({
    project: env.SUPABASE_URL.replace(/^https:\/\//, ''),
    exported_at: new Date().toISOString(),
    tables: data,
  });

  const buf = new TextEncoder().encode(payload);
  await env.BACKUPS.put(key, buf, {
    httpMetadata: { contentType: 'application/json' },
  });

  return { ok: true, skipped: false, key, bytes: buf.byteLength, tables };
}

function retentionDays(env, override) {
  const value = Number.isFinite(override) && override > 0 ? override : Number(env.BACKUP_RETENTION_DAYS);
  return Number.isFinite(value) && value > 0 ? value : DEFAULT_RETENTION_DAYS;
}

/// Delete db-backup/YYYY-MM-DD.json snapshots older than the retention window.
/// When `dryRun` is true, lists the expired keys without deleting anything.
/// Returns the set of removed (or would-be removed) keys.
async function runCleanup(env, { dryRun = false, days } = {}) {
  const retention = retentionDays(env, days);
  const cutoff = Date.now() - retention * 24 * 60 * 60 * 1000;
  const removed = [];
  const errors = [];

  const objects = await env.BACKUPS.list({ prefix: BUCKET_KEY_PREFIX });
  for (const obj of objects.objects) {
    const name = obj.key.slice(BUCKET_KEY_PREFIX.length); // YYYY-MM-DD.json
    const parsed = parseSnapshotDate(name);
    if (parsed === null) {
      // Not a date-named snapshot; leave it alone.
      continue;
    }
    if (parsed.getTime() >= cutoff) {
      continue;
    }
    try {
      if (!dryRun) {
        await env.BACKUPS.delete(obj.key);
      }
      removed.push(obj.key);
    } catch (e) {
      errors.push({ key: obj.key, error: String(e) });
      console.error(`cleanup failed for ${obj.key}:`, String(e));
    }
  }

  return {
    ok: errors.length === 0,
    dryRun,
    retentionDays: retention,
    cutoff: new Date(cutoff).toISOString(),
    removed,
    deleted: removed.length,
    errors,
  };
}

/// Parse `YYYY-MM-DD.json` into a Date, or null when the name does not match.
function parseSnapshotDate(name) {
  const match = /^(\d{4})-(\d{2})-(\d{2})\.json$/.exec(name);
  if (!match) return null;
  const date = new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00.000Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}

async function fetchAllRows(env, table) {
  const rows = [];
  const limit = 1000;
  let from = 0;

  for (;;) {
    const res = await fetch(
      `${env.SUPABASE_URL}/rest/v1/${table}?select=*`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE}`,
          Range: `${from}-${from + limit - 1}`,
          Prefer: 'count=exact',
        },
      },
    );
    if (!res.ok) {
      throw new Error(`${table}: HTTP ${res.status}`);
    }
    const page = await res.json();
    rows.push(...page);
    if (!Array.isArray(page) || page.length < limit) break;
    from += limit;
  }

  return rows;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}
