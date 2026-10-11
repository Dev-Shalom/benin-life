// B1 arrange: where a piece of the player's furniture may stand. Pure data (no three.js), shared by the
// Buy sheet's arrange mode (live red tint) and scripts that generate the server's copy of the same rules
// (home_layouts in supabase/migrations/20261012000200_buy_catalogue.sql, checked by bl_furniture_check).
//
// Rules (metres, layout space, footprint = the rotated KINDS w×d around x/z):
// - in: fully inside the house rectangle 0..w × 0..d; out: fully in the yard (inside the lot, not
//   touching the house); any: one or the other; wall: inside, touching the north or west wall.
// - a SOLID piece may not overlap the house's fixtures (toilet, shower, shared stalls, generator, drum),
//   interior partitions, the clear zone inside/outside each door, or another solid piece of yours.
//   Rugs, curtains and other non-solid pieces only follow the area rule.
import { FIXED_KINDS, KINDS, LAYOUTS, type FurnitureItem, type HomeLayout, type HomeLayoutId, type Placement } from './model';

export type Rect = [number, number, number, number];

/** One D-pad nudge. */
export const GRID_STEP = 0.25;
/** Overlaps smaller than this (m) on either axis are allowed (touching pieces). */
const EPS = 0.02;
/** How close (m) a wall piece's back edge must be to the north / west wall. */
export const WALL_REACH = 0.35;

export function placementOf(kind: string): Placement {
  return KINDS[kind as keyof typeof KINDS]?.place ?? 'in';
}

/** Footprint of a kind at x/z with a quarter-turn rotation. */
export function rectOf(kind: string, x: number, z: number, rot: number): Rect {
  const k = KINDS[kind as keyof typeof KINDS];
  const q = ((rot % 4) + 4) % 4;
  const w = q % 2 ? k.d : k.w;
  const d = q % 2 ? k.w : k.d;
  return [x - w / 2, z - d / 2, x + w / 2, z + d / 2];
}

const overlaps = (a: Rect, b: Rect) => Math.min(a[2], b[2]) - Math.max(a[0], b[0]) > EPS && Math.min(a[3], b[3]) - Math.max(a[1], b[1]) > EPS;
const inside = (a: Rect, b: Rect) => a[0] >= b[0] - 1e-6 && a[1] >= b[1] - 1e-6 && a[2] <= b[2] + 1e-6 && a[3] <= b[3] + 1e-6;

export interface HomeBlocks {
  w: number;
  d: number;
  lot: Rect;
  /** Where solid pieces may not go (fixtures, partitions, door zones). */
  blocks: Rect[];
  /** The door clear zones (a subset of blocks), for the "blocking the door" message. */
  doors: Rect[];
}

/** The fixed obstacles of a layout (the server stores the same numbers in home_layouts). */
export function homeBlocks(id: HomeLayoutId): HomeBlocks {
  const L: HomeLayout = LAYOUTS[id];
  const r2 = (n: number) => Math.round(n * 100) / 100;
  const R = (a: Rect): Rect => a.map(r2) as Rect;
  const blocks: Rect[] = [];
  for (const f of L.furniture) {
    if (!FIXED_KINDS.has(f.kind) || f.kind === 'ac' || f.kind === 'clothesline') continue;
    blocks.push(R(rectOf(f.kind, f.x, f.z, f.rot ?? 0)));
  }
  for (const [x1, z1, x2, z2] of L.partitions) {
    blocks.push(R([Math.min(x1, x2) - 0.06, Math.min(z1, z2) - 0.06, Math.max(x1, x2) + 0.06, Math.max(z1, z2) + 0.06]));
  }
  const doors: Rect[] = [];
  for (const [side, a0, a1] of L.doors) {
    doors.push(R(side === 'e' ? [L.w - 0.8, a0, L.w + 0.8, a1] : [a0, L.d - 0.8, a1, L.d + 0.8]));
  }
  return { w: L.w, d: L.d, lot: L.lot, blocks: [...blocks, ...doors], doors };
}

/**
 * Why `item` can't stand where it is (null = fine). `others` = the rest of the room's own pieces.
 * Messages are the same Pidgin-light lines the server raises.
 */
export function placementIssue(layoutId: HomeLayoutId, item: Pick<FurnitureItem, 'id' | 'kind' | 'x' | 'z' | 'rot'>, others: FurnitureItem[]): string | null {
  const hb = homeBlocks(layoutId);
  const r = rectOf(item.kind, item.x, item.z, item.rot ?? 0);
  const house: Rect = [0, 0, hb.w, hb.d];
  const place = placementOf(item.kind);
  const inHouse = inside(r, house);
  const inYard = inside(r, hb.lot) && !overlaps(r, house) ;
  if (place === 'in' && !inHouse) return 'This one must stay inside the house.';
  if (place === 'out' && !inYard) return 'This one belongs outside in the compound.';
  if (place === 'any' && !inHouse && !inYard) return 'Keep it fully inside the house or fully in the compound.';
  if (place === 'wall') {
    if (!inHouse) return 'Hang it on a wall inside the house.';
    if (r[1] > WALL_REACH && r[0] > WALL_REACH) return 'Push it against the back wall to hang it.';
  }
  if (!KINDS[item.kind].solid) return null;
  for (const dz of hb.doors) if (overlaps(r, dz)) return 'You are blocking the door.';
  for (const b of hb.blocks) if (overlaps(r, b)) return 'Something is already there (wall or fixture).';
  for (const o of others) {
    if (o.id === item.id || !o.id.startsWith('own_') || !KINDS[o.kind]?.solid || (o.y ?? 0) > 0) continue;
    if (overlaps(r, rectOf(o.kind, o.x, o.z, o.rot ?? 0))) return `It is touching your ${KINDS[o.kind].label.toLowerCase()}.`;
  }
  return null;
}

/** A free starting spot for a newly bought / unstored piece: scan the area on the grid. */
export function findFreeSpot(layoutId: HomeLayoutId, kind: string, others: FurnitureItem[], prefer?: { x: number; z: number }): { x: number; z: number; rot: number } | null {
  const hb = homeBlocks(layoutId);
  const place = placementOf(kind);
  const area: Rect = place === 'out' ? hb.lot : [0, 0, hb.w, hb.d];
  const cands: { x: number; z: number; rot: number; s: number }[] = [];
  const cx = prefer?.x ?? hb.w / 2;
  const cz = prefer?.z ?? hb.d / 2;
  for (const rot of place === 'wall' ? [0, 1] : [0, 1, 2, 3]) {
    for (let x = area[0]; x <= area[2] + 1e-6; x += GRID_STEP) {
      for (let z = area[1]; z <= area[3] + 1e-6; z += GRID_STEP) {
        let px = x, pz = z;
        if (place === 'wall') {
          // hang flush: back edge on the wall (rot 0 = north wall, rot 1 = west wall)
          const k = KINDS[kind as keyof typeof KINDS];
          if (rot === 0) pz = k.d / 2; else px = k.d / 2;
        }
        const item = { id: '__new', kind: kind as FurnitureItem['kind'], x: px, z: pz, rot };
        if (!placementIssue(layoutId, item, others)) cands.push({ x: px, z: pz, rot, s: Math.hypot(px - cx, pz - cz) + rot * 0.01 });
      }
    }
  }
  cands.sort((a, b) => a.s - b.s);
  const best = cands[0];
  return best ? { x: Math.round(best.x * 1000) / 1000, z: Math.round(best.z * 1000) / 1000, rot: best.rot } : null;
}
