// Growth measurement (docs/GROWTH.md).
// * Channel links: playbeninlife.app/?src=tiktok. The first visit's channel is kept in localStorage until the Sim exists,
//   then saved once (growth_source_set). Player invite links use ?ref=CODE (src/lib/referral.ts): different parameter, no collision.
// * "How did you hear about Benin Life?": one optional tap in the creator, saved with the channel.
// * Phone app opens: counted on the server at most once per player per app per day; this file also skips the call
//   when this device already sent it today.
import { rpc } from './api';

const KEY = 'bl.src';
const DONE = 'bl.src.saved';
const RE = /^[a-z0-9_]{2,24}$/;

export const HEARD_OPTIONS: { id: string; label: string }[] = [
  { id: 'tiktok', label: 'TikTok' },
  { id: 'whatsapp', label: 'WhatsApp' },
  { id: 'friend', label: 'A friend' },
  { id: 'campus', label: 'Campus' },
  { id: 'instagram', label: 'Instagram' },
  { id: 'x', label: 'X' },
  { id: 'google', label: 'Google' },
  { id: 'other', label: 'Other' },
];

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}
function write(key: string, v: string) {
  try {
    window.localStorage.setItem(key, v);
  } catch {
    /* blocked storage: the channel is simply not measured */
  }
}

/** Read ?src= from the address and remember the FIRST one. Call once at start-up. */
export function captureChannel(): void {
  try {
    const v = new URLSearchParams(window.location.search).get('src')?.trim().toLowerCase();
    if (v && RE.test(v) && !read(KEY) && !read(DONE)) write(KEY, v);
  } catch {
    /* ignore */
  }
}

export function storedChannel(): string | null {
  const v = read(KEY);
  return v && RE.test(v) ? v : null;
}

/** Save the channel link and/or the "how did you hear" answer. Any server answer ends it; no_profile and network errors retry later. */
export async function saveSource(heard: string | null): Promise<void> {
  const channel = storedChannel();
  if (!heard && !channel) return;
  try {
    await rpc('growth_source_set', { p_heard: heard, p_channel: channel });
    write(DONE, '1');
    try {
      window.localStorage.removeItem(KEY);
    } catch {
      /* nothing to clear */
    }
  } catch {
    /* keep the stored channel; the next game start tries again */
  }
}

/** Game start: if a channel is still waiting (the creator call failed or was skipped), save it now. */
export function flushChannel(): void {
  if (storedChannel()) void saveSource(null);
}

const sent = new Set<string>();
function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Count one phone-app open (once per app per device per day; the server dedupes per player too). */
export function trackAppOpen(app: string): void {
  const id = String(app || '').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 30);
  if (!id) return;
  const k = `${today()}:${id}`;
  if (sent.has(k)) return;
  sent.add(k);
  try {
    const store = `bl.apps.${today()}`;
    const have = (window.localStorage.getItem(store) ?? '').split(',');
    if (have.includes(id)) return;
    window.localStorage.setItem(store, [...have.filter(Boolean), id].join(','));
  } catch {
    /* storage blocked: the in-memory set still limits calls this session */
  }
  void rpc('growth_app_open', { p_app: id }).catch(() => undefined);
}
