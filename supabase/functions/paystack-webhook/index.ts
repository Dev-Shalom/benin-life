// Paystack webhook (backup path): verifies x-paystack-signature (HMAC-SHA512 of the raw body with the secret
// key), and on charge.success verifies + credits the same way as paystack-verify (idempotent).
// Deployed with verify_jwt = false (supabase/config.toml): Paystack sends no Supabase JWT.
import { serviceClient, validSignature, verifyAndCredit } from '../_shared/paystack.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('ok', { status: 200 });
  const raw = await req.text();
  if (!(await validSignature(raw, req.headers.get('x-paystack-signature')))) {
    return new Response('bad signature', { status: 401 });
  }
  let evt: { event?: string; data?: { reference?: string } } | null = null;
  try { evt = JSON.parse(raw); } catch { return new Response('ok', { status: 200 }); }
  const reference = String(evt?.data?.reference ?? '');
  if (evt?.event === 'charge.success' && reference.startsWith('BL-')) {
    // answer Paystack fast; finish the credit in the background
    const work = verifyAndCredit(serviceClient(), reference).catch(() => null);
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime;
    if (rt?.waitUntil) rt.waitUntil(work);
    else await work;
  }
  return new Response('ok', { status: 200 });
});
