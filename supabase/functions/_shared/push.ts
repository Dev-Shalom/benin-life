// Web Push for the owner's phone (H3, docs/BILLBOARDS.md): VAPID (RFC 8292) + aes128gcm payload encryption
// (RFC 8291 / RFC 8188) with WebCrypto only, so it runs on Supabase Edge (Deno) without npm packages.
// Secrets: VAPID_PRIVATE_KEY (base64url, 32 bytes) and VAPID_SUBJECT ("mailto:you@example.com") are Supabase
// function secrets. The public key is public by design (also baked into the client, src/lib/push.ts).

/** Default public key (matches the private key given to the owner). Override with the VAPID_PUBLIC_KEY secret. */
export const DEFAULT_VAPID_PUBLIC_KEY =
  'BLdPAJnlb5_3P_wOrtqveyTRo4flZj3qRxN13ga9KNSUNn4rAVMR5EpxANvF--aYhgIedHRrfYSd7EvfU02qssc';

export interface PushSub { endpoint: string; p256dh: string; auth: string }
export interface PushMessage { title: string; body: string; url?: string; tag?: string; kind?: string }
export interface PushKeys { publicKey: string; privateKey: string; subject: string }

const enc = new TextEncoder();

export function b64uDecode(s: string): Uint8Array {
  const b = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  const bin = atob(b);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64uEncode(bytes: Uint8Array | ArrayBuffer): string {
  const u = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = '';
  for (let i = 0; i < u.length; i++) bin += String.fromCharCode(u[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, bytes: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, bytes * 8));
}

/** VAPID private key (raw d) + public key (uncompressed point) -> a signing CryptoKey. */
function vapidSigningKey(publicKey: string, privateKey: string): Promise<CryptoKey> {
  const pub = b64uDecode(publicKey);
  if (pub.length !== 65 || pub[0] !== 4) throw new Error('VAPID public key must be an uncompressed P-256 point');
  const jwk: JsonWebKey = {
    kty: 'EC', crv: 'P-256', ext: true,
    x: b64uEncode(pub.slice(1, 33)), y: b64uEncode(pub.slice(33, 65)), d: privateKey.trim(),
  };
  return crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

/** "vapid t=<jwt>, k=<public key>" for one push service origin. */
export async function vapidAuthorization(endpoint: string, keys: PushKeys, now = Date.now()): Promise<string> {
  const aud = new URL(endpoint).origin;
  const header = b64uEncode(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64uEncode(enc.encode(JSON.stringify({ aud, exp: Math.floor(now / 1000) + 12 * 3600, sub: keys.subject })));
  const unsigned = `${header}.${claims}`;
  const key = await vapidSigningKey(keys.publicKey, keys.privateKey);
  // WebCrypto ECDSA returns raw r||s (64 bytes), which is exactly the JOSE ES256 signature format
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(unsigned));
  return `vapid t=${unsigned}.${b64uEncode(sig)}, k=${keys.publicKey}`;
}

/** RFC 8291 aes128gcm body for one subscription (single record, no padding). */
export async function encryptPayload(payload: Uint8Array, sub: Pick<PushSub, 'p256dh' | 'auth'>,
                                     fixed?: { salt: Uint8Array; serverKeys: CryptoKeyPair }): Promise<Uint8Array> {
  const uaPublic = b64uDecode(sub.p256dh);
  const authSecret = b64uDecode(sub.auth);
  if (uaPublic.length !== 65) throw new Error('bad p256dh');
  const server = fixed?.serverKeys ?? await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair;
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', server.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, server.privateKey, 256));
  const keyInfo = concat(enc.encode('WebPush: info\0'), uaPublic, asPublic);
  const ikm = await hkdf(authSecret, ecdhSecret, keyInfo, 32);
  const salt = fixed?.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);
  const aes = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const plain = concat(payload, new Uint8Array([2])); // last (only) record delimiter
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aes, plain));
  const rs = new Uint8Array([0, 0, 0x10, 0]); // record size 4096
  return concat(salt, rs, new Uint8Array([asPublic.length]), asPublic, cipher);
}

export type SendResult = { ok: true } | { ok: false; status: number; gone: boolean; error: string };

/** Send one notification. `gone` = the subscription is dead (404/410): delete it. */
export async function sendPush(sub: PushSub, msg: PushMessage, keys: PushKeys): Promise<SendResult> {
  try {
    const body = await encryptPayload(enc.encode(JSON.stringify(msg)), sub);
    const res = await fetch(sub.endpoint, {
      method: 'POST',
      headers: {
        Authorization: await vapidAuthorization(sub.endpoint, keys),
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        TTL: '86400',
        Urgency: 'high',
      },
      body,
    });
    if (res.status >= 200 && res.status < 300) return { ok: true };
    const text = (await res.text().catch(() => '')).slice(0, 200);
    return { ok: false, status: res.status, gone: res.status === 404 || res.status === 410, error: text };
  } catch (e) {
    return { ok: false, status: 0, gone: false, error: e instanceof Error ? e.message : String(e) };
  }
}
