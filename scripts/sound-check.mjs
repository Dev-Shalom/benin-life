// Dev check for the sound system (docs/SOUND.md). Needs the dev server (window.__blSound.stats() is DEV only) and a
// test account. Travels between places, hides/shows the tab, stalls the main thread, spams hype and mute, and
// asserts: one AudioContext, one soundtrack at a time, bounded voices, no catch-up burst, mute respected.
//   BASE=http://localhost:5242 PW=/path/to/playwright/index.mjs EMAIL=... PASSWORD=... GFX=low node scripts/sound-check.mjs
const PW = process.env.PW || '/opt/node22/lib/node_modules/playwright/index.mjs';
const { chromium } = await import(PW);
const BASE = process.env.BASE || 'http://localhost:5242';
const EMAIL = process.env.EMAIL || 'r6nepo@test.local';
const PASSWORD = process.env.PASSWORD || 'secret123';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fails = [];
const ok = (cond, msg) => { console.log((cond ? 'PASS ' : 'FAIL ') + msg); if (!cond) fails.push(msg); };

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
await ctx.addInitScript((g) => { try { const k = 'bl.prefs.v1'; const v = JSON.parse(localStorage.getItem(k) || '{}'); v.graphics = g; v.keepOwnMusic = false; localStorage.setItem(k, JSON.stringify(v)); } catch {} }, process.env.GFX || 'low');
const page = await ctx.newPage();
page.on('pageerror', (e) => { console.log('pageerror', e.message); fails.push('pageerror ' + e.message); });
await page.goto(`${BASE}/auth?mode=signin`);
await page.getByLabel('Email').fill(EMAIL);
await page.locator('input[type="password"]').fill(PASSWORD);
await page.locator('button[type="submit"]').click();
await page.waitForURL(/\/play/, { timeout: 60000 });
try { await page.locator('.welcome__go').click({ timeout: 15000 }); } catch {}
await page.locator('.pill-bar').waitFor({ timeout: 60000 });
await sleep(1500);
await page.mouse.click(200, 400); // first gesture unlocks audio
await sleep(1500);

const stats = () => page.evaluate(() => window.__blSound.stats());
const sb = (fn, ...a) => page.evaluate(fn, ...a);
// sample the counters in-page every 100 ms for `ms`, return the maxima
const watch = (ms) => page.evaluate((ms) => new Promise((res) => {
  const m = { track: 0, bus: 0, timers: 0, music: 0, sfx: 0, ctx: 0 };
  const iv = setInterval(() => {
    const s = window.__blSound.stats();
    m.track = Math.max(m.track, s.trackActive); m.bus = Math.max(m.bus, s.busActive);
    m.timers = Math.max(m.timers, s.intervals); m.music = Math.max(m.music, s.music); m.sfx = Math.max(m.sfx, s.sfx); m.ctx = Math.max(m.ctx, s.ctxCreated);
  }, 100);
  setTimeout(() => { clearInterval(iv); res(m); }, ms);
}), ms);
const supa = (fn, args) => page.evaluate(async ([fn, args]) => { const m = await import('/src/lib/supabase.ts'); const r = await m.supabase.rpc(fn, args); return r.error ? { error: r.error.message } : r.data; }, [fn, args]);

let s = await stats();
ok(s.state === 'running' && s.unlocked, `audio unlocked and running (${s.state})`);
ok(s.ctxCreated === 1, `one AudioContext (${s.ctxCreated})`);

// 1. travel between places several times
const route = ['mama_ebo', 'oba_market', 'club_360', 'mama_ebo', 'uselu_park', 'club_360'];
let peak = { track: 0, bus: 0, timers: 0, music: 0, sfx: 0 };
for (const dest of route) {
  const r = await supa('travel_start', { p_dest: dest, p_mode: 'walk' });
  if (r.error) { console.log('travel', dest, r.error); await sleep(1000); continue; }
  const w = watch((r.real_seconds + 6) * 1000);
  await sleep((r.real_seconds + 6) * 1000);
  const m = await w;
  for (const k of Object.keys(peak)) peak[k] = Math.max(peak[k], m[k]);
  s = await stats();
  console.log(`  -> ${dest}: place=${s.place} track=${s.trackActive} buses=${s.buses} engines=${s.engines} timers=${s.intervals}`);
}
await sleep(3500); // old buses are cut 2.5 s after their fade
s = await stats();
ok(peak.track <= 1, `never more than one soundtrack (peak ${peak.track})`);
ok(peak.bus <= 1, `never more than one place bus attached (peak ${peak.bus})`);
ok(s.buses <= 1 && s.engines <= 1, `old buses/engines released (buses ${s.buses}, engines ${s.engines})`);
ok(peak.timers <= 3, `timers bounded: music + city bed + place (peak ${peak.timers})`);
ok(s.ctxCreated === 1, `still one AudioContext after travelling (${s.ctxCreated})`);
console.log('  voice peaks while travelling:', JSON.stringify(peak));
const baseMusic = Math.max(peak.music, s.peakMusic);

// 2. hide / show (headless cannot really hide a tab: fake the Page Visibility API)
const setHidden = (h) => sb((h) => {
  Object.defineProperty(document, 'hidden', { configurable: true, get: () => h });
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (h ? 'hidden' : 'visible') });
  document.dispatchEvent(new Event('visibilitychange'));
}, h);
await setHidden(true);
await sleep(1500);
s = await stats();
ok(s.state === 'suspended', `hidden tab suspends the context (${s.state})`);
await sleep(8000);
await setHidden(false);
const afterShow = watch(2500);
await sleep(2700);
const m2 = await afterShow;
s = await stats();
ok(s.state === 'running', `visible again resumes (${s.state})`);
ok(m2.track <= 1 && m2.music <= baseMusic + 15, `no burst after show (music voices ${m2.music}, normal peak ${baseMusic})`);

// 3. main-thread stall (phone busy / throttled timers): no catch-up flood
await sb(() => { const t = performance.now(); while (performance.now() - t < 4000) { /* block */ } });
const afterStall = await watch(2000);
ok(afterStall.music <= baseMusic + 15, `no flood after a 4 s stall (music voices ${afterStall.music}, normal peak ${baseMusic})`);

// 4. hype spam inside the club
const inClub = (await stats()).place === 'club';
ok(inClub, `at the club (${(await stats()).place})`);
const spam = watch(6000);
await sb(async () => {
  const k = ['club', 'big', 'global', 'calm'];
  for (let i = 0; i < 80; i++) { window.__blSound.playHype(k[i % 4]); if (i % 10 === 9) await new Promise((r) => setTimeout(r, 120)); }
});
const sm = await spam;
s = await stats();
ok(sm.sfx <= 64, `hype spam keeps one-shot voices under the cap (peak ${sm.sfx}, cap 64, skipped ${s.hypeSkipped}, dropped ${s.dropped})`);
await sleep(5000);
s = await stats();
ok(s.sfx <= 3, `one-shot voices all ended and were released (${s.sfx} left)`);

// 5. mute / sound-off respected
await sb(async () => { const p = await import('/src/lib/prefs.ts'); p.usePrefs.getState().set({ music: false }); });
await sleep(1500);
s = await stats();
ok(!s.musicTimer && s.trackActive === 0, `Music off stops everything (musicTimer ${s.musicTimer}, track ${s.trackActive})`);
await sb(async () => { const p = await import('/src/lib/prefs.ts'); p.usePrefs.getState().set({ music: true }); });
await sleep(1500);
s = await stats();
ok(s.trackActive === 1 && s.intervals <= 3, `Music on again: one track, timers ${s.intervals}`);

await browser.close();
console.log(fails.length ? `\n${fails.length} FAILED` : '\nALL PASSED');
process.exit(fails.length ? 1 : 0);
