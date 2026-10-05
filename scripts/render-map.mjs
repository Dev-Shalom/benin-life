// Render the Benin City map (day + night) to PNG for visual review.
// Usage: node scripts/render-map.mjs [outDir] [--old]
//   --old  use the seed positions only (skip the map_geo migration) for before/after comparison
// Locations come from supabase/migrations/20261004000200_core_seed.sql with x/y overridden by
// supabase/migrations/20261005000100_map_geo.sql. Writes:
//   map-day.png / map-night.png        1000x1000, zoom 1 (every label tier)
//   phone-day.png / phone-night.png    390x844 phone viewport at the app's initial zoom (cover)
//   zoom-day.png                       1000x1000 window at zoom 2 around the centre
import { createServer } from 'vite';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
function loadChromium() {
  try { return require('playwright').chromium; } catch { /* fall through */ }
  const globalRoot = require('node:child_process').execSync('npm root -g').toString().trim();
  return require(resolve(globalRoot, 'playwright')).chromium;
}

const args = process.argv.slice(2);
const old = args.includes('--old');
const outDir = resolve(args.find((a) => !a.startsWith('--')) ?? 'render-out/map');
mkdirSync(outDir, { recursive: true });

/* ---------- locations from the seed + geo migration ---------- */
function sqlValues(sql) {
  // split the VALUES list of the locations insert into tuples, honouring '' escapes
  const start = sql.indexOf('insert into public.locations');
  const body = sql.slice(sql.indexOf('values', start) + 6, sql.indexOf(';\n', start));
  const rows = [];
  let i = 0;
  while (i < body.length) {
    if (body[i] !== '(') { i++; continue; }
    const fields = [];
    let cur = '';
    let inStr = false;
    i++;
    for (; i < body.length; i++) {
      const c = body[i];
      if (inStr) {
        if (c === "'" && body[i + 1] === "'") { cur += "'"; i++; }
        else if (c === "'") inStr = false;
        else cur += c;
      } else if (c === "'") inStr = true;
      else if (c === ',') { fields.push(cur.trim()); cur = ''; }
      else if (c === ')') { fields.push(cur.trim()); i++; break; }
      else cur += c;
    }
    rows.push(fields);
  }
  return rows;
}
const seed = readFileSync(resolve('supabase/migrations/20261004000200_core_seed.sql'), 'utf8');
const geo = old ? '' : readFileSync(resolve('supabase/migrations/20261005000100_map_geo.sql'), 'utf8');
const moved = new Map([...geo.matchAll(/set x = ([\d.]+), y = ([\d.]+) where id = '(\w+)'/g)].map((m) => [m[3], [+m[1], +m[2]]]));
const num = (s) => Number(s.startsWith('.') ? '0' + s : s);
const locations = sqlValues(seed).filter((f) => f.length >= 15).map((f) => {
  const [id, name, district, scene, x, y, risk, nrm, cctv, keke, cong, remote, actions, sort, blurb] = f;
  const [mx, my] = moved.get(id) ?? [num(x), num(y)];
  return {
    id, name, district, scene, blurb, x: mx, y: my, risk: num(risk), night_risk_mult: num(nrm),
    cctv: cctv === 'true', keke_ok: keke === 'true', congestion: num(cong), remote_km: num(remote),
    actions: actions.replace(/[{}]/g, '').split(','), sort: Number(sort),
  };
});
console.log(`${locations.length} locations (${moved.size} moved by map_geo)`);

/* ---------- render ---------- */
const vite = await createServer({ server: { middlewareMode: true }, appType: 'custom', logLevel: 'error' });
const { createElement } = await import('react');
const { renderToStaticMarkup } = await import('react-dom/server');
const t0 = performance.now();
const model = await vite.ssrLoadModule('/src/art/map/mapModel.ts');
const m = model.getMapModel();
console.log(`map model: ${Math.round(performance.now() - t0)} ms (incl. module load)`, JSON.stringify(m.stats));
const { BeninMapSvg } = await vite.ssrLoadModule('/src/art/map/BeninMap.tsx');

const svgFor = (night, zoom, extra = {}) =>
  renderToStaticMarkup(createElement(BeninMapSvg, { locations, night, zoom, onSelect: () => {}, currentId: 'ekenwan_room', ...extra }));

/* ---------- layout diagnostics: pin overlaps, label sides, pin labels vs district labels ---------- */
const pins = await vite.ssrLoadModule('/src/art/map/MapPins.tsx');
const geoMod = await vite.ssrLoadModule('/src/art/map/mapGeo.ts');
const ov = (a, b) => a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1];
const districtBoxes = geoMod.DISTRICT_LABELS.filter((d) => !d.rot).map((d) => {
  const fs = d.size ?? 18;
  const w = d.t.length * fs * 0.62 + (d.t.length - 1) * fs * 0.22;
  return { t: d.t, box: [d.x - w / 2, d.y - fs * 0.78, d.x + w / 2, d.y + fs * 0.1] };
});
for (const zoom of [0.844, 1, 2]) {
  const ps = pins.pinScaleFor(zoom);
  const sides = pins.layoutLabels(locations, zoom, 'ekenwan_room');
  const problems = [];
  const badge = (l) => [l.x - 13 * ps, l.y - 37 * ps, l.x + 13 * ps, l.y + 2 * ps];
  for (let i = 0; i < locations.length; i++)
    for (let j = i + 1; j < locations.length; j++)
      if (ov(badge(locations[i]), badge(locations[j]))) problems.push(`pins overlap: ${locations[i].id} / ${locations[j].id}`);
  for (const l of locations) {
    const meta = geoMod.PIN_META[l.id];
    const side = sides.get(l.id);
    if (!side) { if (zoom >= 0.95 || meta?.tier === 1) problems.push(`no label: ${l.id}`); continue; }
    if (meta?.side && side !== meta.side) problems.push(`side ${l.id}: wanted ${meta.side}, got ${side}`);
    const text = geoMod.shortName(l.id, l.name);
    const w = text.length * 11.5 * 0.56 * ps;
    const h = 11.5 * 1.15 * ps;
    const box = side === 'r' ? [l.x + 15 * ps, l.y - 31 * ps, l.x + 15 * ps + w, l.y - 31 * ps + h]
      : side === 'l' ? [l.x - 15 * ps - w, l.y - 31 * ps, l.x - 15 * ps, l.y - 31 * ps + h]
      : side === 't' ? [l.x - w / 2, l.y - 52 * ps, l.x + w / 2, l.y - 52 * ps + h]
      : [l.x - w / 2, l.y + 3 * ps, l.x + w / 2, l.y + 3 * ps + h];
    for (const d of districtBoxes) {
      if (ov(box, d.box)) problems.push(`label ${l.id} covers district ${d.t}`);
      if (ov(badge(l), d.box)) problems.push(`pin ${l.id} covers district ${d.t}`);
    }
  }
  console.log(`zoom ${zoom}: ${problems.length ? '\n  ' + problems.join('\n  ') : 'clean'}`);
}

const chromium = loadChromium();
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage({ viewport: { width: 1000, height: 1000 } });

async function shot(file, svg, vw, vh, s, cx, cy) {
  // place the 1000x1000 map scaled by s so that map point (cx, cy) is at the viewport centre
  const tx = Math.min(0, Math.max(vw - 1000 * s, vw / 2 - cx * s));
  const ty = Math.min(0, Math.max(vh - 1000 * s, vh / 2 - cy * s));
  await page.setViewportSize({ width: vw, height: vh });
  await page.setContent(`<html><body style="margin:0;overflow:hidden;background:#b57447"><div style="position:absolute;left:0;top:0;width:1000px;height:1000px;transform-origin:0 0;transform:translate(${tx}px,${ty}px) scale(${s})">${svg}</div></body></html>`);
  await page.screenshot({ path: resolve(outDir, file) });
  console.log(file);
}

const pfx = old ? 'old-' : '';
for (const night of [false, true]) {
  const tag = night ? 'night' : 'day';
  const full = svgFor(night, 1);
  writeFileSync(resolve(outDir, `${pfx}map-${tag}.svg`), full);
  await shot(`${pfx}map-${tag}.png`, full, 1000, 1000, 1, 500, 500);
  // phone: initial zoom = cover = 844/1000, centred on the player's home (Ekenwan)
  const cover = 844 / 1000;
  const cur = locations.find((l) => l.id === 'ekenwan_room');
  await shot(`${pfx}phone-${tag}.png`, svgFor(night, cover), 390, 844, cover, cur.x, cur.y);
}
await shot(`${pfx}zoom-day.png`, svgFor(false, 2), 1000, 1000, 2, 500, 470);
await shot(`${pfx}zoom-north-day.png`, svgFor(false, 2), 1000, 1000, 2, 470, 220);
await shot(`${pfx}zoom-east-day.png`, svgFor(false, 2), 1000, 1000, 2, 700, 500);
await shot(`${pfx}zoom-east-night.png`, svgFor(true, 2), 1000, 1000, 2, 700, 560);

await browser.close();
await vite.close();
