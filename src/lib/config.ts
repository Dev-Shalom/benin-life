// Live game config — P1-SHELL. Loads `game_config` (key, value) and follows realtime changes,
// so admin edits take effect instantly on every client.
import { create } from 'zustand';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase, supabaseConfigured } from './supabase';

interface ConfigStore {
  values: Record<string, unknown>;
  ready: boolean;
  version: number;
}

const useConfigStore = create<ConfigStore>(() => ({ values: {}, ready: false, version: 0 }));

let started = false;
let channel: RealtimeChannel | null = null;

/** Start loading + realtime subscription (idempotent). */
export function ensureConfig(): void {
  if (started || !supabaseConfigured) return;
  started = true;
  void loadAll();
  channel = supabase
    .channel('game_config_live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'game_config' }, (payload) => {
      const row = (payload.eventType === 'DELETE' ? payload.old : payload.new) as { key?: string; value?: unknown };
      if (!row?.key) return;
      useConfigStore.setState((s) => {
        const values = { ...s.values };
        if (payload.eventType === 'DELETE') delete values[row.key!];
        else values[row.key!] = row.value;
        return { values, version: s.version + 1 };
      });
    })
    .subscribe((status) => {
      // After a reconnect, reload everything so we don't miss edits made while offline.
      if (status === 'SUBSCRIBED' && useConfigStore.getState().ready) void loadAll();
    });
}

async function loadAll(): Promise<void> {
  const { data, error } = await supabase.from('game_config').select('key,value');
  if (error) {
    console.warn('[config] load failed:', error.message);
    useConfigStore.setState({ ready: true });
    return;
  }
  const values: Record<string, unknown> = {};
  for (const row of (data ?? []) as { key: string; value: unknown }[]) values[row.key] = row.value;
  useConfigStore.setState((s) => ({ values, ready: true, version: s.version + 1 }));
}

/** Stop realtime (used on full sign-out / tests). */
export function stopConfig(): void {
  if (channel) void supabase.removeChannel(channel);
  channel = null;
  started = false;
}

function coerce<T>(raw: unknown, fallback: T): T {
  if (raw === undefined || raw === null) return fallback;
  // jsonb might hold {"v": 12} style wrappers in future; unwrap common shapes.
  if (typeof raw === 'object' && !Array.isArray(raw) && raw && 'value' in (raw as Record<string, unknown>)) {
    return coerce((raw as Record<string, unknown>).value, fallback);
  }
  if (typeof fallback === 'number') {
    const n = typeof raw === 'number' ? raw : Number(raw);
    return (Number.isFinite(n) ? n : fallback) as T;
  }
  if (typeof fallback === 'boolean') {
    if (typeof raw === 'boolean') return raw as T;
    if (raw === 'true' || raw === 1 || raw === '1') return true as T;
    if (raw === 'false' || raw === 0 || raw === '0') return false as T;
    return fallback;
  }
  if (typeof fallback === 'string') return String(raw) as T;
  return raw as T;
}

/** Read a config value outside React. */
export function getCfg<T>(key: string, fallback: T): T {
  return coerce(useConfigStore.getState().values[key], fallback);
}

/** React hook: `const { cfg, ready } = useConfig(); cfg('crime.night_mult', 1.5)`. Re-renders on live edits. */
export function useConfig() {
  ensureConfig();
  const values = useConfigStore((s) => s.values);
  const ready = useConfigStore((s) => s.ready);
  const cfg = <T,>(key: string, fallback: T): T => coerce(values[key], fallback);
  return { cfg, ready, values };
}

/** Subscribe to config changes outside React. */
export const subscribeConfig = useConfigStore.subscribe;
