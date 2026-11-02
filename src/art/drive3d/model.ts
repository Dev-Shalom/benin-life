// Drive scene data (no three.js): which real Benin roads a trip uses, what vehicle the player drives, day/night helpers.
// docs/DRIVE.md. The road names come from the same map data as the 3D city (mapGeo ROADS + the Ring Road), so a trip from
// Ekenwan to the airport really reads "Ekenwan Road > Ring Road > Airport Road".
import { RING, ROADS, type Pt } from '../map/mapGeo';
import { roadRoute } from '../city3d/route';
import type { TravelMode } from '../../lib/types';

export type CamMode = 'chase' | 'side' | 'inside';
export const CAMS: CamMode[] = ['chase', 'side', 'inside'];
export const CAM_LABEL: Record<CamMode, string> = { chase: 'Chase', side: 'Side', inside: 'Driver' };

/** Real road names (the only place the word "Lagos" may appear is the real road name). */
export const ROAD_NAME: Record<string, string> = {
  ring: 'Ring Road',
  ugbowo: 'Ugbowo-Lagos Road',
  mission: 'Mission Road',
  akpakpava: 'Akpakpava Road',
  auchi: 'Benin-Auchi Road',
  agbor: 'Benin-Agbor Road',
  sakponba: 'Sakponba Road',
  sapele: 'Sapele Road',
  airport: 'Airport Road',
  siluko: 'Siluko Road',
  ekenwan: 'Ekenwan Road',
  thirdeast: '3rd East Circular',
  'oluku-bypass': 'Oluku Bypass',
  'second-east': '2nd East Circular',
  'first-east': '1st East Circular',
  'uselu-siluko': 'Uselu Road',
  'uselu-newbenin': 'New Benin Road',
};

export interface RoadSeg {
  name: string;
  /** Share of the trip (0..1) where this road starts and ends. */
  f0: number;
  f1: number;
}

type Line = { id: string; pts: Pt[] };
let lines: Line[] | null = null;

function allLines(): Line[] {
  if (lines) return lines;
  const ring: Pt[] = [];
  for (let i = 0; i <= 24; i++) {
    const a = (i / 24) * Math.PI * 2;
    ring.push([RING.x + Math.cos(a) * RING.r, RING.y + Math.sin(a) * RING.r]);
  }
  lines = [{ id: 'ring', pts: ring }, ...ROADS.map((r) => ({ id: r.id, pts: r.pts as Pt[] }))];
  return lines;
}

function distSeg(px: number, py: number, a: Pt, b: Pt): number {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy || 1;
  const t = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
  return Math.hypot(px - (a[0] + dx * t), py - (a[1] + dy * t));
}

function nearestRoad(x: number, y: number): string {
  let best = 'ring';
  let bd = Infinity;
  for (const ln of allLines()) {
    for (let i = 0; i + 1 < ln.pts.length; i++) {
      const d = distSeg(x, y, ln.pts[i], ln.pts[i + 1]);
      if (d < bd) {
        bd = d;
        best = ln.id;
      }
    }
  }
  return best;
}

/** The roads a trip follows, in order, with the share of the trip each covers. Always at least one. */
export function routeRoads(from: { x: number; y: number }, to: { x: number; y: number }): RoadSeg[] {
  const pts = roadRoute(from, to);
  // densify to ~5 map units and name each sample by the nearest road
  const samples: { id: string; at: number }[] = [];
  let total = 0;
  const cum: number[] = [0];
  for (let i = 1; i < pts.length; i++) {
    total += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
    cum.push(total);
  }
  if (total < 1) return [{ name: ROAD_NAME[nearestRoad(from.x, from.y)] ?? 'Ring Road', f0: 0, f1: 1 }];
  const n = Math.max(6, Math.round(total / 5));
  let k = 0;
  for (let s = 0; s <= n; s++) {
    const d = (s / n) * total;
    while (k + 2 < cum.length && cum[k + 1] < d) k++;
    const seg = cum[k + 1] - cum[k] || 1;
    const t = Math.max(0, Math.min(1, (d - cum[k]) / seg));
    const x = pts[k][0] + (pts[k + 1][0] - pts[k][0]) * t;
    const y = pts[k][1] + (pts[k + 1][1] - pts[k][1]) * t;
    samples.push({ id: nearestRoad(x, y), at: s / n });
  }
  // runs
  const runs: { id: string; f0: number; f1: number }[] = [];
  for (const s of samples) {
    const last = runs[runs.length - 1];
    if (last && last.id === s.id) last.f1 = s.at;
    else runs.push({ id: s.id, f0: last ? last.f1 : 0, f1: s.at });
  }
  // fold short runs (< 12 % of the trip) into the previous one so the signs don't flicker
  const merged: typeof runs = [];
  for (const r of runs) {
    const last = merged[merged.length - 1];
    if (last && (r.f1 - r.f0 < 0.12 || last.id === r.id)) last.f1 = r.f1;
    else merged.push({ ...r });
  }
  if (merged.length > 1 && merged[0].f1 - merged[0].f0 < 0.12) {
    merged[1].f0 = 0;
    merged.shift();
  }
  merged[0].f0 = 0;
  merged[merged.length - 1].f1 = 1;
  return merged.map((r) => ({ name: ROAD_NAME[r.id] ?? 'Ring Road', f0: r.f0, f1: r.f1 }));
}

export function roadAt(roads: RoadSeg[], f: number): RoadSeg {
  return roads.find((r) => f >= r.f0 && f <= r.f1) ?? roads[roads.length - 1];
}

/** A short key for the presence channel: players on the same main road see each other. */
export function roadKey(roads: RoadSeg[]): string {
  const main = [...roads].sort((a, b) => b.f1 - b.f0 - (a.f1 - a.f0))[0];
  return main.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

export type VehicleKind = 'sedan' | 'suv' | 'pickup' | 'moto' | 'bike' | 'keke' | 'bus';
export interface VehicleLook {
  kind: VehicleKind;
  /** Body colour, a muted real-world colour. */
  color: number;
  /** Item id of the player's own vehicle, when it is theirs. */
  itemId?: string | null;
}

const SUV_IDS = new Set(['gwagon_g63', 'gle63_coupe', 'lambo_urus', 'escalade', 'lexus_rx350']);
const PICKUP_IDS = new Set(['tesla_cybertruck', 'hilux_new']);
export const CAR_COLORS = [0xc3c7cd, 0x4a5d7a, 0xa23c36, 0xefebe0, 0x5a8068, 0x6c7480, 0xaab3bd, 0x7d8ca0, 0x9a7650];

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

/** What the player rides: their own car (item id) for mode car, else the keke / ECTS bus / a taxi for the other modes. */
export function vehicleFor(mode: TravelMode | string, itemId?: string | null, seed = 'me'): VehicleLook {
  if (mode === 'keke') return { kind: 'keke', color: 0xe3b53c };
  if (mode === 'bus') return { kind: 'bus', color: 0xe9e6dc };
  if (mode === 'drop') return { kind: 'sedan', color: 0xe8e4da };
  const id = itemId ?? '';
  const color = CAR_COLORS[hash(id || seed) % CAR_COLORS.length];
  if (id === 'bajaj_boxer') return { kind: 'moto', color: 0x2c3a52, itemId: id };
  if (id === 'bicycle') return { kind: 'bike', color: 0x2f6f54, itemId: id };
  if (SUV_IDS.has(id)) return { kind: 'suv', color: id === 'escalade' || id === 'gwagon_g63' ? 0x6c7480 : color, itemId: id };
  if (PICKUP_IDS.has(id)) return { kind: 'pickup', color: id === 'tesla_cybertruck' ? 0xaab0b8 : color, itemId: id };
  return { kind: 'sedan', color, itemId: id || null };
}

/** The look of another player's vehicle from the presence payload (`v` = a kind and a colour index). */
export function vehicleFromPresence(v: string | undefined): VehicleLook {
  const [kind, ci] = String(v ?? 'sedan.0').split('.');
  const k = (['sedan', 'suv', 'pickup', 'moto', 'keke', 'bus'] as const).includes(kind as 'sedan') ? (kind as VehicleKind) : 'sedan';
  const color = k === 'keke' ? 0xe3b53c : k === 'bus' ? 0xe9e6dc : CAR_COLORS[Math.abs(Number(ci) || 0) % CAR_COLORS.length];
  return { kind: k, color };
}

export function presenceVehicle(look: VehicleLook): string {
  const idx = Math.max(0, CAR_COLORS.indexOf(look.color));
  return `${look.kind === 'bike' ? 'moto' : look.kind}.${idx}`;
}

/** Cruising speed in scene metres a second (visual only; the trip length is the server's). */
export const CRUISE = 15;

/** Format seconds left as m:ss. */
export function clock(sec: number): string {
  const s = Math.max(0, Math.ceil(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
