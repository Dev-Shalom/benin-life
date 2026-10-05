// Dev gallery for the 3D avatar system (route /dev/avatars, not linked anywhere in the app).
// Sections can be shown alone with ?s=presets|pviews|bodies|faces|hair|hats|acc|views|fabrics|portraits|stage|landing|stats
// and turned with &yaw=0.8. Everything renders through the shared portrait renderer (one WebGL context).
import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react';
import type { AvatarConfig, Gender } from '../../../lib/types';
import {
  AVATAR_OPTIONS,
  applyPreset,
  defaultAvatar,
  optionsFor,
  presetsFor,
  randomAvatar,
  SKIN_TONES,
  type AvatarOption,
} from '../catalog';
import { AvatarPortrait } from '../AvatarPortrait';
import { AvatarStage } from '../AvatarStage';

/** The two Sims on the landing page (public/art/sim-*.webp are rendered from these). */
export const LANDING_SIMS: Record<'lapo' | 'nepo', AvatarConfig> = {
  lapo: { ...applyPreset({ ...defaultAvatar('male'), skin: 'tone5', face: 'square', mouth: 'grin', hair: 'low_cut', facialHair: 'stubble' }, 'keke') },
  nepo: { ...applyPreset({ ...defaultAvatar('female'), skin: 'tone3', face: 'heart', hair: 'bone_straight', mouth: 'smirk' }, 'glam') },
};

const page: CSSProperties = { padding: 16, background: 'linear-gradient(#dfeefb, #f4f8fc)', minHeight: '100vh', font: '13px system-ui, sans-serif', color: '#1c2633' };
const grid: CSSProperties = { display: 'flex', flexWrap: 'wrap', gap: 10 };
const card: CSSProperties = { background: '#fff', borderRadius: 14, padding: 6, display: 'grid', justifyItems: 'center', gap: 2, boxShadow: '0 2px 8px rgba(20,40,70,.08)' };

function Cell({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={card}>
      {children}
      <span style={{ fontWeight: 600, fontSize: 12, maxWidth: 150, textAlign: 'center' }}>{label}</span>
    </div>
  );
}

function Section({ id, title, children, only }: { id: string; title: string; children: ReactNode; only: string | null }) {
  if (only && only !== id) return null;
  return (
    <section style={{ marginBottom: 28 }} id={id}>
      <h2 style={{ font: '700 17px system-ui', margin: '6px 0 10px' }}>{title}</h2>
      <div style={grid}>{children}</div>
    </section>
  );
}

const G: Gender[] = ['male', 'female'];
const BODIES = ['slim', 'average', 'thick'] as const;

export default function AvatarLab() {
  const q = new URLSearchParams(location.search);
  const only = q.get('s');
  const yaw = Number(q.get('yaw') ?? 0) || 0;
  const size = Number(q.get('size') ?? 0) || 0;
  const gOnly = q.get('g') as Gender | null;
  const genders = gOnly ? [gOnly] : G;
  const [stagePreset, setStagePreset] = useState('owambe');
  const [stageG, setStageG] = useState<Gender>('female');
  const stageCfg = useMemo(() => applyPreset(defaultAvatar(stageG), stagePreset), [stageG, stagePreset]);
  const [stats, setStats] = useState<string>('');

  useEffect(() => {
    if (only && only !== 'stats') return;
    // triangle counts per preset (built directly, not rendered)
    void import('../engine/character').then(({ buildCharacter }) => {
      const rows: string[] = [];
      for (const g of G) {
        for (const p of presetsFor(g)) {
          const ch = buildCharacter(applyPreset(defaultAvatar(g), p.id));
          rows.push(`${g.padEnd(6)} ${p.label.padEnd(24)} ${String(ch.stats.tris).padStart(6)} tris  ${String(ch.stats.meshes).padStart(3)} meshes  ${ch.stats.buildMs.toFixed(1)} ms`);
          ch.dispose();
        }
      }
      for (const hair of AVATAR_OPTIONS.hair) {
        const g: Gender = hair.gender ?? 'female';
        const ch = buildCharacter({ ...defaultAvatar(g), hair: hair.id });
        rows.push(`hair   ${hair.label.padEnd(24)} ${String(ch.stats.tris).padStart(6)} tris`);
        ch.dispose();
      }
      setStats(rows.join('\n'));
    });
  }, [only]);

  const opt = (slot: Parameters<typeof optionsFor>[0], g: Gender) => optionsFor(slot, g) as AvatarOption[];
  const fullW = size || 130;
  const portW = size || 120;

  return (
    <div style={page}>
      <h1 style={{ font: '800 22px system-ui', margin: '0 0 12px' }}>Benin Life 3D avatars (dev)</h1>

      <Section id="stage" title="Live turntable (drag to spin)" only={only}>
        <div style={{ display: 'grid', gap: 8 }}>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {G.map((g) => <button key={g} onClick={() => setStageG(g)}>{g}</button>)}
            {presetsFor(stageG).map((p) => <button key={p.id} onClick={() => setStagePreset(p.id)}>{p.label}</button>)}
          </div>
          <AvatarStage config={stageCfg} autoRotate style={{ width: 360, height: 520, background: 'linear-gradient(#d6e8f8,#eef5fb)', borderRadius: 20 }} />
        </div>
      </Section>

      <Section id="presets" title="Outfit presets" only={only}>
        {genders.flatMap((g) => presetsFor(g).map((p, i) => {
          const cfg = applyPreset({ ...defaultAvatar(g), skin: SKIN_TONES[(i * 3) % 8].id, body: BODIES[i % 3] }, p.id);
          return (
            <Cell key={g + p.id} label={`${p.emoji} ${p.label}`}>
              <AvatarPortrait config={cfg} view="full" size={fullW} yaw={yaw} />
            </Cell>
          );
        }))}
      </Section>

      <Section id="views" title="Front / 3-quarter / side / back" only={only}>
        {genders.flatMap((g) => (g === 'male' ? ['yahoo', 'agbada', 'corporate'] : ['owambe', 'bini', 'market']).flatMap((pid) =>
          [0, 0.7, Math.PI / 2, Math.PI].map((y) => (
            <Cell key={g + pid + y} label={`${pid} ${y.toFixed(1)}`}>
              <AvatarPortrait config={applyPreset(defaultAvatar(g), pid)} view="full" size={size || 110} yaw={y} />
            </Cell>
          )),
        ))}
      </Section>

      <Section id="pviews" title="Every preset: front / side / back" only={only}>
        {genders.flatMap((g) => presetsFor(g).flatMap((p) =>
          [0, Math.PI / 2, Math.PI].map((y) => (
            <Cell key={g + p.id + y} label={`${p.label} ${['front', 'side', 'back'][Math.round(y / (Math.PI / 2))]}`}>
              <AvatarPortrait config={applyPreset(defaultAvatar(g), p.id)} view="full" size={size || 110} yaw={y} />
            </Cell>
          )),
        ))}
      </Section>

      <Section id="bodies" title="Body types x skin tones" only={only}>
        {genders.flatMap((g) => BODIES.flatMap((b) => SKIN_TONES.filter((_, i) => i % 2 === (b === 'average' ? 1 : 0)).map((t) => (
          <Cell key={g + b + t.id} label={`${b} · ${t.label}`}>
            <AvatarPortrait config={{ ...defaultAvatar(g), body: b, skin: t.id }} view="full" size={size || 100} yaw={yaw} />
          </Cell>
        ))))}
      </Section>

      <Section id="faces" title="Face shapes" only={only}>
        {genders.flatMap((g) => opt('face', g).map((f) => (
          <Cell key={g + f.id} label={`${f.label}`}>
            <AvatarPortrait config={{ ...defaultAvatar(g), face: f.id, hair: g === 'male' ? 'low_cut' : 'bun', skin: 'tone3', facialHair: 'none' }} size={portW} yaw={yaw} />
          </Cell>
        )))}
      </Section>

      <Section id="features" title="Eyes, brows, noses, lips, expressions, facial hair" only={only}>
        {(['eyes', 'brows', 'nose', 'lips', 'mouth'] as const).flatMap((slot) => opt(slot, 'female').map((o) => (
          <Cell key={slot + o.id} label={`${slot}: ${o.label}`}>
            <AvatarPortrait config={{ ...defaultAvatar('female'), [slot]: o.id, hair: 'bun' }} size={portW} yaw={yaw} />
          </Cell>
        )))}
        {opt('facialHair', 'male').map((o) => (
          <Cell key={'fh' + o.id} label={o.label}>
            <AvatarPortrait config={{ ...defaultAvatar('male'), facialHair: o.id, skin: 'tone3' }} size={portW} yaw={yaw} />
          </Cell>
        ))}
      </Section>

      <Section id="hair" title="Hairstyles" only={only}>
        {genders.flatMap((g) => opt('hair', g).map((h, i) => (
          <Cell key={g + h.id} label={`${h.label}`}>
            <AvatarPortrait config={{ ...defaultAvatar(g), hair: h.id, hairColor: i % 4 === 3 ? '#b47b3c' : '#15100d' }} size={portW} yaw={yaw} />
          </Cell>
        )))}
      </Section>

      <Section id="hats" title="Headwear" only={only}>
        {genders.flatMap((g) => opt('hat', g).filter((h) => h.id !== 'none').map((h) => (
          <Cell key={g + h.id} label={h.label}>
            <AvatarPortrait config={{ ...defaultAvatar(g), hat: h.id, accent: h.id === 'gele' ? '#e0a526' : '#7a1f33' }} size={portW} yaw={yaw} />
          </Cell>
        )))}
      </Section>

      <Section id="acc" title="Accessories" only={only}>
        {AVATAR_OPTIONS.accessories.map((a, i) => (
          <Cell key={a.id} label={a.label}>
            <AvatarPortrait config={{ ...defaultAvatar(i % 2 ? 'female' : 'male'), accessories: [a.id], accent: '#2346a8' }} view="full" size={size || 110} yaw={yaw || (a.id === 'backpack' ? 2.4 : 0)} />
          </Cell>
        ))}
      </Section>

      <Section id="fabrics" title="Fabrics" only={only}>
        {AVATAR_OPTIONS.fabric.flatMap((f) => ['#d2342a', '#2346a8', '#e0a526'].map((c) => (
          <Cell key={f.id + c} label={`${f.label}`}>
            <AvatarPortrait config={{ ...defaultAvatar('male'), top: { s: 'kaftan', f: f.id as never, c }, bottom: { s: 'trousers', f: 'plain', c } }} view="full" size={size || 100} yaw={yaw} />
          </Cell>
        )))}
      </Section>

      <Section id="portraits" title="HUD portraits (random)" only={only}>
        {Array.from({ length: 16 }, (_, i) => (
          <span key={i} style={{ width: 56, height: 56, borderRadius: '50%', overflow: 'hidden', background: 'linear-gradient(180deg,#cfe5f8,#eaf3fb)', boxShadow: '0 0 0 2px #fff, 0 0 0 3.5px #2fbf77', display: 'grid' }}>
            <AvatarPortrait config={randomAvatar(G[i % 2])} size={56} />
          </span>
        ))}
      </Section>

      <Section id="landing" title="Landing images (save as public/art/sim-*.webp)" only={only}>
        {(['lapo', 'nepo'] as const).map((k) => (
          <Cell key={k} label={k}>
            <AvatarPortrait config={LANDING_SIMS[k]} view="full" size={240} yaw={k === 'lapo' ? 0.35 : -0.35} />
          </Cell>
        ))}
      </Section>

      <Section id="stats" title="Triangles per look" only={only}>
        <pre style={{ background: '#fff', padding: 12, borderRadius: 12, fontSize: 12 }}>{stats || 'Counting…'}</pre>
      </Section>
    </div>
  );
}
