#!/usr/bin/env node
/**
 * Convert a small OpenStreetMap API XML extract to the compact building-footprint
 * dataset consumed by the Three.js Benin City renderer.
 *
 * Usage: node scripts/import-osm-buildings.mjs <extract.osm> <output.json>
 * Dataset output is derived from OSM and is available under ODbL 1.0.
 */
import { readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { mkdir } from 'node:fs/promises';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error('Usage: node scripts/import-osm-buildings.mjs <extract.osm> <output.json>');
  process.exit(2);
}

const CENTER = { lat: 6.33297, lon: 5.62262 };
const MAP = { x: 500, y: 500, unitsPerKm: 80 };
const DEG_KM = 111.32;
const xml = await readFile(input, 'utf8');
const attr = (s) => Object.fromEntries([...s.matchAll(/([\w:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
const nodes = new Map();
for (const m of xml.matchAll(/<node\b([^>]*)\/?\s*>/g)) {
  const a = attr(m[1]);
  if (a.id && a.lat && a.lon) nodes.set(a.id, [Number(a.lat), Number(a.lon)]);
}
const coordinate = ([lat, lon]) => [
  MAP.x + (lon - CENTER.lon) * DEG_KM * Math.cos((CENTER.lat * Math.PI) / 180) * MAP.unitsPerKm,
  MAP.y - (lat - CENTER.lat) * DEG_KM * MAP.unitsPerKm,
];
const round = (v) => Math.round(v * 100) / 100;
const features = [];
let tagged = 0;
let missingNodes = 0;
for (const m of xml.matchAll(/<way\b([^>]*)>([\s\S]*?)<\/way>/g)) {
  const id = attr(m[1]).id;
  const body = m[2];
  const tags = Object.fromEntries([...body.matchAll(/<tag\b([^>]*)\/?\s*>/g)].map((x) => {
    const a = attr(x[1]);
    return [a.k, a.v];
  }));
  if (!tags.building || tags.building === 'no' || tags['building:part']) continue;
  tagged++;
  const refs = [...body.matchAll(/<nd\b([^>]*)\/?\s*>/g)].map((x) => attr(x[1]).ref);
  if (refs.length < 4 || refs[0] !== refs.at(-1)) continue;
  const ll = refs.map((ref) => nodes.get(ref));
  if (ll.some((p) => !p)) { missingNodes++; continue; }
  const ring = ll.slice(0, -1).map(coordinate).map(([x, y]) => [round(x), round(y)]);
  if (ring.length < 3) continue;
  const xs = ring.map((p) => p[0]), ys = ring.map((p) => p[1]);
  const cx = xs.reduce((a, b) => a + b, 0) / ring.length;
  const cy = ys.reduce((a, b) => a + b, 0) / ring.length;
  // Keep only the source-covered central city window. This boundary is also used
  // to suppress procedural buildings there; outside it, the existing LOD stays.
  if (cx < 400 || cx > 600 || cy < 400 || cy > 600) continue;
  const levelsRaw = Number.parseFloat(tags['building:levels'] ?? '');
  const heightRaw = Number.parseFloat(tags.height ?? '');
  features.push({
    id,
    levels: Number.isFinite(levelsRaw) ? Math.max(1, Math.min(20, levelsRaw)) : 0,
    heightM: Number.isFinite(heightRaw) ? Math.max(2, Math.min(80, heightRaw)) : 0,
    kind: tags.building,
    ring,
  });
}

features.sort((a, b) => Number(a.id) - Number(b.id));
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify({
  source: 'OpenStreetMap contributors',
  retrieved: new Date().toISOString().slice(0, 10),
  license: 'ODbL-1.0',
  center: CENTER,
  bounds: [400, 400, 600, 600],
  features,
}), 'utf8');
console.log(`Saved ${features.length} closed building footprints (${tagged} tagged buildings; ${missingNodes} incomplete ways).`);
