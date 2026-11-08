// Sun / moon pill in the marketing nav. Flips Light <-> Dark with a circular reveal from the button.
// The choice is the game's own preference (src/lib/prefs.ts), so it carries into the game. docs/FRONTEND.md.
import { useEffect, useRef, useState } from 'react';
import { setThemeAnimated, type ResolvedTheme } from '../../lib/theme';
import { Ph } from './Ph';

const read = (): ResolvedTheme => (document.documentElement.dataset.theme === 'light' ? 'light' : 'dark');

export function ThemeToggle() {
  const [theme, setTheme] = useState<ResolvedTheme>(read);
  const ref = useRef<HTMLButtonElement>(null);

  // data-theme is the source of truth (the inline script, the game settings and this button all write it).
  useEffect(() => {
    setTheme(read());
    const mo = new MutationObserver(() => setTheme(read()));
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return () => mo.disconnect();
  }, []);

  const label = theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme';
  return (
    <button
      ref={ref}
      type="button"
      className="mk-theme is-ready"
      aria-label={label}
      title={label}
      onClick={() => setThemeAnimated(theme === 'dark' ? 'light' : 'dark', ref.current)}
    >
      <span className="mk-theme__thumb" aria-hidden="true" />
      <Ph name="sun" className="mk-theme__sun" />
      <Ph name="moon" className="mk-theme__moon" />
    </button>
  );
}
