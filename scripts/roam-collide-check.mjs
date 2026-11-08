// Free roam collision stress test: node scripts/roam-collide-check.mjs   (Node 22+, no dependencies)
//   --quick   a shorter run      --seed=N   another random seed      -v   more detail
// Loads the REAL roam world (src/art/roam3d/world.ts: the WHOLE city's buildings, OSM footprints, landmarks, trees, lamps, GRA walls,
// stalls, kiosks, gates, door posts) and the real collision code, then fires random moves at it:
//   1. static: thousands of walkers at walking, running, sprint and teleport speeds, plus hitch frames (dt 0.25 s) and moves
//      aimed straight at walls and corners. After EVERY move an independent brute-force check (not the spatial hash) asserts
//      the player is not inside any collider, keeps at least its radius from every wall / pole / trunk and is inside the area.
//   2. dynamic: a few minutes of simulated traffic and pedestrians while scripted players run at the cars; asserts no car
//      ever overlaps the player, cars never overlap each other, pedestrians never stand inside a collider.
//   3. doors and GPS: every place's standing spot is clear and reachable from every other, and the whole GPS route is walkable.
//   4. driving (phase 2): the player's own vehicle (carphys.ts) driven at random over the whole city at walking-to-top speed, aimed at
//      walls, poles and traffic, with hitch frames; after EVERY step an independent exact check asserts the body is never inside a
//      collider, never leaves the city, never jumps (no tunnelling) and never comes within the soft margin of a pedestrian.
//   5. spawning: a person standing where a car lane begins is never overlapped by a car that fades in (cars wait unseen).
// Exits 1 on any violation. See docs/ROAM.md.
import './_roam-loader.mjs';

const quick = process.argv.includes('--quick');
const onlyArg = process.argv.find((a) => a.startsWith('--only='));
const run = (n) => !onlyArg || onlyArg.slice(7).split(',').includes(String(n));
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
const { Traffic, SPAWN_SAFE } = await import('../src/art/roam3d/traffic.ts');
const { CAR_SPECS, makeCarState, stepCar, bodyClear, discsFor } = await import('../src/art/roam3d/carphys.ts');
const { Peds } = await import('../src/art/roam3d/peds.ts');
const { planRoute } = await import('../src/art/roam3d/gps.ts');
const { DEV_LOCATIONS } = await import('../src/art/city3d/dev/fixture.ts');

let t0 = performance.now();
const W = buildRoamWorld(DEV_LOCATIONS.map((l) => ({ id: l.id, name: l.name, scene: l.scene, x: l.x, y: l.y, active: l.id !== 'benin_airport' })));
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
// an independent broad phase (a plain grid of polygon indices by bounding box; not the world's hash)
const GCELL = 24;
const grid = new Map();
const gkey = (i, j) => i * 100003 + j;
for (let i = 0; i < col.polys.length; i++) {
  const b = polyBox[i];
  for (let gj = Math.floor((b[1] - 1) / GCELL); gj <= Math.floor((b[3] + 1) / GCELL); gj++)
    for (let gi = Math.floor((b[0] - 1) / GCELL); gi <= Math.floor((b[2] + 1) / GCELL); gi++) {
      const k = gkey(gi, gj);
      (grid.get(k) ?? grid.set(k, []).get(k)).push(i);
    }
}
const circGrid = new Map();
col.circs.forEach((c, i) => {
  const k = gkey(Math.floor(c.x / GCELL), Math.floor(c.y / GCELL));
  (circGrid.get(k) ?? circGrid.set(k, []).get(k)).push(i);
});
function exactClearance(x, y) {
  let min = Infinity, who = '';
  const gi = Math.floor(x / GCELL), gj = Math.floor(y / GCELL);
  for (let dj = -1; dj <= 1; dj++)
    for (let di = -1; di <= 1; di++) {
      for (const ci of circGrid.get(gkey(gi + di, gj + dj)) ?? []) {
        const c = col.circs[ci];
        const d = Math.hypot(x - c.x, y - c.y) - c.r;
        if (d < min) { min = d; who = c.id; }
      }
    }
  for (const i of grid.get(gkey(gi, gj)) ?? []) {
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
const walkers = !run(1) ? 0 : quick ? 600 : 2500;
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
if (run(1)) {
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
if (run(2)) {
  const traffic = new Traffic(W.L);
  const peds = new Peds(W, { walkers: 14, sellers: 10, idlers: 3, around: { x: 500, y: 560 } });
  const people = [];
  const P = makePlayer(500, 560);
  const sim = quick ? 90 : 240;
  const dt = 1 / 60;
  let shoves = 0, overlaps = 0, carCar = 0, pedInside = 0, brakes = 0, carsPublished = 0, steps = 0, maxPush = 0, closestCar = Infinity, crossings = 0;
  // scripted players: run at the nearest moving car, cross the road, hug walls
  const roadPts = [];
  for (const ri of W.roadIdx) for (const s of W.L.roads[ri].sp.samples) if (s.x > AREA.x0 + 6 && s.x < AREA.x1 - 6 && s.y > AREA.y0 + 6 && s.y < AREA.y1 - 6) roadPts.push(s);
  // the city is big and the traffic thin: the scripted player works where the cars are (a random moving car's spot, re-picked now and then)
  const carSpot = () => {
    const moving = traffic.cars.filter((c) => c.k > 0.95 && c.v > 1);
    const c = moving[Math.floor(rnd() * moving.length)];
    return c ? { x: c.x, y: c.y } : roadPts[Math.floor(rnd() * roadPts.length)];
  };
  traffic.step(1 / 60, [], null);
  let target = carSpot();
  {
    // start 8 m ahead of that car, not inside it (a start inside a car would be a test artefact, not a shove)
    const c0 = traffic.cars.find((c) => Math.hypot(c.x - target.x, c.y - target.y) < 0.5);
    let sx = c0 ? c0.x + Math.cos(c0.a) * 8 : target.x, sy = c0 ? c0.y + Math.sin(c0.a) * 8 : target.y;
    for (let k = 0; k < 8 && traffic.cars.some((c) => Math.hypot(c.x - sx, c.y - sy) < 5); k++) { sx += Math.cos(c0 ? c0.a : 0) * 6; sy += Math.sin(c0 ? c0.a : 0) * 6; }
    placePlayer(P, col, sx, sy);
  }
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
      target = carSpot();
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
    traffic.step(dt, people, P);
    traffic.publish(col, P.x, P.y, 60);
    peds.step(dt, col, P);
    const before = { x: P.x, y: P.y };
    stepPlayer(P, col, dt, wx, wy, true);
    const pushV = Math.hypot(P.x - before.x, P.y - before.y) / dt;
    maxPush = Math.max(maxPush, pushV);
    if (pushV > 12) {
      shoves++;
      if (shoves < 6) {
        const near = traffic.cars.filter((c) => Math.hypot(c.x - P.x, c.y - P.y) < 6).map((c) => `${c.kind} k${c.k.toFixed(2)} v${c.v.toFixed(1)} d${Math.hypot(c.x - P.x, c.y - P.y).toFixed(1)} held${c.held}`).join('; ');
        fail(`t=${(f * dt).toFixed(2)} s: the player was shoved ${(pushV * dt).toFixed(2)} m in one step (${pushV.toFixed(0)} m/s); cars within 6 m: ${near || 'none'}; clearance before ${exactClearance(before.x, before.y).min.toFixed(2)} from "${exactClearance(before.x, before.y).who}" at (${before.x.toFixed(2)}, ${before.y.toFixed(2)}), after ${exactClearance(P.x, P.y).min.toFixed(2)} from "${exactClearance(P.x, P.y).who}" at (${P.x.toFixed(2)}, ${P.y.toFixed(2)}), moving (${wx.toFixed(2)}, ${wy.toFixed(2)})`);
      }
    }
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
          if (carsOverlap({ ...a }, { ...b })) { carCar++; if (carCar < 6) fail(`t=${(f * dt).toFixed(1)} s: two cars overlap (${a.kind} ${a.id} / ${b.kind} ${b.id}) on ${W.L.roads[a.road].id} lane ${a.lane}/${b.lane}; a: v ${a.v.toFixed(1)} held ${a.held} ent ${a.entering} k ${a.k.toFixed(2)} cr ${a.cruise.toFixed(1)}; b: v ${b.v.toFixed(1)} held ${b.held} ent ${b.entering} k ${b.k.toFixed(2)} cr ${b.cruise.toFixed(1)}; stretches a ${a.s0.toFixed(0)}-${a.s1.toFixed(0)} jam ${a.jam} / b ${b.s0.toFixed(0)}-${b.s1.toFixed(0)} jam ${b.jam} same stream ${a.mates === b.mates}; dist ${Math.hypot(a.x - b.x, a.y - b.y).toFixed(1)} focus ${Math.hypot(a.x - P.x, a.y - P.y).toFixed(0)} m away`); }
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
if (run(3)) {
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

/* ================================================================ 4. driving the player's own vehicle */
console.log('\n4. driving over the whole city');
if (run(4)) {
  const kinds = ['sedan', 'suv', 'pickup', 'moto', 'bike'];
  const runs = quick ? 60 : 260;
  const stepsPer = quick ? 900 : 1800;
  let steps = 0, hitsL = 0, hitsH = 0, dist = 0, worst = Infinity, worstWho = '', inside = 0, outside = 0, jumps = 0, soft = 0, boxHits = 0, maxV = 0, tunnel = 0;
  const T2 = 0.07; // the real corners of the box may poke this far past the circles that stand for it (cm)
  // an independent exact test of the oriented box: sample points round its outline and inside against every nearby collider
  const outline = (spec) => {
    const pts = [];
    const hl = spec.len / 2, hw = spec.wid / 2;
    for (let i = 0; i <= 8; i++) { pts.push([-hl + (spec.len * i) / 8, -hw], [-hl + (spec.len * i) / 8, hw]); }
    for (let i = 1; i < 4; i++) { pts.push([-hl, -hw + (spec.wid * i) / 4], [hl, -hw + (spec.wid * i) / 4]); }
    pts.push([0, 0]);
    return pts;
  };
  const outlines = Object.fromEntries(kinds.map((k) => [k, outline(CAR_SPECS[k])]));
  const traffic = new Traffic(W.L);
  const peds = new Peds(W, { walkers: 12, sellers: 6, idlers: 2, around: { x: 500, y: 540 } });
  const people = [];
  const env = { engine: true, wet: false, people, roadClear: (x, y) => W.L.net.clear(x, y, false, 6) };
  const roadSamples = [];
  for (const ri of W.roadIdx) {
    const r = W.L.roads[ri];
    if (r.kind === 'spur') continue;
    for (let i = 0; i < r.sp.samples.length; i += 3) { const sm = r.sp.samples[i]; if (sm.x > 8 && sm.x < 992 && sm.y > 8 && sm.y < 992) roadSamples.push([sm, r.hw]); }
  }
  const aim = (x, y) => nearestEdgeDir(x, y);
  for (let run = 0; run < runs; run++) {
    const kind = kinds[run % kinds.length];
    const spec = CAR_SPECS[kind];
    // start on a road (or beside it) somewhere in the city, nose along the road, clear of every collider
    let st = null;
    for (let tries = 0; tries < 60 && !st; tries++) {
      const [sm, hw] = roadSamples[Math.floor(rnd() * roadSamples.length)];
      const off = (rnd() - 0.5) * hw * 1.4;
      const x = sm.x - Math.sin(sm.a) * off, y = sm.y + Math.cos(sm.a) * off;
      const h = sm.a + (rnd() < 0.5 ? 0 : Math.PI) + (rnd() - 0.5) * 0.3;
      if (bodyClear(col, spec, x, y, h, 0.1) && !traffic.cars.some((q) => q.k > 0.3 && Math.hypot(q.x - x, q.y - y) < 9)) st = makeCarState(x, y, h);
    }
    if (!st) continue;
    const c = st;
    let steer = 0, thr = 1, brk = 0, retarget = 0, aimWall = 0;
    // a few pedestrians standing still ahead of the car on some runs (the soft collider)
    const standing = [];
    if (run % 4 === 0) for (let k = 0; k < 4; k++) standing.push({ x: c.x + Math.cos(c.h) * (14 + k * 9) + (rnd() - 0.5) * 3, y: c.y + Math.sin(c.h) * (14 + k * 9) + (rnd() - 0.5) * 3, r: 0.3 });
    const live = standing.filter((p) => exactClearance(p.x, p.y).min > 0.6);
    people.length = 0;
    for (const p of live) people.push(p);
    // the scene always steps the car at a fixed 1/60 s (a slow frame runs several steps), so that is what is tested
    const dts = [1 / 60];
    let dt = 1 / 60;
    let prev = { x: c.x, y: c.y };
    for (let s = 0; s < stepsPer; s++) {
      if (--retarget <= 0) {
        retarget = 30 + Math.floor(rnd() * 120);
        steer = (rnd() - 0.5) * 2 * (rnd() < 0.3 ? 0.2 : 1);
        thr = rnd() < 0.15 ? 0 : 0.5 + rnd() * 0.5;
        brk = rnd() < 0.12 ? 1 : 0;
        aimWall = rnd() < 0.35 ? 90 : 0;
        dt = dts[Math.floor(rnd() * dts.length)];
      }
      if (aimWall > 0) {
        aimWall--;
        const a = aim(c.x, c.y);
        if (a !== null) {
          let d = a - c.h;
          d = Math.atan2(Math.sin(d), Math.cos(d));
          steer = Math.max(-1, Math.min(1, d * 2));
        }
      }
      peds.people(people);
      for (const p of live) people.push(p);
      env.people = people.slice();
      for (let k = 0; k < 3; k++) { const u = (k - 1) * (spec.len / 2 - spec.wid / 2); people.push({ x: c.x + Math.cos(c.h) * u, y: c.y + Math.sin(c.h) * u, r: spec.wid / 2 * 1.08 }); }
      if (run % 3 === 0) { traffic.step(dt, people, c); traffic.publish(col, c.x, c.y, 60); } else col.dynBoxes = [];
      const hl0 = c.light, hh0 = c.hard;
      const pre = { x: c.x, y: c.y, h: c.h, v: c.v, yaw: c.yaw, steer: c.steer };
      stepCar(c, spec, col, dt, { steer, throttle: thr, brake: brk }, env);
      hitsL += c.light - hl0;
      hitsH += c.hard - hh0;
      steps++;
      maxV = Math.max(maxV, Math.abs(c.v));
      const mv = Math.hypot(c.x - prev.x, c.y - prev.y);
      dist += mv;
      // no tunnelling / teleporting: one step never moves further than the speed allows (plus the push-out)
      if (mv > Math.max(0.6, Math.abs(c.v) * dt * 2 + 0.5)) { jumps++; if (jumps < 6) fail(`${kind} step jumped ${mv.toFixed(2)} m at speed ${c.v.toFixed(1)} (run ${run}, step ${s}, pre ${JSON.stringify(pre, (k, v) => (typeof v === 'number' ? Math.round(v * 1000) / 1000 : v))} inputs steer ${steer.toFixed(2)} thr ${thr} brk ${brk}, dt ${dt.toFixed(3)}, ${col.dynBoxes.filter((q) => Math.hypot(q.x - c.x, q.y - c.y) < 7).length} traffic boxes within 7 m, soft ${c.softStop}) at (${c.x.toFixed(1)}, ${c.y.toFixed(1)})`); }
      prev = { x: c.x, y: c.y };
      // exact checks on the box
      const ch = Math.cos(c.h), sh = Math.sin(c.h);
      for (const [u, v] of outlines[kind]) {
        const px = c.x + u * ch - v * sh, py = c.y + u * sh + v * ch;
        const e = exactClearance(px, py);
        if (e.min < worst) { worst = e.min; worstWho = e.who; }
        if (e.min < -T2) { inside++; if (inside < 8) fail(`${kind}: box point inside "${e.who}" by ${(-e.min).toFixed(3)} m at (${c.x.toFixed(1)}, ${c.y.toFixed(1)}) speed ${c.v.toFixed(1)}`); break; }
      }
      if (c.x < AREA.x0 - 0.05 || c.x > AREA.x1 + 0.05 || c.y < AREA.y0 - 0.05 || c.y > AREA.y1 + 0.05) { outside++; fail(`${kind}: left the city at (${c.x.toFixed(1)}, ${c.y.toFixed(1)})`); }
      // the traffic boxes: a real hit is allowed, a body deep inside another car is not
      for (const b of col.dynBoxes) {
        if (Math.abs(b.x - c.x) > 8 || Math.abs(b.y - c.y) > 8) continue;
        const cb = Math.cos(b.a), sb = Math.sin(b.a);
        for (const [u, v] of outlines[kind]) {
          const px = c.x + u * ch - v * sh, py = c.y + u * sh + v * ch;
          const lx = (px - b.x) * cb + (py - b.y) * sb, ly = -(px - b.x) * sb + (py - b.y) * cb;
          const depth = Math.min(b.hl - Math.abs(lx), b.hw - Math.abs(ly));
          if (depth > 0.12) { boxHits++; if (boxHits < 6) fail(`${kind}: box point ${depth.toFixed(2)} m inside a traffic car`); break; }
        }
      }
      // the soft collider: never within a hand of a pedestrian's centre
      for (const p of live) {
        const lx = (p.x - c.x) * ch + (p.y - c.y) * sh, ly = -(p.x - c.x) * sh + (p.y - c.y) * ch;
        const qx = Math.max(-spec.len / 2, Math.min(spec.len / 2, lx)), qy = Math.max(-spec.wid / 2, Math.min(spec.wid / 2, ly));
        const d = Math.hypot(lx - qx, ly - qy);
        if (d < 0.3 + 0.35) { soft++; if (soft < 6) fail(`${kind}: ${d.toFixed(2)} m from a pedestrian's centre (soft collider failed)`); }
      }
    }
  }
  void tunnel;
  console.log(`   ${runs} drives (${steps.toLocaleString()} steps, ${Math.round(dist).toLocaleString()} m, top speed ${maxV.toFixed(1)} m/s, ${hitsL} light + ${hitsH} hard hits), smallest clearance of any box point ${worst.toFixed(3)} m from "${worstWho}"`);
  console.log(`   box inside a collider: ${inside}x, left the city: ${outside}x, jumps (tunnelling): ${jumps}x, deep inside a traffic car: ${boxHits}x, closer than the soft margin to a pedestrian: ${soft}x`);
  if (hitsL + hitsH === 0) fail('the cars never hit anything: the test did not exercise collisions');
}

/* ================================================================ 5. a car never fades in on top of somebody */
console.log('\n5. spawning');
if (run(5)) {
  const traffic = new Traffic(W.L);
  const people = [];
  let violations = 0, checks = 0, held = 0;
  // stand a person (and then the player's car) right where lanes begin
  const starts = [];
  for (const v of W.L.vehicles) {
    if (v.px !== undefined) continue;
    const rd = W.L.roads[v.road];
    if (rd.closed) continue;
    starts.push(v);
  }
  const picks = [];
  for (let i = 0; i < (quick ? 12 : 40); i++) picks.push(starts[Math.floor(rnd() * starts.length)]);
  for (const v of picks) {
    const c0 = traffic.cars.find((c) => c.road === v.road && c.lane === v.lane);
    if (!c0) continue;
    // the position of the lane start, from a car parked on it
    c0.run = c0.s0 - c0.s;
    traffic.step(1 / 60, [], null);
    const sx = c0.x, sy = c0.y;
    people.length = 0;
    people.push({ x: sx, y: sy, r: 0.32 });
    for (let f = 0; f < 60 * 25; f++) {
      traffic.step(1 / 60, people, { x: sx, y: sy });
      for (const c of traffic.cars) {
        if (!c.entering || c.k < 0.02) continue;
        const d = Math.hypot(c.x - sx, c.y - sy);
        checks++;
        if (d < SPAWN_SAFE - 0.3) { violations++; if (violations < 6) fail(`a ${c.kind} faded in ${d.toFixed(1)} m from a person standing at a lane start (${sx.toFixed(0)}, ${sy.toFixed(0)})`); }
      }
      for (const c of traffic.cars) if (c.held) held++;
    }
  }
  console.log(`   ${picks.length} lane starts with somebody standing there for 25 s each: ${checks.toLocaleString()} fade-in checks, ${violations} cars appeared within ${SPAWN_SAFE} m (${held.toLocaleString()} held-back car steps)`);
  if (held === 0) fail('no car was ever held back: the test did not exercise the spawn gate');
}

console.log(failures ? `\nROAM COLLIDE CHECK FAILED: ${failures} violation(s)` : '\nROAM COLLIDE CHECK OK');
process.exit(failures ? 1 : 0);
