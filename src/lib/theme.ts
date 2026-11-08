// Light / Dark theme (docs/THEME.md). The choice lives in prefs ("light" | "dark" | "system"); the resolved
// theme is written to <html data-theme="light|dark"> and the browser bar colour to <meta name="theme-color">.
// index.html runs the same resolution in an inline script before first paint, so a reload never flashes the
// wrong theme. All colour tokens live in src/styles/tokens.css and are re-pointed under [data-theme='dark'].
import { hasStoredTheme, usePrefs, type ThemeChoice } from './prefs';

export type ResolvedTheme = 'light' | 'dark';

/** Browser-bar colours: light = sky, dark = the indigo page. Keep in sync with index.html. */
const BAR: Record<ResolvedTheme, { day: string; night: string }> = {
  light: { day: '#e4f0fa', night: '#1d2542' },
  dark: { day: '#0f1130', night: '#0b0c22' },
};

const mq = (): MediaQueryList | null => {
  try {
    return window.matchMedia('(prefers-color-scheme: dark)');
  } catch {
    return null;
  }
};

export function resolveTheme(choice: ThemeChoice): ResolvedTheme {
  if (choice === 'dark') return 'dark';
  if (choice === 'light') return 'light';
  return mq()?.matches ? 'dark' : 'light';
}

/** Marketing pages (html.mk-page) use the graphite and off-white page colours. */
const MK_BAR: Record<ResolvedTheme, string> = { light: '#f6f5f2', dark: '#0e0f11' };

function paintBar(theme: ResolvedTheme) {
  const root = document.documentElement;
  const night = root.dataset.daypart === 'night';
  const color = root.classList.contains('mk-page') ? MK_BAR[theme] : BAR[theme][night ? 'night' : 'day'];
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', color);
  document.querySelector('meta[name="color-scheme"]')?.setAttribute('content', theme);
}

/** The game sets the time of day (the sky and status bar follow it in the light theme). */
export function setDaypart(night: boolean | null) {
  const root = document.documentElement;
  if (night === null) delete root.dataset.daypart;
  else root.dataset.daypart = night ? 'night' : 'day';
  paintBar((root.dataset.theme as ResolvedTheme) || 'light');
}

let fadeTimer: number | undefined;

/** Apply a theme to <html>. With `animate`, a short-lived class fades colours (~250 ms), never on page load. */
export function applyTheme(choice: ThemeChoice, animate: boolean) {
  const root = document.documentElement;
  const next = resolveTheme(choice);
  if (root.dataset.theme === next) {
    paintBar(next);
    return;
  }
  const reduce = (() => {
    try {
      return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch {
      return false;
    }
  })();
  if (animate && !reduce) {
    root.classList.add('theme-fade');
    window.clearTimeout(fadeTimer);
    fadeTimer = window.setTimeout(() => root.classList.remove('theme-fade'), 320);
  }
  root.dataset.theme = next;
  paintBar(next);
}

/** Follow the phone only when the player chose "Match my phone". Light is the default everywhere. */
export function followsPhone(): boolean {
  const c = usePrefs.getState().theme;
  if (hasStoredTheme()) return c === 'system';
  return false; // light is the default everywhere until the player picks (owner rule)
}

let committing = false;

/**
 * The theme toggle on the marketing pages. Saves the choice in prefs (so the game keeps it) and reveals the
 * new theme in a circle growing from the button (View Transitions API, ~520 ms). Without the API it falls back
 * to the 250 ms colour fade; with prefers-reduced-motion it just switches. Docs: docs/FRONTEND.md.
 */
export function setThemeAnimated(next: ResolvedTheme, origin: Element | null) {
  const root = document.documentElement;
  if (root.dataset.theme === next && hasStoredTheme() && usePrefs.getState().theme === next) return;
  const commit = () => {
    committing = true;
    usePrefs.getState().set({ theme: next });
    committing = false;
    root.dataset.theme = next;
    paintBar(next);
  };
  let reduce = false;
  try {
    reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    /* no matchMedia: animate */
  }
  const doc = document as Document & { startViewTransition?: (cb: () => void) => { ready: Promise<void>; finished: Promise<void> } };
  if (reduce || !origin || typeof doc.startViewTransition !== 'function') {
    if (reduce) commit();
    else {
      usePrefs.getState().set({ theme: next }); // the prefs subscriber runs the colour fade
      paintBar(next);
    }
    return;
  }
  const r = origin.getBoundingClientRect();
  const x = r.left + r.width / 2;
  const y = r.top + r.height / 2;
  const radius = Math.hypot(Math.max(x, window.innerWidth - x), Math.max(y, window.innerHeight - y));
  root.classList.add('mk-vt');
  const vt = doc.startViewTransition(commit);
  const done = () => root.classList.remove('mk-vt');
  vt.ready.then(() => {
    root.animate(
      { clipPath: [`circle(0px at ${x}px ${y}px)`, `circle(${radius}px at ${x}px ${y}px)`] },
      { duration: 520, easing: 'cubic-bezier(0.23, 1, 0.32, 1)', pseudoElement: '::view-transition-new(root)' },
    );
  }, done);
  vt.finished.then(done, done);
}

/** Call once at startup: follows the prefs choice and, for "Match my phone", the OS setting live. */
export function initTheme() {
  // First visit on a marketing page: follow the phone until the visitor picks a theme.
  applyTheme(usePrefs.getState().theme, false);
  let last = usePrefs.getState().theme;
  usePrefs.subscribe((s) => {
    if (s.theme !== last) {
      last = s.theme;
      // The toggle commits inside a View Transition (which sets data-theme itself and animates it).
      if (!committing) applyTheme(s.theme, true);
    }
  });
  mq()?.addEventListener?.('change', () => {
    if (followsPhone()) applyTheme('system', true);
  });
}
