// L1: send client crashes and unhandled errors to the owner (Admin -> Errors). The server function
// client_error_log is size-capped and rate-limited and stores only the user id (from the session),
// the message, a short stack, the page path (no query string), the build id and the browser.
// Fire-and-forget: reporting never throws and never shows anything to the player.
import { supabase, supabaseConfigured } from './supabase';

type Kind = 'error' | 'rejection' | 'boundary' | 'chunk';

const MAX_PER_SESSION = 20;
const REPEAT_MS = 60_000;
const NOISE = [
  /ResizeObserver loop/i,
  /^Script error\.?$/i, // cross-origin script, no details
  /AbortError|The user aborted a request|signal is aborted/i,
  /Load failed$|NetworkError when attempting to fetch|Failed to fetch$/i, // flaky mobile data, not a bug
];

let sent = 0;
// dev builds only report when localStorage 'bl.debug.errors' = '1' (to test Admin -> Errors locally)
function devReporting() {
  try {
    return localStorage.getItem('bl.debug.errors') === '1';
  } catch {
    return false;
  }
}
const lastSeen = new Map<string, number>();

function text(v: unknown): { message: string; stack?: string } {
  if (v instanceof Error) return { message: `${v.name && v.name !== 'Error' ? v.name + ': ' : ''}${v.message}`, stack: v.stack };
  if (typeof v === 'string') return { message: v };
  try {
    return { message: JSON.stringify(v).slice(0, 500) };
  } catch {
    return { message: String(v) };
  }
}

export function reportError(kind: Kind, err: unknown, extraStack?: string) {
  try {
    if (!supabaseConfigured || (import.meta.env.DEV && !devReporting())) return;
    const { message, stack } = text(err);
    const msg = message.trim().slice(0, 500);
    if (!msg || NOISE.some((re) => re.test(msg))) return;
    const now = Date.now();
    if ((lastSeen.get(msg) ?? 0) > now - REPEAT_MS) return;
    lastSeen.set(msg, now);
    if (sent >= MAX_PER_SESSION) return;
    sent += 1;
    const fullStack = [stack, extraStack].filter(Boolean).join('\n--- component stack ---\n').slice(0, 4000);
    void supabase
      .rpc('client_error_log', {
        p_kind: kind,
        p_message: msg,
        p_stack: fullStack || null,
        p_url: location.pathname,
        p_build: (import.meta.env.VITE_BUILD_ID as string | undefined) ?? null,
        p_ua: navigator.userAgent.slice(0, 200),
      })
      .then(() => undefined, () => undefined);
  } catch {
    /* never let reporting break the game */
  }
}

/** Global listeners: window.onerror and unhandled promise rejections. Call once at startup. */
export function initErrorReporting() {
  window.addEventListener('error', (e) => {
    // resource load errors (img/script) have no error object; ignore them
    if (!e.error && !e.message) return;
    reportError('error', e.error ?? e.message);
  });
  window.addEventListener('unhandledrejection', (e) => reportError('rejection', e.reason));
}
