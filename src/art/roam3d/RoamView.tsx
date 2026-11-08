// Free roam (phase 1): walk the streets around King's Square in 3D. The scene is lazy (three.js); this file is the HUD:
// joystick bottom-left, Run + the contextual Action bottom-right, a small top bar, the mini-map with the GPS line top-left.
// Positions are cosmetic: the server decides where the player is (roam_enter). See docs/ROAM.md.
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { AvatarConfig } from '../../lib/types';
import { Icon } from '../../ui/Icon';
import { useTier } from '../feel/quality';
import { AREA, type PlaceIn } from './area';
import type { RoamApi, RoamInput, RoamLive } from './engine/RoamScene';
import { RoamMap } from './RoamMap';
import { getRoamWorld } from './world';
import './roam3d.css';

const RoamScene = lazy(() => import('./engine/RoamScene'));

export interface RoamViewProps {
  places: PlaceIn[];
  /** The place whose door you stand at when roam opens (null = King's Square). */
  startId: string | null;
  avatar: AvatarConfig | null;
  /** Benin time as an hour float. */
  hour: number;
  /** "Go in": return a message to show (refused) or nothing when the game has moved on. */
  onGoIn: (placeId: string) => Promise<string | void> | string | void;
  onLeave: () => void;
  onLost?: () => void;
  /** Dev page / screenshots. */
  demo?: {
    dest?: string;
    fp?: boolean;
    debug?: boolean;
    x?: number;
    y?: number;
    h?: number;
    cam?: { yaw?: number; pitch?: number; dist?: number };
    miniOpen?: boolean;
    fps?: boolean;
    warm?: number;
    tier?: 'low' | 'high';
    say?: string;
    note?: string;
    run?: boolean;
  };
  onApi?: (api: RoamApi) => void;
}

const TALK = [
  'How far, oga? Fresh things today!',
  'Welcome! Come and see, na correct price.',
  'Good afternoon. You dey find something?',
  'Walk well. Mind the road.',
  'Beta tomatoes, just come in!',
];

const timeText = (hour: number) => {
  const h = ((Math.floor(hour) % 24) + 24) % 24;
  const m = Math.floor((hour - Math.floor(hour)) * 60);
  const ap = h >= 12 ? 'PM' : 'AM';
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${ap}`;
};

function loadFp(): boolean {
  try {
    return localStorage.getItem('bl.roam.fp') === '1';
  } catch {
    return false;
  }
}

export function RoamView({ places, startId, avatar, hour, onGoIn, onLeave, onLost, demo, onApi }: RoamViewProps) {
  const hookTier = useTier();
  const tier = demo?.tier ?? hookTier;
  const world = useMemo(() => getRoamWorld(places), [places]);
  const input = useRef<RoamInput>({ sx: 0, sy: 0, run: Boolean(demo?.run), lookX: 0, lookY: 0 });
  const live = useRef<RoamLive>({ x: 0, y: 0, h: 0, speed: 0, nearId: null, nearDist: 99, street: '', left: null, route: null, nearTalk: false, camYaw: 0, running: false, t: 0, ready: false });
  const [fp, setFp] = useState<boolean>(demo?.fp ?? loadFp());
  const [run, setRun] = useState(Boolean(demo?.run));
  const [miniOpen, setMiniOpen] = useState(Boolean(demo?.miniOpen));
  const [destId, setDestId] = useState<string | null>(demo?.dest ?? null);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(demo?.note ?? null);
  const [say, setSay] = useState<string | null>(demo?.say ?? null);
  const [hud, setHud] = useState({ near: null as string | null, street: '', left: null as number | null, talk: false });
  const [fps, setFps] = useState('');
  const apiRef = useRef<RoamApi | null>(null);

  // where we start: standing at the door of the place we came from, facing the street
  const start = useMemo(() => {
    const pl = startId ? world.places.find((p) => p.id === startId) : null;
    if (demo?.x !== undefined && demo?.y !== undefined) return { x: demo.x, y: demo.y, h: demo.h ?? 0 };
    if (pl) { const h = Math.atan2(pl.door.ny, pl.door.nx); return { x: pl.door.sx, y: pl.door.sy, h, camYaw: h + Math.PI }; }
    const m = world.places.find((p) => p.id === 'national_museum');
    return m ? { x: m.door.sx, y: m.door.sy, h: Math.atan2(m.door.ny, m.door.nx), camYaw: Math.atan2(m.door.ny, m.door.nx) + Math.PI } : { x: 500, y: 540, h: Math.PI / 2 };
  }, [world, startId, demo?.x, demo?.y, demo?.h]);
  const dest = useMemo(() => {
    const pl = destId ? world.places.find((p) => p.id === destId) : null;
    return pl ? { x: pl.door.sx, y: pl.door.sy } : null;
  }, [world, destId]);
  const labelOf = useCallback((id: string | null) => world.places.find((p) => p.id === id)?.label ?? '', [world]);

  const showNote = useCallback((t: string, ms = 4200) => {
    setNote(t);
    window.setTimeout(() => setNote((n) => (n === t ? null : n)), ms);
  }, []);

  // HUD text from the scene's live numbers, a few times a second
  useEffect(() => {
    const id = window.setInterval(() => {
      const L = live.current;
      setHud((h) => {
        const near = L.nearId;
        const left = L.left === null ? null : Math.round(L.left / 5) * 5;
        if (h.near === near && h.street === L.street && h.left === left && h.talk === L.nearTalk) return h;
        return { near, street: L.street, left, talk: L.nearTalk };
      });
      if (L.ready) setReady(true);
      if (demo?.fps || import.meta.env.DEV) {
        const api = apiRef.current;
        if (api && demo?.fps) {
          const s = api.stats();
          setFps(`${s.calls} calls · ${(s.triangles / 1000).toFixed(0)}k tris · ${s.rigs} rigs · ${s.cars} cars`);
        }
      }
    }, 250);
    return () => window.clearInterval(id);
  }, [demo?.fps]);

  // arriving at the destination
  useEffect(() => {
    if (destId && hud.near === destId) {
      setDestId(null);
      showNote(`You are at ${labelOf(destId)}`, 2600);
    }
  }, [hud.near, destId, labelOf, showNote]);

  /* ---------------- controls ---------------- */
  const keys = useRef({ up: false, down: false, left: false, right: false, shift: false });
  const stick = useRef({ x: 0, y: 0 });
  const knob = useRef<HTMLDivElement>(null);
  const pushInput = useCallback(() => {
    const k = keys.current;
    const kx = (k.right ? 1 : 0) - (k.left ? 1 : 0);
    const ky = (k.up ? 1 : 0) - (k.down ? 1 : 0);
    let sx = stick.current.x + kx, sy = stick.current.y + ky;
    const m = Math.hypot(sx, sy);
    if (m > 1) { sx /= m; sy /= m; }
    input.current.sx = sx;
    input.current.sy = sy;
    input.current.run = run || k.shift;
  }, [run]);
  useEffect(pushInput, [pushInput]);

  const action = useCallback(async () => {
    const L = live.current;
    if (busy) return;
    if (L.nearId) {
      setBusy(true);
      try {
        const msg = await onGoIn(L.nearId);
        if (typeof msg === 'string' && msg) showNote(msg, 5200);
      } catch (e) {
        showNote(e instanceof Error ? e.message : 'Could not go in just now.', 5200);
      } finally {
        setBusy(false);
      }
    } else if (L.nearTalk) {
      const line = TALK[Math.floor(Math.random() * TALK.length)];
      setSay(line);
      window.setTimeout(() => setSay((s) => (s === line ? null : s)), 2800);
    }
  }, [busy, onGoIn, showNote]);
  const actionRef = useRef(action);
  actionRef.current = action;

  useEffect(() => {
    const map: Record<string, keyof typeof keys.current> = { w: 'up', arrowup: 'up', s: 'down', arrowdown: 'down', a: 'left', arrowleft: 'left', d: 'right', arrowright: 'right' };
    const down = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement | null)?.closest?.('input,textarea')) return;
      const k = e.key.toLowerCase();
      if (map[k]) { keys.current[map[k]] = true; pushInput(); e.preventDefault(); }
      else if (k === 'shift') { keys.current.shift = true; pushInput(); }
      else if ((k === 'e' || k === 'enter') && !e.repeat) { void actionRef.current(); e.preventDefault(); }
      else if (k === 'v' && !e.repeat) toggleFp();
      else if (k === 'm' && !e.repeat) setMiniOpen((o) => !o);
      else if (k === 'r' && !e.repeat) setRun((r) => !r);
      else if (k === 'escape') { if (miniOpenRef.current) setMiniOpen(false); }
    };
    const up = (e: KeyboardEvent) => {
      const k = e.key.toLowerCase();
      if (map[k]) { keys.current[map[k]] = false; pushInput(); }
      else if (k === 'shift') { keys.current.shift = false; pushInput(); }
    };
    const blur = () => {
      keys.current = { up: false, down: false, left: false, right: false, shift: false };
      pushInput();
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('blur', blur);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('blur', blur);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pushInput]);
  const miniOpenRef = useRef(miniOpen);
  miniOpenRef.current = miniOpen;
  const toggleFp = () => {
    setFp((v) => {
      try {
        localStorage.setItem('bl.roam.fp', v ? '0' : '1');
      } catch {
        /* storage blocked */
      }
      return !v;
    });
  };

  // virtual joystick
  const stickPtr = useRef<number | null>(null);
  const stickBase = useRef<HTMLDivElement>(null);
  const moveStick = (e: React.PointerEvent) => {
    const el = stickBase.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const R = r.width / 2;
    let dx = e.clientX - (r.left + R), dy = e.clientY - (r.top + R);
    const m = Math.hypot(dx, dy);
    const lim = R - 10;
    if (m > lim) { dx = (dx / m) * lim; dy = (dy / m) * lim; }
    if (knob.current) knob.current.style.transform = `translate(${dx}px, ${dy}px)`;
    const k = Math.hypot(dx, dy) / lim;
    const dz = 0.12;
    const mag = k < dz ? 0 : (k - dz) / (1 - dz);
    const a = Math.atan2(dy, dx);
    stick.current.x = Math.cos(a) * mag;
    stick.current.y = -Math.sin(a) * mag;
    pushInput();
  };
  const endStick = () => {
    stickPtr.current = null;
    stick.current.x = 0;
    stick.current.y = 0;
    if (knob.current) knob.current.style.transform = '';
    pushInput();
  };

  // drag anywhere else to look round
  const lookPtr = useRef<{ id: number; x: number; y: number } | null>(null);
  const onLookDown = (e: React.PointerEvent) => {
    if (lookPtr.current) return;
    lookPtr.current = { id: e.pointerId, x: e.clientX, y: e.clientY };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    if (miniOpen) setMiniOpen(false);
  };
  const onLookMove = (e: React.PointerEvent) => {
    const p = lookPtr.current;
    if (!p || p.id !== e.pointerId) return;
    const k = fp ? 0.0062 : 0.0052;
    input.current.lookX += (e.clientX - p.x) * k;
    input.current.lookY += (e.clientY - p.y) * k * (fp ? 1 : 0.8);
    p.x = e.clientX;
    p.y = e.clientY;
  };
  const onLookUp = (e: React.PointerEvent) => {
    if (lookPtr.current?.id === e.pointerId) lookPtr.current = null;
  };

  const ready2 = hud.near !== null || hud.talk;
  const nearLabel = hud.near ? labelOf(hud.near) : '';
  const title = nearLabel || hud.street || 'Free roam';

  return (
    <div className="roam" data-testid="roam">
      <Suspense fallback={null}>
        <RoamScene
          world={world}
          avatar={avatar}
          hour={hour}
          tier={tier}
          start={start}
          input={input}
          live={live}
          dest={dest}
          firstPerson={fp}
          debug={demo?.debug}
          warm={demo?.warm}
          cam={demo?.cam}
          paused={false}
          onReady={(api) => {
            apiRef.current = api;
            onApi?.(api);
          }}
          onLost={onLost}
        />
      </Suspense>
      <div className="roam__look" onPointerDown={onLookDown} onPointerMove={onLookMove} onPointerUp={onLookUp} onPointerCancel={onLookUp} />
      {!ready && (
        <div className="roam__loading" role="status">
          <span>Stepping out…</span>
        </div>
      )}

      <div className="roam__top">
        <div className="roam__left">
          <RoamMap world={world} live={live} open={miniOpen} onToggle={() => setMiniOpen((o) => !o)} destId={destId} onPick={(id) => { setDestId(id); setMiniOpen(false); }} />
          {!miniOpen && (
            <div className="roam-pill" aria-live="polite">
              <span className="roam-pill__name">{title}</span>
              <span className="roam-pill__sub">
                <span>{timeText(hour)}</span>
                {destId && hud.left !== null && (
                  <span className="roam-pill__go">
                    To {labelOf(destId)} · {hud.left} m
                    <button type="button" className="roam-pill__x" aria-label="Clear the route" onClick={() => setDestId(null)}>✕</button>
                  </span>
                )}
              </span>
            </div>
          )}
        </div>
        <div className="roam__ctrls">
          <button type="button" className="roam-btn roam-btn--pill" onClick={onLeave} aria-label="Leave free roam">
            <Icon name="close" size={16} /> Leave
          </button>
          <button type="button" className={`roam-btn roam-btn--round${fp ? ' is-on' : ''}`} onClick={toggleFp} aria-label={fp ? 'Third person view' : 'First person view'} aria-pressed={fp}>
            <Icon name="eye" size={18} />
          </button>
        </div>
      </div>

      {note && <div className="roam-note" role="status">{note}</div>}
      {say && <div className="roam-say" role="status">{say}</div>}

      <div className="roam-stick" ref={stickBase} aria-label="Move" role="presentation"
        onPointerDown={(e) => { if (stickPtr.current !== null) return; stickPtr.current = e.pointerId; (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); moveStick(e); }}
        onPointerMove={(e) => { if (stickPtr.current === e.pointerId) moveStick(e); }}
        onPointerUp={(e) => { if (stickPtr.current === e.pointerId) endStick(); }}
        onPointerCancel={(e) => { if (stickPtr.current === e.pointerId) endStick(); }}>
        <div className="roam-stick__knob" ref={knob} />
      </div>

      <div className="roam__right">
        <button type="button" className={`roam-btn roam-btn--round roam-run${run ? ' is-on' : ''}`} onClick={() => setRun((r) => !r)} aria-pressed={run} aria-label="Run">
          <Icon name="walk" size={18} />
          <span>{run ? 'Run' : 'Walk'}</span>
        </button>
        <button type="button" className={`roam-act${ready2 ? ' is-ready' : ''}`} disabled={busy || !ready2} onClick={() => void action()} data-testid="roam-action">
          <span>{busy ? 'Opening…' : hud.near ? 'Go in' : hud.talk ? 'Talk' : 'Go in'}</span>
          <small>{hud.near ? nearLabel : hud.talk ? 'Say hello' : 'Walk up to a door'}</small>
        </button>
      </div>
      {fps && <div className="roam-fps">{fps}</div>}
    </div>
  );
}

export default RoamView;
export { AREA };
