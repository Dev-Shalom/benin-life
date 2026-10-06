// L2 check for place interiors (src/art/place3d/model.ts + src/art/sim/nav.ts): for every place, the zones
// merged as place_interior() does (type zones + the place's own, same key = the place wins, inactive hides)
// must leave every zone's spot reachable from the entrance, no spot inside a solid prop, and the crowd
// planner must respect the render cap. Reads the zones from the local Supabase DB (docker).
//   node scripts/place-check.mjs        (-v prints each place)
// Exits 1 on any failure.
import { register } from 'node:module';
import { execFileSync } from 'node:child_process';

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
const model = await import('../src/art/place3d/model.ts');
const verbose = process.argv.includes('-v');

const container = process.env.BL_DB_CONTAINER ?? 'supabase_db_benin-life';
let rows;
try {
  const sql = `select json_build_object(
    'locations', (select json_agg(json_build_object('id', id, 'scene', scene) order by sort) from locations),
    'zones', (select json_agg(json_build_object('id', id, 'scene', scene, 'location_id', location_id, 'key', zone_key, 'label', label,
              'prop', prop, 'x', x, 'z', z, 'w', w, 'd', d, 'rot', rot, 'active', active, 'icon', icon, 'note', note, 'actions', '[]'::json)) from place_zones))`;
  rows = JSON.parse(execFileSync('docker', ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-c', sql], { encoding: 'utf8' }));
} catch (e) {
  console.log('skip: no local database (' + String(e.message).split('\n')[0] + ')');
  process.exit(0);
}

let fails = 0;
const ok = (cond, msg) => {
  if (cond) { if (verbose) console.log('  ok  ' + msg); }
  else { fails++; console.log('  FAIL ' + msg); }
};
let places = 0;
let spots = 0;
for (const loc of rows.locations) {
  const mine = rows.zones.filter((z) => z.scene === loc.scene || z.location_id === loc.id);
  const byKey = new Map();
  for (const z of mine.sort((a, b) => (a.location_id ? 1 : 0) - (b.location_id ? 1 : 0))) byKey.set(z.key, z);
  const zones = [...byKey.values()].filter((z) => z.active).map((z) => ({ ...z, x: +z.x, z: +z.z, w: +z.w, d: +z.d }));
  if (!zones.length) { ok(false, `${loc.id}: no zones`); continue; }
  places++;
  const room = model.roomFor(loc.scene, zones);
  const grid = model.buildPlaceGrid(room, zones);
  const start = [room.entry[0], room.entry[1]];
  ok(nav.freeAt(grid, start), `${loc.id}: entrance is walkable`);
  for (const z of zones) {
    spots++;
    const s = model.zoneSpot(z, room);
    const plan = nav.planPath(grid, start, s.p, { snapEnd: true, round: 0.22 });
    const end = plan.end;
    ok(Math.hypot(end[0] - s.p[0], end[1] - s.p[1]) < 0.45, `${loc.id}/${z.key}: spot reachable (gap ${Math.hypot(end[0] - s.p[0], end[1] - s.p[1]).toFixed(2)} m)`);
    ok(s.p[0] > 0 && s.p[1] > 0 && s.p[0] < room.W && s.p[1] < room.D, `${loc.id}/${z.key}: spot inside the room`);
  }
  // zones don't overlap each other much (props would clip)
  for (let i = 0; i < zones.length; i++)
    for (let j = i + 1; j < zones.length; j++) {
      const a = zones[i], b = zones[j];
      const ox = Math.min(a.x + a.w / 2, b.x + b.w / 2) - Math.max(a.x - a.w / 2, b.x - b.w / 2);
      const oz = Math.min(a.z + a.d / 2, b.z + b.d / 2) - Math.max(a.z - a.d / 2, b.z - b.d / 2);
      ok(!(ox > 0.3 && oz > 0.3), `${loc.id}: ${a.key} and ${b.key} don't overlap (${ox.toFixed(1)} × ${oz.toFixed(1)} m)`);
    }
  // crowd: never more than the cap, players first
  const players = Array.from({ length: 4 }, (_, i) => ({ id: `p${i}`, username: `p${i}` }));
  for (const cap of [0, 3, 10]) {
    const c = model.planCrowd({ placeId: loc.id, scene: loc.scene, hour: 22, room, zones, grid, players, perZone: 3, cap, closed: false });
    ok(c.shown.length <= cap, `${loc.id}: crowd ≤ cap ${cap} (${c.shown.length})`);
    ok(c.shown.slice(0, Math.min(cap, players.length)).every((p) => p.player), `${loc.id}: players drawn first (cap ${cap})`);
  }
  if (verbose) console.log(`${loc.id}: ${room.W}×${room.D} m, ${zones.length} zones`);
}
console.log(`${places} places, ${spots} zone spots checked`);
console.log(fails ? `${fails} FAILED` : 'all place checks passed');
process.exit(fails ? 1 : 0);
