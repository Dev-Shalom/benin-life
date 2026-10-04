// Dev-only preview of the avatar system (not routed). Mount it manually, e.g. temporarily
// render <AvatarGallery /> from main.tsx, to eyeball every option combination.
import type { CSSProperties, ReactNode } from 'react';
import type { AvatarConfig, Gender } from '../../lib/types';
import { Avatar } from './Avatar';
import { AVATAR_OPTIONS, defaultAvatar, optionsFor, randomAvatar } from './catalog';

const GENDERS: Gender[] = ['male', 'female'];
const grid: CSSProperties = { display: 'flex', flexWrap: 'wrap', gap: 6 };
const cell: CSSProperties = {
  background: 'linear-gradient(#f6efe4, #ded3c4)', borderRadius: 8, padding: 4,
  display: 'flex', flexDirection: 'column', alignItems: 'center', font: '11px sans-serif', color: '#553',
};

function Cell({ label, children }: { label: string; children: ReactNode }) {
  return <div style={cell}>{children}<span>{label}</span></div>;
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ marginBottom: 24 }}>
      <h2 style={{ font: '600 16px sans-serif', margin: '8px 0' }}>{title}</h2>
      <div style={grid}>{children}</div>
    </section>
  );
}

const cfg = (g: Gender, o: Partial<AvatarConfig> = {}): AvatarConfig => ({ ...defaultAvatar(g), ...o, gender: g });
const colors = AVATAR_OPTIONS.outfitColor.map((o) => o.id);
const bodies: AvatarConfig['body'][] = ['slim', 'average', 'thick'];

export function AvatarGallery() {
  return (
    <div style={{ padding: 16, background: '#e9e3da', minHeight: '100vh' }}>
      {GENDERS.map((g) => (
        <Section key={'o' + g} title={`Outfits (${g})`}>
          {optionsFor('outfit', g).map((o, i) => (
            <Cell key={o.id} label={`${o.label} · ${bodies[i % 3]}`}>
              <Avatar config={cfg(g, { outfit: o.id, outfitColor: colors[i % colors.length], body: bodies[i % 3] })} size={150} />
            </Cell>
          ))}
        </Section>
      ))}
      <Section title="Hair">
        {GENDERS.flatMap((g) => optionsFor('hair', g).map((o, i) => (
          <Cell key={g + o.id} label={o.label}>
            <Avatar config={cfg(g, { hair: o.id, hairColor: AVATAR_OPTIONS.hairColor[i % AVATAR_OPTIONS.hairColor.length].id })} view="portrait" size={120} />
          </Cell>
        )))}
      </Section>
      <Section title="Skin tones">
        {AVATAR_OPTIONS.skin.map((o, i) => (
          <Cell key={o.id} label={o.label}>
            <Avatar config={cfg(i % 2 ? 'female' : 'male', { skin: o.id })} view="portrait" size={120} />
          </Cell>
        ))}
      </Section>
      <Section title="Accessories">
        {GENDERS.flatMap((g) => optionsFor('accessories', g).map((o) => (
          <Cell key={g + o.id} label={o.label}>
            <Avatar config={cfg(g, { accessories: [o.id], outfit: 'student' })} size={110} />
          </Cell>
        )))}
      </Section>
      <Section title="Tiny portraits (64px / 40px) — random">
        {Array.from({ length: 16 }, (_, i) => (
          <Avatar key={i} config={randomAvatar(GENDERS[i % 2])} view="portrait" size={i < 8 ? 64 : 40} />
        ))}
      </Section>
    </div>
  );
}

export default AvatarGallery;
