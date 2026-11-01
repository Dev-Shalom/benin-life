// Fix it 8: a player deletes their OWN account (docs/FIXIT.md item 8). POST { confirm: "DELETE" } with the player's JWT.
//  1. self_delete_start with the caller's JWT: the database checks the confirmation text, refuses admins and writes the
//     admin_audit row (username + email snapshot) BEFORE anything is deleted.
//  2. bl_user_storage_paths (service role): billboard images + voice notes, removed through the Storage API.
//  3. auth.admin.deleteUser (service role). Every game row goes by FK cascade, exactly like the admin delete (migration
//     20261012000800); payments stay for the books with user_id = null; the audit row stays. This cannot be undone.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth' }, 401);
  let body: { confirm?: unknown } = {};
  try { body = (await req.json()) ?? {}; } catch { /* fall through */ }

  const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: caller } = await userClient.auth.getUser();
  const userId = caller?.user?.id;
  if (!userId) return json(req, { ok: false, error: 'auth', message: 'Sign in again and retry.' }, 401);
  const { data: start, error: startErr } = await userClient.rpc('self_delete_start', { p_confirm: String(body.confirm ?? '') });
  if (startErr || !start?.ok) {
    return json(req, { ok: false, error: startErr?.hint || 'refused', message: startErr?.message ?? 'Refused.' }, 403);
  }

  const db = serviceClient();
  const { data: paths } = await db.rpc('bl_user_storage_paths', { p_user: userId });
  const byBucket = new Map<string, string[]>();
  for (const p of (paths ?? []) as { bucket: string; name: string }[]) {
    byBucket.set(p.bucket, [...(byBucket.get(p.bucket) ?? []), p.name]);
  }
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) await db.storage.from(bucket).remove(names.slice(i, i + 100));
  }

  const { error: delErr } = await db.auth.admin.deleteUser(userId);
  if (delErr) {
    await db.rpc('bl_self_delete_failed', { p_user: userId, p_error: delErr.message });
    return json(req, { ok: false, error: 'delete_failed', message: `Delete failed: ${delErr.message}. Nothing was lost, try again.` }, 500);
  }
  return json(req, { ok: true, message: 'Your account and all its data are deleted.' });
});
