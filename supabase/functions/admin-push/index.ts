// H3 admin Web Push (docs/BILLBOARDS.md). POST with any signed-in user's JWT:
//   {}            -> end finished billboard ads (bl_billboard_sweep), then push the unsent admin notifications
//                    to every admin's subscribed devices. Players call this after reporting an ad, the map after
//                    loading boards, the admin page while open. It only ever sends rows the database created.
//   { test: true } -> admins only: a test notification to the caller's own devices.
// Secrets: VAPID_PRIVATE_KEY, VAPID_SUBJECT (and optionally VAPID_PUBLIC_KEY). Without them it answers
// { configured:false } and the admin page falls back to its unread badge + sound.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { flushAdminPush } from '../_shared/notify.ts';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth' }, 401);
  const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: u } = await userClient.auth.getUser(auth.slice(7));
  if (!u?.user) return json(req, { ok: false, error: 'auth' }, 401);

  let body: { test?: boolean } = {};
  try { body = await req.json(); } catch { /* empty body */ }
  const db = serviceClient();
  try {
    if (body.test) {
      const { data: me } = await db.from('profiles').select('is_admin, banned').eq('id', u.user.id).maybeSingle();
      if (!me?.is_admin || me.banned) return json(req, { ok: false, error: 'not_admin' }, 403);
      const r = await flushAdminPush(db, u.user.id, {
        title: 'Benin Life admin', body: 'Notifications work on this device. You will hear about new ads here.', url: '/admin/ads', tag: 'bl-admin-test',
      });
      return json(req, { ok: true, ...r });
    }
    await db.rpc('bl_billboard_sweep');
    const r = await flushAdminPush(db);
    return json(req, { ok: true, ...r });
  } catch {
    return json(req, { ok: false, error: 'server_error' }, 500);
  }
});
