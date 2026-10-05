// Desktop keyboard shortcuts for the game screen (R4). See docs/HUD_HOME.md.
import { useEffect, useRef } from 'react';

export interface ShortcutHandlers {
  map: () => void;
  home: () => void;
  buy: () => void;
  phone: () => void;
  sheet: () => void;
  things: () => void;
  people: () => void;
  help: () => void;
}

export const SHORTCUTS: [string, string][] = [
  ['M', 'Open the map'],
  ['H', 'Home (or head home from anywhere)'],
  ['B', 'Buy mode (at home)'],
  ['P', 'Phone'],
  ['S', "Your Sim's needs and skills"],
  ['T', 'Things to do here'],
  ['E', 'People here'],
  ['Esc', 'Close / go back'],
  ['?', 'Show these shortcuts'],
];

/** Single-key shortcuts. Ignored while typing, with modifier keys, or when a non-game dialog is open. */
export function useGameShortcuts(h: ShortcutHandlers) {
  const ref = useRef(h);
  useEffect(() => {
    ref.current = h;
  });
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      const map: Record<string, keyof ShortcutHandlers> = { m: 'map', h: 'home', b: 'buy', p: 'phone', s: 'sheet', t: 'things', e: 'people', '?': 'help' };
      const act = map[k];
      if (!act) return;
      e.preventDefault();
      ref.current[act]();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}
