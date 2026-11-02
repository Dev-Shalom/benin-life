// Drive scene data (no three.js): road names, what vehicle the player drives, small helpers. docs/DRIVE.md.
// The route itself (road graph, turns, roundabouts, timing) is in ./track.ts; its road names come from the same map data
// as the 3D city (mapGeo ROADS + the Ring Road).
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
  wifi: 'Ugbowo Link Road',
  backgate: 'Back Gate Road',
  'aduwawa-link': 'Aduwawa Link Road',
  oregbeni: 'Oregbeni Road',
  'upper-sakponba': 'Upper Sakponba Road',
  'gra-1': 'GRA Avenue',
  'gra-2': 'GRA Crescent',
  'farm-1': 'Farm Road',
  'farm-2': 'Farm Road',
  shrine: 'Shrine Path',
};

export interface RoadSeg {
  name: string;
  /** Share of the trip (0..1) where this road starts and ends. */
  f0: number;
  f1: number;
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
  if (mode === 'bus') return { kind: 'bus', color: 0xffffff };
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
  const color = k === 'keke' ? 0xe3b53c : k === 'bus' ? 0xffffff : CAR_COLORS[Math.abs(Number(ci) || 0) % CAR_COLORS.length];
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
