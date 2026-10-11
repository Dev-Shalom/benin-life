// B1 arrange toolbar (inside Buy): D-pad nudges the selected piece one grid step, rotate turns it 90°,
// Store sends it back to the inventory, Done saves it on the server (refused while it is red).
// The D-pad is drawn as a diamond because the camera looks at the room from the south-east: the
// top-left arrow moves a piece toward the left (west) wall, the top-right one toward the back (north) wall.
import { useEffect } from 'react';
import { useArrange } from '../../state/arrange';
import { Icon } from '../../ui';

export interface ArrangeBarProps {
  /** Name of the selected piece (null = nothing selected yet). */
  name: string | null;
  /** Why the piece can't stay where it is (null = fine). */
  issue: string | null;
  busy: boolean;
  onDone: () => void;
  onStore: () => void;
  onCancel: () => void;
  onExit: () => void;
  onOwned: () => void;
}

// [label, dx, dz, arrow rotation (deg, 0 = up)]
const PAD: [string, number, number, number, string][] = [
  ['Move toward the left wall', -1, 0, -45, 'arrange-pad__btn--tl'],
  ['Move toward the back wall', 0, -1, 45, 'arrange-pad__btn--tr'],
  ['Move toward the front', 0, 1, -135, 'arrange-pad__btn--bl'],
  ['Move toward the right', 1, 0, 135, 'arrange-pad__btn--br'],
];

export function ArrangeBar({ name, issue, busy, onDone, onStore, onCancel, onExit, onOwned }: ArrangeBarProps) {
  const nudge = useArrange((s) => s.nudge);
  const rotate = useArrange((s) => s.rotate);
  const selected = name != null;

  // desktop: arrow keys nudge, R rotates, Enter = Done, Esc = Cancel / exit
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      const keys: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowRight: [1, 0] };
      if (selected && keys[e.key]) { e.preventDefault(); nudge(...keys[e.key]); return; }
      if (selected && (e.key === 'r' || e.key === 'R')) { e.preventDefault(); rotate(); return; }
      if (selected && e.key === 'Enter') { e.preventDefault(); onDone(); return; }
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (selected) onCancel(); else onExit(); }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [selected, nudge, rotate, onDone, onCancel, onExit]);

  if (!selected) {
    return (
      <div className="arrange-bar arrange-bar--idle" role="toolbar" aria-label="Arrange home">
        <span className="arrange-bar__hint"><Icon name="info" size={15} /> Tap one of your pieces to move it</span>
        <div className="arrange-bar__row">
          <button type="button" className="arrange-btn" onClick={onOwned}><Icon name="bag" size={16} /> My items</button>
          <button type="button" className="arrange-btn arrange-btn--done" onClick={onExit}><Icon name="check" size={16} /> Finish</button>
        </div>
      </div>
    );
  }

  return (
    <div className={`arrange-bar${issue ? ' is-invalid' : ''}`} role="toolbar" aria-label={`Arrange ${name}`}>
      <div className="arrange-bar__top">
        <span className="arrange-bar__name">{name}</span>
        <button type="button" className="arrange-bar__x" onClick={onCancel} aria-label="Cancel"><Icon name="close" size={16} /></button>
      </div>
      <p className={`arrange-bar__status${issue ? ' is-bad' : ''}`} role="status" aria-live="polite">
        {issue ? <><Icon name="warning" size={15} /> {issue}</> : <><Icon name="check" size={15} /> Fine here. Tap Done to save.</>}
      </p>
      <div className="arrange-bar__controls">
        <div className="arrange-pad" aria-label="Move">
          {PAD.map(([label, dx, dz, deg, cls]) => (
            <button key={cls} type="button" className={`arrange-pad__btn ${cls}`} aria-label={label} onClick={() => nudge(dx, dz)}>
              <span style={{ transform: `rotate(${deg}deg)` }}><Icon name="arrowUp" size={22} stroke={2.6} /></span>
            </button>
          ))}
          <button type="button" className="arrange-pad__mid" aria-label="Rotate 90 degrees" onClick={rotate}><Icon name="rotate" size={20} /></button>
        </div>
        <div className="arrange-bar__actions">
          <button type="button" className="arrange-btn" onClick={rotate}><Icon name="rotate" size={16} /> Rotate</button>
          <button type="button" className="arrange-btn" onClick={onStore} disabled={busy}><Icon name="bag" size={16} /> Store</button>
          <button type="button" className="arrange-btn arrange-btn--done" onClick={onDone} disabled={busy} aria-disabled={Boolean(issue)}>
            <Icon name="check" size={16} /> {busy ? 'Saving…' : 'Done'}
          </button>
        </div>
      </div>
    </div>
  );
}
