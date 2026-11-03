// Which kind of neighbourhood a map point is in (no three.js): the same zones and rules the 3D city layout uses to dress each
// district (city3d/engine/layout.ts `styleAt`), plus the campus and the market zones, so the drive's roadside matches the map.
import { CAMPUS, CORES, GRA_ZONE, MARKETS, UBTH, inPoly } from '../map/mapGeo';
import type { Style } from './engine/world';

const dist = (ax: number, ay: number, bx: number, by: number) => Math.hypot(ax - bx, ay - by);

/** Urban density 0..1 from the map's density cores (same formula as the layout's `urban`). */
export function urbanAt(x: number, y: number): number {
  let keep = 1;
  for (const [cx, cy, r, w] of CORES) {
    const d2 = ((x - cx) ** 2 + (y - cy) ** 2) / (r * r * 1.38);
    if (d2 < 8) keep *= 1 - w * Math.exp(-d2);
  }
  return 1 - keep;
}

export function districtAt(x: number, y: number): Style {
  if (inPoly(x, y, CAMPUS) || inPoly(x, y, UBTH) || dist(x, y, 500, 128) < 46) return 'campus';
  for (const [mx, my, r] of MARKETS) if (dist(x, y, mx, my) < r + 16) return 'market';
  if (dist(x, y, GRA_ZONE.x, GRA_ZONE.y) < GRA_ZONE.r) return 'gra';
  if (dist(x, y, 725, 700) < 85 || dist(x, y, 850, 370) < 80 || dist(x, y, 260, 570) < 90 || dist(x, y, 320, 340) < 70) return 'cramped';
  const u = urbanAt(x, y);
  if (u > 0.82 && dist(x, y, 500, 500) < 190) return 'core';
  if (u < 0.3 || x < 120 || x > 960 || y < 10 || y > 960) return 'farm';
  return 'res';
}

/** A short name for the chip / debugging. */
export const DISTRICT_LABEL: Record<Style, string> = {
  core: 'City centre',
  res: 'Residential',
  cramped: 'Crowded quarter',
  gra: 'GRA',
  campus: 'Campus',
  market: 'Market',
  farm: 'Outskirts',
};
