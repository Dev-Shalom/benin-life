// POST { reference } with the player's JWT, after Paystack Inline reports success.
// Checks the caller owns the payment, verifies it with Paystack (secret key) and credits once.
// Returns { ok, credited, already, bank } or { ok:false, error }.
// Companies: BLRB- references are real-business map listings (first payment or renewal), same flow ({ ok, marked, already, ad_id }).
// H3: BLAD- references are billboard ads: same checks, then the ad moves to pending_review ({ ok, marked, already, ad_id }).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { AD_REF, RB_REF, corsHeaders, env, json, serviceClient, TOPUP_REF, verifyAndCredit } from '../_shared/paystack.ts';

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
  const isAd = AD_REF.test(reference);
  const isRb = RB_REF.test(reference);
  if (!isAd && !isRb && !TOPUP_REF.test(reference)) return json(req, { ok: false, error: 'bad_reference' }, 400);

  const db = serviceClient();
  let owner: string | null = null;
  if (isRb) {
    // real-business listing: the first payment (reference) or a renewal (renew_reference), or a renewal already applied (renewed_refs)
    const { data: rb } = await db.from('real_businesses').select('owner_id')
      .or(`reference.eq.${reference},renew_reference.eq.${reference},renewed_refs.cs.{${reference}}`).maybeSingle();
    owner = rb?.owner_id ?? null;
    if (!rb) return json(req, { ok: false, error: 'unknown_reference' }, 404);
  } else {
    const { data: pay } = await db.from(isAd ? 'billboard_ads' : 'payments').select('user_id').eq('reference', reference).maybeSingle();
    if (!pay) return json(req, { ok: false, error: 'unknown_reference' }, 404);
    owner = pay.user_id;
  }
  if (owner !== u.user.id) return json(req, { ok: false, error: 'not_yours' }, 403);

  try {
    const r = await verifyAndCredit(db, reference);
    const { status, ...out } = r;
    return json(req, out, status ?? (r.ok ? 200 : 400));
  } catch (_e) {
    return json(req, { ok: false, error: 'server_error' }, 500);
  }
});
