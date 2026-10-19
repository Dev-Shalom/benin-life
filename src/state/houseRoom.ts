import { useCallback, useEffect, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import type { AvatarConfig, Profile } from '../lib/types';
import { supabase } from '../lib/supabase';
import { rpc } from '../lib/api';
import { startPoller, trackSubscribe, usePollMode } from '../lib/realtime';

/** F1 poll mode: house_room_state every ~4 s while others are in the house, ~20 s while alone. */
const HOUSE_POLL_BUSY_MS = 5_000;
const HOUSE_POLL_ALONE_MS = 30_000;
/** Poll-mode keep-alive post (live tabs drop a polling member they haven't heard from in PRUNE_MS). */
const KEEPALIVE_MS = 60_000;
const PRUNE_MS = 150_000;

/** A house_room_positions row (Postgres Changes) or a house_room_state member. */
interface PosRow {
  id?: string;
  user_id?: string;
  username?: string;
  avatar?: AvatarConfig | null;
  x: number;
  z: number;
  yaw: number;
  moving: boolean;
  activity?: string | null;
  path?: { p?: number[]; f?: number | null; at?: number } | null;
  via?: string;
  left_at?: string | null;
  at?: number;
  updated_at?: string;
}

function toPath(raw: PosRow['path']): HousePath | undefined {
  if (!raw || !Array.isArray(raw.p) || raw.p.length < 4) return undefined;
  const pts: [number, number][] = [];
  for (let i = 0; i + 1 < raw.p.length && pts.length < 64; i += 2) pts.push([Number(raw.p[i]), Number(raw.p[i + 1])]);
  if (pts.some(([x, z]) => !Number.isFinite(x) || !Number.isFinite(z))) return undefined;
  return { pts, faceTo: typeof raw.f === 'number' ? raw.f : null, at: Number(raw.at) || 0 };
}

export interface HouseActorState {
  id: string;
  username: string;
  avatar: AvatarConfig;
  x: number;
  z: number;
  yaw: number;
  moving: boolean;
  activity: string | null;
  updatedAt: number;
  /** V2: the waypoints of the walk this player started last (their own nav grid = the host's layout). */
  path?: HousePath;
}

/** One message per walk: where the owner set off from, the corners and the end, and the final facing. */
export interface HousePath {
  pts: [number, number][];
  faceTo: number | null;
  /** Sender clock (ms): a new value = a new walk. */
  at: number;
}

interface HouseMove {
  x: number;
  z: number;
  yaw: number;
  moving: boolean;
  activity: string | null;
  updatedAt: number;
}

/** The rest of a flat [x0, z0, x1, z1, ...] path from the walker's current position (nearest segment). */
function remainingPath(p: number[], x: number, z: number): number[] {
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i + 3 < p.length; i += 2) {
    const ax = p[i], az = p[i + 1], bx = p[i + 2], bz = p[i + 3];
    const dx = bx - ax, dz = bz - az;
    const len2 = dx * dx + dz * dz || 1;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / len2));
    const d = Math.hypot(ax + dx * t - x, az + dz * t - z);
    if (d < bestD) { bestD = d; best = i; }
  }
  return [Math.round(x * 100) / 100, Math.round(z * 100) / 100, ...p.slice(best + 2)];
}

/** A private, invite-only home room for low-latency avatar movement updates. */
export function useHouseRoom(locationId: string | null, profile: Profile | null) {
  const poll = usePollMode();
  const pollRef = useRef(poll);
  pollRef.current = poll;
  const [members, setMembers] = useState<HouseActorState[]>([]);
  /** F1: post my moves with house_room_move (poll mode, or live with polling members in the house = "bridge"). */
  const bridgeRef = useRef(false);
  const upRef = useRef({ timer: 0, last: 0, avatarSent: '' });
  const avatarRef = useRef<AvatarConfig | null>(null);
  avatarRef.current = profile?.avatar ?? null;
  /** Members known only from rows (polling players), with when we last heard from them. */
  const rowSeenRef = useRef(new Map<string, number>());
  const channelRef = useRef<RealtimeChannel | null>(null);
  const selfRef = useRef<string | null>(null);
  const subscribedRef = useRef(false);
  const lastPublishRef = useRef(0);
  const selfMoveRef = useRef<HouseMove>({ x: 0, z: 0, yaw: 0, moving: false, activity: null, updatedAt: 0 });
  const latestRef = useRef(new Map<string, HouseActorState>());
  const trailRef = useRef(0);
  // Q1: a walk that started before the room was joined (the walk in from the door on arrival)
  const pendingPathRef = useRef<{ p: number[]; f: number | null; at: number } | null>(null);

  /** F1: post my position now (house_room_move). Fire-and-forget; plain supabase.rpc so it isn't counted as a game action. */
  const sendMove = useCallback((path: { p: number[]; f: number | null; at: number } | null) => {
    const up = upRef.current;
    window.clearTimeout(up.timer);
    up.timer = 0;
    up.last = Date.now();
    const s = selfMoveRef.current;
    const av = avatarRef.current;
    const avKey = av ? JSON.stringify(av) : '';
    const sendAv = avKey !== up.avatarSent;
    void supabase.rpc('house_room_move', {
      p_x: Math.round(s.x * 100) / 100, p_z: Math.round(s.z * 100) / 100, p_yaw: Math.round(s.yaw * 1000) / 1000,
      p_moving: s.moving, p_activity: s.activity, p_path: path, p_avatar: sendAv ? av : null,
      p_via: pollRef.current ? 'poll' : 'bridge',
    }).then(({ error }) => { if (!error && sendAv) up.avatarSent = avKey; });
  }, []);
  /** Throttled post: at most one per `gap` ms, the latest snapshot wins (the final stop is never dropped). */
  const queueMove = useCallback((gap: number) => {
    const up = upRef.current;
    const wait = gap - (Date.now() - up.last);
    if (wait <= 0) return sendMove(null);
    if (!up.timer) up.timer = window.setTimeout(() => { up.timer = 0; sendMove(null); }, wait);
  }, [sendMove]);

  useEffect(() => {
    if (!locationId || !profile || profile.location_id !== locationId) {
      setMembers([]);
      latestRef.current.clear();
      return;
    }
    let alive = true;
    let channel: RealtimeChannel | null = null;
    selfRef.current = profile.id;
    subscribedRef.current = false;
    const publishList = () => setMembers([...latestRef.current.values()].filter((m) => m.id !== profile.id));
    rowSeenRef.current.clear();
    if (poll) {
      // ---- F1 poll mode: post my position, read everyone's every few seconds
      bridgeRef.current = true;
      upRef.current.avatarSent = '';
      const pending = pendingPathRef.current;
      pendingPathRef.current = null;
      sendMove(pending && Date.now() - pending.at < 8000 ? pending : null);
      const known = new Map<string, { username: string; avatar: AvatarConfig }>();
      let alone = true;
      const tick = async () => {
        if (Date.now() - upRef.current.last > KEEPALIVE_MS) sendMove(null); // keep-alive for live tabs (they prune after PRUNE_MS)
        let r = await rpc<{ location: string; members: PosRow[] }>('house_room_state', { p_with_avatars: false });
        if (!alive) return;
        if ((r?.members ?? []).some((m) => m.id && !known.has(m.id))) {
          r = await rpc<{ location: string; members: PosRow[] }>('house_room_state', { p_with_avatars: true });
          if (!alive) return;
          for (const m of r?.members ?? []) if (m.id) known.set(m.id, { username: m.username ?? 'Player', avatar: (m.avatar ?? {}) as AvatarConfig });
        }
        const next = new Map<string, HouseActorState>();
        for (const m of r?.members ?? []) {
          if (!m.id || m.id === profile.id) continue;
          const who = known.get(m.id);
          const prior = latestRef.current.get(m.id);
          const path = toPath(m.path) ?? prior?.path;
          next.set(m.id, {
            id: m.id, username: who?.username ?? prior?.username ?? 'Player', avatar: who?.avatar ?? prior?.avatar ?? ({} as AvatarConfig),
            x: Number(m.x), z: Number(m.z), yaw: Number(m.yaw), moving: Boolean(m.moving), activity: m.activity ?? null,
            updatedAt: Number(m.at) || Date.now(), path,
          });
        }
        alone = next.size === 0;
        latestRef.current = next;
        publishList();
      };
      const poller = startPoller(tick, () => (alone ? HOUSE_POLL_ALONE_MS : HOUSE_POLL_BUSY_MS), { immediate: true });
      return () => {
        alive = false;
        poller.stop();
        window.clearTimeout(upRef.current.timer);
        upRef.current.timer = 0;
        latestRef.current.clear();
        setMembers([]);
      };
    }
    bridgeRef.current = false;
    /** F1 bridge: a polling member's row (Postgres Changes on the house channel). */
    const onRow = (row: PosRow) => {
      const id = row.user_id;
      if (!id || id === profile.id) return;
      const inPresence = channel ? Boolean(channel.presenceState()[id]) : false;
      if (row.left_at) {
        rowSeenRef.current.delete(id);
        if (!inPresence && latestRef.current.delete(id)) publishList();
        return;
      }
      if (row.via !== 'poll' || inPresence) return; // another live tab bridging: Presence already has them
      if (!bridgeRef.current) {
        bridgeRef.current = true;
        sendMove(null); // let the polling member see us
      }
      rowSeenRef.current.set(id, Date.now());
      const prior = latestRef.current.get(id);
      latestRef.current.set(id, {
        id, username: row.username || prior?.username || 'Player', avatar: (row.avatar ?? prior?.avatar ?? {}) as AvatarConfig,
        x: Number(row.x), z: Number(row.z), yaw: Number(row.yaw), moving: Boolean(row.moving), activity: row.activity ?? null,
        updatedAt: Date.now(), path: toPath(row.path) ?? prior?.path,
      });
      publishList();
    };
    const prune = window.setInterval(() => {
      let changed = false;
      for (const [id, t] of rowSeenRef.current) {
        if (Date.now() - t > PRUNE_MS) { rowSeenRef.current.delete(id); if (latestRef.current.delete(id)) changed = true; }
      }
      if (changed) publishList();
    }, 30_000);
    const start = async () => {
      try {
        const { data } = await supabase.auth.getSession();
        const token = data.session?.access_token;
        if (!alive || !token) return;
        await supabase.realtime.setAuth(token);
        channel = supabase.channel(`house:${locationId}`, {
          config: { private: true, presence: { key: profile.id }, broadcast: { ack: true, self: false } },
        });
        channelRef.current = channel;
        channel.on('presence', { event: 'sync' }, () => {
          if (!channel) return;
          const current = channel.presenceState<HouseActorState>();
          const next = new Map<string, HouseActorState>();
          for (const metas of Object.values(current)) {
            for (const meta of metas) if (meta.id && meta.id !== profile.id) next.set(meta.id, meta);
          }
          // Preserve a newer movement broadcast, while accepting a fresher presence snapshot if a
          // player rejoined the room with a new position.
          for (const [id, prior] of latestRef.current) {
            const tracked = next.get(id);
            if (tracked && prior.updatedAt > tracked.updatedAt) next.set(id, { ...tracked, ...prior });
            else if (tracked && prior.path) next.set(id, { ...tracked, path: prior.path });
          }
          // F1 bridge: polling members are not on Presence; keep them
          for (const id of rowSeenRef.current.keys()) {
            const m = latestRef.current.get(id);
            if (m && !next.has(id)) next.set(id, m);
          }
          latestRef.current = next;
          publishList();
        }).on('presence', { event: 'join' }, ({ key }) => {
          // a newcomer: tell them where we stand now (our last snapshot may predate their join)
          if (!channel || key === profile.id || !subscribedRef.current) return;
          void channel.send({ type: 'broadcast', event: 'move', payload: { ...selfMoveRef.current, updatedAt: Date.now(), id: profile.id } });
        }).on('broadcast', { event: 'move' }, ({ payload }) => {
          const move = payload as HouseMove & { id: string };
          if (!move?.id || move.id === profile.id) return;
          const prior = latestRef.current.get(move.id);
          if (!prior) return;
          latestRef.current.set(move.id, { ...prior, ...move });
          publishList();
        }).on('broadcast', { event: 'path' }, ({ payload }) => {
          const msg = payload as { id: string; p: number[]; f: number | null; at: number };
          if (!msg?.id || msg.id === profile.id || !Array.isArray(msg.p) || msg.p.length < 2) return;
          const prior = latestRef.current.get(msg.id);
          if (!prior) return;
          const pts: [number, number][] = [];
          for (let i = 0; i + 1 < msg.p.length && pts.length < 64; i += 2) pts.push([Number(msg.p[i]), Number(msg.p[i + 1])]);
          if (pts.some(([x, z]) => !Number.isFinite(x) || !Number.isFinite(z))) return;
          latestRef.current.set(msg.id, { ...prior, moving: true, path: { pts, faceTo: typeof msg.f === 'number' ? msg.f : null, at: Number(msg.at) || Date.now() } });
          publishList();
        }).on('postgres_changes', { event: '*', schema: 'public', table: 'house_room_positions', filter: `location_id=eq.${locationId}` },
          (payload) => { if (payload.eventType !== 'DELETE') onRow(payload.new as PosRow); });
        trackSubscribe(channel, 'house', async (status) => {
          subscribedRef.current = alive && status === 'SUBSCRIBED';
          if (!subscribedRef.current || !channel) return;
          const snapshot = { ...selfMoveRef.current, updatedAt: Date.now() };
          selfMoveRef.current = snapshot;
          await channel.track({ id: profile.id, username: profile.username, avatar: profile.avatar, ...snapshot });
          lastPublishRef.current = performance.now();
          await channel.send({ type: 'broadcast', event: 'move', payload: { ...snapshot, id: profile.id } });
          // the arrival walk began before we joined: send it now (if still fresh), shortly after our presence
          // lands, so the others see us walk in from the door instead of popping in
          const pending = pendingPathRef.current;
          pendingPathRef.current = null;
          if (pending && Date.now() - pending.at < 8000) {
            window.setTimeout(() => {
              const cur = selfMoveRef.current;
              if (!alive || !subscribedRef.current || channelRef.current !== channel || !cur.moving) return;
              const p = remainingPath(pending.p, cur.x, cur.z);
              if (p.length >= 4) void channel?.send({ type: 'broadcast', event: 'path', payload: { id: profile.id, ...pending, p, at: Date.now() } });
            }, 350);
          }
        });
      } catch {
        // The local home remains playable if Realtime is unavailable; visitors simply do not appear live.
      }
    };
    void start();
    return () => {
      alive = false;
      window.clearInterval(prune);
      window.clearTimeout(upRef.current.timer);
      upRef.current.timer = 0;
      subscribedRef.current = false;
      window.clearTimeout(trailRef.current);
      trailRef.current = 0;
      latestRef.current.clear();
      setMembers([]);
      if (channelRef.current === channel) channelRef.current = null;
      if (channel) void supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locationId, profile?.id, profile?.username, JSON.stringify(profile?.avatar), profile?.location_id, poll]);

  const publish = useCallback((move: Omit<HouseMove, 'updatedAt'>) => {
    const prev = selfMoveRef.current;
    const snapshot = { ...move, updatedAt: Date.now() };
    selfMoveRef.current = snapshot;
    if (bridgeRef.current) {
      // F1: stop / pose change at once (short gap), while walking only every 2.5 s (the walk path covers the rest)
      if (prev.moving !== move.moving || prev.activity !== move.activity) queueMove(400);
      else if (move.moving) queueMove(2500);
      else if (Math.hypot(prev.x - move.x, prev.z - move.z) > 0.3 || Math.abs(prev.yaw - move.yaw) > 0.5) queueMove(1500);
    }
    const channel = channelRef.current;
    const id = selfRef.current;
    const now = performance.now();
    if (!channel || !id || !subscribedRef.current) return;
    const wait = (move.moving ? 100 : 280) - (now - lastPublishRef.current);
    if (wait > 0) {
      // throttled: send the latest snapshot when the window ends (never drop the final stop)
      if (!trailRef.current) trailRef.current = window.setTimeout(() => {
        trailRef.current = 0;
        const ch = channelRef.current;
        if (!ch || !subscribedRef.current) return;
        lastPublishRef.current = performance.now();
        void ch.send({ type: 'broadcast', event: 'move', payload: { ...selfMoveRef.current, id } });
      }, wait);
      return;
    }
    lastPublishRef.current = now;
    void channel.send({ type: 'broadcast', event: 'move', payload: { ...snapshot, id } });
  }, [queueMove]);

  /** V2: once per walk, the path the local Sim set off on (receivers walk it on their own grid). */
  const publishPath = useCallback((pts: [number, number][], faceTo: number | null) => {
    const channel = channelRef.current;
    const id = selfRef.current;
    if (pts.length < 2) return;
    const p = pts.slice(0, 48).flatMap(([x, z]) => [Math.round(x * 100) / 100, Math.round(z * 100) / 100]);
    const msg = { p, f: faceTo == null ? null : Math.round(faceTo * 1000) / 1000, at: Date.now() };
    if (bridgeRef.current) sendMove(msg); // F1: polling members see the walk on their next poll
    if (pollRef.current) return;
    if (!channel || !id || !subscribedRef.current) {
      pendingPathRef.current = msg;
      return;
    }
    pendingPathRef.current = null;
    void channel.send({ type: 'broadcast', event: 'path', payload: { id, ...msg } });
  }, [sendMove]);

  return { members, publish, publishPath };
}
