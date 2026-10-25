// H3 billboard refunds (docs/BILLBOARDS.md). Companies: POST { biz_id } refunds a real-business listing the same way
// (admin_real_biz_refund_start / bl_real_biz_refund_claim / bl_real_biz_refund_result). POST { ad_id } with an ADMIN's JWT, after the admin rejected an ad
// (admin_billboard_reject) or removed it with "refund" ticked, or to retry a failed refund.
//  1. admin_billboard_refund_start with the caller's JWT: the database checks admin + that a refund is due, and audits.
//  2. bl_billboard_refund_claim (service role): pending/refund_failed -> processing (two clicks can't refund twice).
//  3. POST https://api.paystack.co/refund { transaction: <reference>, amount } with PAYSTACK_SECRET_KEY.
//  4. bl_billboard_refund_result: refunded, or refund_failed (+ admin notification) with Paystack's message.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { flushQuietly } from '../_shared/notify.ts';
import { corsHeaders, env, json, serviceClient } from '../_shared/paystack.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(req, { ok: false, error: 'auth' }, 401);
  let adId = '';
  let bizId = '';
  try { const b = await req.json(); adId = String(b?.ad_id ?? ''); bizId = String(b?.biz_id ?? ''); } catch { /* fall through */ }
  const isBiz = bizId !== '';
  if (isBiz ? !UUID.test(bizId) : !UUID.test(adId)) return json(req, { ok: false, error: isBiz ? 'bad_biz' : 'bad_ad' }, 400);

  const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: startErr } = isBiz
    ? await userClient.rpc('admin_real_biz_refund_start', { p_id: bizId })
    : await userClient.rpc('admin_billboard_refund_start', { p_ad: adId });
  if (startErr) return json(req, { ok: false, error: startErr.hint || 'refused', message: startErr.message }, 403);

  const secret = env('PAYSTACK_SECRET_KEY');
  if (!secret) return json(req, { ok: false, error: 'not_configured', message: 'PAYSTACK_SECRET_KEY is not set.' }, 503);
  const db = serviceClient();
  const { data: claim, error: claimErr } = isBiz
    ? await db.rpc('bl_real_biz_refund_claim', { p_biz: bizId })
    : await db.rpc('bl_billboard_refund_claim', { p_ad: adId });
  if (claimErr || !claim?.ok) return json(req, { ok: false, error: claim?.error ?? 'claim_failed' }, 409);

  let ok = false;
  let message = '';
  let raw: Record<string, unknown> = {};
  try {
    const res = await fetch('https://api.paystack.co/refund', {
      method: 'POST',
      headers: { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ transaction: claim.reference, amount: Number(claim.amount_kobo) }),
    });
    const body = await res.json().catch(() => null) as { status?: boolean; message?: string; data?: Record<string, unknown> } | null;
    ok = res.ok && body?.status === true;
    message = body?.message ?? `HTTP ${res.status}`;
    const d = body?.data ?? {};
    raw = { http: res.status, message, id: d.id ?? null, status: d.status ?? null, amount: d.amount ?? null,
            currency: d.currency ?? null, expected_at: d.expected_at ?? null };
  } catch (e) {
    message = e instanceof Error ? e.message : 'network error';
    raw = { error: message };
  }
  if (isBiz) await db.rpc('bl_real_biz_refund_result', { p_biz: bizId, p_ok: ok, p_error: ok ? null : message, p_raw: raw });
  else await db.rpc('bl_billboard_refund_result', { p_ad: adId, p_ok: ok, p_error: ok ? null : message, p_raw: raw });
  await flushQuietly(db);
  return json(req, ok ? { ok: true, refund_status: 'refunded', message } : { ok: false, refund_status: 'refund_failed', error: 'paystack', message }, ok ? 200 : 502);
});
