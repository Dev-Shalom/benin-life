// S1 admin account deletion (docs/ADMIN.md "Delete a player"). POST { user_id, confirm, reason } with an ADMIN's JWT.
//  1. admin_delete_user_start with the caller's JWT: the database checks the caller is an admin (profiles.is_admin),
//     refuses yourself / other admins / a wrong confirmation, and writes the admin_audit row (username + email
//     snapshot) BEFORE anything is deleted.
//  2. bl_user_storage_paths (service role): billboard images + voice notes, removed through the Storage API.
//  3. auth.admin.deleteUser (service role). Every game row goes by FK cascade (migration 20261012000800);
//     payments stay for the books with user_id = null; the audit row stays.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth' }, 401);
  let body: { user_id?: unknown; confirm?: unknown; reason?: unknown } = {};
  try { body = (await req.json()) ?? {}; } catch { /* fall through */ }
  const userId = String(body.user_id ?? '');
  if (!UUID.test(userId)) return json(req, { ok: false, error: 'bad_user', message: 'Pick a player.' }, 400);

  const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: caller } = await userClient.auth.getUser();
  const { data: start, error: startErr } = await userClient.rpc('admin_delete_user_start', {
    p_user: userId, p_confirm: String(body.confirm ?? ''), p_reason: String(body.reason ?? ''),
  });
  if (startErr || !start?.ok) {
    return json(req, { ok: false, error: startErr?.hint || 'refused', message: startErr?.message ?? 'Refused.' }, 403);
  }

  const db = serviceClient();
  // storage first: once the account is gone, nothing would point at these files any more
  let removedFiles = 0;
  const { data: paths } = await db.rpc('bl_user_storage_paths', { p_user: userId });
  const byBucket = new Map<string, string[]>();
  for (const p of (paths ?? []) as { bucket: string; name: string }[]) {
    byBucket.set(p.bucket, [...(byBucket.get(p.bucket) ?? []), p.name]);
  }
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const { data: gone } = await db.storage.from(bucket).remove(names.slice(i, i + 100));
      removedFiles += gone?.length ?? 0;
    }
  }

  const { error: delErr } = await db.auth.admin.deleteUser(userId);
  if (delErr) {
    await db.rpc('bl_admin_delete_user_failed', { p_admin: caller?.user?.id ?? null, p_user: userId, p_error: delErr.message });
    return json(req, { ok: false, error: 'delete_failed', message: `Delete failed: ${delErr.message}` }, 500);
  }
  return json(req, {
    ok: true, username: start.username, removed_files: removedFiles,
    message: `@${start.username ?? 'player'} has been deleted with all their game data.`,
  });
});
