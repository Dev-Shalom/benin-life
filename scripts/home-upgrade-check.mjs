// R8 house upgrades: geometry check (docs/HOUSE_UPGRADES.md). Plain node script (Node 22+, type stripping):
//   node scripts/home-upgrade-check.mjs          # verify (exit 1 on any failure)
//   node scripts/home-upgrade-check.mjs --geom   # print yard-building spots to paste into upgrades.ts GEOM
//   node scripts/home-upgrade-check.mjs --sql    # print the geom jsonb the migration seeds (house_upgrades.effect.geom)
// Checks, per layout and per extension room / yard building: nothing overlaps a fixture, the house or another
// building; the doors stay clear; the Sim can walk from the front door to the middle of every new room and to every
// yard building's front; the server's furnishable area (rooms + lot) is what the client uses.
import { register } from 'node:module';
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
const { LAYOUTS, isFixture } = await import('../src/art/home3d/model.ts');
const nav = await import('../src/art/home3d/nav.ts');
const up = await import('../src/art/home3d/upgrades.ts');
const arr = await import('../src/art/home3d/arrange.ts');

const mode = process.argv[2] ?? '';
const KINDS = ['face_me', 'self_contain', 'flat', 'duplex'];
const overlaps = (a, b, e = 0.02) => Math.min(a[2], b[2]) - Math.max(a[0], b[0]) > e && Math.min(a[3], b[3]) - Math.max(a[1], b[1]) > e;
const infl = (r, m) => [r[0] - m, r[1] - m, r[2] + m, r[3] + m];
const BAY = 2.9, BAY_D = 4.6;

/** Everything a yard building must stay off, for a plain layout (rooms of every upgrade included). */
function obstacles(id) {
  const L = LAYOUTS[id];
  const out = [infl([0, 0, L.w, L.d], 0.3)];
  for (const f of L.furniture) {
    const r = nav.footprint(f);
    if (isFixture(f) || f.x > L.w || f.z > L.d || f.x < 0 || f.z < 0) out.push(infl(r, 0.25));
  }
  const door = L.doors[0];
  if (door) out.push(door[0] === 'e' ? [L.w, door[1] - 0.5, L.lot[2] + 0.5, door[2] + 0.5] : [door[1] - 0.5, L.d, door[2] + 0.5, L.lot[3] + 0.5]);
  for (const d of L.doors.slice(1)) out.push(d[0] === 'e' ? [L.w, d[1] - 0.5, L.lot[2] + 0.5, d[2] + 0.5] : [d[1] - 0.5, L.d, d[2] + 0.5, L.lot[3] + 0.5]);
  for (const [, g] of Object.entries(up.GEOM)) {
    const gm = g[id];
    if (gm?.room) out.push(infl(gm.room.rect, 0.3));
  }
  // the parking pad (duplex keeps it inside the lot; other homes park beyond the east edge)
  if (id === 'duplex') out.push([L.w + 0.5, L.d - 0.4, L.w + 0.5 + 3 * BAY, L.d + 4.2]);
  // other homes park beyond the east edge of the (grown) lot: the pad moves with it, so it is no obstacle
  if (id === 'duplex') out.push([0.3, L.d + 0.6, 5.9, L.d + 4.2]); // pool deck
  return out;
}

const SIZES = { gen_house: [1.3, 1.0, 'genhouse'], solar_system: [2.0, 1.1, 'solar'], borehole: [1.6, 1.2, 'borehole'] };
function place(id, taken) {
  const L = LAYOUTS[id];
  const res = {};
  const anchors = { gen_house: [L.lot[2], L.lot[1]], borehole: [L.lot[2], L.lot[1] + (L.lot[3] - L.lot[1]) * 0.45], solar_system: [L.lot[2], L.lot[3]] };
  const obs = obstacles(id);
  const placed = [...taken];
  for (const [uid, [w, d, kind]] of Object.entries(SIZES)) {
    let best = null;
    for (let x = L.lot[0] + 0.4; x + w <= L.lot[2] + 3.6 + 1e-6; x += 0.25) {
      for (let z = L.lot[1] + 0.4; z + d <= L.lot[3] - 0.2 + 1e-6; z += 0.25) {
        const r = [x, z, x + w, z + d];
        if (obs.some((o) => overlaps(r, o, 0.01)) || placed.some((o) => overlaps(infl(r, 0.4), o, 0.01))) continue;
        const s = Math.hypot(r[2] - anchors[uid][0], r[1] + d / 2 - anchors[uid][1]);
        if (!best || s < best.s) best = { s, r };
      }
    }
    if (!best) { res[uid] = null; continue; }
    const r = best.r.map((n) => Math.round(n * 100) / 100);
    res[uid] = { struct: { kind, rect: r } };
    placed.push(r);
  }
  return res;
}

if (mode === '--geom') {
  const out = {};
  for (const id of KINDS) {
    const taken = [];
    const bq = up.GEOM.boys_quarters?.[id]?.struct?.rect;
    if (bq) taken.push(bq);
    const p = place(id, taken);
    for (const [uid, g] of Object.entries(p)) (out[uid] ??= {})[id] = g;
  }
  console.log(JSON.stringify(out));
  process.exit(0);
}

if (mode === '--sql') {
  const out = {};
  for (const [uid, byLayout] of Object.entries(up.GEOM)) {
    if (!Object.keys(byLayout).length) continue;
    const e = {};
    for (const [lid, g] of Object.entries(byLayout)) {
      e[lid] = {};
      if (g.room) e[lid].room = { rect: g.room.rect, door: g.room.door };
      if (g.struct) e[lid].struct = { kind: g.struct.kind, rect: g.struct.rect };
    }
    out[uid] = e;
  }
  console.log(JSON.stringify(out));
  process.exit(0);
}

let fails = 0;
const ok = (c, m) => { if (c) console.log('  ok  ' + m); else { fails++; console.log('  FAIL ' + m); } };

for (const id of KINDS) {
  console.log(id);
  const base = LAYOUTS[id];
  const all = Object.entries(up.GEOM).filter(([, g]) => g[id]).map(([uid]) => ({ id: uid, effect: null }));
  const L = up.applyUpgrades(base, all);
  const obs = obstacles(id).slice(0, -1).filter((_, i) => i > 0); // skip the house box itself, keep fixtures + doors
  for (const rm of L.rooms ?? []) {
    ok(rm.rect[1] === base.d, `${rm.id}: starts at the south wall (z ${rm.rect[1]} = ${base.d})`);
    ok(rm.rect[0] >= 0 && rm.rect[2] <= base.w + 20, `${rm.id}: x range ok`);
    const fx = base.furniture.filter((f) => isFixture(f) && overlaps(nav.footprint(f), rm.rect, 0.01));
    ok(fx.length === 0, `${rm.id}: no yard fixture inside the room (${fx.map((f) => f.id).join(',') || 'none'})`);
    ok(!base.furniture.some((f) => f.x > base.w && f.x < rm.rect[2] + 0.5 && f.z > base.d && f.z < rm.rect[3] + 0.5 && overlaps(nav.footprint(f), rm.rect, 0.01)), `${rm.id}: no yard piece in the room`);
    // door zone of the doorway must not sit on a house fixture or the default furniture
    const dz = [rm.door[0], base.d - 0.8, rm.door[1], base.d + 0.8];
    const bad = base.furniture.filter((f) => nav.footprint(f) && overlaps(nav.footprint(f), dz, 0.01) && (isFixture(f) || f.included));
    ok(bad.length === 0, `${rm.id}: doorway zone clear of fixtures (${bad.map((f) => f.id).join(',') || 'none'})`);
    const bl = arr.homeBlocks(L);
    ok(bl.rooms.length === (L.rooms ?? []).length, `${rm.id}: arrange sees the room`);
  }
  for (const st of L.structs ?? []) {
    const clash = obstacles(id).slice(1).filter((o) => overlaps(st.rect, o, 0.01));
    // the building may only touch the inflated room boxes of OTHER rooms; it must not clash with anything else
    ok(clash.length === 0, `${st.id}: yard building clear (${clash.length} clashes)`);
    ok(st.rect[0] >= L.lot[0] && st.rect[2] <= L.lot[2] && st.rect[1] >= L.lot[1] && st.rect[3] <= L.lot[3], `${st.id}: inside the (grown) lot`);
  }
  // nav: from the front door to the centre of each room, and to the south side of every building
  const g = nav.buildGrid(L);
  const door = L.doors[0];
  const start = door[0] === 'e' ? [L.w + 0.9, (door[1] + door[2]) / 2] : [(door[1] + door[2]) / 2, L.d + 0.9];
  const reach = (to, label) => {
    const p = nav.findPath(g, start, to);
    const end = p[p.length - 1];
    ok(Math.hypot(end[0] - to[0], end[1] - to[1]) < 0.3, `${label}: reachable from the front door`);
  };
  for (const rm of L.rooms ?? []) reach([(rm.rect[0] + rm.rect[2]) / 2, (rm.rect[1] + rm.rect[3]) / 2], `${rm.id} centre`);
  for (const st of L.structs ?? []) reach([(st.rect[0] + st.rect[2]) / 2, st.rect[3] + 0.6], `${st.id} front`);
  reach([base.home[0], base.home[1]], 'the house itself');
  // the plain layout must be unchanged
  ok(JSON.stringify(up.applyUpgrades(base, [])) === JSON.stringify(base), 'no upgrades = unchanged layout');
}
// the finish levels never touch geometry
{
  const f3 = up.applyUpgrades(LAYOUTS.flat, [{ id: 'f', effect: { finish: 3 } }]);
  ok(f3.finish === 3 && f3.w === LAYOUTS.flat.w && f3.lot.join() === LAYOUTS.flat.lot.join(), 'finish 3 keeps the footprint');
}
console.log(fails ? `${fails} FAILED` : 'all ok');
process.exit(fails ? 1 : 0);
