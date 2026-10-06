// Dev page for the 3D home: /dev/home?l=flat&h=21.5&busy=bed (dev server only).
// l = hostel | face_me | self_contain | flat | duplex, h = game hour, busy = a HomeGroup,
// f = lapo | nepo (preview a starter furniture set) or a comma list of furniture ids; none = the full room.
import { useMemo, useState } from 'react';
import { defaultAvatar } from '../../avatar3d';
import { HomeView } from '../HomeView';
import { LAYOUTS, type HomeGroup, type HomeLayoutId } from '../model';

export default function HomeLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  const [layout, setLayout] = useState<HomeLayoutId>((q.get('l') as HomeLayoutId) || 'face_me');
  const [hour, setHour] = useState(Number(q.get('h') ?? 10));
  const [busy, setBusy] = useState<HomeGroup | null>((q.get('busy') as HomeGroup) || null);
  const [picked, setPicked] = useState<string | null>(null);
  const owned = useMemo(() => {
    const f = q.get('f');
    if (!f) return null;
    if (f === 'lapo') return ['water_drum', 'bucket', 'stool', 'kerosene_stove', 'foam_mattress'];
    if (f === 'nepo') return ['water_drum', 'bucket', 'bed', 'sofa', 'tv', 'fridge', 'gas_cooker', 'wardrobe', 'standing_fan', 'rug', 'centre_table'];
    return f.split(',');
  }, [q]);
  const avatar = useMemo(() => defaultAvatar(q.get('g') === 'female' ? 'female' : 'male'), [q]);
  return (
    <div style={{ position: 'fixed', inset: 0 }}>
      <HomeView layoutId={layout} owned={owned} avatar={avatar} hour={hour} busy={busy ? { group: busy, key: busy } : null}
        selectedId={picked} onPick={(f) => setPicked(f.id)} fallbackScene="home_flat" insetTop={70} insetBottom={110} />
      <div style={{ position: 'fixed', left: 8, top: 8, display: 'flex', gap: 6, flexWrap: 'wrap', zIndex: 5 }}>
        {(Object.keys(LAYOUTS) as HomeLayoutId[]).map((l) => (
          <button key={l} type="button" onClick={() => setLayout(l)} style={{ fontWeight: l === layout ? 800 : 400 }}>{l}</button>
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
