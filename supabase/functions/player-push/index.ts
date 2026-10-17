// P1 player Web Push sender (docs/NOTIFICATIONS.md). POST, no body needed. Who may call it:
//   * pg_cron / Supabase Cron every minute (Authorization: Bearer <service role or anon key>): club events that just
//     started, stuck rows, expiry, cleanup, and every push that is due (including the "3 new messages" bundles that wait
//     two minutes). This is what makes bundled pushes arrive; set it up once (docs/NOTIFICATIONS.md, "Owner setup").
//   * a signed-in player's game right after they send a DM / money / friend request (Authorization: Bearer <user JWT>):
//     the push is delivered at once instead of waiting for the next minute. It only ever sends rows the database queued.
// verify_jwt is off (supabase/config.toml) so the new sb_secret / sb_publishable API keys work too; the caller is
// checked here instead. Secrets: VAPID_PRIVATE_KEY, VAPID_SUBJECT (shared with admin-push), optional VAPID_PUBLIC_KEY.
// Without VAPID_PRIVATE_KEY it answers { configured:false } and leaves the rows queued.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { pushKeys } from '../_shared/notify.ts';
import { drainPlayerPush } from '../_shared/playerPush.ts';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

let lastRun = 0;
let lastTick = 0;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return json(req, { ok: false, error: 'auth' }, 401);

  // cron / server callers carry one of the project keys; players carry their own session
  const projectKey = [env('SUPABASE_SERVICE_ROLE_KEY'), env('SUPABASE_ANON_KEY')].filter(Boolean).includes(token);
  const isCron = projectKey; // a Cron job: always runs, and always does the minute work
  if (!projectKey) {
    const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: u } = await userClient.auth.getUser(token);
    if (!u?.user) return json(req, { ok: false, error: 'auth' }, 401);
  }

  // one run at a time per instance: a burst of pokes becomes one run
  const now = Date.now();
  if (!isCron && now - lastRun < 3000) return json(req, { ok: true, throttled: true });
  lastRun = now;
  const tick = isCron || now - lastTick > 55_000;
  if (tick) lastTick = now;
  try {
    const r = await drainPlayerPush(serviceClient(), pushKeys(), { tick });
    return json(req, { ok: true, ...r });
  } catch {
    return json(req, { ok: false, error: 'server_error' }, 500);
  }
});
