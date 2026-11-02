// Light / Dark theme (docs/THEME.md). The choice lives in prefs ("light" | "dark" | "system"); the resolved
// theme is written to <html data-theme="light|dark"> and the browser bar colour to <meta name="theme-color">.
// index.html runs the same resolution in an inline script before first paint, so a reload never flashes the
// wrong theme. All colour tokens live in src/styles/tokens.css and are re-pointed under [data-theme='dark'].
import { usePrefs, type ThemeChoice } from './prefs';

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

function paintBar(theme: ResolvedTheme) {
  const night = document.documentElement.dataset.daypart === 'night';
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', BAR[theme][night ? 'night' : 'day']);
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

/** Call once at startup: follows the prefs choice and, for "Match my phone", the OS setting live. */
export function initTheme() {
  applyTheme(usePrefs.getState().theme, false);
  let last = usePrefs.getState().theme;
  usePrefs.subscribe((s) => {
    if (s.theme !== last) {
      last = s.theme;
      applyTheme(s.theme, true);
    }
  });
  mq()?.addEventListener?.('change', () => {
    const c = usePrefs.getState().theme;
    if (c === 'system') applyTheme(c, true);
  });
}
