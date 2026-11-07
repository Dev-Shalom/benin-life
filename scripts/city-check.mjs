// Phase 0 audit of the 3D city map layout: node scripts/city-check.mjs   (Node 22+, type stripping; no dependencies)
//   -v      list more offenders      --json   print the numbers as JSON
// Loads the very layout the game builds (src/art/city3d/engine/layout.ts) and checks that the world is solid:
// nothing on the road, nothing inside anything else, traffic stays on the tarmac and out of the houses.
// Exits 1 on any violation. See docs/CITY_CHECK.md.
import { register } from 'node:module';

register(
  'data:text/javascript,' +
    encodeURIComponent(`
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && !/\\.[cm]?[jt]sx?$|\\.json$/.test(spec)) {
    try { return await next(spec + '.ts', ctx); } catch {}
  }
  return next(spec, ctx);
}
export async function load(url, ctx, next) {
  if (url.endsWith('.json')) {
    const { readFile } = await import('node:fs/promises');
    const { fileURLToPath } = await import('node:url');
    return { format: 'module', shortCircuit: true, source: 'export default ' + (await readFile(fileURLToPath(url), 'utf8')) };
  }
  return next(url, ctx);
}`),
  import.meta.url,
);

const verbose = process.argv.includes('-v');
const asJson = process.argv.includes('--json');
const layoutMod = await import('../src/art/city3d/engine/layout.ts');
const { RoadNet, KERB } = await import('../src/art/city3d/engine/roadnet.ts');
const G = await import('../src/art/city3d/engine/geom.ts');
const geo = await import('../src/art/map/mapGeo.ts');
const { DEV_LOCATIONS } = await import('../src/art/city3d/dev/fixture.ts');
const { COMING_SOON } = await import('../src/art/city3d/model.ts');

const L = layoutMod.getCityLayout();
const net = new RoadNet(L.roads);
const f1 = (n) => (Math.round(n * 10) / 10).toFixed(1);
const pos = (x, y) => `(${f1(x)}, ${f1(y)})`;

/* ------------------------------------------------------------------ footprints */
// Rendered footprint = the roof (build.ts scales hip / gable roofs by 1.08 x 1.1, flat ones by 1.03).
const gen = L.buildings.map((b, i) => {
  const k = b.roofType === 'flat' ? [1.03, 1.03] : [1.08, 1.1];
  return { id: `house#${i} ${b.st}`, poly: G.rectCorners(b.x, b.y, b.w * k[0], b.d * k[1], b.a), x: b.x, y: b.y, osm: false };
});
const osm = L.osmBuildings.map((b) => {
  const x = b.ring.reduce((s, p) => s + p[0], 0) / b.ring.length;
  const y = b.ring.reduce((s, p) => s + p[1], 0) / b.ring.length;
  return { id: `osm#${b.id}`, poly: b.ring, x, y, osm: true };
});
const all = [...gen, ...osm];
const index = new G.PolyIndex(24);
all.forEach((b, i) => index.add(b.poly, i));
const hitsAt = (x, y, pad = 0) => index.query(x - pad, y - pad, x + pad, y + pad).filter((i) => G.pointInPoly(x, y, all[i].poly));

// Landmark models drawn by buildLandmarks() (build.ts), as footprints in map units (world size x 10, yaw from at2).
const R = (id, x, y, w, d, a = 0) => ({ id: 'landmark ' + id, poly: G.rectCorners(x, y, w, d, a), x, y });
const circ = (id, x, y, r) => ({ id: 'landmark ' + id, poly: Array.from({ length: 16 }, (_, k) => [x + Math.cos((k / 16) * 6.2832) * r, y + Math.sin((k / 16) * 6.2832) * r]), x, y });
const ang = Math.atan2(geo.RUNWAY.y2 - geo.RUNWAY.y1, geo.RUNWAY.x2 - geo.RUNWAY.x1);
const landmarks = [
  circ('national museum', 500, 500, 10.5),
  { id: 'landmark oba palace compound', poly: geo.PALACE, x: 405, y: 503 },
  R('palace hall', 405, 503, 20, 13),
  R('uniben senate block', 497, 118, 7, 5.5),
  R('ubth', 421, 170, 19, 15),
  R('bronze tech hub', geo.TECH_HUB.x, geo.TECH_HUB.y, 22, 19, 0.1),
  R('police hq', 497, 610, 15, 9),
  R('airport terminal', geo.TERMINAL.x, geo.TERMINAL.y, 22, 14, -ang),
  circ('baba shrine', geo.GROVE.x + 3, geo.GROVE.y + 2, 5),
  ...geo.MARKETS.map(([x, y, r, id]) => R('market ' + id, x, y, (id === 'oba_market' ? 2.0 : 1.2) * (r / 22) * 12, 7, 0.15)),
];
const landIndex = new G.PolyIndex(24);
landmarks.forEach((m, i) => landIndex.add(m.poly, i));

/* ------------------------------------------------------------------ report plumbing */
const results = [];
const section = (title, list, describe, worstBy) => {
  const sorted = worstBy ? [...list].sort((a, b) => worstBy(b) - worstBy(a)) : list;
  results.push({ title, count: list.length });
  console.log(`\n${list.length === 0 ? 'ok  ' : 'FAIL'} ${title}: ${list.length}`);
  for (const it of sorted.slice(0, verbose ? 40 : 6)) console.log('       ' + describe(it));
  if (list.length > (verbose ? 40 : 6)) console.log(`       ... and ${list.length - (verbose ? 40 : 6)} more`);
};

console.log(`City layout: ${L.buildings.length} houses, ${L.osmBuildings.length} OSM footprints, ${L.trees.length} trees, ${L.lamps.length} lamps, ${L.vehicles.length} vehicles, ${L.roads.length} roads (${L.ms} ms)`);

/* ------------------------------------------------------------------ 1. buildings vs roads / pavement */
{
  const onRoad = [];
  const onKerb = [];
  for (const b of all) {
    let car = Infinity;
    let paved = Infinity;
    let at = null;
    for (const [x, y] of G.cover(b.poly, 1.2)) {
      const c = net.clear(x, y, false, 4);
      const p = net.clear(x, y, true, 4);
      if (c < car) car = c;
      if (p < paved) {
        paved = p;
        at = [x, y];
      }
    }
    if (car < -0.05) onRoad.push({ b, depth: -car, at });
    else if (paved < -0.05) onKerb.push({ b, depth: -paved, at });
  }
  section('buildings standing on a carriageway', onRoad, (o) => `${o.b.id} at ${pos(o.b.x, o.b.y)} is ${f1(o.depth)} units into the road (${pos(...o.at)})`, (o) => o.depth);
  section('buildings on the pavement / kerb band', onKerb, (o) => `${o.b.id} at ${pos(o.b.x, o.b.y)} is ${f1(o.depth)} units into the pavement`, (o) => o.depth);
}

/* ------------------------------------------------------------------ 2. buildings vs each other / landmarks */
{
  const pairs = [];
  for (let i = 0; i < all.length; i++) {
    const a = all[i];
    const [x0, y0, x1, y1] = index.items[i].box;
    for (const j of index.query(x0, y0, x1, y1)) {
      if (j <= i) continue;
      const b = all[j];
      if (G.polysOverlap(a.poly, b.poly)) pairs.push({ a, b, depth: G.overlapDepth(a.poly, b.poly) });
    }
  }
  const genPairs = pairs.filter((p) => !p.a.osm || !p.b.osm);
  const osmPairs = pairs.filter((p) => p.a.osm && p.b.osm);
  section('house overlaps another house or OSM footprint', genPairs, (p) => `${p.a.id} x ${p.b.id} near ${pos(p.a.x, p.a.y)} depth ${f1(p.depth)}`, (p) => p.depth);
  section('OSM footprints overlapping each other', osmPairs, (p) => `${p.a.id} x ${p.b.id} near ${pos(p.a.x, p.a.y)} depth ${f1(p.depth)}`, (p) => p.depth);
  const lm = [];
  for (const m of landmarks) {
    const bx = G.polyBox(m.poly);
    for (const j of index.query(...bx)) if (G.polysOverlap(m.poly, all[j].poly)) lm.push({ m, b: all[j] });
  }
  section('buildings overlapping a landmark model', lm, (o) => `${o.b.id} at ${pos(o.b.x, o.b.y)} inside ${o.m.id}`);
  const lroad = [];
  for (const m of landmarks) {
    let worst = Infinity;
    let at = null;
    for (const [x, y] of G.cover(m.poly, 1.5)) {
      const c = net.clear(x, y, true, 4);
      if (c < worst) {
        worst = c;
        at = [x, y];
      }
    }
    if (worst < -0.05) lroad.push({ m, depth: -worst, at });
  }
  section('landmark models on a road / pavement', lroad, (o) => `${o.m.id} at ${pos(o.m.x, o.m.y)} is ${f1(o.depth)} units into the road (${pos(...o.at)})`, (o) => o.depth);
}

/* ------------------------------------------------------------------ 3. props: trees, lamps, parked cars */
const SIZE = { car: [3.6, 2.0], bus: [5.2, 2.4], keke: [2.0, 1.5] }; // length, width in map units (build.ts SIZE x 10)
{
  const treeRoad = [];
  const treeHouse = [];
  for (const t of L.trees) {
    const c = net.clear(t.x, t.y, false, 4);
    if (c < -0.05) treeRoad.push({ t, depth: -c });
    const h = hitsAt(t.x, t.y);
    if (h.length) treeHouse.push({ t, b: all[h[0]] });
    else {
      const lm = landIndex.query(t.x, t.y, t.x, t.y).filter((j) => G.pointInPoly(t.x, t.y, landmarks[j].poly));
      if (lm.length) treeHouse.push({ t, b: landmarks[lm[0]] });
    }
  }
  section('trees / palms planted on a carriageway', treeRoad, (o) => `${o.t.palm ? 'palm' : 'tree'} at ${pos(o.t.x, o.t.y)} ${f1(o.depth)} units into the road`, (o) => o.depth);
  section('trees / palms planted inside a building', treeHouse, (o) => `${o.t.palm ? 'palm' : 'tree'} at ${pos(o.t.x, o.t.y)} inside ${o.b.id}`);

  const lampRoad = [];
  const lampHouse = [];
  for (const [x, y] of L.lamps) {
    const c = net.clear(x, y, false, 4);
    if (c < -0.05) lampRoad.push({ x, y, depth: -c });
    const h = hitsAt(x, y);
    if (h.length) lampHouse.push({ x, y, b: all[h[0]] });
  }
  section('street lamps standing on a carriageway', lampRoad, (o) => `lamp at ${pos(o.x, o.y)} ${f1(o.depth)} units into a road`, (o) => o.depth);
  section('street lamps inside a building', lampHouse, (o) => `lamp at ${pos(o.x, o.y)} inside ${o.b.id}`);

  const parkRoad = [];
  const parkHouse = [];
  const parked = L.vehicles.filter((v) => v.px !== undefined);
  const pPolys = parked.map((v) => G.rectCorners(v.px, v.py, SIZE[v.kind][0], SIZE[v.kind][1], v.pa));
  parked.forEach((v, i) => {
    let worst = Infinity;
    for (const [x, y] of G.cover(pPolys[i], 0.8)) worst = Math.min(worst, net.clear(x, y, false, 4));
    if (worst < -0.05) parkRoad.push({ v, depth: -worst });
    for (const j of index.query(...G.polyBox(pPolys[i]))) if (G.polysOverlap(pPolys[i], all[j].poly)) parkHouse.push({ v, b: all[j] });
  });
  section('parked vehicles on a carriageway', parkRoad, (o) => `parked ${o.v.kind} at ${pos(o.v.px, o.v.py)} ${f1(o.depth)} units into the road`, (o) => o.depth);
  section('parked vehicles inside a building', parkHouse, (o) => `parked ${o.v.kind} at ${pos(o.v.px, o.v.py)} overlaps ${o.b.id}`);
}

/* ------------------------------------------------------------------ 4. traffic */
{
  // same formula as build.ts placeVehicle / animate (layout.vehiclePose when the layout exports it)
  const poseOf = layoutMod.vehiclePose ?? ((roads, v, s) => {
    const rd = roads[v.road];
    const S = rd.sp.samples;
    let lo = 0;
    let hi = S.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (S[mid].s < s) lo = mid;
      else hi = mid;
    }
    const a = S[lo];
    const b = S[hi];
    const t = (s - a.s) / Math.max(1e-6, b.s - a.s);
    const px = a.x + (b.x - a.x) * t;
    const py = a.y + (b.y - a.y) * t;
    const off = rd.hw * 0.48 * v.lane;
    return { x: px - Math.sin(a.a) * off, y: py + Math.cos(a.a) * off, a: a.a + (v.lane < 0 ? Math.PI : 0) };
  });
  const moving = L.vehicles.map((v, i) => ({ v, i })).filter(({ v }) => v.px === undefined);
  const hitHouse = new Map(); // vehicle index -> {b, at}
  const offRoad = new Map();
  let samples = 0;
  const posAt = (v, i, t) => {
    const len = v.s1 - v.s0;
    if (v.jam) {
      const creep = t * v.speed * (0.5 + 0.5 * Math.sin(t * 0.7 + i));
      return v.s0 + ((((v.s - v.s0 + creep * v.lane) % len) + len) % len);
    }
    return (((v.s + t * v.speed * v.lane) % len) + len) % len;
  };
  for (const { v, i } of moving) {
    // sweep the full lane (every 1.5 units of the road it drives on)
    const rd = L.roads[v.road];
    for (let s = v.s0; s <= v.s1; s += 1.5) {
      const p = poseOf(L.roads, v, s);
      const [vl, vw] = SIZE[v.kind];
      const poly = G.rectCorners(p.x, p.y, vl, vw, p.a);
      samples++;
      for (const j of index.query(...G.polyBox(poly))) if (G.polysOverlap(poly, all[j].poly) && !hitHouse.has(i)) hitHouse.set(i, { b: all[j], at: [p.x, p.y], s, road: rd.id });
      if (!offRoad.has(i)) {
        let worst = Infinity;
        for (const [x, y] of poly) worst = Math.min(worst, -net.clear(x, y, false, 6)); // want every corner on tarmac: clear <= 0
        // a corner more than 0.3 units off the tarmac of every road
        let bad = false;
        for (const [x, y] of poly) if (net.clear(x, y, false, 6) > 0.3) bad = true;
        if (bad) offRoad.set(i, { at: [p.x, p.y], s, road: rd.id });
      }
    }
  }
  section(`traffic vehicles driving through a building (${moving.length} moving, ${samples} lane samples)`, [...hitHouse], ([i, o]) => `${L.vehicles[i].kind} on ${o.road} s=${f1(o.s)} at ${pos(...o.at)} hits ${o.b.id}`);
  section('traffic vehicles with a corner off the road surface', [...offRoad], ([i, o]) => `${L.vehicles[i].kind} on ${o.road} s=${f1(o.s)} at ${pos(...o.at)}`);

  // vehicles driving through each other (simulated over two minutes)
  const clash = new Map();
  for (let t = 0; t <= 120; t += 4) {
    const poses = moving.map(({ v, i }) => {
      const p = poseOf(L.roads, v, posAt(v, i, t));
      return { i, p, poly: G.rectCorners(p.x, p.y, SIZE[v.kind][0] * 0.9, SIZE[v.kind][1] * 0.9, p.a) };
    });
    const idx = new G.PolyIndex(12);
    poses.forEach((o, k) => idx.add(o.poly, k));
    for (let k = 0; k < poses.length; k++)
      for (const m of idx.query(...G.polyBox(poses[k].poly))) {
        if (m <= k) continue;
        const key = poses[k].i + '-' + poses[m].i;
        if (!clash.has(key) && G.polysOverlap(poses[k].poly, poses[m].poly)) clash.set(key, { a: poses[k].i, b: poses[m].i, t, at: [poses[k].p.x, poses[k].p.y] });
      }
  }
  section('traffic vehicles driving through each other (120 s simulated)', [...clash.values()], (o) => `${L.vehicles[o.a].kind} x ${L.vehicles[o.b].kind} at t=${o.t}s near ${pos(...o.at)} on ${L.roads[L.vehicles[o.a].road].id}`);
}

/* ------------------------------------------------------------------ 5. place markers */
{
  // street-type places are meant to sit on their street
  const ON_STREET = new Set(['street', 'pos', 'motorpark']);
  const inHouse = [];
  const inRoad = [];
  const pins = [...DEV_LOCATIONS.map((l) => ({ id: l.id, scene: l.scene, x: l.x, y: l.y })), ...COMING_SOON.map((c) => ({ id: c.id, scene: 'soon', x: c.x, y: c.y }))];
  for (const l of pins) {
    const h = hitsAt(l.x, l.y);
    if (h.length) inHouse.push({ l, b: all[h[0]] });
    const c = net.clear(l.x, l.y, false, 4);
    if (c < -0.05 && !ON_STREET.has(l.scene)) inRoad.push({ l, depth: -c });
  }
  section('place markers inside a building', inHouse, (o) => `${o.l.id} at ${pos(o.l.x, o.l.y)} inside ${o.b.id}`);
  section('place markers in the carriageway (non-street places)', inRoad, (o) => `${o.l.id} (${o.l.scene}) at ${pos(o.l.x, o.l.y)} ${f1(o.depth)} units into the road`, (o) => o.depth);
}

const total = results.reduce((n, r) => n + r.count, 0);
console.log(`\n${total === 0 ? 'PASS' : 'FAIL'}: ${total} violation(s) in ${results.length} checks`);
if (asJson) console.log(JSON.stringify(results));
process.exit(total === 0 ? 0 : 1);
