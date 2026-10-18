// Dev page for the 3D home: /dev/home?l=flat&h=21.5&busy=bed (dev server only).
// l = hostel | face_me | self_contain | flat | duplex, h = game hour, busy = a HomeGroup,
// o = lapo | nepo (the seeded starter furniture set; omit for the full default furnishing).
// R8: up = finished upgrades (comma list of upgrade ids, e.g. up=ext_bedroom,paint_fresh,finish_pop,fence_wall,gate_security,gen_house),
// build = upgrades the builders are on (scaffolding), e.g. build=ext_guest_wing.
import { useMemo, useState } from 'react';
import { defaultAvatar } from '../../avatar3d';
import { HomeView } from '../HomeView';
import { applyUpgrades } from '../upgrades';
import { furnishLayout, KINDS, LAYOUTS, type FurnitureItem, type FurnitureKind, type HomeGroup, type HomeLayout, type HomeLayoutId, type OwnedPiece } from '../model';

/** B1: ?show=1 lays every furniture kind out in rows on the duplex lot (model check). */
function showroom(): HomeLayout {
  const base = LAYOUTS.duplex;
  const kinds = (Object.keys(KINDS) as FurnitureKind[]).filter((k) => !['toilet', 'pit_toilet', 'shower', 'bathtub', 'sink', 'bucket_bath', 'stall', 'kitchen', 'island'].includes(k));
  const furniture: FurnitureItem[] = [];
  let x = 0, z = 0, row = 0;
  for (const k of kinds) {
    const m = KINDS[k];
    if (x + m.w > 15) { x = 0; z += row + 0.5; row = 0; }
    furniture.push({ id: `own_${k}`, kind: k, x: base.lot[0] + 0.3 + x + m.w / 2, z: base.lot[1] + 0.3 + z + m.d / 2 });
    x += m.w + 0.4;
    row = Math.max(row, m.d);
  }
  return { ...base, partitions: [], doors: [], windows: [], furniture, w: 0.01, d: 0.01 };
}

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
  // R8: ?up= / ?build= show house upgrades (the finish / security levels the server's effect json carries)
  const upgraded = useMemo(() => {
    const info = (id: string) => ({ id, effect: ({ paint_fresh: { finish: 1 }, finish_pop: { finish: 2 }, finish_premium: { finish: 3 }, fence_wall: { security: 1 }, gate_security: { security: 2 } } as Record<string, Record<string, number>>)[id] ?? null });
    const ids = (k: string) => (q.get(k) ?? '').split(',').filter(Boolean).map(info);
    return applyUpgrades(LAYOUTS[layout], ids('up'), ids('build'));
  }, [layout, q]);
  const furnished = useMemo(() => (q.get('show') ? showroom() : furnishLayout(upgraded, SETS[origin] ?? null)), [upgraded, origin, q]);
  const avatar = useMemo(() => defaultAvatar(q.get('g') === 'female' ? 'female' : 'male'), [q]);
  // ?cars=gwagon_g63,benz_c300&garage=garage:2 parks cars so the tap-to-name label can be checked
  const parking = useMemo(() => {
    const cars = (q.get('cars') ?? '').split(',').filter(Boolean);
    if (!cars.length) return null;
    const [style, cap] = (q.get('garage') ?? '').split(':');
    return { cars, names: cars.map((c) => c.replace(/_/g, ' ')), garage: style ? { style: style as 'garage' | 'carport', capacity: Number(cap) || 1 } : null };
  }, [q]);
  return (
    <div style={{ position: 'fixed', inset: 0 }}>
      <HomeView layoutId={layout} parking={parking} layout={furnished} origin={origin === 'nepo' ? 'nepo' : origin === 'lapo' ? 'lapo' : undefined} avatar={avatar} hour={hour} busy={busy ? { group: busy, key: busy } : null}
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
