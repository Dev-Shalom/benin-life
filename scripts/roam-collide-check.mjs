// Free roam collision stress test: node scripts/roam-collide-check.mjs   (Node 22+, no dependencies)
//   --quick   a shorter run      --seed=N   another random seed      -v   more detail
// Loads the REAL roam world (src/art/roam3d/world.ts: the city layout's buildings, OSM footprints, landmarks, trees, lamps,
// stalls, kiosks, door posts) and the real collision code, then fires random moves at it:
//   1. static: thousands of walkers at walking, running, sprint and teleport speeds, plus hitch frames (dt 0.25 s) and moves
//      aimed straight at walls and corners. After EVERY move an independent brute-force check (not the spatial hash) asserts
//      the player is not inside any collider, keeps at least its radius from every wall / pole / trunk and is inside the area.
//   2. dynamic: a few minutes of simulated traffic and pedestrians while scripted players run at the cars; asserts no car
//      ever overlaps the player, cars never overlap each other, pedestrians never stand inside a collider.
//   3. doors and GPS: every place's standing spot is clear and reachable from every other, and the whole GPS route is walkable.
// Exits 1 on any violation. See docs/ROAM.md.
import './_roam-loader.mjs';

const quick = process.argv.includes('--quick');
const verbose = process.argv.includes('-v');
const seedArg = process.argv.find((a) => a.startsWith('--seed='));
let seed = seedArg ? Number(seedArg.slice(7)) : 424242;
const rnd = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const { buildRoamWorld } = await import('../src/art/roam3d/world.ts');
const { AREA, PLAYER_R, SPEED } = await import('../src/art/roam3d/area.ts');
const { clearance, inPoly } = await import('../src/art/roam3d/collide.ts');
const { makePlayer, stepPlayer, placePlayer } = await import('../src/art/roam3d/player.ts');
const { Traffic } = await import('../src/art/roam3d/traffic.ts');
const { Peds } = await import('../src/art/roam3d/peds.ts');
const { planRoute } = await import('../src/art/roam3d/gps.ts');
const { DEV_LOCATIONS } = await import('../src/art/city3d/dev/fixture.ts');

let t0 = performance.now();
const W = buildRoamWorld(DEV_LOCATIONS);
const col = W.col;
console.log(`world: ${W.buildings.filter((b) => b.detail).length} buildings, ${col.polys.length} polygons, ${col.segmentCount} edges, ${col.circs.length} round colliders, ${W.places.length} places, ${W.stalls.length} stalls (built in ${Math.round(performance.now() - t0)} ms)`);

let failures = 0;
const fail = (msg) => {
  failures++;
  if (failures <= 25) console.log('  FAIL ' + msg);
};

/* ---- independent exact check (own broad phase, no use of the world's hash) ---- */
const polyBox = col.polys.map((p) => {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const [x, y] of p.pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  return [x0, y0, x1, y1];
});
function segDist(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const l2 = dx * dx + dy * dy;
  const t = l2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0;
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}
function exactClearance(x, y) {
  let min = Infinity, who = '';
  for (const c of col.circs) {
    if (Math.abs(c.x - x) > 12 || Math.abs(c.y - y) > 12) continue;
    const d = Math.hypot(x - c.x, y - c.y) - c.r;
    if (d < min) { min = d; who = c.id; }
  }
  for (let i = 0; i < col.polys.length; i++) {
    const b = polyBox[i];
    if (x < b[0] - 12 || x > b[2] + 12 || y < b[1] - 12 || y > b[3] + 12) continue;
    const pts = col.polys[i].pts;
    let d = Infinity;
    for (let k = 0; k < pts.length; k++) {
      const a = pts[k], c = pts[(k + 1) % pts.length];
      d = Math.min(d, segDist(x, y, a[0], a[1], c[0], c[1]));
    }
    if (inPoly(x, y, pts)) d = -d;
    if (d < min) { min = d; who = col.polys[i].id; }
  }
  return { min, who };
}
const TOL = 0.0015;
const inBounds = (x, y) => x >= AREA.x0 + PLAYER_R - TOL && x <= AREA.x1 - PLAYER_R + TOL && y >= AREA.y0 + PLAYER_R - TOL && y <= AREA.y1 - PLAYER_R + TOL;

/* ---- random valid starting spots ---- */
function randomValid() {
  for (let i = 0; i < 500; i++) {
    const x = AREA.x0 + 1 + rnd() * (AREA.x1 - AREA.x0 - 2);
    const y = AREA.y0 + 1 + rnd() * (AREA.y1 - AREA.y0 - 2);
    if (exactClearance(x, y).min >= PLAYER_R + 0.05) return [x, y];
  }
  throw new Error('no valid spot');
}

/* ================================================================ 1. static stress */
console.log('\n1. static colliders: random fast moves');
const walkers = quick ? 600 : 2500;
const stepsEach = quick ? 400 : 700;
let moves = 0, bumps = 0, dist = 0, worst = Infinity, worstWho = '', insideCount = 0, outCount = 0;
const speeds = [SPEED.walk, SPEED.run, 9, 14, 30, 60]; // walking ... teleport-fast (60 m/s = 1 m per 60 Hz step)
const dts = [1 / 60, 1 / 60, 1 / 60, 1 / 30, 0.1, 0.25]; // hitch frames too
const nearestEdgeDir = (x, y) => {
  // direction towards the closest point of any collider within 6 m (to aim straight at walls and corners)
  let best = Infinity, tx = 0, ty = 0;
  for (let i = 0; i < col.polys.length; i++) {
    const b = polyBox[i];
    if (x < b[0] - 6 || x > b[2] + 6 || y < b[1] - 6 || y > b[3] + 6) continue;
    const pts = col.polys[i].pts;
    for (let k = 0; k < pts.length; k++) {
      const a = pts[k], c = pts[(k + 1) % pts.length];
      const dx = c[0] - a[0], dy = c[1] - a[1];
      const l2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2));
      const qx = a[0] + dx * t, qy = a[1] + dy * t;
      const d = Math.hypot(qx - x, qy - y);
      if (d < best) { best = d; tx = qx; ty = qy; }
    }
  }
  return best < 6 ? Math.atan2(ty - y, tx - x) : null;
};
t0 = performance.now();
const pos = { x: 0, y: 0 };
for (let w = 0; w < walkers; w++) {
  const [sx, sy] = randomValid();
  pos.x = sx;
  pos.y = sy;
  let ang = rnd() * Math.PI * 2;
  let sp = speeds[Math.floor(rnd() * speeds.length)];
  let dt = dts[Math.floor(rnd() * dts.length)];
  for (let s = 0; s < stepsEach; s++) {
    if (rnd() < 0.04) ang = rnd() * Math.PI * 2;
    else if (rnd() < 0.03) {
      const a = nearestEdgeDir(pos.x, pos.y);
      if (a !== null) ang = a + (rnd() - 0.5) * 0.6; // straight at a wall / corner, a little off
    }
    if (rnd() < 0.02) { sp = speeds[Math.floor(rnd() * speeds.length)]; dt = dts[Math.floor(rnd() * dts.length)]; }
    const want = sp * dt;
    const moved = col.move(pos, Math.cos(ang) * want, Math.sin(ang) * want, PLAYER_R);
    moves++;
    dist += moved;
    if (moved < want * 0.6) { bumps++; if (rnd() < 0.5) ang += (rnd() - 0.5) * 2; }
    const c = exactClearance(pos.x, pos.y);
    if (c.min < worst) { worst = c.min; worstWho = c.who; }
    if (c.min < PLAYER_R - TOL) {
      if (c.min < 0) insideCount++;
      fail(`static move ${moves}: clearance ${c.min.toFixed(4)} (< radius ${PLAYER_R}) from "${c.who}" at (${pos.x.toFixed(2)}, ${pos.y.toFixed(2)}) speed ${sp} dt ${dt.toFixed(3)}`);
    }
    if (!inBounds(pos.x, pos.y)) { outCount++; fail(`static move ${moves}: left the area at (${pos.x.toFixed(2)}, ${pos.y.toFixed(2)})`); }
  }
}
console.log(`   ${moves.toLocaleString()} moves (${Math.round(dist).toLocaleString()} m travelled, ${bumps.toLocaleString()} bumped a wall), smallest clearance ${worst.toFixed(4)} m from "${worstWho}" (radius ${PLAYER_R}), inside a collider ${insideCount}x, outside the area ${outCount}x  [${Math.round(performance.now() - t0)} ms]`);

/* ---- corner / jitter: walking along a wall must not stick or shake ---- */
{
  // a long straight wall: walk into it at a shallow angle; progress along the wall must stay close to the free-space progress
  let worstRatio = 1, tried = 0, shake = 0, counted = 0;
  for (const pl of col.polys) {
    if (tried > 150) break;
    const pts = pl.pts;
    for (let k = 0; k < pts.length && tried <= 150; k++) {
      const a = pts[k], b = pts[(k + 1) % pts.length];
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (len < 6) continue;
      const ex = (b[0] - a[0]) / len, ey = (b[1] - a[1]) / len;
      // outward side by trying both
      for (const sg of [1, -1]) {
        const nx = -ey * sg, ny = ex * sg;
        const sx = a[0] + ex * 1.5 + nx * 0.8, sy = a[1] + ey * 1.5 + ny * 0.8;
        if (exactClearance(sx, sy).min < PLAYER_R + 0.1) continue;
        // 20 degrees into the wall, running along it
        const ang = 0;
        const p = { x: sx, y: sy };
        let prevS = 0, backward = 0;
        const steps = Math.min(120, Math.floor((len - 3) / (SPEED.run / 60)));
        for (let s = 0; s < steps; s++) {
          const before = (p.x - sx) * ex + (p.y - sy) * ey;
          col.move(p, Math.cos(Math.atan2(ey, ex) - sg * 0.35) * (SPEED.run / 60), Math.sin(Math.atan2(ey, ex) - sg * 0.35) * (SPEED.run / 60), PLAYER_R);
          const after = (p.x - sx) * ex + (p.y - sy) * ey;
          if (after < before - 1e-4) backward++;
          prevS = after;
        }
        void ang;
        tried++;
        // an unobstructed reference run (parallel to the wall) tells whether something else is in the way
        const q = { x: sx, y: sy };
        for (let s = 0; s < steps; s++) col.move(q, ex * (SPEED.run / 60), ey * (SPEED.run / 60), PLAYER_R);
        const refS = (q.x - sx) * ex + (q.y - sy) * ey;
        if (steps > 20 && refS > steps * (SPEED.run / 60) * 0.97) {
          const free = steps * (SPEED.run / 60) * Math.cos(0.35);
          worstRatio = Math.min(worstRatio, prevS / free);
          counted++;
          if (backward > 0) shake++;
        }
        break;
      }
    }
  }
  console.log(`   wall sliding: ${counted} clean runs (of ${tried}) along walls at 20 degrees, worst progress ${(worstRatio * 100).toFixed(0)}% of free movement, ${shake} runs moved backwards (jitter)`);
  if (worstRatio < 0.8) fail(`sliding along a wall loses too much speed (${(worstRatio * 100).toFixed(0)}%)`);
  if (shake > 0) fail(`${shake} wall runs moved backwards (jitter)`);
}

/* ================================================================ 2. dynamic: cars and pedestrians */
console.log('\n2. cars and pedestrians');
{
  const traffic = new Traffic(W.L, W.box);
  const peds = new Peds(W, { walkers: 14, sellers: 10, idlers: 3 });
  const people = [];
  const P = makePlayer(500, 560);
  const sim = quick ? 90 : 240;
  const dt = 1 / 60;
  let overlaps = 0, carCar = 0, pedInside = 0, brakes = 0, carsPublished = 0, steps = 0, maxPush = 0, closestCar = Infinity, crossings = 0;
  // scripted players: run at the nearest moving car, cross the road, hug walls
  const roadPts = [];
  for (const ri of W.roadIdx) for (const s of W.L.roads[ri].sp.samples) if (s.x > AREA.x0 + 6 && s.x < AREA.x1 - 6 && s.y > AREA.y0 + 6 && s.y < AREA.y1 - 6) roadPts.push(s);
  let target = roadPts[Math.floor(rnd() * roadPts.length)];
  placePlayer(P, col, target.x, target.y);
  let retarget = 0;
  const obbHit = (x, y, r, c) => {
    // circle (x, y, r) against car c's box
    const ch = Math.cos(c.a), sh = Math.sin(c.a);
    const wx = x - c.x, wy = y - c.y;
    const lx = wx * ch + wy * sh, ly = -wx * sh + wy * ch;
    const qx = Math.max(-c.len / 2, Math.min(c.len / 2, lx)), qy = Math.max(-c.wid / 2, Math.min(c.wid / 2, ly));
    return Math.hypot(lx - qx, ly - qy) < r - 0.01;
  };
  const carsOverlap = (a, b) => {
    // separating axis on the two boxes
    const axes = [a.a, a.a + Math.PI / 2, b.a, b.a + Math.PI / 2];
    for (const t of axes) {
      const ux = Math.cos(t), uy = Math.sin(t);
      const proj = (c) => {
        const ch = Math.cos(c.a), sh = Math.sin(c.a);
        const r = Math.abs(ux * ch + uy * sh) * c.len / 2 + Math.abs(-ux * sh + uy * ch) * c.wid / 2;
        const m = c.x * ux + c.y * uy;
        return [m - r, m + r];
      };
      const pa = proj(a), pb = proj(b);
      if (pa[1] <= pb[0] + 0.02 || pb[1] <= pa[0] + 0.02) return false;
    }
    return true;
  };
  for (let f = 0; f < sim / dt; f++) {
    // choose where the scripted player runs: towards a road point, re-picking now and then (it crosses roads and meets cars)
    if (--retarget <= 0) {
      target = roadPts[Math.floor(rnd() * roadPts.length)];
      retarget = 60 * (4 + rnd() * 10);
    }
    const dx = target.x - P.x, dy = target.y - P.y;
    const d = Math.hypot(dx, dy) || 1;
    // run at the nearest moving car sometimes
    let wx = dx / d, wy = dy / d;
    if ((f / 60) % 20 < 6) {
      let bc = null, bd = 30;
      for (const c of traffic.cars) {
        if (c.k < 0.95 || c.v < 1) continue;
        const dd = Math.hypot(c.x - P.x, c.y - P.y);
        if (dd < bd) { bd = dd; bc = c; }
      }
      if (bc) { wx = (bc.x - P.x) / bd; wy = (bc.y - P.y) / bd; }
    }
    peds.people(people);
    people.push({ x: P.x, y: P.y, r: PLAYER_R });
    traffic.step(dt, people);
    traffic.publish(col, P.x, P.y, 60);
    peds.step(dt, col, P);
    const before = { x: P.x, y: P.y };
    stepPlayer(P, col, dt, wx, wy, true);
    maxPush = Math.max(maxPush, Math.hypot(P.x - before.x, P.y - before.y) / dt);
    steps++;
    carsPublished += col.dynBoxes.length;
    // checks
    for (const c of traffic.cars) {
      if (c.k >= 0.95) {
        const dd = Math.hypot(c.x - P.x, c.y - P.y);
        closestCar = Math.min(closestCar, dd);
        if (dd < 8 && obbHit(P.x, P.y, PLAYER_R, c)) { overlaps++; if (overlaps < 6) fail(`t=${(f * dt).toFixed(1)} s: player overlaps a ${c.kind} (speed ${c.v.toFixed(1)})`); }
      }
      if (c.braking) brakes++;
    }
    if (f % 6 === 0) {
      for (let i = 0; i < traffic.cars.length; i++) {
        const a = traffic.cars[i];
        if (a.k < 0.95) continue;
        for (let j = i + 1; j < traffic.cars.length; j++) {
          const b = traffic.cars[j];
          if (b.k < 0.95 || Math.abs(a.x - b.x) > 7 || Math.abs(a.y - b.y) > 7) continue;
          if (carsOverlap({ ...a }, { ...b })) { carCar++; if (carCar < 6) fail(`t=${(f * dt).toFixed(1)} s: two cars overlap (${a.kind} ${a.id} / ${b.kind} ${b.id}) on ${W.L.roads[a.road].id}`); }
        }
      }
      for (const p of peds.list) {
        const c = exactClearance(p.x, p.y);
        if (c.min < 0.28 - TOL) { pedInside++; if (pedInside < 6) fail(`pedestrian ${p.id} (${p.kind}) clearance ${c.min.toFixed(3)} from "${c.who}"`); }
      }
      const pc = exactClearance(P.x, P.y);
      if (pc.min < PLAYER_R - TOL) fail(`scripted player clearance ${pc.min.toFixed(3)} from "${pc.who}"`);
      if (Math.abs(P.vx) + Math.abs(P.vy) > 0 && W.L.net.clear(P.x, P.y, false, 1) < -0.3) crossings++;
    }
  }
  console.log(`   ${traffic.cars.length} cars simulated for ${sim} s, ${peds.list.length} pedestrians; ${steps.toLocaleString()} steps with ${Math.round(carsPublished / steps)} solid cars near the player on average`);
  console.log(`   player overlapping a car: ${overlaps}x, cars overlapping cars: ${carCar}x, pedestrians inside colliders: ${pedInside}x, car braking steps: ${brakes.toLocaleString()}, closest car centre ${closestCar.toFixed(2)} m, player on the carriageway in ${crossings} samples, fastest push ${maxPush.toFixed(1)} m/s`);
  if (brakes === 0) fail('cars never braked: the test did not exercise braking');
  if (crossings < 20) fail('the scripted player hardly crossed the road: the test did not exercise cars');
}

/* ================================================================ 3. doors and GPS */
console.log('\n3. doors and GPS');
{
  let unreachable = 0, blocked = 0, paths = 0, offGrid = 0;
  for (const p of W.places) {
    const c = exactClearance(p.door.sx, p.door.sy);
    if (c.min < PLAYER_R) fail(`place ${p.id}: the standing spot is not clear (${c.min.toFixed(2)} from "${c.who}")`);
    if (!(p.door.sx > AREA.x0 && p.door.sx < AREA.x1 && p.door.sy > AREA.y0 && p.door.sy < AREA.y1)) fail(`place ${p.id}: door outside the area`);
    // the door faces the street: ground right in front of the stand is open
    if (p.door.kind === 'wall') {
      const q = exactClearance(p.door.x + p.door.nx * 0.5, p.door.y + p.door.ny * 0.5);
      if (q.min < 0.1) fail(`place ${p.id}: the door is blocked in front (${q.who})`);
    }
  }
  for (const a of W.places) {
    for (const b of W.places) {
      if (a === b) continue;
      const r = planRoute(W, [a.door.sx, a.door.sy], [b.door.sx, b.door.sy]);
      paths++;
      if (!r.reachable) { unreachable++; fail(`GPS: ${a.id} -> ${b.id} unreachable`); continue; }
      // walk the polyline with the real collision: the player must follow it without leaving it by more than a hand
      for (let i = 0; i + 1 < r.pts.length; i++) {
        const [x0, y0] = r.pts[i], [x1, y1] = r.pts[i + 1];
        const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0) / 0.25);
        for (let k = 0; k <= n; k++) {
          const x = x0 + ((x1 - x0) * k) / n, y = y0 + ((y1 - y0) * k) / n;
          if (exactClearance(x, y).min < 0.12) { blocked++; if (blocked < 6) fail(`GPS: ${a.id} -> ${b.id} passes through a collider at (${x.toFixed(1)}, ${y.toFixed(1)})`); k = n; i = r.pts.length; }
        }
      }
      if (verbose) console.log(`   ${a.id} -> ${b.id}: ${r.length.toFixed(0)} m`);
    }
  }
  console.log(`   ${W.places.length} places, ${paths} GPS routes between them: unreachable ${unreachable}, through a collider ${blocked}`);
  void offGrid;
}

console.log(failures ? `\nROAM COLLIDE CHECK FAILED: ${failures} violation(s)` : '\nROAM COLLIDE CHECK OK');
process.exit(failures ? 1 : 0);
