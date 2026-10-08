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
}

interface HouseMove {
  id: string;
  x: number;
  z: number;
  yaw: number;
  moving: boolean;
  activity: string | null;
}

/** A private, invite-only home room for low-latency avatar movement updates. */
export function useHouseRoom(locationId: string | null, profile: Profile | null) {
  const [members, setMembers] = useState<HouseActorState[]>([]);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const selfRef = useRef<string | null>(null);
  const lastPublishRef = useRef(0);
  const latestRef = useRef(new Map<string, HouseActorState>());

  useEffect(() => {
    if (!locationId || !profile || profile.location_id !== locationId) {
      setMembers([]);
      latestRef.current.clear();
      return;
    }
    let alive = true;
    let channel: RealtimeChannel | null = null;
    selfRef.current = profile.id;
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
          // Preserve the most recent movement target received after the initial presence sync.
          for (const [id, prior] of latestRef.current) if (next.has(id)) next.set(id, { ...next.get(id)!, ...prior });
          latestRef.current = next;
          publishList();
        }).on('broadcast', { event: 'move' }, ({ payload }) => {
          const move = payload as HouseMove;
          if (!move?.id || move.id === profile.id) return;
          const prior = latestRef.current.get(move.id);
          if (!prior) return;
          latestRef.current.set(move.id, { ...prior, ...move });
          publishList();
        }).subscribe(async (status) => {
          if (!alive || status !== 'SUBSCRIBED' || !channel) return;
          await channel.track({
            id: profile.id, username: profile.username, avatar: profile.avatar,
            x: 0, z: 0, yaw: 0, moving: false, activity: null,
          });
        });
      } catch {
        // The local home remains playable if Realtime is unavailable; visitors simply do not appear live.
      }
    };
    void start();
    return () => {
      alive = false;
      latestRef.current.clear();
      setMembers([]);
      if (channelRef.current === channel) channelRef.current = null;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [locationId, profile?.id, profile?.username, JSON.stringify(profile?.avatar), profile?.location_id]);

  const publish = useCallback((move: Omit<HouseMove, 'id'>) => {
    const channel = channelRef.current;
    const id = selfRef.current;
    const now = performance.now();
    if (!channel || !id || now - lastPublishRef.current < (move.moving ? 100 : 280)) return;
    lastPublishRef.current = now;
    void channel.send({ type: 'broadcast', event: 'move', payload: { ...move, id } });
  }, []);

  return { members, publish };
}
