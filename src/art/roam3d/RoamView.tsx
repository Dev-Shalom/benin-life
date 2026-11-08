// Free roam (phase 2): walk and drive the whole city in 3D. The scene is lazy (three.js); this file is the HUD:
// joystick bottom-left, Run / Brake + the contextual Action + the car button bottom-right, a small top bar, the mini-map with the GPS line
// top-left, a place search and Hail keke. Positions are cosmetic: the server decides where the player is (roam_enter) and validates the
// car's fuel and damage (roam_drive_report). See docs/ROAM.md.
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RoamCarInfo, RoamDriveReport, RoamDryResult, RoamModeResult } from '../../api/roam';
import type { AvatarConfig } from '../../lib/types';
import { Icon } from '../../ui/Icon';
import { useTier } from '../feel/quality';
import { DriveCluster, DriveHud, Wipers } from '../drive3d/DriveDash';
import { vehicleFor, type VehicleKind } from '../drive3d/model';
import '../drive3d/drive3d.css';
import { AREA, type PlaceIn } from './area';
import type { RoamApi, RoamInput, RoamLive } from './engine/RoamScene';
import { makeBridge } from './live/bridge';
import { LiveChip, LiveControls, LiveSheet, LiveTags, PlayerCard, useLive } from './live/LiveUi';
import { RoamMap } from './RoamMap';
import { MagnifierIcon, RoamSheet, type SheetItem } from './RoamSheet';
import { getRoamWorld, type RoamWorld } from './world';
import './roam3d.css';

const RoamScene = lazy(() => import('./engine/RoamScene'));

/** What the host gives the view for the player's own vehicle (all server calls live in the host). */
export interface RoamCarCtl {
  info: RoamCarInfo | null;
  /** Litres burned per metre driven (litres per km x the free roam fuel scale / 1000), for the gauge between checkpoints. */
  fuelPerM: number;
  /** Cash for the mechanic (shown on the stranded card). */
  mechanicCost: number;
  /** Seconds the car takes to arrive at the kerb after Get my car (roam.car.ready_s). */
  readyS: number;
  /** Re-read the tank and condition from the server (after a mechanic, a repair). */
  refresh(): Promise<void>;
  setMode(mode: 'walk' | 'car', pose?: { x: number; y: number; a: number } | null): Promise<RoamModeResult>;
  report(r: { dist_m: number; light: number; hard: number; x: number; y: number; a: number }): Promise<RoamDriveReport>;
  dry(choice: 'push' | 'mechanic'): Promise<RoamDryResult>;
}

export interface RoamKekeCtl {
  enabled: boolean;
  /** Hail a keke to this place: returns a message when refused, nothing when the trip started. */
  hail(dest: string): Promise<string | void>;
}

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
  car?: RoamCarCtl | null;
  keke?: RoamKekeCtl | null;
  /** Streaming hints from the server (roam.chunk.m / roam.chunk.load_m). */
  stream?: { chunkM: number; loadM: number };
  /** Live players (docs/ROAM.md): see and wave to other real players. Off = free roam alone, nothing is sent or joined. */
  liveOn?: boolean;
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
    /** Own vehicle in the dev page: item id; car=1 puts it at the kerb next to you, drive=1 starts in the seat. */
    vehicle?: string;
    carHere?: boolean;
    drive?: boolean;
    rain?: boolean;
    cam2?: 'chase' | 'inside';
    sheet?: 'search' | 'keke';
    dry?: boolean;
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

function loadPref(k: string, d: string): string {
  try {
    return localStorage.getItem(k) ?? d;
  } catch {
    return d;
  }
}
function savePref(k: string, v: string) {
  try {
    localStorage.setItem(k, v);
  } catch {
    /* storage blocked */
  }
}

const EXIT_MSG: Record<string, string> = {
  moving: 'Stop the car first.',
  illegal: 'You cannot leave it in the middle of the road. Pull over to the kerb.',
  blocked: 'No room to open the door here. Move the car a little.',
};

/** Builds the whole city's collision world AFTER the first paint (a "Loading the city" screen shows at once), then mounts the view. */
export function RoamView(props: RoamViewProps) {
  const chunkM = Math.max(80, Math.min(200, Math.round(props.stream?.chunkM ?? 120)));
  const sig = props.places.map((p) => `${p.id}:${p.x}:${p.y}:${p.scene}`).join('|');
  const [world, setWorld] = useState<RoamWorld | null>(null);
  useEffect(() => {
    let dead = false;
    const id = window.setTimeout(() => {
      const w = getRoamWorld(props.places, chunkM);
      if (!dead) setWorld(w);
    }, 60);
    return () => {
      dead = true;
      window.clearTimeout(id);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sig, chunkM]);
  if (!world) {
    return (
      <div className="roam" data-testid="roam">
        <div className="roam__loading" role="status">
          <span>Loading the city…</span>
          <small>Building the streets and doors</small>
        </div>
      </div>
    );
  }
  return <RoamViewInner {...props} world={world} />;
}

function RoamViewInner({ world, startId, avatar, hour, onGoIn, onLeave, onLost, car: carCtl, keke, stream, liveOn, demo, onApi }: RoamViewProps & { world: RoamWorld }) {
  const hookTier = useTier();
  const tier = demo?.tier ?? hookTier;
  const input = useRef<RoamInput>({ sx: 0, sy: 0, run: Boolean(demo?.run), lookX: 0, lookY: 0, brake: false });
  const live = useRef<RoamLive>({
    x: 0, y: 0, h: 0, speed: 0, nearId: null, nearDist: 99, street: '', left: null, route: null, nearTalk: false, camYaw: 0, running: false, t: 0, ready: false, loaded: 0, atKerb: false,
    car: { here: false, driving: false, nearDoor: false, doorDist: 99, v: 0, pendingDist: 0, pendingHits: 0, canPark: false, sinceHit: 9, braking: false, x: 0, y: 0, h: 0, dry: false },
  });
  const [fp, setFp] = useState<boolean>(demo?.fp ?? loadPref('bl.roam.fp', '0') === '1');
  const [camMode, setCamMode] = useState<'chase' | 'inside'>(demo?.cam2 ?? (loadPref('bl.roam.cam', 'chase') === 'inside' ? 'inside' : 'chase'));
  const [run, setRun] = useState(Boolean(demo?.run));
  const [miniOpen, setMiniOpen] = useState(Boolean(demo?.miniOpen));
  const [destId, setDestId] = useState<string | null>(demo?.dest ?? null);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(demo?.note ?? null);
  const [say, setSay] = useState<string | null>(demo?.say ?? null);
  const [sheet, setSheet] = useState<null | 'search' | 'keke'>(demo?.sheet ?? null);
  const [hud, setHud] = useState({ near: null as string | null, street: '', left: null as number | null, talk: false, loaded: 0, kerb: false, here: false, driving: false, nearDoor: false, kmh: 0, canPark: false, dry: false });
  const [fps, setFps] = useState('');
  const apiRef = useRef<RoamApi | null>(null);

  /* ---------------- live players ---------------- */
  const bridge = useMemo(() => makeBridge(), []);
  const liveClient = useLive(Boolean(liveOn), tier === 'low', () => ({ x: live.current.x, y: live.current.y }), bridge);
  const [cardId, setCardId] = useState<string | null>(null);
  const [liveSheet, setLiveSheet] = useState(false);
  useEffect(() => {
    (window as unknown as { __live?: unknown }).__live = liveClient;
    return () => { delete (window as unknown as { __live?: unknown }).__live; };
  }, [liveClient]);

  /* ---------------- the player's own vehicle ---------------- */
  const info = carCtl?.info ?? null;
  const demoItem = demo?.vehicle;
  const has = Boolean(info?.has_car) || Boolean(demoItem);
  const itemId = info?.item ?? demoItem ?? null;
  const look = useMemo(() => (has ? vehicleFor('car', itemId) : null), [has, itemId]);
  const [fuelL, setFuelL] = useState<number>(info?.fuel_l ?? (demoItem ? 30 : 0));
  const [cond, setCond] = useState<number>(info?.cond ?? 100);
  const tank = info?.tank_l ?? (info?.class === 'bicycle' ? 0 : 45);
  const noFuelNeeded = info?.class === 'bicycle' || info?.fuel_on === false || (demoItem === 'bicycle');
  const engine = (noFuelNeeded || fuelL > 0.01) && cond > 0;
  const fuelFrac = noFuelNeeded ? null : tank > 0 ? Math.max(0, Math.min(1, fuelL / tank)) : 0;
  const rain = Boolean(info?.rain) || Boolean(demo?.rain);
  const pend = useRef({ dist: 0, light: 0, hard: 0 });
  const fuelRef = useRef(fuelL);
  fuelRef.current = fuelL;
  useEffect(() => {
    if (info?.fuel_l !== undefined) setFuelL(info.fuel_l);
    if (info?.cond !== undefined) setCond(info.cond);
  }, [info?.fuel_l, info?.cond]);

  // where we start: standing at the door of the place we came from, facing the street
  const start = useMemo(() => {
    const pl = startId ? world.places.find((p) => p.id === startId) : null;
    if (demo?.x !== undefined && demo?.y !== undefined) return { x: demo.x, y: demo.y, h: demo.h ?? 0 };
    if (pl) { const h = Math.atan2(pl.door.ny, pl.door.nx); return { x: pl.door.sx, y: pl.door.sy, h, camYaw: h + Math.PI }; }
    const m = world.places.find((p) => p.id === 'national_museum');
    return m ? { x: m.door.sx, y: m.door.sy, h: Math.atan2(m.door.ny, m.door.nx), camYaw: Math.atan2(m.door.ny, m.door.nx) + Math.PI } : { x: 500, y: 540, h: Math.PI / 2 };
  }, [world, startId, demo?.x, demo?.y, demo?.h]);
  // the car stands where it was left: a map spot, or the kerb at the door of the place it pulled up at
  const carStart = useMemo(() => {
    if (!has) return null;
    if (demo?.carHere || demo?.drive) {
      return { x: start.x + Math.sin(start.h) * 3.2 + Math.cos(start.h) * 3, y: start.y - Math.cos(start.h) * 3.2 + Math.sin(start.h) * 3, h: start.h + Math.PI / 2 };
    }
    if (info?.car_x != null && info?.car_y != null) return { x: info.car_x, y: info.car_y, h: info.car_a ?? 0 };
    if (info?.car_place && info.car_place === startId) {
      const pl = world.places.find((p) => p.id === startId);
      if (pl) return { x: pl.door.sx + pl.door.nx * 4.5, y: pl.door.sy + pl.door.ny * 4.5, h: Math.atan2(pl.door.ny, pl.door.nx) + Math.PI / 2 };
    }
    return null;
  }, [has, info?.car_x, info?.car_y, info?.car_a, info?.car_place, startId, world, demo?.carHere, demo?.drive, start.x, start.y, start.h]);
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
        const kmh = Math.round(Math.abs(L.car.v) * 3.6 * 1.35);
        if (h.near === near && h.street === L.street && h.left === left && h.talk === L.nearTalk && h.loaded === L.loaded && h.kerb === L.atKerb && h.here === L.car.here && h.driving === L.car.driving
          && h.nearDoor === L.car.nearDoor && h.kmh === kmh && h.canPark === L.car.canPark && h.dry === L.car.dry) return h;
        return { near, street: L.street, left, talk: L.nearTalk, loaded: L.loaded, kerb: L.atKerb, here: L.car.here, driving: L.car.driving, nearDoor: L.car.nearDoor, kmh, canPark: L.car.canPark, dry: L.car.dry };
      });
      if (L.ready) setReady(true);
      const api = apiRef.current;
      if (api && demo?.fps) {
        const s = api.stats();
        const st = api.stream();
        setFps(`${s.calls} calls · ${(s.triangles / 1000).toFixed(0)}k tris · ${st.detail}+${st.far} chunks · ${st.lastChunkMs.toFixed(0)} ms/chunk · ${s.rigs} rigs · ${s.cars} cars`);
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

  /* ---------------- driving: checkpoints to the server ---------------- */
  const sending = useRef(false);
  const flush = useCallback(async (force = false) => {
    const api = apiRef.current;
    if (!api || !carCtl) return;
    const r = api.car.takeReport();
    pend.current.dist += r.dist;
    pend.current.light += r.light;
    pend.current.hard += r.hard;
    // the gauge falls between checkpoints
    if (r.dist > 0 && carCtl.fuelPerM > 0) setFuelL((f) => Math.max(0, f - r.dist * carCtl.fuelPerM));
    if (sending.current) return;
    const p = pend.current;
    if (!force && p.dist < 20 && p.light + p.hard === 0) return;
    if (p.dist < 0.5 && p.light + p.hard === 0) return;
    sending.current = true;
    const sent = { ...p };
    try {
      const res = await carCtl.report({ dist_m: sent.dist, light: sent.light, hard: sent.hard, x: r.x, y: r.y, a: r.a });
      if (res.ok) {
        pend.current.dist -= sent.dist;
        pend.current.light -= sent.light;
        pend.current.hard -= sent.hard;
        if (res.fuel_l !== undefined) setFuelL(res.fuel_l);
        if (res.cond !== undefined) {
          setCond(res.cond);
          if (res.damage && res.damage > 0) showNote(res.wont_start ? 'The car is wrecked. It will not start again until it is repaired.' : `Damage: condition ${Math.round(res.cond)}%`, 3000);
        }
      } else if (res.reason === 'off' || res.reason === 'not_driving') {
        pend.current = { dist: 0, light: 0, hard: 0 };
      }
    } catch {
      /* the next checkpoint sends it again */
    } finally {
      sending.current = false;
    }
  }, [carCtl, showNote]);
  const flushRef = useRef(flush);
  flushRef.current = flush;
  useEffect(() => {
    if (!hud.driving) return;
    const id = window.setInterval(() => void flushRef.current(false), 4200);
    return () => window.clearInterval(id);
  }, [hud.driving]);

  /* ---------------- the car button ---------------- */
  const getMyCar = useCallback(() => {
    const api = apiRef.current;
    if (!api || !has) return;
    if ((info?.ready_in_s ?? 0) > 0) { showNote('The mechanic is still working on it.'); return; }
    if (info?.wont_start || cond <= 0) { showNote('Your vehicle is too damaged to start. Repair it at the Mechanic Village, or hail a keke.'); return; }
    if (!noFuelNeeded && fuelL <= 0.01) { showNote('The tank is empty. Call a mechanic, push it to a pump, or hail a keke.'); return; }
    const ask = () => {
      const r = api.car.summon();
      if (r === 'ok') showNote(`Your ${info?.name ?? 'car'} is at the kerb, a short walk away.`, 3600);
      else if (r === 'no_spot') showNote('No free kerb close by. Walk to a main road and try again.');
    };
    const wait = carCtl?.readyS ?? 0;
    if (wait > 0.4) {
      // the car is on its way: it takes a moment to reach the nearest kerb
      showNote(`Your ${info?.name ?? 'car'} is on its way…`, wait * 1000 + 200);
      window.setTimeout(() => { if (!drivingRef.current) ask(); }, wait * 1000);
    } else ask();
  }, [has, info?.ready_in_s, info?.wont_start, info?.name, cond, fuelL, noFuelNeeded, showNote, carCtl?.readyS]);

  const getIn = useCallback(async () => {
    const api = apiRef.current;
    if (!api || !carCtl || busy) return;
    setBusy(true);
    try {
      // the scene decides first (are you at the door?), the server second; if the server refuses, we step back out
      if (!api.car.enter()) { showNote('Walk up to the driver\'s door first.'); return; }
      try {
        const r = await carCtl.setMode('car');
        if (r.fuel_l !== undefined) setFuelL(r.fuel_l);
        if (r.cond !== undefined) setCond(r.cond);
        pend.current = { dist: 0, light: 0, hard: 0 };
        api.car.takeReport();
      } catch (e) {
        api.car.exit();
        input.current.sx = 0;
        input.current.sy = 0;
        showNote(e instanceof Error ? e.message : 'Could not start the car.', 5000);
      }
    } finally {
      setBusy(false);
    }
  }, [carCtl, busy, showNote]);

  const getOut = useCallback(async () => {
    const api = apiRef.current;
    if (!api || !carCtl || busy) return;
    const r = api.car.exit();
    if (r !== 'ok') {
      showNote(EXIT_MSG[r] ?? 'Cannot get out here.');
      return;
    }
    input.current.sx = 0;
    input.current.sy = 0;
    const st = api.car.state();
    await flushRef.current(true);
    const pose = { x: st.x, y: st.y, a: st.h };
    try {
      await carCtl.setMode('walk', pose);
    } catch {
      // never leave the server thinking you drive: try once more, then say so
      try {
        await carCtl.setMode('walk', pose);
      } catch {
        showNote('Could not tell the server you left the car. It will sort itself out when you leave the street.', 5000);
      }
    }
  }, [carCtl, busy, showNote]);

  /* ---------------- controls ---------------- */
  const keys = useRef({ up: false, down: false, left: false, right: false, shift: false, space: false });
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
    input.current.brake = k.space;
  }, [run]);
  useEffect(pushInput, [pushInput]);

  const action = useCallback(async () => {
    const L = live.current;
    if (busy) return;
    if (L.nearId) {
      setBusy(true);
      try {
        if (L.car.driving) await flushRef.current(true);
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
  const carBtn = useCallback(() => {
    const L = live.current.car;
    if (L.driving) void getOut();
    else if (L.nearDoor) void getIn();
    else getMyCar();
  }, [getOut, getIn, getMyCar]);
  const carBtnRef = useRef(carBtn);
  carBtnRef.current = carBtn;

  useEffect(() => {
    const map: Record<string, keyof typeof keys.current> = { w: 'up', arrowup: 'up', s: 'down', arrowdown: 'down', a: 'left', arrowleft: 'left', d: 'right', arrowright: 'right', ' ': 'space' };
    const down = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement | null)?.closest?.('input,textarea')) return;
      const k = e.key.toLowerCase();
      if (map[k]) { keys.current[map[k]] = true; pushInput(); e.preventDefault(); }
      else if (k === 'shift') { keys.current.shift = true; pushInput(); }
      else if ((k === 'e' || k === 'enter') && !e.repeat) { void actionRef.current(); e.preventDefault(); }
      else if (k === 'g' && !e.repeat) carBtnRef.current();
      else if (k === 'v' && !e.repeat) toggleView();
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
      keys.current = { up: false, down: false, left: false, right: false, shift: false, space: false };
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
  const drivingRef = useRef(false);
  drivingRef.current = hud.driving;
  const toggleView = () => {
    if (drivingRef.current) {
      setCamMode((m) => {
        const n = m === 'chase' ? 'inside' : 'chase';
        savePref('bl.roam.cam', n);
        return n;
      });
      return;
    }
    setFp((v) => {
      savePref('bl.roam.fp', v ? '0' : '1');
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

  // drag anywhere else to look round (on foot)
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

  /* ---------------- stranded: out of fuel ---------------- */
  const [dryBusy, setDryBusy] = useState(false);
  const stranded = hud.driving && hud.dry && !engine && (fuelL <= 0.01 || demo?.dry);
  const dryChoice = async (choice: 'push' | 'mechanic' | 'keke') => {
    const api = apiRef.current;
    if (!api || !carCtl || dryBusy) return;
    setDryBusy(true);
    try {
      if (choice === 'keke') {
        // leave the car by the roadside, then pick where the keke takes you
        api.car.pushToKerb();
        const r = api.car.exit();
        if (r === 'ok') {
          const st = api.car.state();
          await carCtl.setMode('walk', { x: st.x, y: st.y, a: st.h }).catch(() => undefined);
          setSheet('keke');
        } else showNote(EXIT_MSG[r] ?? 'Cannot get out here.');
        return;
      }
      const res = await carCtl.dry(choice);
      showNote(res.message, 5200);
      void carCtl.refresh();
      if (choice === 'push') api.car.pushToKerb();
      if (choice === 'mechanic' || choice === 'push') setFuelL(res.fuel_l);
      const r = api.car.exit();
      void r;
      pend.current = { dist: 0, light: 0, hard: 0 };
    } catch (e) {
      showNote(e instanceof Error ? e.message : 'That did not work.', 5200);
    } finally {
      setDryBusy(false);
    }
  };

  /* ---------------- sheets: GPS search and hail a keke ---------------- */
  const me = live.current;
  const sheetItems: SheetItem[] = useMemo(() => {
    if (!sheet) return [];
    const here = apiRef.current ? { x: live.current.x, y: live.current.y } : { x: start.x, y: start.y };
    return world.places
      .filter((p) => (sheet === 'search' ? true : p.keke_ok !== false && !p.closed))
      .map((p) => ({
        id: p.id,
        label: p.label,
        sub: p.closed ? 'Under construction' : (SCENE_LABEL[p.scene] ?? p.scene.replace(/_/g, ' ')),
        dist: Math.hypot(p.door.sx - here.x, p.door.sy - here.y),
        disabled: p.closed && sheet === 'keke',
      }));
  }, [sheet, world, start.x, start.y]);
  void me;
  const pickSheet = async (id: string) => {
    if (sheet === 'search') {
      setDestId(id);
      setSheet(null);
      setMiniOpen(false);
      showNote(`GPS: ${labelOf(id)}`, 2200);
      return;
    }
    if (!keke) return;
    setBusy(true);
    try {
      const msg = await keke.hail(id);
      if (typeof msg === 'string' && msg) { showNote(msg, 5200); setSheet(null); }
    } catch (e) {
      showNote(e instanceof Error ? e.message : 'The keke did not stop.', 5200);
    } finally {
      setBusy(false);
    }
  };

  const ready2 = hud.near !== null || hud.talk;
  const nearLabel = hud.near ? labelOf(hud.near) : '';
  const title = nearLabel || hud.street || 'Free roam';
  const driving = hud.driving;
  const carLabel = driving ? 'Get out' : hud.nearDoor ? 'Get in' : 'Get my car';
  const night = hour >= 19 || hour < 6;

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
          vehicle={look ? { kind: look.kind as VehicleKind, color: look.color } : null}
          carStart={carStart}
          engine={engine}
          wet={rain}
          camMode={camMode}
          cond={cond}
          startDriving={demo?.drive}
          loadM={stream?.loadM}
          bridge={bridge}
          onReady={(api) => {
            apiRef.current = api;
            onApi?.(api);
          }}
          onLost={onLost}
        />
      </Suspense>
      <div className="roam__look" onPointerDown={onLookDown} onPointerMove={onLookMove} onPointerUp={onLookUp} onPointerCancel={onLookUp} />
      <LiveTags bridge={bridge} client={liveClient} onPick={setCardId} />
      {!ready && (
        <div className="roam__loading" role="status">
          <span>Stepping out…</span>
          <small>{hud.loaded > 0 ? `${hud.loaded} streets ready` : 'Building the streets round you'}</small>
        </div>
      )}
      {driving && camMode === 'inside' && rain && <Wipers />}

      <div className="roam__top">
        <div className="roam__left">
          <RoamMap world={world} live={live} open={miniOpen} onToggle={() => setMiniOpen((o) => !o)} destId={destId} onPick={(id) => { setDestId(id); setMiniOpen(false); }} />
          {!miniOpen && (
            <div className="roam-pill" aria-live="polite">
              <span className="roam-pill__name">{title}</span>
              <span className="roam-pill__sub">
                {!(destId && hud.left !== null) && <span>{timeText(hour)}</span>}
                {destId && hud.left !== null && (
                  <span className="roam-pill__go">
                    To {labelOf(destId)} · {hud.left >= 1000 ? `${(hud.left / 1000).toFixed(1)} km` : `${hud.left} m`}
                    <button type="button" className="roam-pill__x" aria-label="Clear the route" onClick={() => setDestId(null)}>✕</button>
                  </span>
                )}
              </span>
            </div>
          )}
        </div>
        <div className="roam__ctrls">
          <button type="button" className="roam-btn roam-btn--pill" onClick={() => { if (driving) void getOut().then(onLeave); else onLeave(); }} aria-label="Leave free roam">
            <Icon name="close" size={16} /> Leave
          </button>
          <button type="button" className={`roam-btn roam-btn--round${(driving ? camMode === 'inside' : fp) ? ' is-on' : ''}`} onClick={toggleView} aria-label={driving ? (camMode === 'chase' ? 'Driver view' : 'Chase view') : fp ? 'Third person view' : 'First person view'} aria-pressed={driving ? camMode === 'inside' : fp}>
            <Icon name="eye" size={18} />
          </button>
          <button type="button" className={`roam-btn roam-btn--round${destId ? ' is-on' : ''}`} onClick={() => setSheet('search')} aria-label="Search for a place" data-testid="roam-search">
            <MagnifierIcon size={18} />
          </button>
          {keke?.enabled && !driving && (hud.kerb || demo?.sheet === 'keke') && (
            <button type="button" className="roam-btn roam-btn--pill roam-hail" onClick={() => setSheet('keke')} data-testid="roam-hail">
              <Icon name="keke" size={16} /> Hail keke
            </button>
          )}
        </div>
      </div>

      {liveClient && !miniOpen && <LiveChip client={liveClient} onOpen={() => setLiveSheet(true)} />}

      {driving && (
        <div className="roam-carhud">
          <DriveHud fuel={fuelFrac} cond={cond} manual={false} showMode={false} showFuel={fuelFrac !== null} showCond lowFuel={fuelFrac !== null && fuelFrac < 0.15} lowCond={cond < 35} />
        </div>
      )}
      {driving && camMode === 'inside' && (
        <DriveCluster v={hud.kmh / 4.86} fuel={fuelFrac} lowFuel={fuelFrac !== null && fuelFrac < 0.15} lowCond={cond < 35} signal={0} rain={rain} night={night} wipers={rain} />
      )}
      {driving && camMode !== 'inside' && <div className="roam-speed" aria-label="Speed"><b>{hud.kmh}</b><small>km/h</small></div>}

      {note && <div className="roam-note" role="status">{note}</div>}
      {say && <div className="roam-say" role="status">{say}</div>}

      {stranded && (
        <div className="roam-dry" role="alertdialog" aria-label="Out of fuel" data-testid="roam-dry">
          <b>Out of fuel</b>
          <p>The engine coughs and dies. The needle sits on empty and you roll to a stop.</p>
          <button type="button" disabled={dryBusy} onClick={() => void dryChoice('push')}>Push the car to the kerb<small>Free, tiring</small></button>
          <button type="button" disabled={dryBusy} onClick={() => void dryChoice('mechanic')}>Call a mechanic<small>₦{(carCtl?.mechanicCost ?? 3500).toLocaleString('en-NG')} and a short wait</small></button>
          {keke?.enabled && <button type="button" disabled={dryBusy} onClick={() => void dryChoice('keke')}>Hitch a keke<small>Normal keke fare</small></button>}
        </div>
      )}

      <div className="roam-stick" ref={stickBase} aria-label={driving ? 'Steer and speed' : 'Move'} role="presentation"
        onPointerDown={(e) => { if (stickPtr.current !== null) return; stickPtr.current = e.pointerId; (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); moveStick(e); }}
        onPointerMove={(e) => { if (stickPtr.current === e.pointerId) moveStick(e); }}
        onPointerUp={(e) => { if (stickPtr.current === e.pointerId) endStick(); }}
        onPointerCancel={(e) => { if (stickPtr.current === e.pointerId) endStick(); }}>
        <div className="roam-stick__knob" ref={knob} />
        {driving && <span className="roam-stick__tag roam-stick__tag--u">Go</span>}
        {driving && <span className="roam-stick__tag roam-stick__tag--d">Brake</span>}
      </div>

      <div className="roam__right">
        <LiveControls client={liveClient} driving={driving} />
        {driving ? (
          <button type="button" className="roam-btn roam-btn--round roam-run roam-brake" aria-label="Hold to brake"
            onPointerDown={(e) => { (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); input.current.brake = true; }}
            onPointerUp={() => { input.current.brake = keys.current.space; }} onPointerCancel={() => { input.current.brake = keys.current.space; }}>
            <span>Brake</span>
          </button>
        ) : (
          <button type="button" className={`roam-btn roam-btn--round roam-run${run ? ' is-on' : ''}`} onClick={() => setRun((r) => !r)} aria-pressed={run} aria-label="Run">
            <Icon name="walk" size={18} />
            <span>{run ? 'Run' : 'Walk'}</span>
          </button>
        )}
        {has && (
          <button type="button" className={`roam-carbtn${hud.nearDoor || (driving && hud.canPark) ? ' is-ready' : ''}`} disabled={busy} onClick={carBtn} data-testid="roam-car-btn">
            <Icon name="car" size={18} />
            <span>{carLabel}</span>
          </button>
        )}
        <button type="button" className={`roam-act${ready2 ? ' is-ready' : ''}`} disabled={busy || !ready2} onClick={() => void action()} data-testid="roam-action">
          <span>{busy ? 'Opening…' : hud.near ? 'Go in' : hud.talk ? 'Talk' : 'Go in'}</span>
          <small>{hud.near ? nearLabel : hud.talk ? 'Say hello' : driving ? 'Pull up at a door' : 'Walk up to a door'}</small>
        </button>
      </div>

      {sheet && (
        <RoamSheet
          title={sheet === 'search' ? 'Where to?' : 'Hail a keke'}
          hint={sheet === 'search' ? 'Pick a place for the green GPS line. It works on foot and in the car.' : 'A keke takes you at the normal fare, then the street opens again at the door.'}
          items={sheetItems}
          busy={busy}
          onPick={(id) => void pickSheet(id)}
          onClose={() => setSheet(null)}
        />
      )}
      {liveClient && cardId && <PlayerCard client={liveClient} id={cardId} onClose={() => setCardId(null)} />}
      {liveClient && liveSheet && <LiveSheet client={liveClient} onClose={() => setLiveSheet(false)} onPick={(id) => { setLiveSheet(false); setCardId(id); }} />}
      {fps && <div className="roam-fps">{fps}</div>}
    </div>
  );
}

const SCENE_LABEL: Record<string, string> = {
  buka: 'Restaurant', salon: 'Salon', cyber: 'Cyber cafe', pos: 'PoS stand', club: 'Lounge', lounge: 'Lounge', bank: 'Bank', hospital: 'Hospital', police: 'Police', market: 'Market',
  museum: 'Museum', palace: 'Palace', workshop: 'Workshop', office: 'Office', street: 'Street', motorpark: 'Motor park', campus: 'Campus', shrine: 'Shrine', farm: 'Farm', airport: 'Airport',
  home_flat: 'Home', home_duplex: 'Home', home_face_me: 'Home',
};

export default RoamView;
export { AREA };
