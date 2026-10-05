// Dev page for the 3D city: /dev/city?f=palace&h=21&cur=ekenwan_room&travel=ekenwan_room,ramat_park,0.4
// f = a close-up preset (or x,y,zoom via ?x=&y=&z=), h = game hour, cur = "you are here",
// travel = from,to,progress, sel = selected place. Dev server only.
import { useMemo, useState } from 'react';
import { CityView } from '../CityView';
import { DEV_LOCATIONS } from './fixture';
import type { CityFilter } from '../model';

const PRESETS: Record<string, { x: number; y: number; zoom: number }> = {
  city: { x: 500, y: 480, zoom: 60 },
  centre: { x: 470, y: 500, zoom: 16 },
  palace: { x: 412, y: 505, zoom: 9 },
  museum: { x: 500, y: 505, zoom: 9 },
  river: { x: 662, y: 425, zoom: 12 },
  ramat: { x: 700, y: 415, zoom: 11 },
  airport: { x: 270, y: 665, zoom: 16 },
  uniben: { x: 480, y: 135, zoom: 14 },
  ubth: { x: 425, y: 172, zoom: 9 },
  police: { x: 495, y: 615, zoom: 10 },
  market: { x: 446, y: 430, zoom: 10 },
  north: { x: 460, y: 200, zoom: 40 },
  gra: { x: 460, y: 650, zoom: 18 },
};

export default function CityLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  const [hour, setHour] = useState(Number(q.get('h') ?? 11));
  const [sel, setSel] = useState<string | undefined>(q.get('sel') ?? undefined);
  const preset = PRESETS[q.get('f') ?? 'city'] ?? PRESETS.city;
  const initial = q.get('x') ? { x: Number(q.get('x')), y: Number(q.get('y')), zoom: Number(q.get('z') ?? 20) } : { ...preset, zoom: Number(q.get('z') ?? preset.zoom) };
  const tr = q.get('travel')?.split(',');
  const travel = tr ? { from: tr[0], to: tr[1], progress: Number(tr[2] ?? 0.4) } : null;
  const night = hour >= 20 || hour < 6;
  return (
    <div className={`game${night ? ' is-night' : ''}`} style={{ position: 'fixed', inset: 0 }}>
      <CityView
        locations={DEV_LOCATIONS}
        currentId={travel ? undefined : (q.get('cur') ?? 'ekenwan_room')}
        selectedId={sel}
        onSelect={setSel}
        night={night}
        hour={hour}
        travel={travel}
        initial={initial}
        hideChrome={q.has('bare')}
        initialFilters={(q.get('filters')?.split(',') as CityFilter[] | undefined) ?? undefined}
        insetTop={q.has('bare') ? 0 : 70}
        insetBottom={q.has('bare') ? 0 : 110}
      />
      {!q.has('bare') && (
        <div style={{ position: 'fixed', left: 8, bottom: 8, display: 'flex', gap: 6, alignItems: 'center', zIndex: 5, background: '#fff', padding: 6, borderRadius: 12 }}>
          <input type="range" min={0} max={24} step={0.25} value={hour} onChange={(e) => setHour(Number(e.target.value))} />
          <span>{hour.toFixed(2)}h</span>
          <span>{sel}</span>
        </div>
      )}
    </div>
  );
}
