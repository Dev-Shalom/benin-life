#!/usr/bin/env node
// Free roam, live players: load test against the LOCAL Supabase (docs/ROAM.md "Live players").
//   node scripts/roam-load.mjs [--k=30] [--secs=90] [--warm=25] [--seed=1] [--cars=0.15] [--idle=0.2]
// Starts K fake clients (supabase-js, real WebSockets, real private Realtime channels, real RPCs) in two areas:
//   * the main crowd walks random paths in a 70 m square round King's Square (everyone is near everyone, so the 20-player cap bites at K > 21),
//   * 1 in 6 walks 350 m away in another cell (they must NEVER receive anything from the crowd: interest management check).
// It measures messages and bytes sent / received per client (a counting WebSocket), the Realtime and database containers' CPU
// (docker stats), the database's own view of the RPCs (pg_stat_statements), and checks:
//   * every client only subscribes to / receives from players the server listed as near it,
//   * the far group receives nothing from the crowd (and the crowd nothing from the far group),
//   * chat bubbles reach players within the bubble radius only and carry the server's name,
//   * impersonation: a client that joins another player's topic and broadcasts on it is never heard.
// Needs the local stack (npx supabase start) with the roam3 migration. Test users are load_<n>@roam.bl (created with the admin API,
// reused on later runs). Nothing is written to the repo.
import { spawnSync, spawn } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';

const arg = (k, d) => {
  const a = process.argv.find((x) => x.startsWith(`--${k}=`));
  return a ? a.slice(k.length + 3) : d;
};
const K = Number(arg('k', 30));
const SECS = Number(arg('secs', 90));
const WARM = Number(arg('warm', 25));
const CARS = Number(arg('cars', 0.15));
const IDLE = Number(arg('idle', 0.2));
let seed = Number(arg('seed', 1));
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const P = await import('../src/art/roam3d/live/protocol.ts');

/* ---------- environment ---------- */
function env() {
  if (process.env.LOAD_URL && process.env.LOAD_ANON && process.env.LOAD_SERVICE) return { url: process.env.LOAD_URL, anon: process.env.LOAD_ANON, service: process.env.LOAD_SERVICE };
  const r = spawnSync('npx', ['supabase', 'status', '-o', 'env'], { encoding: 'utf8' });
  const m = (k) => new RegExp(`^${k}="?([^"\\n]+)"?`, 'm').exec(r.stdout)?.[1];
  const url = m('API_URL'), anon = m('ANON_KEY'), service = m('SERVICE_ROLE_KEY');
  if (!url || !anon || !service) throw new Error('npx supabase status did not give the keys. Is the local stack running?');
  return { url, anon, service };
}
const E = env();
const psql = (sql) => spawnSync('docker', ['exec', 'supabase_db_benin-life', 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-F', '|', '-c', sql], { encoding: 'utf8' }).stdout.trim();

/* ---------- counting WebSocket ---------- */
const size = (d) => (typeof d === 'string' ? Buffer.byteLength(d) : (d.byteLength ?? d.size ?? 0));
function countingWS(stats) {
  return class extends WebSocket {
    constructor(u, p) {
      super(u, p);
      this.addEventListener('message', (e) => {
        const n = size(e.data);
        stats.rx += n; stats.rxN++;
        if (typeof e.data !== 'string') { stats.rxB += n; stats.rxBN++; }
        else if (e.data.length < 4096 && e.data.split(',', 5)[3]?.includes('broadcast')) { stats.rxB += n; stats.rxBN++; }
        else stats.rxCtl += n;
      });
    }
    send(d) {
      const n = size(d);
      stats.tx += n; stats.txN++;
      if (typeof d !== 'string' || (d.includes('"broadcast"') && d.includes('"event":"p"'))) { stats.txB += n; stats.txBN++; }
      super.send(d);
    }
  };
}

/* ---------- users ---------- */
const admin = createClient(E.url, E.service, { auth: { persistSession: false, autoRefreshToken: false } });
const AVATAR = { gender: 'male' };

async function makeClient(i) {
  const stats = { tx: 0, rx: 0, txN: 0, rxN: 0, txB: 0, txBN: 0, rxB: 0, rxBN: 0, rxCtl: 0 };
  const email = `load_${i}@roam.bl`, password = 'load-test-pass-1';
  const sb = createClient(E.url, E.anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: countingWS(stats), params: { eventsPerSecond: 10 }, heartbeatIntervalMs: 25000 },
  });
  let { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) {
    const c = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (c.error && !/already/i.test(c.error.message)) throw c.error;
    ({ data, error } = await sb.auth.signInWithPassword({ email, password }));
    if (error) throw error;
  }
  const uid = data.user.id;
  // a Sim with a home (once)
  const own = await sb.from('profiles').select('id,location_id,home_chosen,username').eq('id', uid).maybeSingle();
  if (!own.data) {
    const r = await sb.rpc('create_profile_v2', { p_username: `Load${i}`, p_gender: i % 2 ? 'male' : 'female', p_avatar: AVATAR, p_traits: ['hustler', 'foodie'], p_dream: 'oga_at_the_top' });
    if (r.error) throw new Error('create_profile_v2: ' + r.error.message);
    const h = await sb.rpc('choose_start_home', { p_home: 'ekenwan_face_me' });
    if (h.error) throw new Error('choose_start_home: ' + h.error.message);
  } else if (!own.data.home_chosen) {
    const h = await sb.rpc('choose_start_home', { p_home: 'ekenwan_face_me' });
    if (h.error) throw new Error('choose_start_home: ' + h.error.message);
  }
  const prof = (await sb.from('profiles').select('location_id,username').eq('id', uid).single()).data;
  const st = await sb.rpc('roam_start', { p_place: prof.location_id });
  if (st.error) throw new Error('roam_start: ' + st.error.message);
  await sb.realtime.setAuth(data.session.access_token);
  return { i, sb, uid, name: prof.username, stats };
}

/* ---------- the simulated walker ---------- */
function makeWalker(c, group, cfg) {
  c.cfg = cfg;
  const cx = group === 'far' ? 150 : 500, cy = group === 'far' ? 150 : 500, half = group === 'far' ? 30 : 35;
  const car = group === 'main' && rnd() < CARS;
  c.group = group;
  c.pose = { x: cx + (rnd() * 2 - 1) * half, y: cy + (rnd() * 2 - 1) * half, h: rnd() * 6.28 - 3.14, v: 0, car, run: false, brake: false, reverse: false, emote: 0 };
  c.target = null; c.pauseUntil = 0; c.centre = { x: cx, y: cy, half };
  c.speedFor = () => (car ? 7 + rnd() * 5 : rnd() < 0.25 ? 4.6 : 1.9);
  c.sender = new P.PosSender(c.cfg);
  c.step = (now, dt) => {
    const p = c.pose;
    if (now < c.pauseUntil) { p.v = 0; p.brake = false; return; }
    if (!c.target) {
      c.target = { x: cx + (rnd() * 2 - 1) * half, y: cy + (rnd() * 2 - 1) * half, v: c.speedFor() };
      p.run = !car && c.target.v > 3;
    }
    const dx = c.target.x - p.x, dy = c.target.y - p.y, d = Math.hypot(dx, dy);
    if (d < 1.2) {
      c.target = null;
      c.pauseUntil = now + (rnd() < IDLE ? 4000 + rnd() * 9000 : rnd() * 2500);
      p.v = 0;
      return;
    }
    const want = Math.atan2(dy, dx);
    let dh = want - p.h; dh = Math.atan2(Math.sin(dh), Math.cos(dh));
    const turn = (car ? 1.6 : 6) * dt;
    p.h += Math.max(-turn, Math.min(turn, dh));
    p.v = c.target.v * (Math.abs(dh) > 1 ? 0.4 : 1);
    p.x += Math.cos(p.h) * p.v * dt;
    p.y += Math.sin(p.h) * p.v * dt;
  };
}

/* ---------- networking per client ---------- */
function startNet(c, info, all) {
  c.near = new Map();           // id -> row
  c.have = new Set();
  c.chans = new Map();          // topic -> channel
  c.recvFrom = new Map();       // uid -> count
  c.bubbles = [];
  c.badSource = 0;
  c.forged = 0;
  c.ticks = 0;
  c.tickMs = [];
  c.errors = [];
  c.joined = false;
  const mk = (topic, onMsg) => {
    const ch = c.sb.channel(topic, { config: { private: true, broadcast: { self: false, ack: false } } });
    if (onMsg) ch.on('broadcast', { event: topic.startsWith('roam:t:') ? 'b' : 'p' }, onMsg);
    ch.subscribe((s, err) => { if (s === 'CHANNEL_ERROR' || s === 'TIMED_OUT') c.errors.push(`${topic}: ${s} ${err?.message ?? ''}`); if (s === 'SUBSCRIBED' && topic === P.posTopic(c.uid)) c.joined = true; });
    c.chans.set(topic, ch);
    return ch;
  };
  mk(P.posTopic(c.uid));
  const sync = (rows) => {
    const want = new Set(rows.slice(0, info.max_shown).map((r) => r.id));
    for (const r of rows) { c.near.set(r.id, { ...c.near.get(r.id), ...r }); c.have.add(r.id); }
    for (const id of [...c.near.keys()]) if (!want.has(id)) { c.near.delete(id); const t = P.posTopic(id); const ch = c.chans.get(t); if (ch) { void c.sb.removeChannel(ch); c.chans.delete(t); } }
    for (const id of want) {
      const t = P.posTopic(id);
      if (c.chans.has(t)) continue;
      mk(t, (m) => {
        c.recvFrom.set(id, (c.recvFrom.get(id) ?? 0) + 1);
        const d = P.decodePose(m.payload?.d ?? m.payload);
        if (!d) { c.badSource++; return; }
        if (d.seq === 200 && d.x === 0.5) c.forged++;
        const owner = all.find((o) => o.uid === id);
        if (owner && owner.group !== c.group) c.badSource++;
      });
    }
    // bubbles: the text topic of each player within the bubble radius (+10 m); the server applies the same rules as for positions
    const wantT = new Set(rows.filter((r) => Math.hypot(r.x - c.pose.x, r.y - c.pose.y) <= info.bubble_m + 10).map((r) => P.textTopic(r.id)));
    for (const t of [...c.chans.keys()]) if (t.startsWith('roam:t:') && !wantT.has(t)) { void c.sb.removeChannel(c.chans.get(t)); c.chans.delete(t); }
    for (const t of wantT) if (!c.chans.has(t)) mk(t, (m) => {
      const bb = P.parseBubble(m.payload);
      if (!bb || bb.u !== t.slice(7)) return;
      const dist = Math.hypot(bb.x - c.pose.x, bb.y - c.pose.y);
      c.bubbles.push({ from: bb.u, name: bb.n, text: bb.t, dist, atMs: Date.now() });
    });
  };
  const tick = async () => {
    const t0 = performance.now();
    const r = await c.sb.rpc('roam_live_tick', { p_x: c.pose.x, p_y: c.pose.y, p_have: [...c.have].slice(0, 60) });
    c.tickMs.push(performance.now() - t0);
    c.ticks++;
    if (r.error) { c.errors.push('tick: ' + r.error.message); return; }
    c.lastTick = r.data;
    if (r.data.players) sync(r.data.players);
  };
  c.tick = tick;
  c.loop = async () => {
    await tick();
    while (!c.stop) {
      await new Promise((r) => setTimeout(r, (info.presence_s + (rnd() * 2 - 1) * 1.5) * 1000));
      if (c.stop) break;
      await tick();
    }
  };
  c.send = (pkt) => {
    const ch = c.chans.get(P.posTopic(c.uid));
    if (!ch || !c.joined) return;
    ch.send({ type: 'broadcast', event: 'p', payload: pkt });
  };
}

/* ---------- main ---------- */
console.log(`roam-load: K=${K} secs=${SECS} warm=${WARM} url=${E.url}`);
const t00 = Date.now();
const clients = [];
// create / sign in in small batches (the auth service is the slow part)
for (let b = 0; b < K; b += 6) {
  const part = await Promise.all(Array.from({ length: Math.min(6, K - b) }, (_, j) => makeClient(b + j + 1)));
  clients.push(...part);
}
console.log(`  ${K} users ready in ${((Date.now() - t00) / 1000).toFixed(1)} s`);
const nFar = Math.floor(K / 6);
const first = (await clients[0].sb.rpc('roam_live_info')).data;
const sendCfg = { moveHz: first.move_hz, idleS: first.idle_s, maxGapMs: 1200, budget: first.budget_mps };
clients.forEach((c, i) => makeWalker(c, i >= K - nFar ? 'far' : 'main', sendCfg));
console.log('  roam_live_info:', JSON.stringify({ budget_mps: first.budget_mps, presence_s: first.presence_s, max_shown: first.max_shown, cell_m: first.cell_m, radius_m: first.radius_m, move_hz: first.move_hz, idle_s: first.idle_s }));
clients.forEach((c) => startNet(c, first, clients));
// phase 1: everyone ticks once, then joins (a tick makes the row; the join policy needs it)
await Promise.all(clients.map((c) => c.tick()));
await new Promise((r) => setTimeout(r, 2500));
await Promise.all(clients.map((c) => c.tick()));   // second tick: now the others are visible to everybody
clients.forEach((c) => c.loop());

/* the simulation loop: 20 Hz */
let tAt = performance.now();
const sim = setInterval(() => {
  const now = performance.now(), dt = Math.min(0.2, (now - tAt) / 1000); tAt = now;
  for (const c of clients) {
    c.step(now, dt);
    const pkt = c.sender.next(now, c.pose, c.near.size);
    if (pkt) c.send(pkt);
  }
}, 50);

// sample the containers' CPU
const cpu = { realtime: [], db: [], rest: [] };
const sampler = setInterval(() => {
  const r = spawnSync('docker', ['stats', '--no-stream', '--format', '{{.Name}} {{.CPUPerc}}', 'supabase_realtime_benin-life', 'supabase_db_benin-life', 'supabase_rest_benin-life'], { encoding: 'utf8' }).stdout;
  for (const line of r.trim().split('\n')) {
    const [n, p] = line.split(' ');
    const v = parseFloat(p);
    if (n.includes('realtime')) cpu.realtime.push(v); else if (n.includes('_db_')) cpu.db.push(v); else if (n.includes('rest')) cpu.rest.push(v);
  }
}, 6000);

console.log(`  warming up ${WARM} s (joins, first ticks) ...`);
await new Promise((r) => setTimeout(r, WARM * 1000));
const snap = () => clients.map((c) => ({ ...c.stats, sent: c.sender.sent, bub: c.bubbles.length, from: new Map(c.recvFrom) }));
const s0 = snap();
const statements0 = psql("select coalesce(sum(calls),0), coalesce(sum(total_exec_time),0) from pg_stat_statements where query ilike '%roam_live_tick%' or query ilike '%roam_say%' or query ilike '%bl_roam_%'");
const db0 = psql("select xact_commit, tup_inserted, tup_updated, tup_deleted from pg_stat_database where datname='postgres'");
const t0 = Date.now();

// the impersonation attempt + bubbles during the measured window
const main = clients.filter((c) => c.group === 'main');
const speakers = main.slice(0, Math.max(2, Math.floor(main.length / 8)));
const sayLog = [];
let sayErrors = [];
const sayTimers = speakers.map((c, j) => setInterval(async () => {
  const text = `hello from ${c.name} ${Math.floor(rnd() * 99)}`;
  const r = await c.sb.rpc('roam_say', { p_text: text });
  if (r.error) sayErrors.push(r.error.message); else sayLog.push({ id: r.data.id, from: c.uid, text: r.data.text, x: c.pose.x, y: c.pose.y, at: Date.now() });
}, 14000 + j * 900));
// attacker = main[1] tries to broadcast a forged "victim" packet (x = 0.5 m, seq 200 are unmistakable) on main[0]'s topic
const victim = main[0], attacker = main[1];
let forgeResult = 'not tried';
setTimeout(async () => {
  // the attacker is subscribed to the victim's topic (read-only, as any near player is): he broadcasts a forged packet on it
  const ch = attacker.chans.get(P.posTopic(victim.uid));
  if (!ch) { forgeResult = 'attacker had no channel on the victim topic'; return; }
  try {
    const r1 = await ch.send({ type: 'broadcast', event: 'p', payload: [5, 5, 0, 0, 0, 200] });
    const r2 = await ch.send({ type: 'broadcast', event: 'p', payload: { d: [5, 5, 0, 0, 0, 200] } });
    forgeResult = `sent twice on the victim's topic (client says ${r1} / ${r2}); delivered to others: see forged_packets_delivered`;
  } catch (e) { forgeResult = `send threw ${e.message}`; }
}, 8000);

await new Promise((r) => setTimeout(r, SECS * 1000));
const secs = (Date.now() - t0) / 1000;
const s1 = snap();
const statements1 = psql("select coalesce(sum(calls),0), coalesce(sum(total_exec_time),0) from pg_stat_statements where query ilike '%roam_live_tick%' or query ilike '%roam_say%' or query ilike '%bl_roam_%'");
const db1 = psql("select xact_commit, tup_inserted, tup_updated, tup_deleted from pg_stat_database where datname='postgres'");
clients.forEach((c) => (c.stop = true));
clearInterval(sim); clearInterval(sampler); sayTimers.forEach(clearInterval);
await new Promise((r) => setTimeout(r, 1500));

/* ---------- report ---------- */
const d = (a, b, k) => b[k] - a[k];
const per = (k, idx) => idx.map((i) => d(s0[i], s1[i], k) / secs * 60);
const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
const mainIdx = clients.map((c, i) => (c.group === 'main' ? i : -1)).filter((i) => i >= 0);
const farIdx = clients.map((c, i) => (c.group === 'far' ? i : -1)).filter((i) => i >= 0);
const kb = (n) => (n / 1024).toFixed(1);
const near = mainIdx.map((i) => clients[i].near.size);
const sentMsgs = per('txBN', mainIdx), sentB = per('txB', mainIdx), rxMsgs = per('rxBN', mainIdx), rxB = per('rxB', mainIdx), rxAll = per('rx', mainIdx), txAll = per('tx', mainIdx);
const ctlRx = per('rxCtl', mainIdx);
// on-the-wire estimate: + WebSocket frame header (rx 4, tx 6 bytes) + one TLS record (22 bytes) per message
const wireRx = avg(rxAll) + avg(per('rxN', mainIdx)) * (4 + 22);
const wireTx = avg(txAll) + avg(per('txN', mainIdx)) * (6 + 22);
let bad = 0, forged = 0, errs = [];
for (const c of clients) { bad += c.badSource; forged += c.forged; errs.push(...c.errors); }
const farLeak = farIdx.reduce((n, i) => n + [...clients[i].recvFrom.keys()].filter((id) => clients.find((o) => o.uid === id)?.group === 'main').length, 0)
  + mainIdx.reduce((n, i) => n + [...clients[i].recvFrom.keys()].filter((id) => clients.find((o) => o.uid === id)?.group === 'far').length, 0);
const maxChans = Math.max(...clients.map((c) => c.chans.size));
const bubbleRecv = clients.reduce((n, c) => n + c.bubbles.length, 0);
const farBubbles = farIdx.reduce((n, i) => n + clients[i].bubbles.length, 0);
const outsideRadius = clients.reduce((n, c) => n + c.bubbles.filter((b) => b.dist > first.bubble_m).length, 0);
const wrongName = clients.reduce((n, c) => n + c.bubbles.filter((b) => !/^Load\d+$/.test(b.name)).length, 0);
const [c0, ms0] = statements0.split('|').map(Number), [c1, ms1] = statements1.split('|').map(Number);
const [x0, i0, u0, de0] = db0.split('|').map(Number), [x1, i1, u1, de1] = db1.split('|').map(Number);
const tm = clients.flatMap((c) => c.tickMs).sort((a, b) => a - b);
const pct = (a, p) => a[Math.min(a.length - 1, Math.floor(a.length * p))] ?? 0;

const posRecv = clients.reduce((n, c) => n + [...c.recvFrom.values()].reduce((a, b) => a + b, 0), 0);
const posSent = clients.reduce((n, c) => n + c.sender.sent, 0);
const out = {
  debug: { pos_received_total: posRecv, pos_sent_total: posSent, joined: clients.filter((c) => c.joined).length },
  K, measured_s: Math.round(secs), crowd: mainIdx.length, far_group: farIdx.length,
  nearby_per_client: { avg: +avg(near).toFixed(1), max: Math.max(...near), cap: first.max_shown },
  channels_per_client_max: maxChans,
  per_player_per_minute: {
    sent_messages: +avg(sentMsgs).toFixed(0), sent_KB_ws_payload: +kb(avg(sentB)), sent_KB_all_ws_traffic: +kb(avg(txAll)), sent_KB_on_the_wire_est: +kb(wireTx),
    received_messages: +avg(rxMsgs).toFixed(0), received_KB_positions_and_bubbles: +kb(avg(rxB)), received_KB_all_ws_traffic: +kb(avg(rxAll)), received_KB_on_the_wire_est: +kb(wireRx), received_control_KB: +kb(avg(ctlRx)),
  },
  rpc_tick_ms: { p50: +pct(tm, 0.5).toFixed(1), p95: +pct(tm, 0.95).toFixed(1), n: tm.length },
  checks: {
    messages_from_unexpected_source: bad, cross_area_topics_received: farLeak, forged_packets_delivered: forged, forge_attempt: forgeResult,
    bubbles_sent: sayLog.length, bubble_receipts: bubbleRecv, bubble_receipts_in_far_area: farBubbles, bubble_receipts_beyond_radius_dropped_by_the_client: outsideRadius, bubble_receipts_within_radius: bubbleRecv - outsideRadius, bubbles_with_unknown_name: wrongName, say_errors: sayErrors.slice(0, 3),
    channel_errors: errs.slice(0, 5), channel_error_count: errs.length,
  },
  server: {
    realtime_cpu_pct: { avg: +avg(cpu.realtime).toFixed(1), max: Math.max(0, ...cpu.realtime) },
    db_cpu_pct: { avg: +avg(cpu.db).toFixed(1), max: Math.max(0, ...cpu.db) },
    postgrest_cpu_pct: { avg: +avg(cpu.rest).toFixed(1), max: Math.max(0, ...cpu.rest) },
    roam_statements: { calls: c1 - c0, total_ms: +(ms1 - ms0).toFixed(0), avg_ms: c1 - c0 ? +((ms1 - ms0) / (c1 - c0)).toFixed(2) : 0 },
    db_per_minute: { commits: Math.round((x1 - x0) / secs * 60), rows_inserted: Math.round((i1 - i0) / secs * 60), rows_updated: Math.round((u1 - u0) / secs * 60), rows_deleted: Math.round((de1 - de0) / secs * 60) },
  },
};
if (process.env.LOAD_DEBUG) console.log('client0 stats', clients[0].stats, 'delta', s1[0], s0[0]);
console.log(JSON.stringify(out, null, 2));
// every client leaves the street so the presence rows go
await Promise.all(clients.map((c) => c.sb.rpc('roam_leave').then(() => c.sb.removeAllChannels()).catch(() => null)));
const fail = bad || farLeak || forged || wrongName || farBubbles;
console.log(fail ? 'RESULT: CHECKS FAILED' : 'RESULT: all checks passed');
process.exit(fail ? 1 : 0);
