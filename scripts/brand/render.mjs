// Renders the PNG brand assets listed by build_brand.py with headless Chromium, then builds favicon.ico.
// Run from the repo root: node scripts/brand/render.mjs   (needs playwright + ImageMagick `convert`)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = await import(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright/index.mjs')); }
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const jobs = JSON.parse(fs.readFileSync(path.join(root, 'scripts/brand/.fonts/jobs.json'), 'utf8'));
const b = await chromium.launch();
const p = await b.newPage();
for (const j of jobs) {
  const w = j.w, h = j.h ?? j.w;
  await p.setViewportSize({ width: w, height: h });
  const svg = fs.readFileSync(path.join(root, j.svg));
  await p.setContent(`<!doctype html><body style="margin:0;background:transparent"><img src="data:image/svg+xml;base64,${svg.toString('base64')}" style="display:block;width:${w}px;height:${h}px">`, { waitUntil: 'load' });
  await p.screenshot({ path: path.join(root, j.out), omitBackground: true });
  console.log('wrote', j.out);
}
await b.close();
const f = (n) => path.join(root, 'scripts/brand/.fonts', n);
execFileSync('convert', [f('fav-16.png'), f('fav-32.png'), f('fav-48.png'), path.join(root, 'public/favicon.ico')]);
console.log('wrote public/favicon.ico');
