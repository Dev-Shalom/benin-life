// Home floor-plan check (docs/HUD_HOME.md "Home sizes"). Plain node script (Node 22+, type stripping):
//   node scripts/home-space-check.mjs        # exit 1 on any failure
//   node scripts/home-space-check.mjs --sql  # print the home_layouts rows the migration seeds
//   node scripts/home-space-check.mjs --lights-sql  # print the L1 built-in lights per layout (home_layouts.lights)
// For every layout, with the default furnishing and with the LAPO / NEPO starter sets, checks:
//   - every piece stands fully inside the house (or, for yard pieces, inside the lot)
//   - the server's placement rule (arrange.ts placementIssue = bl_furniture_check) accepts every owned piece
//   - solid pieces never overlap each other, a fixture or a partition (default set too)
//   - the Sim can walk from the front door to every piece's spot, and to the middle of every room
//   - the front door and every doorway keep a 0.9 m clear walk
//   - tiers get strictly bigger (face_me < self_contain < flat < duplex; hostel <= face_me)
// Also prints the tightest gaps between pieces (warnings only) so the plan stays roomy.
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
const { LAYOUTS, KINDS, LIGHTS, LIGHT_BUILTIN_IDS, isFixture, furnishLayout } = await import('../src/art/home3d/model.ts');
const nav = await import('../src/art/home3d/nav.ts');
const arr = await import('../src/art/home3d/arrange.ts');

const mode = process.argv[2] ?? '';
let fails = 0;
const ok = (c, m) => { if (c) console.log('  ok  ' + m); else { fails++; console.log('  FAIL ' + m); } };
const overlaps = (a, b, e = 0.02) => Math.min(a[2], b[2]) - Math.max(a[0], b[0]) > e && Math.min(a[3], b[3]) - Math.max(a[1], b[1]) > e;

// the seeds of 20261006000400_starter_furniture.sql (the hostel nepo room takes a single bed)
const SETS = {
  lapo: [
    { id: 'drum_bucket', kind: 'drum_bucket', slot: 'bath', activities: ['bathe'] },
    { id: 'stool', kind: 'stool', slot: 'seat', activities: ['sit_rest'] },
    { id: 'kerosene_stove', kind: 'kerosene_stove', slot: 'stove', activities: ['cook_home'] },
    { id: 'foam_mat', kind: 'mattress', slot: 'bed', activities: ['sleep', 'nap'] },
  ],
  nepo: [
    { id: 'bed_double', kind: 'bed_double', slot: 'bed', activities: ['sleep', 'nap'] },
    { id: 'sofa', kind: 'sofa', slot: 'sofa', activities: ['relax_sofa'] },
    { id: 'tv', kind: 'tv', slot: 'tv', activities: ['watch_tv'] },
    { id: 'fridge', kind: 'fridge', slot: 'fridge', activities: ['cold_drink'] },
    { id: 'gas_cooker', kind: 'gas_cooker', slot: 'stove', activities: ['cook_home'] },
    { id: 'wardrobe', kind: 'wardrobe', slot: 'wardrobe', activities: [] },
    { id: 'rug', kind: 'rug', slot: 'rug', activities: [] },
    { id: 'centre_table', kind: 'centre_table', slot: 'ctable', activities: [] },
  ],
};
const setFor = (name, id) => (name === 'nepo' && id === 'hostel' ? SETS.nepo.map((p) => (p.id === 'bed_double' ? { ...p, id: 'bed_single', kind: 'bed_single' } : p)) : SETS[name]);

if (mode === '--sql') {
  const q = (n) => String(Math.round(n * 100) / 100);
  const rows = [];
  for (const id of ['hostel', 'face_me', 'self_contain', 'flat', 'duplex']) {
    const L = LAYOUTS[id];
    const hb = arr.homeBlocks(id);
    const inc = L.furniture.filter((f) => f.included && !LIGHT_BUILTIN_IDS.has(f.included)).map((f) => ({ id: f.id, furniture: f.included, kind: f.kind, x: f.x, z: f.z, rot: f.rot ?? 0 }));
    rows.push(`  ('${id}', ${q(L.w)}, ${q(L.d)}, '${JSON.stringify(L.lot.map(Number))}'::jsonb, '${JSON.stringify(hb.blocks)}'::jsonb, '${JSON.stringify(hb.doors)}'::jsonb, '${JSON.stringify(L.slots)}'::jsonb, '${JSON.stringify(inc)}'::jsonb)`);
  }
  console.log(rows.join(',\n'));
  process.exit(0);
}

if (mode === '--lights-sql') {
  const rows = [];
  for (const id of ['hostel', 'face_me', 'self_contain', 'flat', 'duplex']) {
    const L = LAYOUTS[id];
    const lights = L.furniture.filter((f) => f.included && LIGHT_BUILTIN_IDS.has(f.included)).map((f) => ({ id: f.id, furniture: f.included, kind: f.kind, x: f.x, z: f.z, rot: f.rot ?? 0 }));
    rows.push(`  ('${id}', '${JSON.stringify(lights)}'::jsonb)`);
  }
  console.log(rows.join(',\n'));
  process.exit(0);
}

// L1: the rooms of each plan (a built-in light must hang in every one)
const ROOMS = {
  hostel: [[0, 0, 6.2, 5.0]],
  face_me: [[0, 0, 6.8, 5.6]],
  self_contain: [[0, 0, 2.6, 2.6], [2.6, 0, 9.0, 2.6], [5.0, 2.6, 9.0, 6.8], [0, 2.6, 5.0, 6.8]],
  flat: [[0, 0, 5.0, 4.2], [5.0, 0, 9.2, 3.6], [9.2, 0, 13.0, 3.2], [0, 4.2, 9.2, 9.4], [9.2, 4.2, 13.0, 9.4]],
  duplex: [[0, 0, 6.0, 5.0], [6.0, 0, 12.2, 4.2], [12.2, 0, 15.4, 3.6], [15.4, 0, 19.0, 3.6], [15.2, 6.6, 19.0, 9.8], [13.6, 9.8, 19.0, 13.4], [0, 5.0, 9.6, 13.4], [9.6, 5.0, 15.2, 13.4]],
};
const inRect = (f, r) => f.x >= r[0] && f.x <= r[2] && f.z >= r[1] && f.z <= r[3];

const area = (id) => LAYOUTS[id].w * LAYOUTS[id].d;
console.log('sizes');
for (const id of Object.keys(LAYOUTS)) console.log(`  ${id}: ${LAYOUTS[id].w} x ${LAYOUTS[id].d} = ${area(id).toFixed(1)} m2, lot ${LAYOUTS[id].lot.join(',')}`);
ok(area('hostel') <= area('face_me'), 'hostel is not bigger than face-me');
ok(area('face_me') * 1.1 < area('self_contain') && area('self_contain') * 1.3 < area('flat') && area('flat') * 1.3 < area('duplex'), 'tiers grow: face-me < self-contain < flat < duplex');
ok(LAYOUTS.duplex.w === Math.max(...Object.values(LAYOUTS).map((l) => l.w)), 'duplex is the widest');

for (const id of Object.keys(LAYOUTS)) {
  const base = LAYOUTS[id];
  const door = base.doors[0];
  const start = door[0] === 'e' ? [base.w + 0.9, (door[1] + door[2]) / 2] : [(door[1] + door[2]) / 2, base.d + 0.9];
  for (const name of ['default', 'lapo', 'nepo']) {
    console.log(`${id} / ${name}`);
    const L = name === 'default' ? base : furnishLayout(base, setFor(name, id));
    const g = nav.buildGrid(L);
    // bounds
    const out = [];
    // the bathing corner of the hostel / face-me / self-contain is in the compound (slot "bath"), as before
    const yardBath = (f) => f.kind === 'drum_bucket' && (id === 'hostel' || id === 'face_me' || id === 'self_contain');
    for (const f of L.furniture) {
      if (isFixture(f) || yardBath(f)) continue;
      const r = nav.footprint(f);
      const place = KINDS[f.kind].place ?? 'in';
      const inHouse = r[0] >= -1e-6 && r[1] >= -1e-6 && r[2] <= base.w + 1e-6 && r[3] <= base.d + 1e-6;
      const inLot = r[0] >= base.lot[0] && r[1] >= base.lot[1] && r[2] <= base.lot[2] && r[3] <= base.lot[3];
      if (place === 'in' || place === 'wall' ? !inHouse : place === 'out' ? !inLot : !inHouse && !inLot) out.push(f.id);
    }
    ok(out.length === 0, `inside the plan${out.length ? ' (not: ' + out.join(', ') + ')' : ''}`);
    // server rule for owned pieces
    if (name !== 'default') {
      const bad = [];
      for (const f of L.furniture) {
        if (!f.id.startsWith('own_') || yardBath(f)) continue;
        const why = arr.placementIssue(id, f, L.furniture);
        if (why) bad.push(`${f.id}: ${why}`);
      }
      ok(bad.length === 0, `server placement rule accepts every starter piece${bad.length ? ' (' + bad.join('; ') + ')' : ''}`);
    }
    // solid overlaps (any piece vs piece / fixture / partition)
    const solids = L.furniture.filter((f) => KINDS[f.kind].solid && !(f.y > 0) && !f.included);
    const clash = [];
    for (let i = 0; i < solids.length; i++) {
      for (let j = i + 1; j < solids.length; j++) if (overlaps(nav.footprint(solids[i]), nav.footprint(solids[j]))) clash.push(`${solids[i].id}/${solids[j].id}`);
      for (const [x1, z1, x2, z2] of L.partitions) {
        if (overlaps(nav.footprint(solids[i]), [Math.min(x1, x2) - 0.06, Math.min(z1, z2) - 0.06, Math.max(x1, x2) + 0.06, Math.max(z1, z2) + 0.06])) clash.push(`${solids[i].id}/wall`);
      }
    }
    ok(clash.length === 0, `no solid overlaps${clash.length ? ' (' + clash.join(', ') + ')' : ''}`);
    // walking: door -> every spot
    const unreachable = [];
    for (const f of L.furniture) {
      const k = KINDS[f.kind];
      if (!k.group) continue;
      const [lx, lz] = k.spot ?? [0, k.d / 2 + 0.35];
      const s = nav.toLayout(f, lx, lz);
      const q = nav.planPath(g, start, s);
      if (!q.reachable || Math.hypot(q.end[0] - s[0], q.end[1] - s[1]) > 0.35) unreachable.push(f.id);
    }
    ok(unreachable.length === 0, `door -> every activity spot${unreachable.length ? ' (not: ' + unreachable.join(', ') + ')' : ''}`);
    // every room's middle
    const mids = [[base.home[0], base.home[1]], [base.w / 2, base.d / 2]];
    for (const [px, pz] of mids) {
      const q = nav.planPath(g, start, [px, pz]);
      ok(q.reachable, `door -> (${px.toFixed(1)}, ${pz.toFixed(1)})`);
    }
    // roomy: tight gaps between solid pieces (warning only)
    const tight = [];
    for (let i = 0; i < solids.length; i++) {
      for (let j = i + 1; j < solids.length; j++) {
        const a = nav.footprint(solids[i]), b = nav.footprint(solids[j]);
        const gx = Math.max(a[0], b[0]) - Math.min(a[2], b[2]);
        const gz = Math.max(a[1], b[1]) - Math.min(a[3], b[3]);
        const ox = Math.min(a[2], b[2]) - Math.max(a[0], b[0]);
        const oz = Math.min(a[3], b[3]) - Math.max(a[1], b[1]);
        if ((gx >= 0.06 && gx < 0.6 && oz > 0.3) || (gz >= 0.06 && gz < 0.6 && ox > 0.3)) tight.push(`${solids[i].id}/${solids[j].id} ${Math.max(gx, gz).toFixed(2)}`);
      }
    }
    if (tight.length) console.log('  warn tight gaps: ' + tight.join(', '));
    // doorway walk width
    for (const d of L.doors) ok(d[2] - d[1] >= 0.9, `door ${d.join(' ')} is at least 0.9 m wide`);
  }
}
// L1 lighting: every plan comes with a working light in each room, all placeable by the server rule
console.log('lighting');
for (const id of Object.keys(LAYOUTS)) {
  const L = LAYOUTS[id];
  const lights = L.furniture.filter((f) => f.included && LIGHT_BUILTIN_IDS.has(f.included));
  const bad = lights.filter((f) => !LIGHTS[f.kind]);
  ok(lights.length > 0 && bad.length === 0, `${id}: ${lights.length} built-in lights, all light kinds`);
  const dark = ROOMS[id].filter((r) => !lights.some((f) => LIGHTS[f.kind] && LIGHTS[f.kind].mount === 'ceiling' && inRect(f, r)));
  ok(dark.length === 0, `${id}: a ceiling light in every room${dark.length ? ' (dark: ' + dark.map((r) => r.join(',')).join(' | ') + ')' : ''}`);
  const notOk = lights.map((f) => { const why = arr.placementIssue(id, { ...f, id: 'own_' + f.id }, []); return why ? `${f.id}: ${why}` : null; }).filter(Boolean);
  ok(notOk.length === 0, `${id}: the server placement rule accepts every built-in light${notOk.length ? ' (' + notOk.join('; ') + ')' : ''}`);
}
console.log(fails ? `\n${fails} FAILED` : '\nall ok');
process.exit(fails ? 1 : 0);
