// Drive scene 3 UI pieces (docs/DRIVE.md): the steering pad (lane buttons, hold to brake, hold to speed up, swipe), the small HUD chips
// (fuel, condition, who is driving) and the Driver-view instrument cluster (speed, fuel gauge, warning lights, turn signal) with wipers.
// Everything uses the theme tokens (src/styles/tokens.css) and sits in the corners: the road stays clear.
import { useEffect, useRef, type MutableRefObject, type PointerEvent as RPointerEvent } from 'react';
import { kmh, type SteerInput } from './steer';

export const FuelIcon = ({ size = 14 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16" />
    <path d="M3 21h12" />
    <path d="M7 8h4" />
    <path d="M14 10h2a2 2 0 0 1 2 2v4a1.5 1.5 0 0 0 3 0V9l-3-3" />
  </svg>
);

export const WrenchIcon = ({ size = 14 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.6 2.6-2.4-.6-.6-2.4 2.6-2.6Z" />
  </svg>
);

const Arrow = ({ dir }: { dir: -1 | 1 }) => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style={{ transform: dir < 0 ? 'scaleX(-1)' : undefined }}>
    <path d="M13 4l8 8-8 8v-5H4V9h9V4Z" />
  </svg>
);

// ---------------------------------------------------------------- steering pad
export function SteerPad({ input, hidden }: { input: MutableRefObject<SteerInput>; hidden: boolean }) {
  // keyboard (desktop and the dev lab): arrows
  useEffect(() => {
    const steer = input.current;
    const down = (e: KeyboardEvent) => {
      if (e.repeat) return;
      if (e.key === 'ArrowLeft') steer.lane = -1;
      else if (e.key === 'ArrowRight') steer.lane = 1;
      else if (e.key === 'ArrowDown') steer.brake = true;
      else if (e.key === 'ArrowUp') steer.boost = true;
    };
    const up = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown') steer.brake = false;
      else if (e.key === 'ArrowUp') steer.boost = false;
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      steer.brake = false;
      steer.boost = false;
    };
  }, [input]);

  // swipe left / right anywhere on the road
  const sw = useRef<{ x: number; id: number; done: boolean } | null>(null);
  const onDown = (e: RPointerEvent) => {
    sw.current = { x: e.clientX, id: e.pointerId, done: false };
  };
  const onMove = (e: RPointerEvent) => {
    const s = sw.current;
    if (!s || s.done || s.id !== e.pointerId) return;
    const dx = e.clientX - s.x;
    if (Math.abs(dx) > 34) {
      input.current.lane = dx < 0 ? -1 : 1;
      s.done = true;
    }
  };
  const onUp = () => {
    sw.current = null;
  };

  const hold = (key: 'brake' | 'boost') => ({
    onPointerDown: (e: RPointerEvent) => {
      e.preventDefault();
      (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
      input.current[key] = true;
    },
    onPointerUp: () => {
      input.current[key] = false;
    },
    onPointerCancel: () => {
      input.current[key] = false;
    },
    onLostPointerCapture: () => {
      input.current[key] = false;
    },
    onContextMenu: (e: React.MouseEvent) => e.preventDefault(),
  });

  return (
    <>
      <div className="drive-swipe" onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp} aria-hidden="true" />
      {!hidden && (
        <>
          <div className="drive-pad drive-pad--l" role="group" aria-label="Change lane">
            <button type="button" className="drive-pad__btn" aria-label="Lane left" onPointerDown={(e) => { e.preventDefault(); input.current.lane = -1; }}>
              <Arrow dir={-1} />
            </button>
            <button type="button" className="drive-pad__btn" aria-label="Lane right" onPointerDown={(e) => { e.preventDefault(); input.current.lane = 1; }}>
              <Arrow dir={1} />
            </button>
          </div>
          <div className="drive-pad drive-pad--r" role="group" aria-label="Brake and speed up">
            <button type="button" className="drive-pad__btn drive-pad__btn--brake" aria-label="Hold to brake" {...hold('brake')}>
              <span>Brake</span>
            </button>
            <button type="button" className="drive-pad__btn drive-pad__btn--go" aria-label="Hold to speed up" {...hold('boost')}>
              <span>Go</span>
            </button>
          </div>
        </>
      )}
    </>
  );
}

// ---------------------------------------------------------------- HUD chips
export function DriveHud({ fuel, cond, manual, showMode, showFuel, showCond, lowFuel, lowCond }: {
  fuel: number | null;
  cond: number | null;
  manual: boolean;
  showMode: boolean;
  showFuel: boolean;
  showCond: boolean;
  lowFuel: boolean;
  lowCond: boolean;
}) {
  return (
    <div className="drive-hud" aria-label="Vehicle">
      {showFuel && fuel != null && (
        <span className={`drive-pill${lowFuel ? ' is-warn' : ''}`} title="Fuel">
          <FuelIcon />
          {Math.round(fuel * 100)}%
        </span>
      )}
      {showCond && cond != null && (
        <span className={`drive-pill${lowCond ? ' is-bad' : ''}`} title="Condition">
          <WrenchIcon />
          {Math.round(cond)}%
        </span>
      )}
      {showMode && <span className={`drive-pill drive-pill--mode${manual ? ' is-on' : ''}`}>{manual ? 'You drive' : 'Auto'}</span>}
    </div>
  );
}

// ---------------------------------------------------------------- Driver view cluster
function Gauge({ frac, low }: { frac: number; low: boolean }) {
  // a half-dial: empty on the left, full on the right
  const a = Math.PI * (1 - Math.max(0, Math.min(1, frac)));
  const cx = 34;
  const cy = 36;
  const r = 26;
  const nx = cx + Math.cos(a) * (r - 4);
  const ny = cy - Math.sin(a) * (r - 4);
  const arc = (from: number, to: number) => {
    const p = (t: number) => `${(cx + Math.cos(Math.PI * (1 - t)) * r).toFixed(1)} ${(cy - Math.sin(Math.PI * (1 - t)) * r).toFixed(1)}`;
    return `M ${p(from)} A ${r} ${r} 0 0 1 ${p(to)}`;
  };
  return (
    <svg className="drive-gauge" width="68" height="44" viewBox="0 0 68 44" aria-hidden="true">
      <path d={arc(0, 1)} className="drive-gauge__track" />
      <path d={arc(0, 0.2)} className="drive-gauge__low" />
      <line x1={cx} y1={cy} x2={nx} y2={ny} className={`drive-gauge__needle${low ? ' is-low' : ''}`} />
      <circle cx={cx} cy={cy} r="3" className="drive-gauge__hub" />
      <text x="8" y="43" className="drive-gauge__t">E</text>
      <text x="55" y="43" className="drive-gauge__t">F</text>
    </svg>
  );
}

export function DriveCluster({ v, fuel, lowFuel, lowCond, signal, rain, night, wipers }: {
  v: number;
  fuel: number | null;
  lowFuel: boolean;
  lowCond: boolean;
  signal: -1 | 0 | 1;
  rain: boolean;
  night: boolean;
  wipers: boolean;
}) {
  return (
    <div className={`drive-dash${night ? ' is-night' : ''}`} aria-hidden="true">
      <span className={`drive-dash__sig${signal < 0 ? ' is-blink' : ''}`}><Arrow dir={-1} /></span>
      <div className="drive-dash__speed">
        <b>{kmh(v)}</b>
        <small>km/h</small>
      </div>
      {fuel != null && (
        <div className="drive-dash__fuel">
          <Gauge frac={fuel} low={lowFuel} />
        </div>
      )}
      <div className="drive-dash__lamps">
        <span className={`drive-lamp${lowFuel ? ' is-warn' : ''}`} title="Fuel"><FuelIcon size={15} /></span>
        <span className={`drive-lamp${lowCond ? ' is-bad' : ''}`} title="Condition"><WrenchIcon size={15} /></span>
        <span className={`drive-lamp drive-lamp--rain${rain && wipers ? ' is-on' : ''}`} title="Wipers">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
            <path d="M3 18a9 9 0 0 1 18 0" />
            <path d="M12 18 8 8" />
          </svg>
        </span>
      </div>
      <span className={`drive-dash__sig${signal > 0 ? ' is-blink' : ''}`}><Arrow dir={1} /></span>
    </div>
  );
}

/** Windscreen wipers and a few drops (Driver view in the rain). Pure CSS animation. */
export function Wipers() {
  return (
    <div className="drive-wipers" aria-hidden="true">
      <i className="drive-wipers__arm drive-wipers__arm--a" />
      <i className="drive-wipers__arm drive-wipers__arm--b" />
      {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
        <i key={i} className="drive-drop" style={{ ['--i' as string]: String(i) }} />
      ))}
    </div>
  );
}
