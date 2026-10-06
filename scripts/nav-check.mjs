// M1 check for the shared pathing + locomotion (src/art/sim). No test runner in the repo, so this
// is a plain node script (Node 22+, type stripping):  node scripts/nav-check.mjs   (add -v for maps)
// Exits 1 on any failure.
import { register } from 'node:module';

// let node resolve the app's extensionless relative imports ('./model' -> './model.ts')
register(
  'data:text/javascript,' +
    encodeURIComponent(`
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && !/\\.[cm]?[jt]sx?$/.test(spec)) {
    try { return await next(spec + '.ts', ctx); } catch {}
  }
  return next(spec, ctx);
}`),
  import.meta.url,
);

const nav = await import('../src/art/sim/nav.ts');
const loco = await import('../src/art/sim/locomotion.ts');
const home = await import('../src/art/home3d/nav.ts');
const { LAYOUTS, KINDS } = await import('../src/art/home3d/model.ts');

const verbose = process.argv.includes('-v');
let fails = 0;
const ok = (cond, msg) => {
  if (cond) console.log('  ok  ' + msg);
  else {
    fails++;
    console.log('  FAIL ' + msg);
  }
};
const segsClear = (g, pts) => pts.every((p, i) => i === 0 || nav.lineClear(g, pts[i - 1], p));
const near = (a, b, e = 0.25) => Math.hypot(a[0] - b[0], a[1] - b[1]) <= e;

// ---------------------------------------------------------------- synthetic grids
console.log('synthetic');
{
  // 6 x 4 m room, a wall across the middle with a gap at the top
  const g = nav.makeGrid([0, 0, 6, 4], 0.25);
  nav.blockRect(g, 2.9, 1.2, 3.1, 4, 0.1);
  const p = nav.planPath(g, [1, 3], [5, 3]);
  ok(p.reachable, 'around a wall: reachable');
  ok(p.points.length >= 3, `around a wall: has corners (${p.points.length} points)`);
  ok(segsClear(g, p.points.slice(1)), 'around a wall: every leg is clear');
  ok(near(p.end, [5, 3], 1e-6), 'around a wall: ends on the target');
  ok(p.length < 7.5 && p.length > 4, `around a wall: sensible length ${p.length.toFixed(2)} m`);
  if (verbose) console.log(nav.dump(g, p.points));

  // straight line in open space = 2 points (string pulling)
  const q = nav.planPath(g, [0.6, 0.6], [2.2, 0.8]);
  ok(q.points.length === 2, `open floor: a single straight leg (${q.points.length} points)`);

  // target inside an obstacle with snapEnd -> nearest free cell next to it
  const r = nav.planPath(g, [1, 3], [3, 2.5], { snapEnd: true });
  ok(nav.freeAt(g, r.end), 'tap on an obstacle (snapEnd): ends on a free cell');
  ok(Math.hypot(r.end[0] - 3, r.end[1] - 2.5) < 0.6, 'tap on an obstacle: ends right next to it');

  // closed pocket: unreachable -> nearest reachable point, not through the wall
  const h = nav.makeGrid([0, 0, 6, 4], 0.25);
  nav.blockRect(h, 3.8, 0, 4.0, 4, 0); // full-height wall, no gap
  const u = nav.planPath(h, [1, 2], [5, 2]);
  ok(!u.reachable, 'sealed room: reported unreachable');
  ok(u.end[0] < 3.8, `sealed room: stops on our side of the wall (x=${u.end[0].toFixed(2)})`);
  ok(Math.abs(u.end[1] - 2) < 0.4, 'sealed room: stops at the closest point to the tap');
  ok(segsClear(h, u.points.slice(1)), 'sealed room: path stays on free cells');

  // corner rounding keeps clear and adds points only at corners
  const rr = nav.planPath(g, [1, 3], [5, 3], { round: 0.25 });
  ok(rr.points.length > p.points.length, `rounded corners add curve points (${p.points.length} -> ${rr.points.length})`);
  ok(segsClear(g, rr.points.slice(1)), 'rounded path stays clear');
  ok(rr.length <= p.length + 1e-6, `rounded path is not longer (${rr.length.toFixed(2)} <= ${p.length.toFixed(2)})`);

  // start inside the padding (standing at a furniture spot) still works
  const s = nav.planPath(g, [2.95, 1.0], [0.6, 0.6]);
  ok(s.points.length >= 2 && near(s.points[0], [2.95, 1.0], 1e-6), 'start inside an obstacle pad: path starts at the exact point');

  // speed: a big grid A* stays fast
  const big = nav.makeGrid([0, 0, 40, 40], 0.2);
  for (let i = 0; i < 14; i++) nav.blockRect(big, 2 + i * 2.7, i % 2 ? 0 : 6, 2.3 + i * 2.7, i % 2 ? 34 : 40, 0.1);
  const t0 = performance.now();
  const b = nav.planPath(big, [1, 1], [39, 39]);
  const ms = performance.now() - t0;
  ok(b.reachable && segsClear(big, b.points.slice(1)), `200x200 serpentine maze solved (${b.points.length} corners)`);
  ok(ms < 60, `200x200 maze in ${ms.toFixed(1)} ms`);
}

// ---------------------------------------------------------------- locomotion
console.log('locomotion');
{
  const w = loco.makeWalker([0, 0], Math.PI); // facing away from the path
  loco.walkPath(w, [[0, 0], [3, 0], [3, 2]], 0);
  let t = 0;
  let maxSpeed = 0;
  let maxJump = 0;
  let turnedBeforeMoving = 0;
  let movedBeforeTurn = false;
  let prev = [...w.pos];
  let arrived = false;
  let firstMove = -1;
  let maxAccel = 0;
  let lastSpeed = 0;
  while (t < 15 && !arrived) {
    const dt = 1 / 60;
    const r = loco.stepWalker(w, dt);
    t += dt;
    if (r.moved > 0 && firstMove < 0) firstMove = t;
    if (firstMove < 0) turnedBeforeMoving += r.turned;
    if (firstMove > 0 && t - firstMove < 0.05 && Math.abs(loco.angleTo(w.yaw, Math.PI / 2)) > 0.9) movedBeforeTurn = true;
    maxSpeed = Math.max(maxSpeed, w.speed);
    maxJump = Math.max(maxJump, Math.hypot(w.pos[0] - prev[0], w.pos[1] - prev[1]));
    if (!r.arrived) maxAccel = Math.max(maxAccel, Math.abs(w.speed - lastSpeed) / dt); // the last frame sets 0
    lastSpeed = w.speed;
    prev = [...w.pos];
    arrived = r.arrived;
  }
  ok(arrived, `arrives (${t.toFixed(2)} s for 5 m)`);
  ok(near(w.pos, [3, 2], 1e-6), `ends exactly on the last point (${w.pos.map((v) => v.toFixed(4))})`);
  ok(Math.abs(loco.angleTo(w.yaw, 0)) < 0.03, 'turns to the final facing');
  ok(turnedBeforeMoving > 1.0 && !movedBeforeTurn, `turns on the spot before walking off (${turnedBeforeMoving.toFixed(2)} rad first)`);
  ok(maxSpeed <= 1.15 + 1e-6 && maxSpeed > 0.9, `cruise speed reached, not exceeded (${maxSpeed.toFixed(2)} m/s)`);
  ok(maxJump < 0.03, `no teleport: largest step ${(maxJump * 100).toFixed(1)} cm at 60 fps`);
  ok(maxAccel < 3, `speed eases (peak accel ${maxAccel.toFixed(2)} m/s²)`);

  // re-target mid-walk keeps the speed (no stop-start)
  const v = loco.makeWalker([0, 0], Math.PI / 2);
  loco.walkPath(v, [[0, 0], [4, 0]]);
  for (let i = 0; i < 90; i++) loco.stepWalker(v, 1 / 60);
  const before = v.speed;
  loco.walkPath(v, [[v.pos[0], v.pos[1]], [v.pos[0] + 3, 0.2]]);
  loco.stepWalker(v, 1 / 60);
  ok(before > 0.6 && v.speed > before * 0.85, `re-target mid-walk keeps moving (${before.toFixed(2)} -> ${v.speed.toFixed(2)} m/s)`);
  // the speed when it reaches the last point is low (no hard stop)
  const z = loco.makeWalker([0, 0], Math.PI / 2);
  loco.walkPath(z, [[0, 0], [2.5, 0]]);
  let atEnd = -1;
  for (let i = 0; i < 600 && atEnd < 0; i++) {
    loco.stepWalker(z, 1 / 60);
    if (z.seg >= z.path.length || z.path.length === 0) atEnd = z.speed;
  }
  ok(atEnd >= 0 && atEnd < 0.35, `arrives slow (${atEnd.toFixed(2)} m/s at the last point)`);
}

// ---------------------------------------------------------------- the real home layouts
console.log('home layouts');
for (const id of Object.keys(LAYOUTS)) {
  const L = LAYOUTS[id];
  const g = home.buildGrid(L);
  const d = L.doors[0];
  const door = d[0] === 'e' ? [L.w + 0.7, (d[1] + d[2]) / 2] : [(d[1] + d[2]) / 2, L.d + 0.7];
  const t0 = performance.now();
  const p = home.planPath(g, door, [L.home[0], L.home[1]]);
  ok(p.reachable && segsClear(g, p.points.slice(1, -1)), `${id}: door -> idle spot (${p.points.length} pts, ${p.length.toFixed(1)} m, ${(performance.now() - t0).toFixed(1)} ms)`);
  // every furniture spot reachable from the idle spot
  let bad = [];
  for (const f of L.furniture) {
    const k = KINDS[f.kind];
    if (!k.group) continue;
    const [lx, lz] = k.spot ?? [0, k.d / 2 + 0.35];
    const s = home.toLayout(f, lx, lz);
    const q = home.planPath(g, [L.home[0], L.home[1]], s);
    if (!q.reachable) bad.push(f.id);
  }
  ok(bad.length === 0, `${id}: every furniture spot reachable${bad.length ? ' (not: ' + bad.join(', ') + ')' : ''}`);
  // a tap on a solid piece snaps to a free cell next to it
  const solid = L.furniture.find((f) => KINDS[f.kind].solid && !(f.y > 0));
  if (solid) {
    const q = home.planPath(g, [L.home[0], L.home[1]], [solid.x, solid.z], { snapEnd: true });
    ok(nav.freeAt(g, q.end), `${id}: tap on the ${solid.kind} stops beside it`);
  }
  if (verbose) console.log(nav.dump(g, p.points));
}

console.log(fails ? `\n${fails} FAILED` : '\nall passed');
process.exit(fails ? 1 : 0);
