// POST { reference } with the player's JWT, after Paystack Inline reports success.
// Checks the caller owns the payment, verifies it with Paystack (secret key) and credits once.
// Returns { ok, credited, already, bank } or { ok:false, error }.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { corsHeaders, env, json, serviceClient, verifyAndCredit } from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth' }, 401);
  const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: u, error: uErr } = await userClient.auth.getUser(auth.slice(7));
  if (uErr || !u?.user) return json(req, { ok: false, error: 'auth' }, 401);

  let reference = '';
  try {
    const body = await req.json();
    reference = String(body?.reference ?? '').trim();
  } catch { /* fall through */ }
  if (!/^BL-[a-f0-9]{32}$/.test(reference)) return json(req, { ok: false, error: 'bad_reference' }, 400);

  const db = serviceClient();
  const { data: pay } = await db.from('payments').select('user_id').eq('reference', reference).maybeSingle();
  if (!pay) return json(req, { ok: false, error: 'unknown_reference' }, 404);
  if (pay.user_id !== u.user.id) return json(req, { ok: false, error: 'not_yours' }, 403);

  try {
    const r = await verifyAndCredit(db, reference);
    const { status, ...out } = r;
    return json(req, out, status ?? (r.ok ? 200 : 400));
  } catch (_e) {
    return json(req, { ok: false, error: 'server_error' }, 500);
  }
});
