import { useCallback, useEffect, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import type { AvatarConfig, Profile } from '../lib/types';
import { supabase } from '../lib/supabase';

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
  const [members, setMembers] = useState<HouseActorState[]>([]);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const selfRef = useRef<string | null>(null);
  const subscribedRef = useRef(false);
  const lastPublishRef = useRef(0);
  const selfMoveRef = useRef<HouseMove>({ x: 0, z: 0, yaw: 0, moving: false, activity: null, updatedAt: 0 });
  const latestRef = useRef(new Map<string, HouseActorState>());
  const trailRef = useRef(0);
  // Q1: a walk that started before the room was joined (the walk in from the door on arrival)
  const pendingPathRef = useRef<{ p: number[]; f: number | null; at: number } | null>(null);

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
        }).subscribe(async (status) => {
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
      subscribedRef.current = false;
      window.clearTimeout(trailRef.current);
      trailRef.current = 0;
      latestRef.current.clear();
      setMembers([]);
      if (channelRef.current === channel) channelRef.current = null;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [locationId, profile?.id, profile?.username, JSON.stringify(profile?.avatar), profile?.location_id]);

  const publish = useCallback((move: Omit<HouseMove, 'updatedAt'>) => {
    const snapshot = { ...move, updatedAt: Date.now() };
    selfMoveRef.current = snapshot;
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
  }, []);

  /** V2: once per walk, the path the local Sim set off on (receivers walk it on their own grid). */
  const publishPath = useCallback((pts: [number, number][], faceTo: number | null) => {
    const channel = channelRef.current;
    const id = selfRef.current;
    if (pts.length < 2) return;
    const p = pts.slice(0, 48).flatMap(([x, z]) => [Math.round(x * 100) / 100, Math.round(z * 100) / 100]);
    const msg = { p, f: faceTo == null ? null : Math.round(faceTo * 1000) / 1000, at: Date.now() };
    if (!channel || !id || !subscribedRef.current) {
      pendingPathRef.current = msg;
      return;
    }
    pendingPathRef.current = null;
    void channel.send({ type: 'broadcast', event: 'path', payload: { id, ...msg } });
  }, []);

  return { members, publish, publishPath };
}
