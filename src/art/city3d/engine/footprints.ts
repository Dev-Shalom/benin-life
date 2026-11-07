// Ground footprints (map space) of the landmark models drawn by buildLandmarks() in build.ts, and of the motor-park
// layout. Pure numbers: the layout keeps houses / trees / traffic off them and scripts/city-check.mjs audits them.
// Sizes are the model sizes in world units x 10. Keep in step with build.ts when a landmark model changes.
import { GROVE, MARKETS, PALACE, RUNWAY, STADIUM, TECH_HUB, TERMINAL, type Pt } from '../../map/mapGeo';
import { rectCorners } from './geom';

export interface Footprint {
  id: string;
  poly: Pt[];
}

const rect = (id: string, x: number, y: number, w: number, d: number, a = 0): Footprint => ({ id: 'landmark ' + id, poly: rectCorners(x, y, w, d, a) });
const disc = (id: string, x: number, y: number, r: number): Footprint => ({
  id: 'landmark ' + id,
  poly: Array.from({ length: 16 }, (_, k) => [x + Math.cos((k / 16) * Math.PI * 2) * r, y + Math.sin((k / 16) * Math.PI * 2) * r] as Pt),
});

/** Iguobazuwa farm huts (build.ts draws one round hut at each spot). */
export const FARM_HUTS: readonly (readonly [number, number])[] = [[50, 290], [95, 330], [38, 372]];

const ang = Math.atan2(RUNWAY.y2 - RUNWAY.y1, RUNWAY.x2 - RUNWAY.x1);
/** A box in a landmark's own frame: (ox, oy) is the frame origin, `yaw` the builder's Y rotation, lx / lz the box centre in the frame (map units). */
const local = (id: string, ox: number, oy: number, yaw: number, lx: number, lz: number, w: number, d: number): Footprint => {
  const a = -yaw;
  return rect(id, ox + lx * Math.cos(a) - lz * Math.sin(a), oy + lx * Math.sin(a) + lz * Math.cos(a), w, d, a);
};

/** Footprints of the fixed landmark models (not the motor parks: those move to clear ground, see `padLayout`). */
export const MODEL_FOOTPRINTS: Footprint[] = [
  disc('national museum', 500, 500, 11.5),
  { id: 'landmark oba palace compound', poly: PALACE.map((p) => [p[0], p[1]] as Pt) },
  rect('uniben senate block', 497, 118, 7.6, 6),
  local('uniben gate', 476, 128, Math.PI / 2 - 0.15, 0, 0, 2, 13),
  local('stadium west stand', STADIUM.x, STADIUM.y, 0, -19.5, 0, 2, 16),
  local('stadium east stand', STADIUM.x, STADIUM.y, 0, 19.5, 0, 2, 16),
  local('ubth', 421, 170, 0, 0, 4.4, 22, 16.4),
  local('bronze tech hub', TECH_HUB.x, TECH_HUB.y, 0.1, 0, 2, 22, 19),
  local('police hq', 497, 610, 0, 1, 1, 16, 11),
  local('airport terminal', TERMINAL.x, TERMINAL.y, -ang, -3, 1.5, 22, 14),
  disc('baba shrine', GROVE.x + 3, GROVE.y + 2, 5),
  ...FARM_HUTS.map(([x, y], i) => disc('farm hut ' + i, x, y, 4.3)),
  ...MARKETS.flatMap(([x, y, r, id]) => {
    const l = (id === 'oba_market' ? 2.0 : 1.2) * (r / 22) * 12;
    const out = [local('market ' + id, x, y, 0.15, 0, 0, l + 1, 7.5)];
    if (id === 'oba_market') out.push(local('market oba_market annex', x, y, 0.15, 2, 10, 13, 6.5));
    return out;
  }),
];

/** Motor park pads as listed in the seed (centre x, y and radius, map units). They are moved to clear ground by the layout. */
export const PAD_SEEDS: readonly (readonly [number, number, number])[] = [
  [452, 282, 13],
  [398, 52, 12],
  [705, 400, 10],
  [828, 352, 12],
];

export const BUS: readonly [number, number] = [5.2, 2.4];

/** Everything standing on a motor park pad: two rows of parked danfos and the red shelter roof. */
export function padLayout(px: number, py: number, pr: number) {
  const n = Math.round(pr * 0.7);
  const slots: { x: number; y: number; a: number }[] = [];
  for (let k = 0; k < n; k++) slots.push({ x: px - pr * 0.55 + Math.floor(k / 2) * 4.4, y: py - 3 + (k % 2) * 6.5, a: Math.PI / 2 });
  const parts: Pt[][] = slots.map((s) => rectCorners(s.x, s.y, BUS[0], BUS[1], s.a));
  // shelter roof (build.ts: a box pr*0.14 wide and 0.45 deep in world units, set pr*0.55 south of the centre)
  const shelter = rectCorners(px, py + pr * 0.55, pr * 1.4, 4.5, 0);
  parts.push(shelter);
  return { slots, parts, shelter };
}
