// Free roam: a small bottom sheet that lists places with a search box. Two jobs: pick a GPS destination anywhere in the city, and pick where
// a hailed keke should take you. Tokens only; nothing covers the middle of the street while it is closed.
import { useEffect, useMemo, useRef, useState } from 'react';
import { Icon } from '../../ui/Icon';

export interface SheetItem {
  id: string;
  label: string;
  sub: string;
  /** Distance from the player in metres (for sorting and the small print). */
  dist: number;
  disabled?: boolean;
}

interface Props {
  title: string;
  hint?: string;
  items: SheetItem[];
  onPick: (id: string) => void;
  onClose: () => void;
  busy?: boolean;
}

export function MagnifierIcon({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
      <circle cx="11" cy="11" r="6.5" />
      <path d="m16 16 4.5 4.5" />
    </svg>
  );
}

const fmt = (m: number) => (m < 1000 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(1)} km`);

export function RoamSheet({ title, hint, items, onPick, onClose, busy }: Props) {
  const [q, setQ] = useState('');
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const t = window.setTimeout(() => input.current?.focus({ preventScroll: true }), 120);
    return () => window.clearTimeout(t);
  }, []);
  const list = useMemo(() => {
    const s = q.trim().toLowerCase();
    const f = s ? items.filter((i) => i.label.toLowerCase().includes(s) || i.sub.toLowerCase().includes(s)) : items;
    return [...f].sort((a, b) => a.dist - b.dist);
  }, [items, q]);
  return (
    <div className="roam-sheet" role="dialog" aria-label={title} data-testid="roam-sheet">
      <button type="button" className="roam-sheet__scrim" aria-label="Close" onClick={onClose} />
      <div className="roam-sheet__card">
        <div className="roam-sheet__head">
          <b>{title}</b>
          <button type="button" className="roam-btn roam-btn--round" onClick={onClose} aria-label="Close" style={{ width: 34, height: 34, minWidth: 34 }}>
            <Icon name="close" size={16} />
          </button>
        </div>
        <label className="roam-sheet__search">
          <MagnifierIcon size={16} />
          <input ref={input} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search the whole city" autoComplete="off" enterKeyHint="search" aria-label="Search places" />
        </label>
        {hint && <p className="roam-sheet__hint">{hint}</p>}
        <ul className="roam-sheet__list">
          {list.map((it) => (
            <li key={it.id}>
              <button type="button" className={`roam-sheet__row${it.disabled ? ' is-off' : ''}`} disabled={busy} onClick={() => onPick(it.id)}>
                <span className="roam-sheet__name">{it.label}</span>
                <span className="roam-sheet__sub">{it.sub}</span>
                <span className="roam-sheet__dist">{fmt(it.dist)}</span>
              </button>
            </li>
          ))}
          {list.length === 0 && <li className="roam-sheet__none">No place with that name.</li>}
        </ul>
      </div>
    </div>
  );
}
