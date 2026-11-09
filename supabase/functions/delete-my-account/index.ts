// Fix it 8: a player deletes their OWN account (docs/FIXIT.md item 8). POST { confirm: "DELETE" } with the player's JWT.
//  1. self_delete_start with the caller's JWT: the database checks the confirmation text, refuses admins and writes the
//     admin_audit row (username + email snapshot) BEFORE anything is deleted.
//  2. bl_user_storage_paths (service role): the list of the player's files (billboard images, voice notes, gist photos,
//     real-business photos, club-music uploads). Only COLLECTED here: nothing is removed yet.
//  3. auth.admin.deleteUser (service role). Every game row with a foreign key goes by cascade, exactly like the admin delete
//     (migration 20261012000800); payments stay for the books with user_id = null; the audit row stays. Cannot be undone.
//     If this fails: nothing was removed (files and rows are intact), 'self_delete_account_failed' is written, and the
//     answer carries a short reason.
//  4. Only after step 3 succeeded: the files are removed through the Storage API, bl_delete_user_leftovers clears the rows
//     that hold the user id without a foreign key (docs/SECURITY.md), and 'self_delete_account_done' is written.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method', message: 'Use POST.' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth', message: 'Sign in again and retry.' }, 401);
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
  // 2. collect the file list first (nothing is removed yet)
  const { data: paths } = await db.rpc('bl_user_storage_paths', { p_user: userId });
  const byBucket = new Map<string, string[]>();
  for (const p of (paths ?? []) as { bucket: string; name: string }[]) {
    byBucket.set(p.bucket, [...(byBucket.get(p.bucket) ?? []), p.name]);
  }

  // 3. the account itself
  const { error: delErr } = await db.auth.admin.deleteUser(userId);
  if (delErr) {
    await db.rpc('bl_self_delete_failed', { p_user: userId, p_error: delErr.message });
    return json(req, {
      ok: false, error: 'delete_failed',
      message: `Delete failed: ${delErr.message || 'the server could not remove the account'}. Nothing was lost, try again.`,
    }, 500);
  }

  // 4. the account is gone: clean up what pointed at it (a failure here never undoes the delete; it is audited)
  // supabase-js returns { data, error } and does not throw: every failure is logged and recorded in the done audit row
  let removedFiles = 0;
  const filesErrors: string[] = [];
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const { data: gone, error: rmErr } = await db.storage.from(bucket).remove(names.slice(i, i + 100));
      if (rmErr) {
        console.error('storage remove failed', bucket, rmErr.message);
        filesErrors.push(`${bucket}: ${rmErr.message}`);
      } else removedFiles += gone?.length ?? 0;
    }
  }
  let leftovers: Record<string, unknown> = {};
  const { data: lo, error: loErr } = await db.rpc('bl_delete_user_leftovers', { p_uid: userId });
  if (loErr) {
    console.error('bl_delete_user_leftovers failed', loErr.message);
    leftovers = { error: loErr.message };
  } else leftovers = (lo ?? {}) as Record<string, unknown>;
  if (filesErrors.length) leftovers = { ...leftovers, files_error: filesErrors.join('; ').slice(0, 500) };
  const { error: doneErr } = await db.rpc('bl_self_delete_done', { p_user: userId, p_files: removedFiles, p_leftovers: leftovers });
  if (doneErr) console.error('bl_self_delete_done failed', doneErr.message);
  return json(req, { ok: true, message: 'Your account and all its data are deleted.' });
});
