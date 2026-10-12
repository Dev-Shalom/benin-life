// Shared Paystack helpers for the paystack-verify and paystack-webhook Edge Functions (docs/PAYMENTS.md).
// The secret key lives only in the Supabase secret PAYSTACK_SECRET_KEY; it never reaches the client or the repo.
// Only bl_payment_credit (service role) credits naira: once per reference, only for the exact amount.
// H3: references starting BLAD- are billboard ads (purpose 'billboard_ad'): bl_billboard_paid moves the ad to
// 'pending_review', again only for the exact stored price and only once (docs/BILLBOARDS.md).
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { flushQuietly } from './notify.ts';

/** Top-up references (payments table) and billboard ad references (billboard_ads table). */
export const TOPUP_REF = /^BL-[a-f0-9]{32}$/;
export const AD_REF = /^BLAD-[a-f0-9]{32}$/;

const ALLOWED_ORIGINS = [
  'https://playbeninlife.app',
  'https://www.playbeninlife.app',
  'https://benin-life.vercel.app',
  'http://localhost:5173',
  'http://localhost:4173',
  'http://127.0.0.1:5173',
];

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  // Vercel preview deployments of this project too (benin-life-*.vercel.app)
  const ok = ALLOWED_ORIGINS.includes(origin) || /^https:\/\/benin-life[a-z0-9-]*\.vercel\.app$/.test(origin)
    || /^http:\/\/localhost:\d+$/.test(origin);
  return {
    'Access-Control-Allow-Origin': ok ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

export function json(req: Request | null, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...(req ? corsHeaders(req) : {}) },
  });
}

export function env(name: string): string {
  return (Deno.env.get(name) ?? '').trim();
}

export function serviceClient(): SupabaseClient {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export interface CreditResult {
  ok: boolean;
  credited?: boolean;
  already?: boolean;
  bank?: number;
  game_naira?: number;
  user_id?: string;
  error?: string;
  status?: number;
}

/**
 * Ask Paystack about `reference`, check success + NGN + the exact amount we stored, then credit through
 * bl_payment_credit (idempotent). Safe to call any number of times, from the verify call and the webhook.
 */
export async function verifyAndCredit(db: SupabaseClient, reference: string): Promise<CreditResult> {
  if (AD_REF.test(reference)) return verifyAndMarkAd(db, reference);
  const secret = env('PAYSTACK_SECRET_KEY');
  if (!secret) return { ok: false, error: 'not_configured', status: 503 };

  const { data: pay, error: payErr } = await db.from('payments')
    .select('reference, amount_kobo, status, user_id').eq('reference', reference).maybeSingle();
  if (payErr) return { ok: false, error: 'db_error', status: 500 };
  if (!pay) return { ok: false, error: 'unknown_reference', status: 404 };
  if (pay.status === 'success') {
    const { data: prof } = await db.from('profiles').select('bank').eq('id', pay.user_id).maybeSingle();
    return { ok: true, credited: false, already: true, bank: prof?.bank ?? undefined, user_id: pay.user_id };
  }
  if (pay.status !== 'pending') return { ok: false, error: 'not_pending', status: 409 };

  const res = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  if (!res.ok) return { ok: false, error: res.status === 404 ? 'not_paid' : 'paystack_error', status: 502 };
  const body = await res.json().catch(() => null) as { status?: boolean; data?: Record<string, unknown> } | null;
  const tx = body?.data;
  if (!body?.status || !tx) return { ok: false, error: 'paystack_error', status: 502 };
  if (tx.status !== 'success') return { ok: false, error: 'not_paid', status: 402 };
  if (String(tx.currency ?? '').toUpperCase() !== 'NGN') return { ok: false, error: 'bad_currency', status: 400 };
  if (String(tx.reference ?? '') !== reference) return { ok: false, error: 'bad_reference', status: 400 };

  // keep only what admins need to see (no card data beyond what Paystack already masks)
  const raw = {
    id: tx.id, status: tx.status, reference: tx.reference, amount: tx.amount, currency: tx.currency,
    channel: tx.channel, paid_at: tx.paid_at, gateway_response: tx.gateway_response,
    customer_email: (tx.customer as Record<string, unknown> | undefined)?.email ?? null,
  };
  const { data, error } = await db.rpc('bl_payment_credit', {
    p_reference: reference, p_amount_kobo: Number(tx.amount), p_raw: { data: raw },
  });
  if (error) return { ok: false, error: 'credit_failed', status: 500 };
  const out = data as CreditResult;
  return { ...out, status: out.ok ? 200 : 409 };
}

interface PaystackTx { [k: string]: unknown }

/** GET /transaction/verify/:reference and the checks every purpose shares (success, NGN, same reference). */
async function paystackVerify(reference: string): Promise<{ tx: PaystackTx } | { error: string; status: number }> {
  const secret = env('PAYSTACK_SECRET_KEY');
  if (!secret) return { error: 'not_configured', status: 503 };
  const res = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  if (!res.ok) return { error: res.status === 404 ? 'not_paid' : 'paystack_error', status: 502 };
  const body = await res.json().catch(() => null) as { status?: boolean; data?: PaystackTx } | null;
  const tx = body?.data;
  if (!body?.status || !tx) return { error: 'paystack_error', status: 502 };
  if (tx.status !== 'success') return { error: 'not_paid', status: 402 };
  if (String(tx.currency ?? '').toUpperCase() !== 'NGN') return { error: 'bad_currency', status: 400 };
  if (String(tx.reference ?? '') !== reference) return { error: 'bad_reference', status: 400 };
  return { tx };
}

export interface AdPayResult {
  ok: boolean;
  marked?: boolean;
  already?: boolean;
  ad_id?: string;
  status?: string | number;
  error?: string;
  user_id?: string;
}

/**
 * Billboard ad payment: Paystack must say success for this reference; bl_billboard_paid then checks the paid
 * amount equals the stored price (else: rejected + refund due) and moves the ad to pending_review once.
 * Admins get a push (outbox) when it lands.
 */
export async function verifyAndMarkAd(db: SupabaseClient, reference: string): Promise<CreditResult & AdPayResult> {
  const { data: ad, error: adErr } = await db.from('billboard_ads')
    .select('id, status, paid_at, user_id, price_kobo').eq('reference', reference).maybeSingle();
  if (adErr) return { ok: false, error: 'db_error', status: 500 };
  if (!ad) return { ok: false, error: 'unknown_reference', status: 404 };
  if (ad.paid_at) return { ok: true, already: true, credited: false, marked: false, ad_id: ad.id, user_id: ad.user_id, status: 200 };
  if (ad.status !== 'awaiting_payment' && ad.status !== 'cancelled') return { ok: false, error: 'not_awaiting', status: 409 };

  const v = await paystackVerify(reference);
  if ('error' in v) return { ok: false, error: v.error, status: v.status };
  const tx = v.tx;
  const meta = (tx.metadata ?? {}) as Record<string, unknown>;
  if (meta.ad_id && String(meta.ad_id) !== ad.id) return { ok: false, error: 'bad_metadata', status: 400 };
  const raw = {
    id: tx.id, status: tx.status, reference: tx.reference, amount: tx.amount, currency: tx.currency,
    channel: tx.channel, paid_at: tx.paid_at, gateway_response: tx.gateway_response, purpose: meta.purpose ?? null,
    customer_email: (tx.customer as Record<string, unknown> | undefined)?.email ?? null,
  };
  const { data, error } = await db.rpc('bl_billboard_paid', { p_reference: reference, p_amount_kobo: Number(tx.amount), p_raw: { data: raw } });
  if (error) return { ok: false, error: 'mark_failed', status: 500 };
  const out = data as AdPayResult;
  await flushQuietly(db);
  return { ...out, credited: false, status: out.ok ? 200 : 409 };
}

/** Hex HMAC-SHA512 of the raw body with the secret key, compared in constant time. */
export async function validSignature(rawBody: string, signature: string | null): Promise<boolean> {
  const secret = env('PAYSTACK_SECRET_KEY');
  if (!secret || !signature) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)));
  const hex = Array.from(mac, (b) => b.toString(16).padStart(2, '0')).join('');
  const sig = signature.trim().toLowerCase();
  if (sig.length !== hex.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0;
}
