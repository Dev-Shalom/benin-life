// Live players in free roam: the network side (no React, no three.js). docs/ROAM.md "Live players".
//   * every `presence_s` one RPC (roam_live_tick) tells the server where I am and returns the nearest players (names, looks and
//     badges come from the SERVER, only the first time a player is seen);
//   * I listen to the private topic `roam:u:<uid>` of each of them and publish on my own (Realtime Authorization lets me write only
//     there); bubbles arrive on read-only cell topics `roam:b:<cx>:<cy>` that only the database can write;
//   * everything fails safe: Realtime in poll mode, a refused join, a dead socket => "Live players off" and free roam carries on alone;
//     retries back off (10 s .. 5 min) and never run while the tab is hidden.
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { isPollMode, reportRealtimeOk, trackSubscribe, useRealtime } from '../../../lib/realtime';
import {
  decodePose, EMOTE_MS, EMOTES, EVT_BUBBLE, EVT_POS, parseBubble, PosSender, posTopic, textTopic,
  type EmoteName, type NearbyRow, type Pose,
} from './protocol';
import { RemoteTrack } from './track';

export type LiveStatus = 'idle' | 'connecting' | 'on' | 'off';
export type OffReason = 'server' | 'poll' | 'connection' | 'unsupported' | 'error' | '';

export interface LiveInfo {
  enabled: boolean;
  show_me: boolean;
  location_hidden: boolean;
  presence_s: number;
  max_shown: number;
  low_max: number;
  radius_m: number;
  move_hz: number;
  idle_s: number;
  budget_mps: number;
  buffer_ms: number;
  emotes: boolean;
  cell_m: number;
  bubble: boolean;
  bubble_len: number;
  bubble_m: number;
  bubble_gap_s: number;
  me: string;
  blocked: string[];
}

export interface Remote {
  id: string;
  name: string;
  avatar: unknown;
  streetCred: number;
  title: string | null;
  crew: NearbyRow['c'];
  mode: 'walk' | 'car';
  veh: string | null;
  track: RemoteTrack;
  /** Last position from the server's list (used until the stream starts). */
  px: number;
  py: number;
  bubble: { text: string; until: number } | null;
  seenAt: number;
  /** When the server last listed him (ms): a stream position must stay within reach of that. */
  listedAt: number;
  /** Ticks in a row the server did not list it (a player at the edge of the cap flickers: it is dropped after two). */
  missing: number;
  /** Seconds since it was added (fade in) and since it was dropped (fade out; > 0 means leaving). */
  born: number;
  leaving: number;
  /** Distance to me (m), refreshed by the scene. */
  dist: number;
}

export interface LiveStats {
  rxMsgs: number;
  rxBytes: number;
  txMsgs: number;
  txBytes: number;
  ticks: number;
  since: number;
}

type Listener = () => void;
const nowMs = () => performance.now();

/** Rough size of a broadcast frame on the wire for a position array (vsn 2 text frame: topic + envelope). */
const FRAME_OVERHEAD = 112;

export class LiveClient {
  readonly remotes = new Map<string, Remote>();
  status: LiveStatus = 'idle';
  off: OffReason = '';
  info: LiveInfo | null = null;
  /** Changes whenever the set of remotes, the status or a bubble changes (React re-renders on it). */
  version = 0;
  stats: LiveStats = { rxMsgs: 0, rxBytes: 0, txMsgs: 0, txBytes: 0, ticks: 0, since: Date.now() };
  /** My own bubble (shown over my head by the scene). */
  myBubble: { text: string; until: number } | null = null;
  /** Visible to others (server says so). */
  visible = false;
  hiddenWhy: '' | 'off' | 'location' = '';

  private sb: SupabaseClient;
  private low: boolean;
  private getPose: () => { x: number; y: number };
  private listeners = new Set<Listener>();
  private chans = new Map<string, RealtimeChannel>();
  private denied = new Map<string, { until: number; n: number }>();
  private blocked = new Set<string>();
  private sender = new PosSender();
  private ownJoined = false;
  private ownChan: RealtimeChannel | null = null;
  private timer = 0;
  private stopped = false;
  private failures: number[] = [];
  private retryN = 0;
  private muteBubbles = false;
  private emoteUntil = 0;
  private emoteId = 0;
  private emoteAt = 0;
  private lastRx = new Map<string, number>();
  private unsubRt: (() => void) | null = null;
  private ticking = false;
  private visListening = false;
  /** A hidden tab listens to nothing: channels are left and rejoined when it is shown again. */
  private onVis = () => {
    if (this.stopped || this.status === 'off' || !this.info) return;
    window.clearTimeout(this.timer);
    if (document.visibilityState === 'visible') {
      this.timer = window.setTimeout(() => void this.tick(), 200 + Math.random() * 600);
    } else {
      this.leaveChannels();
    }
  };

  constructor(sb: SupabaseClient, opts: { low: boolean; getPose: () => { x: number; y: number }; muteBubbles?: boolean }) {
    this.sb = sb;
    this.low = opts.low;
    this.getPose = opts.getPose;
    this.muteBubbles = Boolean(opts.muteBubbles);
  }

  on(l: Listener): () => void {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  }
  private bump() {
    this.version++;
    for (const l of this.listeners) l();
  }
  private setStatus(s: LiveStatus, why: OffReason = '') {
    if (this.status === s && this.off === why) return;
    this.status = s;
    this.off = s === 'off' ? why : '';
    this.bump();
  }

  setMuteBubbles(m: boolean) {
    this.muteBubbles = m;
    if (m) for (const r of this.remotes.values()) r.bubble = null;
    this.bump();
  }

  /* ---------------------------------------------------------------- start / stop */
  async start() {
    this.stopped = false;
    if (isPollMode()) return this.setStatus('off', 'poll');
    this.setStatus('connecting');
    if (!this.visListening) {
      this.visListening = true;
      document.addEventListener('visibilitychange', this.onVis);
    }
    // leaving poll mode again brings the feature back by itself; entering it takes it down
    let prev = useRealtime.getState().mode;
    this.unsubRt = useRealtime.subscribe((s) => {
      if (s.mode === prev) return;
      prev = s.mode;
      if (s.mode === 'poll') this.goOff('poll');
      else if (this.status === 'off' && this.off === 'poll' && !this.stopped) {
        this.retryN = 0;
        void this.begin();
      }
    });
    await this.begin();
  }

  private async begin() {
    try {
      const r = await this.sb.rpc('roam_live_info');
      if (r.error) throw r.error;
      this.info = r.data as LiveInfo;
    } catch {
      return this.fail('error');
    }
    if (this.stopped) return;
    const info = this.info!;
    this.blocked = new Set(info.blocked ?? []);
    if (!info.enabled) return this.goOff('server');
    this.sender.cfg = { moveHz: info.move_hz, idleS: info.idle_s, maxGapMs: 1200, budget: info.budget_mps };
    this.stats.since = Date.now();
    await this.tick();
  }

  stop() {
    this.stopped = true;
    window.clearTimeout(this.timer);
    document.removeEventListener('visibilitychange', this.onVis);
    this.visListening = false;
    this.unsubRt?.();
    this.unsubRt = null;
    this.dropAll();
    // forget me on the server at once (best effort)
    void Promise.resolve(this.sb.rpc('roam_live_stop')).catch(() => undefined);
    this.setStatus('idle');
  }

  /** Leave every channel but keep the list (a hidden tab). */
  private leaveChannels() {
    for (const ch of this.chans.values()) void this.sb.removeChannel(ch);
    this.chans.clear();
    this.ownChan = null;
    this.ownJoined = false;
    this.lastRx.clear();
  }

  private dropAll() {
    this.leaveChannels();
    this.remotes.clear();
    this.visible = false;
    this.bump();
  }

  private goOff(why: OffReason) {
    window.clearTimeout(this.timer);
    this.dropAll();
    this.setStatus('off', why);
    // the owner's switch may come back on: look again in a minute (poll mode has its own way back)
    if (why === 'server' && !this.stopped) {
      this.timer = window.setTimeout(() => { if (!this.stopped && !isPollMode()) void this.begin(); }, 60_000 + Math.random() * 15_000);
    }
  }

  /** A connection problem: back off 10 s, 20 s, 40 s ... up to 5 min, then try the whole thing again. */
  private fail(why: OffReason) {
    this.dropAll();
    this.setStatus('off', why);
    this.retryN = Math.min(this.retryN + 1, 5);
    const wait = Math.min(300_000, 10_000 * 2 ** (this.retryN - 1)) * (0.8 + Math.random() * 0.4);
    window.clearTimeout(this.timer);
    this.timer = window.setTimeout(() => {
      if (this.stopped || isPollMode()) return;
      this.setStatus('connecting');
      void this.begin();
    }, wait);
  }

  /* ---------------------------------------------------------------- the presence tick */
  private async tick() {
    window.clearTimeout(this.timer);
    if (this.stopped || !this.info || this.ticking) return;
    if (isPollMode()) return this.goOff('poll');
    // a hidden tab asks for nothing (its channels were left; the tab asks again when shown)
    if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return;
    this.ticking = true;
    try {
      await this.tickOnce();
    } finally {
      this.ticking = false;
    }
  }

  private async tickOnce() {
    const p = this.getPose();
    const next = () => {
      if (this.stopped) return;
      const s = this.info?.presence_s ?? 9;
      window.clearTimeout(this.timer);
      this.timer = window.setTimeout(() => void this.tick(), (s + (Math.random() * 2 - 1) * Math.min(2, s * 0.2)) * 1000);
    };
    type Tick = { visible?: boolean; why?: string; players?: NearbyRow[] | null };
    let data: Tick | null = null as Tick | null;
    const have = [...this.remotes.values()].filter((r) => r.name).map((r) => r.id).slice(0, 60);
    try {
      const r = await this.sb.rpc('roam_live_tick', { p_x: Math.round(p.x * 10) / 10, p_y: Math.round(p.y * 10) / 10, p_have: have });
      if (r.error) {
        // the owner switched live players off: everything stops at this tick
        if ((r.error as { hint?: string }).hint === 'off' || /switched off/i.test(r.error.message)) return this.goOff('server');
        throw r.error;
      }
      data = r.data as Tick;
    } catch {
      this.failures.push(Date.now());
      this.failures = this.failures.filter((t) => Date.now() - t < 60_000);
      if (this.failures.length >= 3) return this.fail('connection');
      next();
      return;
    }
    if (this.stopped || !data) return;
    this.failures = [];
    this.stats.ticks++;
    this.visible = Boolean(data.visible);
    this.hiddenWhy = data.visible ? '' : data.why === 'off' ? 'off' : data.why === 'location' ? 'location' : '';
    // players = null: the server skipped the query (a call sooner than its rate limit): keep what we have
    if (data.players) this.apply(data.players);
    this.syncChannels(p);
    if (this.status === 'connecting' && !this.visible) this.setStatus('on');
    next();
  }

  /** One cap for drawing AND listening: the players drawn are the players whose channels are joined. */
  maxShown(): number {
    const i = this.info!;
    return this.low ? Math.min(i.low_max, i.max_shown) : i.max_shown;
  }

  private apply(rows: NearbyRow[]) {
    const now = nowMs();
    const want = new Map<string, NearbyRow>();
    for (const r of rows) if (!this.blocked.has(r.id)) want.set(r.id, r);
    // shown: the nearest `max` by the server's order
    const ids = [...want.keys()].slice(0, this.maxShown());
    const keep = new Set(ids);
    for (const [id, r] of this.remotes) {
      if (keep.has(id)) r.missing = 0;
      else if (r.leaving === 0 && ++r.missing >= 2) r.leaving = 0.0001;
    }
    for (const id of ids) {
      const row = want.get(id)!;
      let r = this.remotes.get(id);
      if (!r) {
        // static info comes only with the first sight; a row without it (we lost the cache) is skipped until the next tick
        if (!row.n) continue;
        r = {
          id, name: row.n, avatar: row.av ?? null, streetCred: Number(row.sc ?? 0), title: row.t ?? null, crew: row.c ?? null,
          mode: row.m === 'car' ? 'car' : 'walk', veh: row.v ?? null, track: new RemoteTrack(), px: row.x, py: row.y, bubble: null,
          seenAt: now, listedAt: now, missing: 0, born: 0, leaving: 0, dist: 99,
        };
        this.remotes.set(id, r);
      } else {
        if (row.n) { r.name = row.n; r.avatar = row.av ?? r.avatar; r.streetCred = Number(row.sc ?? r.streetCred); r.title = row.t ?? null; r.crew = row.c ?? null; }
        r.leaving = 0;
        r.mode = row.m === 'car' ? 'car' : 'walk';
        r.veh = row.v ?? null;
      }
      r.px = row.x; r.py = row.y; r.seenAt = now; r.listedAt = now;
      r.track.pushPresence(now, row.x, row.y, row.m === 'car');
    }
    this.bump();
  }

  /** Join the topics of the players I listen to, leave the others; the same for my own topic and the bubble cells. */
  private syncChannels(p: { x: number; y: number }) {
    const info = this.info!;
    const now = Date.now();
    const wantTopics = new Set<string>();
    const bm = info.bubble_m + 10;
    for (const [id, r] of this.remotes) {
      if (r.leaving !== 0) continue;
      wantTopics.add(posTopic(id));
      // bubbles only from the players close enough to be read (the text topic has the same server rules as the position topic)
      const x = r.track.has ? r.track.x : r.px, y = r.track.has ? r.track.y : r.py;
      // join within 35 m, leave beyond 50 m (no flapping at the edge: every join carries the access token)
      const d = Math.hypot(x - p.x, y - p.y);
      if (info.bubble && !this.muteBubbles && (d <= bm || (d <= bm + 15 && this.chans.has(textTopic(id))))) wantTopics.add(textTopic(id));
    }
    if (this.visible) wantTopics.add(posTopic(info.me));
    for (const [t, ch] of this.chans) {
      if (!wantTopics.has(t)) {
        void this.sb.removeChannel(ch);
        this.chans.delete(t);
        if (ch === this.ownChan) { this.ownChan = null; this.ownJoined = false; }
      }
    }
    // join a few per tick, own topic first, so a crowd does not open 20 joins in one frame
    let budget = 8;
    for (const t of wantTopics) {
      if (this.chans.has(t)) continue;
      const d = this.denied.get(t);
      if (d && d.until > now) continue;
      if (budget-- <= 0) break;
      this.join(t);
    }
  }

  private join(topic: string) {
    const info = this.info!;
    const own = topic === posTopic(info.me);
    const ch = this.sb.channel(topic, { config: { private: true, broadcast: { self: false, ack: false } } });
    this.chans.set(topic, ch);
    const id = topic.slice(7);
    if (topic.startsWith('roam:t:')) {
      ch.on('broadcast', { event: EVT_BUBBLE }, ({ payload }) => this.onBubble(id, payload));
    } else if (!own) {
      ch.on('broadcast', { event: EVT_POS }, ({ payload }) => this.onPos(id, payload));
    }
    const cb = (status: string) => {
      if (this.stopped) return;
      if (status === 'SUBSCRIBED') {
        this.denied.delete(topic);
        if (own) { this.ownJoined = true; this.ownChan = ch; this.sender.poke(); if (this.status !== 'on') this.setStatus('on'); }
        reportRealtimeOk();
        return;
      }
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        if (this.chans.get(topic) === ch) this.chans.delete(topic);
        void this.sb.removeChannel(ch);
        const prev = this.denied.get(topic);
        const n = (prev?.n ?? 0) + 1;
        // a refused join (the player hid, blocked, left or moved off) is expected: wait longer each time, and do NOT count it as a failure
        this.denied.set(topic, { until: Date.now() + Math.min(300_000, 8000 * 2 ** n), n });
        if (own) {
          this.ownJoined = false;
          this.ownChan = null;
          // only trouble with MY OWN channel (or the socket) counts towards switching the layer off
          this.failures.push(Date.now());
          this.failures = this.failures.filter((t) => Date.now() - t < 60_000);
          if (this.failures.length >= 4) this.fail('connection');
        }
      }
    };
    if (own) trackSubscribe(ch, 'roam', cb);
    else ch.subscribe(cb);
  }

  /* ---------------------------------------------------------------- receiving */
  private onPos(id: string, payload: unknown) {
    const r = this.remotes.get(id);
    if (!r || r.leaving > 0) return;
    const now = nowMs();
    // hostile or buggy senders: at most ~8 messages a second from one player
    const last = this.lastRx.get(id) ?? 0;
    if (now - last < 110) return;
    this.lastRx.set(id, now);
    const d = decodePose((payload as { d?: unknown })?.d ?? payload);
    if (!d) return;
    // a position must stay within reach of where the server last listed him (40 m plus a car's speed): no teleporting avatars, and the
    // collision and bubble radius stay honest
    const reach = 40 + 26 * Math.min(60, (now - r.listedAt) / 1000);
    if (Math.hypot(d.x - r.px, d.y - r.py) > reach) return;
    this.stats.rxMsgs++;
    this.stats.rxBytes += FRAME_OVERHEAD + 28;
    r.track.push(now, d);
    r.seenAt = now;
  }

  private onBubble(topicId: string, payload: unknown) {
    if (this.muteBubbles || !this.info) return;
    const b = parseBubble(payload);
    if (!b || b.u !== topicId) return;
    this.stats.rxMsgs++;
    this.stats.rxBytes += FRAME_OVERHEAD + 40 + b.t.length;
    if (b.u === this.info.me || this.blocked.has(b.u)) return;
    const r = this.remotes.get(b.u);
    // only players the server listed for me (so never someone who blocked me / is hidden) and only within the bubble radius
    if (!r || r.leaving > 0) return;
    const me = this.getPose();
    const sx = r.track.has ? r.track.x : r.px, sy = r.track.has ? r.track.y : r.py;
    if (Math.hypot(sx - me.x, sy - me.y) > this.info.bubble_m + 4) return;
    r.bubble = { text: b.t, until: nowMs() + 4000 + Math.min(4000, b.t.length * 55) };
    this.bump();
  }

  /* ---------------------------------------------------------------- sending (called every frame by the scene) */
  /** Players who really listen to me: the ones drawn (the server lists the same players for both sides). */
  private listenerCount(): number {
    let n = 0;
    for (const r of this.remotes.values()) if (r.leaving === 0) n++;
    return n;
  }

  /** Call each frame with my pose. Sends a message when the rule says so. */
  update(p: Omit<Pose, 'emote'>) {
    if (this.status !== 'on' || !this.visible || !this.ownChan || !this.ownJoined) return;
    const now = nowMs();
    if (this.emoteId && now > this.emoteUntil) this.emoteId = 0;
    const pkt = this.sender.next(now, { ...p, emote: this.emoteId }, this.listenerCount());
    if (!pkt) return;
    if (this.ownChan.state !== 'joined') return;
    void this.ownChan.send({ type: 'broadcast', event: EVT_POS, payload: pkt });
    this.stats.txMsgs++;
    this.stats.txBytes += FRAME_OVERHEAD + 28;
  }

  /** Play an emote on my body and tell the others. */
  emote(name: EmoteName) {
    const id = EMOTES.indexOf(name);
    if (id <= 0 || !this.info?.emotes) return false;
    this.emoteId = id;
    this.emoteAt = nowMs();
    this.emoteUntil = this.emoteAt + EMOTE_MS[name as Exclude<EmoteName, ''>] + 300;
    this.sender.poke();
    return true;
  }

  /** The emote I am playing now (the scene poses my body with it), or null. */
  activeEmote(): { id: number; at: number } | null {
    return this.emoteId && nowMs() < this.emoteUntil ? { id: this.emoteId, at: this.emoteAt } : null;
  }

  cancelEmote() {
    if (this.emoteId) { this.emoteId = 0; this.sender.poke(); }
  }

  /** Send a chat bubble through the server (word filter, mute, rate limit). Resolves with the filtered text or an error message. */
  async say(text: string): Promise<{ ok: true; text: string } | { ok: false; message: string }> {
    const r = await this.sb.rpc('roam_say', { p_text: text });
    if (r.error) return { ok: false, message: r.error.message };
    const t = String((r.data as { text?: string })?.text ?? '');
    this.myBubble = { text: t, until: nowMs() + 4000 + Math.min(4000, t.length * 55) };
    this.bump();
    return { ok: true, text: t };
  }

  /** Block takes effect for me at once (the server filters the next list too). */
  blockLocal(id: string) {
    this.blocked.add(id);
    for (const t of [posTopic(id), textTopic(id)]) {
      const ch = this.chans.get(t);
      if (ch) { void this.sb.removeChannel(ch); this.chans.delete(t); }
    }
    this.lastRx.delete(id);
    this.remotes.delete(id);
    this.bump();
  }

  unblockLocal(id: string) {
    this.blocked.delete(id);
  }

  /** Drop finished fades and bubbles (called by the scene every frame). */
  prune(dt: number) {
    const now = nowMs();
    let changed = false;
    for (const [id, r] of this.remotes) {
      if (r.leaving > 0) {
        r.leaving += dt;
        if (r.leaving > 0.8) {
          this.remotes.delete(id);
          this.lastRx.delete(id);
          for (const t of [posTopic(id), textTopic(id)]) {
            const ch = this.chans.get(t);
            if (ch) { void this.sb.removeChannel(ch); this.chans.delete(t); }
          }
          changed = true;
        }
      } else {
        r.born += dt;
        // nothing from the server about this player for a long time: gone
        if (now - r.seenAt > 40_000) r.leaving = 0.0001;
      }
      if (r.bubble && now > r.bubble.until) { r.bubble = null; changed = true; }
    }
    if (this.myBubble && now > this.myBubble.until) { this.myBubble = null; changed = true; }
    if (changed) this.bump();
  }
}
