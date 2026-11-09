// Cron credential check for Edge Functions that a scheduler calls (player-push). The Supabase anon key is public, so it is never
// treated as a cron credential. A scheduler proves itself with the header x-cron-secret, which must equal the Supabase secret
// CRON_SECRET. If CRON_SECRET is not set (or empty) nobody is a cron caller. See docs/SECURITY.md.

/** Constant-time comparison: both sides are hashed first so the length does not leak, then every byte is compared. */
export async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** True only when `secret` (the CRON_SECRET env value) is set and non-empty and `header` (x-cron-secret) matches it. */
export async function cronSecretOk(header: string | null | undefined, secret: string | null | undefined): Promise<boolean> {
  const s = (secret ?? '').trim();
  const h = (header ?? '').trim();
  if (!s || !h) return false;
  return await constantTimeEqual(h, s);
}
