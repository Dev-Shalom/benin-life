// Render scene SVGs (day + night) to PNG for visual review.
// Usage: node scripts/render-scenes.mjs [outDir] [scene ...]
// Writes <outDir>/<scene>-day.png, <scene>-night.png and contact sheet sheet.png.
import { createServer } from 'vite';
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
function loadChromium() {
  try { return require('playwright').chromium; } catch { /* fall through */ }
  const globalRoot = require('node:child_process').execSync('npm root -g').toString().trim();
  return require(resolve(globalRoot, 'playwright')).chromium;
}

const [outArg, ...only] = process.argv.slice(2);
const outDir = resolve(outArg ?? 'render-out');
mkdirSync(outDir, { recursive: true });

const sceneDir = resolve('src/art/scenes');
const scenes = (only.length ? only : readdirSync(sceneDir)
  .filter((f) => f.endsWith('.tsx') && !f.startsWith('_'))
  .map((f) => f.replace(/\.tsx$/, ''))).sort();

const vite = await createServer({ server: { middlewareMode: true }, appType: 'custom', logLevel: 'error' });
const { createElement } = await import('react');
const { renderToStaticMarkup } = await import('react-dom/server');

const chromium = loadChromium();
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const page = await browser.newPage({ viewport: { width: 800, height: 450 } });

const tiles = [];
for (const name of scenes) {
  const mod = await vite.ssrLoadModule(`/src/art/scenes/${name}.tsx`);
  for (const night of [false, true]) {
    const svg = renderToStaticMarkup(createElement(mod.default, { night }));
    const file = `${name}-${night ? 'night' : 'day'}`;
    writeFileSync(resolve(outDir, `${file}.svg`), svg);
    await page.setContent(`<html><body style="margin:0;width:800px;height:450px">${svg}</body></html>`);
    await page.screenshot({ path: resolve(outDir, `${file}.png`) });
    tiles.push({ file, svg });
    console.log(`${file}.png`);
  }
}

// Contact sheet: two columns (day | night), 400x225 tiles.
const sheet = `<html><body style="margin:0;background:#222;display:grid;grid-template-columns:400px 400px;gap:4px;font:12px sans-serif;color:#fff">${tiles
  .map((t) => `<div style="position:relative;width:400px;height:225px">${t.svg}<span style="position:absolute;left:4px;top:2px;background:#0008;padding:1px 4px">${t.file}</span></div>`)
  .join('')}</body></html>`;
await page.setViewportSize({ width: 804, height: 100 });
await page.setContent(sheet);
await page.screenshot({ path: resolve(outDir, 'sheet.png'), fullPage: true });
console.log('sheet.png');

await browser.close();
await vite.close();
