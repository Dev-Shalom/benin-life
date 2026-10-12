// A2: announcements + gift alerts from the Benin Life team (Admin → Broadcast).
// One `broadcasts` row per announcement on the server; this tab reads its own list with broadcast_inbox().
// When to fetch: once when the game starts, when game_config 'broadcast.last_id' changes (already live on every tab
// through the game_config Realtime channel, or its poll fallback), and when the tab comes back after 5+ minutes.
// The config change fans out to every tab at once, so the fetch waits a random 0–8 s to spread the load.
import { create } from 'zustand';
import { rpc } from '../lib/api';
import { subscribeConfig } from '../lib/config';

export interface Broadcast {
  id: number;
  kind: 'message' | 'gift';
  title: string;
  body: string;
  style: 'info' | 'celebration' | 'warning';
  popup: boolean;
  gift_amount: number | null;
  gift_account: 'cash' | 'bank' | null;
  expires_at: string | null;
  created_at: string;
  seen: boolean;
  dismissed: boolean;
}

interface BroadcastStore {
  rows: Broadcast[];
  lastId: number;
  unseen: number;
  load: () => Promise<void>;
  /** Mark seen (and dismissed when closing the popup). Optimistic; the server ignores ids that aren't mine. */
  mark: (ids: number[], dismiss?: boolean) => void;
}

const unseenOf = (rows: Broadcast[]) => rows.filter((r) => !r.seen).length;
let loading: Promise<void> | null = null;
let loadedAt = 0;

export const useBroadcasts = create<BroadcastStore>((set, get) => ({
  rows: [],
  lastId: 0,
  unseen: 0,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const r = await rpc<{ rows: Broadcast[]; last_id: number }>('broadcast_inbox');
        loadedAt = Date.now();
        set({ rows: r.rows ?? [], lastId: Number(r.last_id) || 0, unseen: unseenOf(r.rows ?? []) });
      } catch {
        /* offline: the next trigger tries again */
      }
    })().finally(() => { loading = null; });
    return loading;
  },
  mark: (ids, dismiss = false) => {
    const want = get().rows.filter((r) => ids.includes(r.id) && (!r.seen || (dismiss && !r.dismissed)));
    if (!want.length) return;
    const rows = get().rows.map((r) => (ids.includes(r.id) ? { ...r, seen: true, dismissed: r.dismissed || dismiss } : r));
    set({ rows, unseen: unseenOf(rows) });
    void rpc('broadcast_mark', { p_ids: want.map((r) => r.id), p_dismiss: dismiss }).catch(() => undefined);
  },
}));

let started = false;
/** Start following broadcasts (call once per signed-in game). Returns a stop function. */
export function startBroadcasts(): () => void {
  if (started) return () => undefined;
  started = true;
  let timer: number | null = null;
  const st = useBroadcasts.getState;
  void st().load();
  const unsub = subscribeConfig((s) => {
    const id = Number(s.values['broadcast.last_id'] ?? 0);
    if (!Number.isFinite(id) || id <= st().lastId || timer != null || !loadedAt) return;
    timer = window.setTimeout(() => { timer = null; void st().load(); }, Math.random() * 8000);
  });
  const onVis = () => {
    if (document.visibilityState === 'visible' && Date.now() - loadedAt > 5 * 60_000) void st().load();
  };
  document.addEventListener('visibilitychange', onVis);
  return () => {
    started = false;
    unsub();
    document.removeEventListener('visibilitychange', onVis);
    if (timer != null) window.clearTimeout(timer);
    useBroadcasts.setState({ rows: [], lastId: 0, unseen: 0 });
    loadedAt = 0;
  };
}
