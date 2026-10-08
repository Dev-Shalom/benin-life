// Dev page for the 3D home: /dev/home?l=flat&h=21.5&busy=bed (dev server only).
// l = hostel | face_me | self_contain | flat | duplex, h = game hour, busy = a HomeGroup,
// o = lapo | nepo (the seeded starter furniture set; omit for the full default furnishing).
import { useMemo, useState } from 'react';
import { defaultAvatar } from '../../avatar3d';
import { HomeView } from '../HomeView';
import { furnishLayout, LAYOUTS, type HomeGroup, type HomeLayoutId, type OwnedPiece } from '../model';

// Mirrors the seeds in 20261006000400_starter_furniture.sql (the game reads them from the server).
const SETS: Record<string, OwnedPiece[]> = {
  lapo: [
    { id: 'drum_bucket', kind: 'drum_bucket', slot: 'bath', activities: ['bathe'] },
    { id: 'stool', kind: 'stool', slot: 'seat', activities: ['sit_rest'] },
    { id: 'kerosene_stove', kind: 'kerosene_stove', slot: 'stove', activities: ['cook_home'] },
    { id: 'foam_mat', kind: 'mattress', slot: 'bed', activities: ['sleep', 'nap'] },
  ],
  nepo: [
    { id: 'bed_double', kind: 'bed_double', slot: 'bed', activities: ['sleep', 'nap'], color: '#5b3fa0' },
    { id: 'sofa', kind: 'sofa', slot: 'sofa', activities: ['relax_sofa'], color: '#7a1f2b' },
    { id: 'tv', kind: 'tv', slot: 'tv', activities: ['watch_tv'] },
    { id: 'fridge', kind: 'fridge', slot: 'fridge', activities: ['cold_drink'] },
    { id: 'gas_cooker', kind: 'gas_cooker', slot: 'stove', activities: ['cook_home'] },
    { id: 'wardrobe', kind: 'wardrobe', slot: 'wardrobe', activities: [], color: '#8a5a33' },
    { id: 'rug', kind: 'rug', slot: 'rug', activities: [], color: '#b3332c' },
    { id: 'centre_table', kind: 'centre_table', slot: 'ctable', activities: [] },
  ],
};

export default function HomeLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  const [layout, setLayout] = useState<HomeLayoutId>((q.get('l') as HomeLayoutId) || 'face_me');
  const [hour, setHour] = useState(Number(q.get('h') ?? 10));
  const [busy, setBusy] = useState<HomeGroup | null>((q.get('busy') as HomeGroup) || null);
  const [picked, setPicked] = useState<string | null>(null);
  const [origin, setOrigin] = useState<string>(q.get('o') ?? '');
  const furnished = useMemo(() => furnishLayout(LAYOUTS[layout], SETS[origin] ?? null), [layout, origin]);
  const avatar = useMemo(() => defaultAvatar(q.get('g') === 'female' ? 'female' : 'male'), [q]);
  return (
    <div style={{ position: 'fixed', inset: 0 }}>
      <HomeView layoutId={layout} layout={furnished} origin={origin === 'nepo' ? 'nepo' : origin === 'lapo' ? 'lapo' : undefined} avatar={avatar} hour={hour} busy={busy ? { group: busy, key: busy } : null}
        selectedId={picked} onPick={(f) => setPicked(f.id)} fallbackScene="home_flat" insetTop={70} insetBottom={110} />
      <div style={{ position: 'fixed', left: 8, top: 8, display: 'flex', gap: 6, flexWrap: 'wrap', zIndex: 5 }}>
        {(Object.keys(LAYOUTS) as HomeLayoutId[]).map((l) => (
          <button key={l} type="button" onClick={() => setLayout(l)} style={{ fontWeight: l === layout ? 800 : 400 }}>{l}</button>
        ))}
        {['', 'lapo', 'nepo'].map((o) => (
          <button key={o || 'all'} type="button" onClick={() => setOrigin(o)} style={{ fontWeight: o === origin ? 800 : 400 }}>{o || 'full'}</button>
        ))}
        <input type="range" min={0} max={24} step={0.25} value={hour} onChange={(e) => setHour(Number(e.target.value))} />
        {(['bed', 'kitchen', 'bath', 'toilet', 'media', 'seat'] as HomeGroup[]).map((g) => (
          <button key={g} type="button" onClick={() => setBusy(busy === g ? null : g)} style={{ fontWeight: g === busy ? 800 : 400 }}>{g}</button>
        ))}
        <span>{picked}</span>
      </div>
    </div>
  );
}
