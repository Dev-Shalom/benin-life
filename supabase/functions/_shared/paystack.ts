// Shared Paystack helpers for the paystack-verify and paystack-webhook Edge Functions (docs/PAYMENTS.md).
// The secret key lives only in the Supabase secret PAYSTACK_SECRET_KEY; it never reaches the client or the repo.
// Only bl_payment_credit (service role) credits naira: once per reference, only for the exact amount.
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const ALLOWED_ORIGINS = [
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
