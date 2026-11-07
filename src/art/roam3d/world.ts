// Free roam: the walkable world as plain data (no three.js). Built from the SAME layout as the 3D city map
// (src/art/city3d/engine/layout.ts: roads, houses, OSM footprints, landmarks, trees, lamps, parked vehicles), cropped to
// the phase-1 area, plus the street-scale extras (place doors, stalls, kiosks, edge fence), the collision world and the
// two walking grids (free walking and the GPS grid that prefers pavements).
// scripts/roam-collide-check.mjs loads this file in node and fires random moves at the real colliders.
import { at, MARKETS, PALACE, rng, type Pt } from '../map/mapGeo';
import { getCityLayout, snapPlace, VEHICLE_SIZE, type CityLayout } from '../city3d/engine/layout';
import { MODEL_FOOTPRINTS, padLayout } from '../city3d/engine/footprints';
import { pointInPoly, polysOverlap, rectCorners } from '../city3d/engine/geom';
import { KERB } from '../city3d/engine/roadnet';
import { blockRect, makeGrid, type NavGrid } from '../sim/nav';
import { shortName } from '../map/mapGeo';
import { AREA, BACKDROP, MARGIN, PLAYER_R, inArea, type PlaceIn } from './area';
import { CollisionWorld, inPoly, obbCorners } from './collide';

export interface Door {
  kind: 'wall' | 'arch' | 'kiosk';
  /** Door / arch centre (on the wall, between the arch posts, at the kiosk window). */
  x: number;
  y: number;
  /** Outward normal: the way the door faces (towards the street). */
  nx: number;
  ny: number;
  /** Where the player stands to use it. */
  sx: number;
  sy: number;
  /** Opening width (m). */
  w: number;
  /** Building index (wall doors). */
  b: number;
  /** Edge index (wall doors). */
  e: number;
}

export interface RoamPlace extends PlaceIn {
  label: string;
  accent: string;
  door: Door;
}

export interface RoamBuilding {
  poly: Pt[];
  /** Wall height (m). */
  h: number;
  wall: string;
  roof: string;
  roofType: 'flat' | 'hip' | 'gable';
  /** Oriented box (houses) for pitched roofs. */
  rect: { x: number; y: number; w: number; d: number; a: number } | null;
  lit: boolean;
  osm: boolean;
  /** Index of the place whose door is on this building (-1 none). */
  place: number;
  /** Edge that carries the door (every building gets one) and where along it (0..1). */
  doorEdge: number;
  doorT: number;
  /** Detail level: 0 = backdrop (no windows), 1 = street scale. */
  detail: 0 | 1;
  /** A landmark model drawn by buildLandmarks: only its door and sign are added. */
  lm?: boolean;
}

export interface Stall {
  x: number;
  y: number;
  a: number;
  w: number;
  d: number;
  color: string;
  /** A seller stands behind the counter. */
  seller: boolean;
  /** Unit vector pointing from the counter to the customer side. */
  fx: number;
  fy: number;
}

export interface EdgeProp {
  x: number;
  y: number;
  a: number;
  kind: 'fence' | 'barrier';
}

export interface RoamWorld {
  L: CityLayout;
  col: CollisionWorld;
  places: RoamPlace[];
  buildings: RoamBuilding[];
  /** Landmark pieces to draw with buildLandmarks (keys). */
  landmarks: string[];
  trees: { x: number; y: number; r: number; c: number; palm: boolean }[];
  lamps: [number, number][];
  parked: { x: number; y: number; a: number; kind: 'car' | 'bus' | 'keke'; color: string }[];
  stalls: Stall[];
  kiosks: { x: number; y: number; a: number; placeIdx: number }[];
  edge: EdgeProp[];
  walk: NavGrid;
  gps: NavGrid;
  /** Roads touching the region (indices into L.roads). */
  roadIdx: number[];
  /** Detail box (walkable box + MARGIN) and backdrop box. */
  box: [number, number, number, number];
  far: [number, number, number, number];
}

const dist = (ax: number, ay: number, bx: number, by: number) => Math.hypot(ax - bx, ay - by);
const GROUND_PAD = 0.28; // extra clearance the walking grids keep from colliders (on top of the player radius)

const ACCENT: Record<string, string> = {
  buka: '#c0643f', salon: '#5c7fb5', cyber: '#3f7f9c', pos: '#2e9d58', club: '#6a5a8a', lounge: '#6a5a8a', bank: '#2f6f55',
  hospital: '#c0392b', police: '#1d4f9c', market: '#d9822b', museum: '#8d6a3a', palace: '#a8702f', workshop: '#b5552b',
  office: '#3d5f80', street: '#7a6a52', motorpark: '#d6b02c', mall: '#7a4ac8', hotel: '#3d5f80',
};

let cache: { key: string; w: RoamWorld } | null = null;

export function getRoamWorld(places: PlaceIn[]): RoamWorld {
  const key = places.map((p) => `${p.id}:${p.x}:${p.y}`).join('|');
  if (cache && cache.key === key) return cache.w;
  const w = buildRoamWorld(places);
  cache = { key, w };
  return w;
}

export function buildRoamWorld(placesIn: PlaceIn[]): RoamWorld {
  const L = getCityLayout();
  const box: [number, number, number, number] = [AREA.x0 - MARGIN, AREA.y0 - MARGIN, AREA.x1 + MARGIN, AREA.y1 + MARGIN];
  const far: [number, number, number, number] = [box[0] - BACKDROP, box[1] - BACKDROP, box[2] + BACKDROP, box[3] + BACKDROP];
  const inBox = (x: number, y: number, pad = 0) => x >= box[0] - pad && x <= box[2] + pad && y >= box[1] - pad && y <= box[3] + pad;
  const inFar = (x: number, y: number, pad = 0) => x >= far[0] - pad && x <= far[2] + pad && y >= far[1] - pad && y <= far[3] + pad;
  const R = rng(20261120);
  const col = new CollisionWorld();
  col.bounds = [AREA.x0, AREA.y0, AREA.x1, AREA.y1];

  /* ---------------- buildings (houses + OSM) ---------------- */
  const buildings: RoamBuilding[] = [];
  const addBuilding = (b: Omit<RoamBuilding, 'place' | 'doorEdge' | 'doorT'>) => {
    const i = buildings.push({ ...b, place: -1, doorEdge: -1, doorT: 0.5 }) - 1;
    if (b.detail === 1 && !b.lm) col.addPoly(b.poly, { tall: true, id: (b.osm ? 'osm ' : 'house ') + i, h: b.h + 1.5 });
    return i;
  };
  const polyIn = (poly: readonly Pt[], pad: number, f: (x: number, y: number, p: number) => boolean) => poly.some((p) => f(p[0], p[1], pad));
  for (const b of L.buildings) {
    if (!inFar(b.x, b.y)) continue;
    const poly = rectCorners(b.x, b.y, b.w, b.d, b.a);
    const detail = polyIn(poly, 0, inBox) ? 1 : 0;
    addBuilding({
      poly, h: Math.min(26, Math.max(3.2, b.h * 10)), wall: b.wall, roof: b.roof, roofType: b.roofType,
      rect: { x: b.x, y: b.y, w: b.w, d: b.d, a: b.a }, lit: b.lit, osm: false, detail,
    });
  }
  for (const o of L.osmBuildings) {
    const poly = o.ring as Pt[];
    if (!poly.some((p) => inFar(p[0], p[1]))) continue;
    const detail = polyIn(poly, 0, inBox) ? 1 : 0;
    addBuilding({ poly, h: Math.min(32, Math.max(3.2, o.h * 10)), wall: o.wall, roof: o.roof, roofType: 'flat', rect: null, lit: true, osm: true, detail });
  }

  /* ---------------- landmark footprints ---------------- */
  const landmarks: string[] = [];
  const lmWanted: [string, string, number, number, number][] = [
    ['museum', '', 500, 500, 60],
    ['palace', '', 405, 503, 40],
    ['police', '', 497, 610, 25],
  ];
  for (const [k, , x, y, rad] of lmWanted) if (inBox(x, y, rad)) landmarks.push(k);
  for (const [mx, my, mr, id] of MARKETS) if (inBox(mx, my, mr)) landmarks.push('market:' + id);
  const museumR = 10.9;
  col.addCircle(500, 500, museumR, { tall: true, id: 'national museum', h: 9 });
  for (const f of MODEL_FOOTPRINTS) {
    if (f.id === 'landmark national museum') continue;
    if (!f.poly.some((p) => inBox(p[0], p[1], 6))) continue;
    col.addPoly(f.poly as Pt[], { tall: true, id: f.id, h: f.id.includes('palace') ? 9 : f.id.includes('police') ? 8 : 5 });
    // walls that can carry a door: the police HQ and the palace compound
    if (f.id === 'landmark police hq' || f.id === 'landmark oba palace compound') {
      addBuilding({ poly: f.poly as Pt[], h: f.id.includes('palace') ? 3 : 7, wall: '#eef2f7', roof: '#1d4f9c', roofType: 'flat', rect: null, lit: false, osm: false, detail: 1, lm: true });
    }
  }
  for (const pad of L.pads) {
    if (!inBox(pad.x, pad.y, 20)) continue;
    const lay = padLayout(pad.x, pad.y, pad.r);
    lay.parts.slice(0, -1).forEach((p, i) => col.addPoly(p as Pt[], { tall: false, id: 'parked bus ' + i }));
  }

  /* ---------------- trees, lamps, parked vehicles ---------------- */
  const trees = L.trees.filter((t) => inFar(t.x, t.y, 4));
  for (const t of trees) if (inBox(t.x, t.y, 2)) col.addCircle(t.x, t.y, t.palm ? 0.22 : 0.32, { tall: true, id: 'tree', h: t.palm ? 7 : 3.5 });
  const lamps = L.lamps.filter((l) => inBox(l[0], l[1], 2));
  for (const l of lamps) col.addCircle(l[0], l[1], 0.14, { tall: true, id: 'lamp' });
  const parked: RoamWorld['parked'] = [];
  for (const v of L.vehicles) {
    if (v.px === undefined || !inBox(v.px, v.py!, 6)) continue;
    const [len, wid] = VEHICLE_SIZE[v.kind];
    parked.push({ x: v.px, y: v.py!, a: v.pa!, kind: v.kind, color: v.color });
    col.addObb(v.px, v.py!, len, wid, v.pa!, { tall: false, id: 'parked ' + v.kind });
  }

  col.build(6);

  /* ---------------- roads touching the box ---------------- */
  const roadIdx: number[] = [];
  L.roads.forEach((r, i) => {
    if (r.sp.samples.some((s) => inFar(s.x, s.y))) roadIdx.push(i);
  });

  /* ---------------- helpers on the finished statics ---------------- */
  const onCarriage = (x: number, y: number, m = 0.2) => L.net.clear(x, y, false, 2) < m;
  const onPaved = (x: number, y: number, m = 0.2) => L.net.clear(x, y, true, 2) < m;
  const nearestRoad = (x: number, y: number): { dx: number; dy: number } => {
    // direction (unit) from the point to the nearest road centre line sample
    let best = Infinity, bx = 0, by = 0;
    for (const ri of roadIdx) {
      for (const s of L.roads[ri].sp.samples) {
        const d = (s.x - x) ** 2 + (s.y - y) ** 2;
        if (d < best) { best = d; bx = s.x; by = s.y; }
      }
    }
    const d = Math.sqrt(best) || 1;
    return { dx: (bx - x) / d, dy: (by - y) / d };
  };
  const spotFree = (x: number, y: number, rad: number) => col.clear(x, y, rad, -1, false) && inArea(x, y, 0.8);

  /* ---------------- stalls around the markets ---------------- */
  const stalls: Stall[] = [];
  const STALL_COL = ['#2f6fd0', '#d63c32', '#f2b632', '#2e9d58', '#e06a1c', '#7a4ac8', '#1aa3a3'];
  for (const [mx, my, mr, id] of MARKETS) {
    if (!inBox(mx, my, 4)) continue;
    const target = id === 'oba_market' ? 26 : 14;
    let tries = 0;
    while (stalls.filter((s) => dist(s.x, s.y, mx, my) < mr + 6).length < target && tries++ < 400) {
      const ang = R() * Math.PI * 2;
      const rr = mr * (0.35 + R() * 0.75);
      const x = mx + Math.cos(ang) * rr;
      const y = my + Math.sin(ang) * rr;
      if (!inArea(x, y, 3)) continue;
      // the counter faces the market centre or away: rows around the sheds
      const a = Math.round((ang + Math.PI / 2) / (Math.PI / 4)) * (Math.PI / 4);
      const poly = rectCorners(x, y, 2.4, 1.6, a);
      if (L.fp.query(x - 3, y - 3, x + 3, y + 3).some((i) => polysOverlap(L.fp.items[i].poly, rectCorners(x, y, 3.2, 2.4, a)))) continue;
      if (polyIn(poly, 0, (px, py) => onPaved(px, py, 1.4))) continue;
      if (stalls.some((s) => dist(s.x, s.y, x, y) < 3.4)) continue;
      if (col.circs.some((c) => dist(c.x, c.y, x, y) < c.r + 1.8)) continue;
      if (col.polys.some((p) => polysOverlap(p.pts, rectCorners(x, y, 3.2, 2.4, a)))) continue;
      const fx = -Math.sin(a);
      const fy = Math.cos(a);
      stalls.push({ x, y, a, w: 1.8, d: 0.9, color: STALL_COL[Math.floor(R() * STALL_COL.length)], seller: R() < 0.8, fx, fy });
      col.addObb(x, y, 1.8, 0.9, a, { tall: false, id: 'stall' });
    }
  }

  /** Rasterise every collider into a walking grid (cells within the player's radius + a margin are blocked). */
  function rasterGrid(): NavGrid {
    const cell = 0.5;
    const g = makeGrid([AREA.x0, AREA.y0, AREA.x1, AREA.y1], cell);
    const pad = PLAYER_R + GROUND_PAD;
    for (const pl of col.polys) {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (const [x, y] of pl.pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
      if (x1 < AREA.x0 - 2 || x0 > AREA.x1 + 2 || y1 < AREA.y0 - 2 || y0 > AREA.y1 + 2) continue;
      for (let cy = Math.floor((y0 - pad - AREA.y0) / cell); cy <= Math.floor((y1 + pad - AREA.y0) / cell); cy++)
        for (let cx = Math.floor((x0 - pad - AREA.x0) / cell); cx <= Math.floor((x1 + pad - AREA.x0) / cell); cx++) {
          if (cx < 0 || cy < 0 || cx >= g.cols || cy >= g.rows) continue;
          const px = AREA.x0 + (cx + 0.5) * cell, py = AREA.y0 + (cy + 0.5) * cell;
          if (cellHits(pl.pts, px, py, pad)) g.blocked[cy * g.cols + cx] = 1;
        }
    }
    for (const c of col.circs) blockRect(g, c.x - c.r, c.y - c.r, c.x + c.r, c.y + c.r, pad);
    return g;
  }
  /** Cells connected to the main street network (flood fill from the Ring Road). */
  function floodMain(g: NavGrid): Uint8Array {
    const seen = new Uint8Array(g.blocked.length);
    let start = -1;
    for (let y = 440; y > 400 && start < 0; y -= 1) {
      const c = Math.floor((500 - AREA.x0) / g.cell), r = Math.floor((y - AREA.y0) / g.cell);
      if (!g.blocked[r * g.cols + c]) start = r * g.cols + c;
    }
    if (start < 0) return seen;
    const q = [start];
    seen[start] = 1;
    for (let h = 0; h < q.length; h++) {
      const i = q[h];
      const c = i % g.cols, r = (i / g.cols) | 0;
      for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nc = c + dc, nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= g.cols || nr >= g.rows) continue;
        const ni = nr * g.cols + nc;
        if (seen[ni] || g.blocked[ni]) continue;
        seen[ni] = 1;
        q.push(ni);
      }
    }
    return seen;
  }
  let mainNet: { g: NavGrid; seen: Uint8Array } | null = null;
  /** The stand spot can be reached from the street network. */
  const connected = (x: number, y: number): boolean => {
    if (!mainNet) {
      const g = rasterGrid();
      mainNet = { g, seen: floodMain(g) };
    }
    const g = mainNet.g;
    const c = Math.floor((x - AREA.x0) / g.cell), r = Math.floor((y - AREA.y0) / g.cell);
    if (c < 0 || r < 0 || c >= g.cols || r >= g.rows) return false;
    // the spot itself may sit just inside a blocked cell (it is only 0.6 m from a wall): accept a free neighbour
    for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
      const nc = c + dc, nr = r + dr;
      if (nc >= 0 && nr >= 0 && nc < g.cols && nr < g.rows && mainNet.seen[nr * g.cols + nc]) return true;
    }
    return false;
  };

  /* ---------------- places: doors ---------------- */
  const places: RoamPlace[] = [];
  const kiosks: RoamWorld['kiosks'] = [];
  const inside = placesIn.filter((p) => inArea(p.x, p.y)).sort((a, b) => a.id.localeCompare(b.id));
  const wallPlaces = new Set(['buka', 'salon', 'cyber', 'bank', 'hospital', 'police', 'workshop', 'office', 'palace', 'mall', 'hotel', 'club', 'lounge', 'cinema', 'car_dealer']);
  for (const p of inside) {
    const snapped = snapPlace(L, p.x, p.y, true);
    const label = shortName(p.id, p.name);
    const accent = ACCENT[p.scene] ?? '#7a6a52';
    let door: Door | null = null;
    if (wallPlaces.has(p.scene) || p.scene.startsWith('home_')) {
      door = wallDoor(snapped.x, snapped.y, p.scene === 'palace' ? 2.0 : 1.1);
      if (!door) door = shopAt(snapped.x, snapped.y, p.scene === 'buka' ? '#e8d3a8' : '#eadfc8', p.scene === 'buka' ? '#b5583a' : '#8f979c');
    }
    if (!door && p.scene === 'museum') door = archAt(500, 500 + 11.9, 0, 1, 6.2, 'arch');
    if (!door && p.scene === 'market') {
      const m = MARKETS.find((q) => q[3] === p.id);
      if (m) {
        const dx = snapped.x - m[0], dy = snapped.y - m[1];
        const dd = Math.hypot(dx, dy) || 1;
        const ux = dx / dd, uy = dy / dd;
        // the entrance arch stands where the stalls end, on the side facing the marker
        const rr = Math.min(dd, m[2] + 3);
        door = archAt(m[0] + ux * rr, m[1] + uy * rr, ux, uy, 5.0, 'arch');
      }
    }
    if (!door) {
      // PoS stands, street corners and anything without a wall of its own: a kiosk with a window on the pavement
      door = kioskAt(snapped.x, snapped.y, places.length);
    }
    if (!door) continue;
    const idx = places.push({ ...p, label, accent, door }) - 1;
    if (door.kind === 'wall') buildings[door.b].place = idx;
  }

  function wallDoor(mx: number, my: number, width: number): Door | null {
    let best: { score: number; door: Door } | null = null;
    const near = L.fp.query(mx - 20, my - 20, mx + 20, my + 20);
    const polyOf = (i: number) => L.fp.items[i].poly as Pt[];
    for (let bi = 0; bi < buildings.length; bi++) {
      const b = buildings[bi];
      if (b.detail !== 1 || b.place >= 0) continue;
      if (!b.poly.some((q) => dist(q[0], q[1], mx, my) < 22)) continue;
      const sgn = signedArea(b.poly) > 0 ? 1 : -1;
      for (let e = 0; e < b.poly.length; e++) {
        const a = b.poly[e], c = b.poly[(e + 1) % b.poly.length];
        const len = dist(a[0], a[1], c[0], c[1]);
        if (len < width + 1.8) continue;
        const ex = (c[0] - a[0]) / len, ey = (c[1] - a[1]) / len;
        const nx = (sgn * ey), ny = (-sgn * ex);
        let t = ((mx - a[0]) * ex + (my - a[1]) * ey) / len;
        const margin = (width / 2 + 0.7) / len;
        t = Math.max(margin, Math.min(1 - margin, t));
        const qx = a[0] + (c[0] - a[0]) * t, qy = a[1] + (c[1] - a[1]) * t;
        const stand = [qx + nx * 1.1, qy + ny * 1.1];
        if (!spotFree(stand[0], stand[1], PLAYER_R + 0.15) || !connected(stand[0], stand[1])) continue;
        // the door must not be hidden by a neighbouring building right in front of it
        if (!col.clear(qx + nx * 1.9, qy + ny * 1.9, 0.4, -1, false)) continue;
        let score = dist(qx, qy, mx, my) + (onCarriage(stand[0], stand[1], 0.3) ? 40 : 0);
        const road = nearestRoad(qx, qy);
        score += (1 - (road.dx * nx + road.dy * ny)) * 5;
        if (!best || score < best.score) best = { score, door: { kind: 'wall', x: qx, y: qy, nx, ny, sx: stand[0], sy: stand[1], w: width, b: bi, e } };
      }
    }
    void near;
    void polyOf;
    return best && best.score < 70 ? best.door : null;
  }

  function archAt(x: number, y: number, nx: number, ny: number, width: number, kind: 'arch'): Door | null {
    // look for clear ground at / near the wanted spot
    for (let r = 0; r <= 14; r += 1) {
      for (let k = 0; k < (r === 0 ? 1 : 12); k++) {
        const a = (k / 12) * Math.PI * 2;
        const px = x + Math.cos(a) * r, py = y + Math.sin(a) * r;
        const sx = px + nx * 0.6, sy = py + ny * 0.6;
        // posts at both sides (perpendicular to the facing), stand in the middle
        const lx = -ny, ly = nx;
        const p1 = [px + lx * (width / 2), py + ly * (width / 2)];
        const p2 = [px - lx * (width / 2), py - ly * (width / 2)];
        if (!spotFree(sx, sy, 0.5) || !spotFree(px, py, 0.5) || !spotFree(p1[0], p1[1], 0.5) || !spotFree(p2[0], p2[1], 0.5) || !connected(sx, sy)) continue;
        if (onCarriage(px, py, 0.8)) continue;
        col.addCircle(p1[0], p1[1], 0.16, { tall: true, id: 'arch post' });
        col.addCircle(p2[0], p2[1], 0.16, { tall: true, id: 'arch post' });
        return { kind, x: px, y: py, nx, ny, sx, sy, w: width, b: -1, e: -1 };
      }
    }
    return null;
  }

  function kioskAt(x: number, y: number, placeIdx: number): Door | null {
    for (let r = 0; r <= 24; r += 1) {
      for (let k = 0; k < (r === 0 ? 1 : 16); k++) {
        const ang = (k / 16) * Math.PI * 2;
        const px = x + Math.cos(ang) * r, py = y + Math.sin(ang) * r;
        const road = nearestRoad(px, py);
        const nx = road.dx, ny = road.dy;
        const a = Math.atan2(ny, nx) - Math.PI / 2; // long side across the facing
        const poly = obbCorners(px, py, 2.4, 1.8, a);
        if (poly.some((q) => !inArea(q[0], q[1], 1) || onCarriage(q[0], q[1], 0.5))) continue;
        if (!col.clear(px, py, 1.6, -1, false)) continue;
        const sx = px + nx * 1.7, sy = py + ny * 1.7;
        if (!spotFree(sx, sy, 0.5) || !connected(sx, sy)) continue;
        col.addObb(px, py, 2.4, 1.8, a, { tall: true, id: 'kiosk' });
        kiosks.push({ x: px, y: py, a, placeIdx });
        return { kind: 'kiosk', x: px + nx * 0.9, y: py + ny * 0.9, nx, ny, sx, sy, w: 1.2, b: -1, e: -1 };
      }
    }
    return null;
  }

  /** No building of its own near the marker: put up a small shop on clear ground beside the road, door to the street. */
  function shopAt(x: number, y: number, wall: string, roof: string): Door | null {
    for (let r = 0; r <= 26; r += 1.5) {
      for (let k = 0; k < (r === 0 ? 1 : 16); k++) {
        const ang = (k / 16) * Math.PI * 2;
        const px = x + Math.cos(ang) * r, py = y + Math.sin(ang) * r;
        const road = nearestRoad(px, py);
        const nx = road.dx, ny = road.dy;
        const a = Math.atan2(ny, nx) - Math.PI / 2;
        const poly = obbCorners(px, py, 7.6, 5.6, a);
        if (poly.some((q) => !inArea(q[0], q[1], 1.5) || onPaved(q[0], q[1], 0.5))) continue;
        let ok = true;
        for (let u = -4.4; u <= 4.4 && ok; u += 1.1)
          for (let v = -3.4; v <= 3.4 && ok; v += 1.1) {
            const qx = px + Math.cos(a) * u - Math.sin(a) * v, qy = py + Math.sin(a) * u + Math.cos(a) * v;
            if (!col.clear(qx, qy, 0.7, -1, false)) ok = false;
          }
        if (!ok) continue;
        const sx = px + nx * 4.2, sy = py + ny * 4.2;
        if (!spotFree(sx, sy, 0.5) || !connected(sx, sy)) continue;
        const bi = addBuilding({ poly, h: 3.8, wall, roof, roofType: 'gable', rect: { x: px, y: py, w: 7.6, d: 5.6, a }, lit: true, osm: false, detail: 1 });
        // the long side that faces the road carries the door: find that edge
        let bestE = 0, bestDot = -2;
        for (let e = 0; e < 4; e++) {
          const c0 = poly[e], c1 = poly[(e + 1) % 4];
          const mx = (c0[0] + c1[0]) / 2 - px, my = (c0[1] + c1[1]) / 2 - py;
          const d = (mx * nx + my * ny) / Math.hypot(mx, my);
          if (d > bestDot) { bestDot = d; bestE = e; }
        }
        const c0 = poly[bestE], c1 = poly[(bestE + 1) % 4];
        const qx = (c0[0] + c1[0]) / 2, qy = (c0[1] + c1[1]) / 2;
        return { kind: 'wall', x: qx, y: qy, nx, ny, sx: qx + nx * 1.1, sy: qy + ny * 1.1, w: 1.1, b: bi, e: bestE };
      }
    }
    return null;
  }

  /* ---------------- parked cars along the wide roads ---------------- */
  {
    const CAR_COL = ['#c8c6c0', '#2f3a4a', '#8c2f2a', '#3d5f80', '#e3dfd2', '#4a5a4c', '#a8a49a', '#1f2a36'];
    let n = 0;
    for (const ri of roadIdx) {
      const rd = L.roads[ri];
      if (rd.hw < 6) continue;
      for (let sArc = 10 + R() * 20; sArc < rd.sp.length && n < 26; sArc += 20 + R() * 45) {
        const p = at(rd.sp, sArc);
        if (!inArea(p.x, p.y, 4)) continue;
        const side = R() < 0.5 ? 1 : -1;
        const off = rd.hw - 1.2;
        const x = p.x - Math.sin(p.a) * off * side, y = p.y + Math.cos(p.a) * off * side;
        if (L.net.clear(x, y, false, 8, ri) < 4.2) continue; // not near a junction
        if (!col.clear(x, y, 1.6, -1, false) || !inArea(x, y, 2)) continue;
        if (places.some((q) => dist(q.door.sx, q.door.sy, x, y) < 6)) continue;
        const a = p.a;
        parked.push({ x, y, a, kind: 'car', color: CAR_COL[Math.floor(R() * CAR_COL.length)] });
        col.addObb(x, y, 3.8, 2.0, a, { tall: false, id: 'parked car' });
        n++;
      }
    }
  }

  /* ---------------- more street lamps along the wide roads (the map has few) ---------------- */
  {
    let side = 1;
    for (const ri of roadIdx) {
      const rd = L.roads[ri];
      if (rd.kind === 'dirt' || rd.kind === 'spur' || rd.hw < 3) continue;
      for (let sArc = 8 + R() * 10; sArc < rd.sp.length; sArc += 30) {
        const p = at(rd.sp, sArc);
        if (!inArea(p.x, p.y, 3)) continue;
        side = -side;
        const off = rd.hw + (KERB[rd.kind] ?? 1) + 0.45;
        const x = p.x - Math.sin(p.a) * off * side, y = p.y + Math.cos(p.a) * off * side;
        if (L.net.clear(x, y, false, 3) < 1.2) continue;
        if (lamps.some((q) => dist(q[0], q[1], x, y) < 14)) continue;
        if (!col.clear(x, y, 0.6, -1, false) || !inArea(x, y, 1.5)) continue;
        if (places.some((q) => dist(q.door.sx, q.door.sy, x, y) < 2.5)) continue;
        lamps.push([x, y]);
        col.addCircle(x, y, 0.14, { tall: true, id: 'lamp' });
      }
    }
  }

  /* ---------------- a door on every building ---------------- */
  buildings.forEach((b) => {
    if (b.place >= 0) {
      const d = places[b.place].door;
      b.doorEdge = d.e;
      const a = b.poly[d.e], c = b.poly[(d.e + 1) % b.poly.length];
      b.doorT = dist(a[0], a[1], d.x, d.y) / dist(a[0], a[1], c[0], c[1]);
      return;
    }
    if (b.detail !== 1) return;
    const sgn = signedArea(b.poly) > 0 ? 1 : -1;
    let bestE = -1, bestS = -Infinity;
    for (let e = 0; e < b.poly.length; e++) {
      const a = b.poly[e], c = b.poly[(e + 1) % b.poly.length];
      const len = dist(a[0], a[1], c[0], c[1]);
      if (len < 3.2) continue;
      const ex = (c[0] - a[0]) / len, ey = (c[1] - a[1]) / len;
      const nx = sgn * ey, ny = -sgn * ex;
      const mx = (a[0] + c[0]) / 2, my = (a[1] + c[1]) / 2;
      const road = nearestRoad(mx, my);
      const s = road.dx * nx + road.dy * ny + len * 0.02;
      if (s > bestS) { bestS = s; bestE = e; }
    }
    b.doorEdge = bestE;
    b.doorT = 0.35 + R() * 0.3;
  });

  /* ---------------- the fence along the edge of the area ---------------- */
  const edge: EdgeProp[] = [];
  const inset = 0.45;
  const step = 3;
  const edges: [number, number, number, number, number][] = [
    [AREA.x0 + inset, AREA.y0 + inset, AREA.x1 - inset, AREA.y0 + inset, 0],
    [AREA.x0 + inset, AREA.y1 - inset, AREA.x1 - inset, AREA.y1 - inset, 0],
    [AREA.x0 + inset, AREA.y0 + inset, AREA.x0 + inset, AREA.y1 - inset, Math.PI / 2],
    [AREA.x1 - inset, AREA.y0 + inset, AREA.x1 - inset, AREA.y1 - inset, Math.PI / 2],
  ];
  for (const [x0, y0, x1, y1, a] of edges) {
    const n = Math.floor(dist(x0, y0, x1, y1) / step);
    for (let i = 0; i <= n; i++) {
      const x = x0 + ((x1 - x0) * i) / n;
      const y = y0 + ((y1 - y0) * i) / n;
      if (!col.clear(x, y, 0.4, -1, false)) continue; // a building / tree already closes the gap
      edge.push({ x, y, a, kind: L.net.clear(x, y, true, 3) < 2.2 ? 'barrier' : 'fence' });
    }
  }

  col.build(6);

  /* ---------------- walking grids ---------------- */
  const walk = rasterGrid();
  const cell = walk.cell;
  const gps = { ...walk, blocked: new Uint8Array(walk.blocked) };
  // cross roads only at crossings (every ~45 m and at junctions) so the GPS line follows the pavements
  const allowed = new Uint8Array(walk.blocked.length);
  const markCross = (cx: number, cy: number, rad: number) => {
    for (let j = Math.floor((cy - rad - AREA.y0) / cell); j <= Math.floor((cy + rad - AREA.y0) / cell); j++)
      for (let i = Math.floor((cx - rad - AREA.x0) / cell); i <= Math.floor((cx + rad - AREA.x0) / cell); i++)
        if (i >= 0 && j >= 0 && i < walk.cols && j < walk.rows) allowed[j * walk.cols + i] = 1;
  };
  for (const ri of roadIdx) {
    const rd = L.roads[ri];
    const len = rd.sp.length;
    for (let s = 6; s < len; s += 3) {
      const p = at(rd.sp, s);
      if (!inArea(p.x, p.y, -4)) continue;
      const junction = L.net.clear(p.x, p.y, false, 1, ri) < 0;
      const isCross = junction || Math.round(s / 3) % 15 === 0;
      if (isCross) markCross(p.x, p.y, rd.hw + (KERB[rd.kind] ?? 0) + 1.2);
    }
  }
  for (let cy = 0; cy < walk.rows; cy++)
    for (let cx = 0; cx < walk.cols; cx++) {
      const i = cy * walk.cols + cx;
      if (gps.blocked[i] || allowed[i]) continue;
      const px = AREA.x0 + (cx + 0.5) * cell, py = AREA.y0 + (cy + 0.5) * cell;
      if (L.net.clear(px, py, false, 1) < -0.3) gps.blocked[i] = 1;
    }

  return { L, col, places, buildings, landmarks, trees, lamps, parked, stalls, kiosks, edge, walk, gps, roadIdx, box, far };
}

function signedArea(poly: readonly Pt[]): number {
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s;
}

/** Is a cell centre within `pad` of the polygon (inside it or near its boundary)? */
function cellHits(pts: readonly Pt[], x: number, y: number, pad: number): boolean {
  if (inPoly(x, y, pts)) return true;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const l2 = dx * dx + dy * dy;
    const t = l2 > 0 ? Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2)) : 0;
    if (Math.hypot(x - (a[0] + t * dx), y - (a[1] + t * dy)) < pad) return true;
  }
  return false;
}

export { PALACE, pointInPoly };
