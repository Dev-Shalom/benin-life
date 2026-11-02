// Other players on the same road (docs/DRIVE.md): a light Supabase Realtime presence channel per road, joined only
// while the drive scene is open. One tiny payload is tracked once on join (name + vehicle): no database writes, no
// per-frame traffic. Skipped in poll mode, when the admin turns it off, or when offline. At most 8 are shown.
import { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { isPollMode, trackSubscribe } from '../../lib/realtime';
import { presenceVehicle, vehicleFromPresence, type VehicleLook } from './model';
import type { OtherCar } from './engine/DriveScene';

export const MAX_OTHERS = 8;

export function useDriveOthers(road: string | null, me: { id: string; name: string } | null, look: VehicleLook, enabled: boolean): OtherCar[] {
  const [others, setOthers] = useState<OtherCar[]>([]);
  const v = presenceVehicle(look);
  useEffect(() => {
    if (!enabled || !road || !me || isPollMode()) {
      setOthers([]);
      return;
    }
    const ch = supabase.channel(`drive:${road}`, { config: { presence: { key: me.id } } });
    let alive = true;
    const sync = () => {
      if (!alive) return;
      const st = ch.presenceState() as Record<string, { n?: string; v?: string }[]>;
      const out: OtherCar[] = [];
      for (const [id, metas] of Object.entries(st)) {
        if (id === me.id) continue;
        const m = metas[0];
        if (!m?.n) continue;
        out.push({ id, name: String(m.n).slice(0, 20), look: vehicleFromPresence(m.v) });
        if (out.length >= MAX_OTHERS) break;
      }
      setOthers((prev) => (prev.map((o) => o.id).join() === out.map((o) => o.id).join() ? prev : out));
    };
    trackSubscribe(ch.on('presence', { event: 'sync' }, sync), 'drive', (status) => {
      if (status === 'SUBSCRIBED') void ch.track({ n: me.name, v });
    });
    return () => {
      alive = false;
      void supabase.removeChannel(ch);
      setOthers([]);
    };
  }, [road, me?.id, me?.name, enabled, v]);
  return others;
}
