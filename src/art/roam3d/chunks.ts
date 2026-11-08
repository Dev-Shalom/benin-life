// Free roam: the world cut into square chunks (pure TypeScript, no three.js). Every drawable thing is listed in each chunk it
// touches; the mesh builder runs the same code for a chunk and keeps only the triangles whose centre lies inside the chunk,
// so a building on a border is split cleanly with no seam and no duplicate. Collision is NOT chunked: the whole city's static
// colliders live in one hash (a few hundred KB), so they are always complete before the player can reach them.
import { AREA } from './area';
import type { RoamWorld } from './world';

export interface ChunkData {
  cx: number;
  cy: number;
  /** Rectangle in map units. */
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  buildings: number[];
  /** Index into W.trees (the tree stands inside this chunk). */
  trees: number[];
  lamps: number[];
  parked: number[];
  stalls: number[];
  displays: number[];
  kiosks: number[];
  edge: number[];
  walls: number[];
  /** Places with an arch / gate in the chunk. */
  places: number[];
  /** Road segments: ri * 100000 + sample index. */
  roadSegs: number[];
  /** Landmark keys anchored in the chunk. */
  landmarks: string[];
}

export interface ChunkIndex {
  size: number;
  cols: number;
  rows: number;
  list: ChunkData[];
  /** Chunk by column / row (null outside). */
  get(cx: number, cy: number): ChunkData | null;
  /** Chunk containing a map point (clamped to the grid). */
  at(x: number, y: number): ChunkData;
}

export function indexChunks(W: RoamWorld, size: number): ChunkIndex {
  const cols = Math.ceil((AREA.x1 - AREA.x0) / size);
  const rows = Math.ceil((AREA.y1 - AREA.y0) / size);
  const list: ChunkData[] = [];
  for (let cy = 0; cy < rows; cy++)
    for (let cx = 0; cx < cols; cx++)
      list.push({
        cx, cy, x0: AREA.x0 + cx * size, y0: AREA.y0 + cy * size, x1: AREA.x0 + (cx + 1) * size, y1: AREA.y0 + (cy + 1) * size,
        buildings: [], trees: [], lamps: [], parked: [], stalls: [], displays: [], kiosks: [], edge: [], walls: [], places: [], roadSegs: [], landmarks: [],
      });
  const ci = (x: number) => Math.max(0, Math.min(cols - 1, Math.floor((x - AREA.x0) / size)));
  const cj = (y: number) => Math.max(0, Math.min(rows - 1, Math.floor((y - AREA.y0) / size)));
  const at = (x: number, y: number) => list[cj(y) * cols + ci(x)];
  const eachRect = (x0: number, y0: number, x1: number, y1: number, f: (c: ChunkData) => void) => {
    for (let j = cj(y0); j <= cj(y1); j++) for (let i = ci(x0); i <= ci(x1); i++) f(list[j * cols + i]);
  };
  W.buildings.forEach((b, i) => {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of b.poly) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    // pitched roofs overhang, doors have awnings and signs: grow a little
    eachRect(x0 - 1.6, y0 - 1.6, x1 + 1.6, y1 + 1.6, (c) => c.buildings.push(i));
  });
  W.trees.forEach((t, i) => at(t.x, t.y).trees.push(i));
  W.lamps.forEach((l, i) => at(l[0], l[1]).lamps.push(i));
  W.parked.forEach((p, i) => eachRect(p.x - 3, p.y - 3, p.x + 3, p.y + 3, (c) => c.parked.push(i)));
  W.stalls.forEach((s, i) => eachRect(s.x - 3, s.y - 3, s.x + 3, s.y + 3, (c) => c.stalls.push(i)));
  W.displays.forEach((d, i) => at(d.x, d.y).displays.push(i));
  W.kiosks.forEach((k, i) => eachRect(k.x - 3, k.y - 3, k.x + 3, k.y + 3, (c) => c.kiosks.push(i)));
  W.edge.forEach((e, i) => at(e.x, e.y).edge.push(i));
  W.walls.forEach((w, i) => eachRect(w.x - w.len / 2, w.y - w.len / 2, w.x + w.len / 2, w.y + w.len / 2, (c) => c.walls.push(i)));
  W.places.forEach((p, i) => {
    if (p.door.kind === 'arch' || p.door.kind === 'gate') eachRect(p.door.x - 6, p.door.y - 6, p.door.x + 6, p.door.y + 6, (c) => c.places.push(i));
  });
  for (const ri of W.roadIdx) {
    const S = W.L.roads[ri].sp.samples;
    for (let i = 0; i < S.length; i++) {
      const a = S[i], b = S[(i + 1) % S.length];
      const rd = W.L.roads[ri];
      if (!rd.closed && i === S.length - 1) break;
      const pad = rd.hw + 4;
      eachRect(Math.min(a.x, b.x) - pad, Math.min(a.y, b.y) - pad, Math.max(a.x, b.x) + pad, Math.max(a.y, b.y) + pad, (c) => c.roadSegs.push(ri * 100000 + i));
    }
  }
  for (const a of W.lmAnchors) at(a.x, a.y).landmarks.push(a.key);
  return { size, cols, rows, list, get: (cx, cy) => (cx < 0 || cy < 0 || cx >= cols || cy >= rows ? null : list[cy * cols + cx]), at };
}
