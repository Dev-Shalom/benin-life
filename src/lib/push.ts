// H3 admin Web Push (docs/BILLBOARDS.md): the owner's phone gets a notification when an ad is paid and needs
// approval, goes live, is reported, ends, or a refund fails. public/sw.js shows it; the admin-push Edge Function
// sends it (VAPID private key = Supabase secret). The public key below is public by design.
import { playChime } from './sound';
import { rpc } from './api';
import { supabase } from './supabase';

export const VAPID_PUBLIC_KEY = String(import.meta.env.VITE_VAPID_PUBLIC_KEY
  || 'BLdPAJnlb5_3P_wOrtqveyTRo4flZj3qRxN13ga9KNSUNn4rAVMR5EpxANvF--aYhgIedHRrfYSd7EvfU02qssc').trim();

export type PushSupport = 'ok' | 'unsupported' | 'ios_install' | 'denied';

const isIos = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const standalone = () => matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true;
/** iPhone / iPad in Safari (not the Home Screen app): web push cannot work until the game is added to the Home Screen. */
export const needsIosInstall = () => typeof window !== 'undefined' && isIos() && !standalone();

export function pushSupport(): PushSupport {
  if (typeof window === 'undefined') return 'unsupported';
  const has = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  if (isIos() && !standalone()) return 'ios_install'; // iOS: only from the Home Screen app (16.4+)
  if (!has) return 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  return 'ok';
}

function keyBytes(b64: string): Uint8Array<ArrayBuffer> {
  const s = b64.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((b64.length + 3) % 4);
  const raw = atob(s);
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

async function registration(): Promise<ServiceWorkerRegistration> {
  // Always wait for an ACTIVE worker: subscribing while it is still installing fails on Android.
  const existing = await navigator.serviceWorker.getRegistration('/');
  if (!existing) await navigator.serviceWorker.register('/sw.js', { scope: '/' });
  return navigator.serviceWorker.ready;
}

/** This device's subscription (if any). */
export async function currentSubscription(): Promise<PushSubscription | null> {
  if (pushSupport() !== 'ok') return null;
  const reg = await navigator.serviceWorker.getRegistration('/');
  return reg ? reg.pushManager.getSubscription() : null;
}

/** Ask permission and subscribe this browser (shared by the admin "Notify me" and the players' Settings switch). */
async function subscribeDevice(): Promise<{ endpoint?: string; keys?: { p256dh?: string; auth?: string } }> {
  const s = pushSupport();
  if (s === 'ios_install') throw new Error('On iPhone, add Benin Life to your Home Screen first (Share → Add to Home Screen), open it from there, then tap Notify me.');
  if (s === 'unsupported') throw new Error('This browser cannot show notifications. The red badge and sound on this page still work.');
  if (s === 'denied') throw new Error('Notifications are blocked for this site. Allow them in your browser settings, then try again.');
  const perm = await Notification.requestPermission();
  if (perm !== 'granted') throw new Error('Notifications were not allowed.');
  const reg = await registration();
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    // Chrome on Android sometimes answers "push service error" on the first try (Google's push
    // service not ready yet). Clear any stale subscription and retry a couple of times.
    let lastErr: unknown = null;
    for (let i = 0; i < 3 && !sub; i++) {
      try {
        sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(VAPID_PUBLIC_KEY) });
      } catch (e) {
        lastErr = e;
        await (await reg.pushManager.getSubscription())?.unsubscribe().catch(() => false);
        await new Promise((r) => setTimeout(r, 1500 * (i + 1)));
      }
    }
    if (!sub) {
      const msg = lastErr instanceof Error ? lastErr.message : String(lastErr);
      throw new Error(/push service/i.test(msg)
        ? 'Your phone\'s push service did not answer. Use Chrome, turn off any VPN or Data Saver, make sure Google Play Services is up to date, then tap Notify me again.'
        : msg);
    }
  }
  return sub.toJSON() as { endpoint?: string; keys?: { p256dh?: string; auth?: string } };
}

/** Ask permission, subscribe and save it on the server (admins only). */
export async function enablePush(): Promise<string> {
  const j = await subscribeDevice();
  const r = await rpc<{ message: string }>('admin_push_subscribe', {
    p_endpoint: j.endpoint, p_p256dh: j.keys?.p256dh, p_auth: j.keys?.auth, p_user_agent: navigator.userAgent.slice(0, 200),
  });
  return r.message;
}

// ---- P1: push for every player (docs/NOTIFICATIONS.md) ----
export type PushCategory = 'messages' | 'money' | 'friends' | 'events' | 'admin';
export interface PushPrefs {
  master: boolean; messages: boolean; money: boolean; friends: boolean; events: boolean; admin: boolean;
  /** Devices this player has saved. */
  devices: number;
  /** Admin's global switches: a category that is off here is off for everyone. */
  global: { enabled: boolean } & Record<PushCategory, boolean>;
}

export const pushState = () => rpc<PushPrefs>('push_state');
export const setPushPrefs = (p: Partial<Record<'master' | PushCategory, boolean>>) => rpc<PushPrefs>('push_prefs_set', { p_prefs: p });

/** Turn notifications on for this player: browser permission, save this device, master switch on. */
export async function enablePlayerPush(): Promise<PushPrefs> {
  const j = await subscribeDevice();
  await rpc<PushPrefs>('push_subscribe', {
    p_endpoint: j.endpoint, p_p256dh: j.keys?.p256dh, p_auth: j.keys?.auth, p_user_agent: navigator.userAgent.slice(0, 200),
  });
  return setPushPrefs({ master: true });
}

/** Master switch off: the server sends this player nothing. The device stays saved so turning it back on is instant. */
export const disablePlayerPush = () => setPushPrefs({ master: false });

export async function disablePush(): Promise<string> {
  const sub = await currentSubscription();
  if (!sub) return 'Notifications are off for this device.';
  const endpoint = sub.endpoint;
  await sub.unsubscribe().catch(() => false);
  const r = await rpc<{ message: string }>('admin_push_unsubscribe', { p_endpoint: endpoint });
  return r.message;
}

/** Send a test notification to this admin's devices. */
export async function testPush(): Promise<{ configured: boolean; sent: number; failed: number }> {
  const { data, error } = await supabase.functions.invoke('admin-push', { body: { test: true } });
  if (error) throw new Error('The notification service did not answer. Is the admin-push function deployed?');
  return data as { configured: boolean; sent: number; failed: number };
}

/** Push anything queued (cheap; the server sends only rows the database created). */
export function flushAdminPush() {
  void supabase.functions.invoke('admin-push', { body: {} }).catch(() => {});
}

/** A short two-tone chime for the in-page fallback (plays on the game's one shared AudioContext). */
export function chime() {
  playChime();
}
