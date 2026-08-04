// AAA Private Agent — Supabase keepalive + backup worker.
//
// Responsibilities:
//  1. Every 5 minutes, ping the Supabase project so the free tier never
//     pauses the database (auth/v1/health is enough to reset the timer).
//  2. Once per day, export every table via the REST API (service_role) and
//     snapshot it as JSON into the R2 bucket under db-backup/YYYY-MM-DD.json.
//
// HTTP routes:
//  GET /              keepalive ping (also used by the app on startup)
//  GET /backup        on-demand full backup (force=1 to override today's file)
//  GET /health        liveness probe

const BUCKET_KEY_PREFIX = 'db-backup/';

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runKeepalive(env));

    // Once per day: only attempt when no snapshot exists for today.
    ctx.waitUntil(
      runBackup(env, { force: false }).catch((e) =>
        console.error('scheduled backup failed:', String(e)),
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
