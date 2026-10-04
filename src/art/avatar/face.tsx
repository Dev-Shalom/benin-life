// Facial features: eyes, brows, nose, mouth, blush, facial hair.
import type { ReactNode } from 'react';
import type { Ctx } from './ctx';
import { CX, r1 } from './geometry';
import { light, luma, mix } from './color';
import { headPath } from './body';

const EY = 60.5;
const EX = 88.2; // left eye centre (viewer's left)
const MIRROR = 'matrix(-1 0 0 1 200 0)';

interface EyeShape { hw: number; top: number; bot: number; tilt: number; ir: number; lid: number }
const EYES: Record<string, EyeShape> = {
  round: { hw: 7.0, top: 6.0, bot: 4.0, tilt: 0, ir: 4.6, lid: 0 },
  almond: { hw: 7.6, top: 5.0, bot: 3.2, tilt: -1.4, ir: 4.4, lid: 0 },
  sleepy: { hw: 7.2, top: 3.4, bot: 3.3, tilt: 0.5, ir: 4.4, lid: 1 },
  sharp: { hw: 7.5, top: 4.1, bot: 2.5, tilt: -2.4, ir: 4.0, lid: 0 },
};

function eyeGeom(e: EyeShape) {
  const ox = EX - e.hw;
  const oy = EY + e.tilt;
  const ix = EX + e.hw;
  const iy = EY + 0.7;
  const upper = `M${r1(ox)} ${r1(oy)} C${r1(EX - e.hw * 0.62)} ${r1(EY - e.top * 1.3 + e.tilt * 0.4)} ${r1(EX + e.hw * 0.45)} ${r1(EY - e.top * 1.32)} ${r1(ix)} ${r1(iy)}`;
  const lower = ` C${r1(EX + e.hw * 0.4)} ${r1(EY + e.bot * 1.25)} ${r1(EX - e.hw * 0.55)} ${r1(EY + e.bot * 1.2 + e.tilt * 0.4)} ${r1(ox)} ${r1(oy)}`;
  return { ox, oy, ix, iy, upper, shape: upper + lower + 'Z' };
}

export function eyes(c: Ctx): ReactNode {
  const e = EYES[c.cfg.eyes] ?? EYES.round;
  const g = eyeGeom(e);
  const s = c.skin;
  const F = c.b.female;
  const lash = '#1c1013';
  c.def('iris', (id) => (
    <radialGradient id={id} cx="0.5" cy="0.6" r="0.55">
      <stop offset="0" stopColor="#8a5530" />
      <stop offset="0.45" stopColor="#5a3220" />
      <stop offset="0.85" stopColor="#2c1712" />
      <stop offset="1" stopColor="#1a0d0d" />
    </radialGradient>
  ));
  const clip = c.def('eyeclip', (id) => (
    <clipPath id={id}><path d={g.shape} /></clipPath>
  ));
  const ix = EX + 0.4;
  const iy = EY + (e.lid ? 1.2 : 0.5);
  const one = (
    <g>
      {/* socket shadow */}
      <path d={`M${r1(g.ox - 1.5)} ${r1(g.oy)} Q${EX} ${r1(EY - e.top * 2.4)} ${r1(g.ix + 1.5)} ${r1(g.iy)}Z`} fill={s.shadow} opacity="0.22" />
      <path d={g.shape} fill="#f6ede6" />
      <g clipPath={clip}>
        <path d={g.shape} fill="#d9c8d6" opacity="0.5" transform={`translate(0 ${r1(e.top * 0.9)})`} />
        <circle cx={ix} cy={iy} r={e.ir} fill={c.url('iris')} />
        <circle cx={ix} cy={iy} r={e.ir * 0.47} fill="#120909" />
        <path d={g.upper + ` L${r1(g.ix)} ${r1(EY - 9)} L${r1(g.ox)} ${r1(EY - 9)}Z`} fill={s.deep} opacity="0.35" transform="translate(0 1.4)" />
      </g>
      {/* upper lash line */}
      <path d={g.upper} fill="none" stroke={lash} strokeWidth={F ? 2.1 : 1.7} strokeLinecap="round" />
      {F && <path d={`M${r1(g.ox + 1.5)} ${r1(g.oy - 1.2)} q-3 -0.5 -4.6 -3.4 q1.4 2.6 4.6 1.6Z`} fill={lash} />}
      {F && <path d={`M${r1(g.ox + 3.6)} ${r1(g.oy - 2.6)} l-2.6 -3`} stroke={lash} strokeWidth="1" strokeLinecap="round" />}
      {/* crease */}
      <path d={`M${r1(EX - e.hw * 0.75)} ${r1(EY - e.top - 1.6 + e.tilt * 0.4)} Q${EX} ${r1(EY - e.top * 1.3 - 3.6)} ${r1(EX + e.hw * 0.85)} ${r1(EY - e.top - 0.6)}`} fill="none" stroke={s.deep} strokeWidth={e.lid ? 1.3 : 0.9} opacity={e.lid ? 0.7 : 0.45} strokeLinecap="round" />
      {e.lid > 0 && <path d={`M${r1(g.ox + 0.5)} ${r1(g.oy - 1.2)} Q${EX} ${r1(EY - e.top - 3.2)} ${r1(g.ix - 0.5)} ${r1(g.iy - 1.2)}`} fill="none" stroke={mix(s.base, s.highlight, 0.5)} strokeWidth="1" opacity="0.5" />}
      {/* lower lid */}
      <path d={`M${r1(g.ox + 1.5)} ${r1(g.oy + 1.2)} Q${EX} ${r1(EY + e.bot * 1.35 + 1)} ${r1(g.ix - 0.5)} ${r1(g.iy + 0.6)}`} fill="none" stroke={s.deep} strokeWidth="0.7" opacity="0.4" />
    </g>
  );
  return (
    <g>
      {one}
      <g transform={MIRROR}>{one}</g>
      {/* catchlights: same side for both eyes (light from top-left) */}
      {[ix, 200 - EX + 0.4].map((x, i) => (
        <g key={i} fill="#fffaf2">
          <circle cx={x - 1.3} cy={iy - 1.5} r={1.35} />
          <circle cx={x + 1.5} cy={iy + 1.4} r={0.6} opacity="0.75" />
        </g>
      ))}
    </g>
  );
}

interface BrowShape { th: number; tt: number; peak: number; at: number; y: number }
const BROWS: Record<string, BrowShape> = {
  soft: { th: 2.1, tt: 0.9, peak: 2.6, at: 0.35, y: 0 },
  thick: { th: 3.5, tt: 2.1, peak: 2.0, at: 0.4, y: 0.4 },
  arched: { th: 2.4, tt: 0.8, peak: 4.6, at: 0.4, y: 0.6 },
  straight: { th: 2.8, tt: 1.6, peak: 0.6, at: 0.5, y: -0.4 },
};

export function brows(c: Ctx): ReactNode {
  const br = BROWS[c.cfg.brows] ?? BROWS.soft;
  const e = EYES[c.cfg.eyes] ?? EYES.round;
  const F = c.b.female;
  const th = br.th * (F ? 0.85 : 1);
  const by = EY - e.top - 6.2 + br.y;
  const ix = EX + 7.5;
  const ox = EX - 8.2;
  const px = ox + (ix - ox) * br.at;
  const col = mix(c.hair, '#1a100c', 0.6);
  const d = `M${r1(ix)} ${r1(by + 1.6)} Q${r1(px + 2)} ${r1(by - br.peak - th * 0.4)} ${r1(ox)} ${r1(by + 1.6 + e.tilt * 0.5)} Q${r1(px)} ${r1(by - br.peak + br.tt + 0.4)} ${r1(ix + 0.3)} ${r1(by + 1.6 + th)}Z`;
  // On deep skin tones a dark brow disappears: lift the brow bone underneath and add a
  // faint sheen on the hairs so the brow still reads at small sizes.
  const dark = Math.max(0, Math.min(1, (0.22 - luma(c.skin.base)) / 0.14));
  const one = (
    <g>
      {dark > 0 && <path d={d} fill={c.skin.highlight} opacity={0.55 * dark} transform="translate(0 1.5)" />}
      <path d={d} fill={col} />
      <path d={d} fill="none" stroke={col} strokeWidth="0.5" opacity="0.6" />
      {dark > 0 && <path d={d} fill="none" stroke={light(col, 0.5)} strokeWidth="0.45" opacity={0.6 * dark} transform="translate(0 -0.3)" />}
    </g>
  );
  return (
    <g>
      {one}
      <g transform={MIRROR}>{one}</g>
    </g>
  );
}

export function nose(c: Ctx): ReactNode {
  const s = c.skin;
  const k = c.b.female ? 0.88 : 1;
  return (
    <g transform={`translate(${CX} 68) scale(${k}) translate(${-CX} -68)`}>
      <path d={`M98.6 58 Q98 65 98.8 69.5`} stroke={s.highlight} strokeWidth="1.6" opacity="0.4" fill="none" strokeLinecap="round" />
      <path d={`M102.6 59 Q104.5 66 104.8 70`} stroke={s.shadow} strokeWidth="2" opacity="0.32" fill="none" strokeLinecap="round" />
      <ellipse cx="99.4" cy="71" rx="4.4" ry="3" fill={s.highlight} opacity="0.22" />
      <path d="M94.6 69.6 Q91.4 72.6 95.4 74.6" stroke={s.shadow} strokeWidth="1.3" fill="none" opacity="0.75" strokeLinecap="round" />
      <path d="M105.4 69.6 Q108.6 72.6 104.6 74.6" stroke={s.deep} strokeWidth="1.3" fill="none" opacity="0.75" strokeLinecap="round" />
      <ellipse cx="97.1" cy="74" rx="1.8" ry="0.95" fill={s.deep} opacity="0.85" />
      <ellipse cx="102.9" cy="74" rx="1.8" ry="0.95" fill={s.deep} opacity="0.85" />
      <ellipse cx="100" cy="76.6" rx="3.5" ry="1.1" fill={s.shadow} opacity="0.3" />
    </g>
  );
}

export function blush(c: Ctx): ReactNode {
  const s = c.skin;
  const o = c.b.female ? 0.22 : 0.13;
  return (
    <g fill={s.blush} opacity={o}>
      <ellipse cx="84" cy="71.5" rx="6" ry="3.4" />
      <ellipse cx="116" cy="71.5" rx="6" ry="3.4" />
    </g>
  );
}

export function mouth(c: Ctx): ReactNode {
  const s = c.skin;
  const F = c.b.female;
  const lipU = F ? mix(s.lip, '#a3253b', 0.22) : s.lip;
  const lipL = mix(lipU, s.highlight, 0.3);
  const inside = '#3d1219';
  const teeth = '#fbf5ec';
  const line = mix(s.deep, '#2a0d14', 0.4);
  const hl = <ellipse cx="98.4" cy="84.2" rx="2.6" ry="0.9" fill="#fff4ea" opacity="0.35" />;
  switch (c.cfg.mouth) {
    case 'grin':
      return (
        <g>
          <path d="M91.6 80.2 Q100 82.6 108.4 80.2 Q105.6 89.6 100 89.8 Q94.4 89.6 91.6 80.2Z" fill={inside} />
          <path d="M92.6 80.8 Q100 82.8 107.4 80.8 L106.4 83.4 Q100 84.8 93.6 83.4Z" fill={teeth} />
          <path d="M95.5 87.5 Q100 85.6 104.5 87.5 Q100 89.4 95.5 87.5Z" fill="#b7495a" opacity="0.8" />
          <path d="M91.6 80.2 Q100 82.6 108.4 80.2 Q105.6 89.6 100 89.8 Q94.4 89.6 91.6 80.2Z" fill="none" stroke={lipL} strokeWidth="1.3" />
          <path d="M91.6 80.2 Q96 78.3 100 79.4 Q104 78.3 108.4 80.2" fill="none" stroke={lipU} strokeWidth="1.4" strokeLinecap="round" />
          <path d="M90.6 79.4 q-1 -1.4 -0.4 -2.8 M109.4 79.4 q1 -1.4 0.4 -2.8" stroke={s.shadow} strokeWidth="0.8" fill="none" opacity="0.6" />
        </g>
      );
    case 'laughing':
      return (
        <g>
          <path d="M90.8 78.6 Q100 81 109.2 78.6 Q108 92.6 100 93.4 Q92 92.6 90.8 78.6Z" fill={inside} />
          <path d="M91.8 79.3 Q100 81.4 108.2 79.3 L107.2 82.2 Q100 83.6 92.8 82.2Z" fill={teeth} />
          <path d="M94 90.2 Q100 85.6 106 90.2 Q100 93.2 94 90.2Z" fill="#c4505d" />
          <path d="M90.8 78.6 Q100 81 109.2 78.6 Q108 92.6 100 93.4 Q92 92.6 90.8 78.6Z" fill="none" stroke={lipL} strokeWidth="1.4" />
          <path d="M90.8 78.6 Q95.4 76.6 100 77.8 Q104.6 76.6 109.2 78.6" fill="none" stroke={lipU} strokeWidth="1.5" strokeLinecap="round" />
          <path d="M89.6 78 q-1.4 -1.8 -0.6 -3.6 M110.4 78 q1.4 -1.8 0.6 -3.6" stroke={s.shadow} strokeWidth="0.9" fill="none" opacity="0.6" />
          <g fill={s.highlight} opacity="0.25"><ellipse cx="84" cy="73" rx="5" ry="2.6" /><ellipse cx="116" cy="73" rx="5" ry="2.6" /></g>
        </g>
      );
    case 'neutral':
      return (
        <g>
          <path d="M93 81 Q96.4 78.6 100 79.6 Q103.6 78.6 107 81 Q100 81.8 93 81Z" fill={lipU} />
          <path d="M93.6 81.3 Q100 82.2 106.4 81.3 Q104.4 86.2 100 86.4 Q95.6 86.2 93.6 81.3Z" fill={lipL} />
          <path d="M93 81 Q100 82 107 81" fill="none" stroke={line} strokeWidth="0.9" strokeLinecap="round" />
          {hl}
        </g>
      );
    case 'smirk':
      return (
        <g>
          <path d="M93.4 81.6 Q96.6 79.4 100.2 80.2 Q104 78.8 107.6 78.6 Q101 82.6 93.4 81.6Z" fill={lipU} />
          <path d="M94 81.8 Q101 82.8 107 79.2 Q105.2 85.6 100 86.2 Q95.6 86 94 81.8Z" fill={lipL} />
          <path d="M93.4 81.6 Q101 82.8 107.6 78.6" fill="none" stroke={line} strokeWidth="0.9" strokeLinecap="round" />
          <path d="M108.2 78 q1.2 0.6 1 2.2" stroke={s.shadow} strokeWidth="0.8" fill="none" opacity="0.7" />
          {hl}
        </g>
      );
    case 'smile':
    default:
      return (
        <g>
          <path d="M92.4 79.8 Q96.2 78 100 79 Q103.8 78 107.6 79.8 Q100 83.4 92.4 79.8Z" fill={lipU} />
          <path d="M93.4 80.6 Q100 84 106.6 80.6 Q104.6 86.6 100 86.8 Q95.4 86.6 93.4 80.6Z" fill={lipL} />
          <path d="M92.4 79.8 Q100 84 107.6 79.8" fill="none" stroke={line} strokeWidth="1" strokeLinecap="round" />
          <path d="M91.6 79.2 q-0.8 -1 -0.3 -2 M108.4 79.2 q0.8 -1 0.3 -2" stroke={s.shadow} strokeWidth="0.8" fill="none" opacity="0.6" />
          {hl}
        </g>
      );
  }
}

export function facialHair(c: Ctx): ReactNode {
  if (c.b.female) return null;
  const col = mix(c.hair, '#140c0a', 0.35);
  const hi = mix(c.hair, '#ffffff', 0.18);
  const beard = 'M72.4 57 L75.6 57 Q76.6 69 83.4 75 Q89 77.4 93 76 Q100 73.8 107 76 Q111 77.4 116.6 75 Q123.4 69 124.4 57 L127.6 57 C128.6 72 122.6 86.6 111.6 93.4 Q100 99.4 88.4 93.4 C77.4 86.6 71.4 72 72.4 57Z';
  const stache = 'M91.2 80 Q92.4 75.2 100 75.8 Q107.6 75.2 108.8 80 Q104.4 77.8 100 78.6 Q95.6 77.8 91.2 80Z';
  const chin = 'M93.6 86 Q100 84.2 106.4 86 Q107.6 93 100 96.2 Q92.4 93 93.6 86Z';
  const tex = (
    <g stroke={hi} strokeWidth="0.6" opacity="0.4" strokeLinecap="round">
      {[[80, 80], [84, 85], [90, 90], [96, 93], [104, 93], [110, 90], [116, 85], [120, 80], [77, 70], [123, 70]].map(([x, y], i) => (
        <path key={i} d={`M${x} ${y} l${i % 2 ? 0.8 : -0.8} 2`} />
      ))}
    </g>
  );
  switch (c.cfg.facialHair) {
    case 'beard':
      return (
        <g>
          <path d={beard} fill={col} />
          <path d={beard} fill={c.url('hairG')} opacity="0.35" />
          <path d={stache} fill={col} />
          {tex}
        </g>
      );
    case 'goatee':
      return (
        <g fill={col}>
          <path d={stache} />
          <path d={chin} />
          <path d="M92 80.6 Q92.4 84 94 86.6 L95 86 Q93.6 83.4 93.4 80.4Z M108 80.6 Q107.6 84 106 86.6 L105 86 Q106.4 83.4 106.6 80.4Z" />
        </g>
      );
    case 'moustache':
      return <path d="M90.4 80.4 Q91.6 74.6 100 75.4 Q108.4 74.6 109.6 80.4 Q104.6 77.6 100 78.6 Q95.4 77.6 90.4 80.4Z" fill={col} />;
    case 'shadow':
      return (
        <g>
          {/* stubble stays inside the face outline (the full-beard shape overhangs the jaw) */}
          <g clipPath={c.def('stubbleClip', (id) => <clipPath id={id}><path d={headPath(c)} /></clipPath>)}>
            <path d={beard} fill={mix(c.skin.deep, c.hair, 0.4)} opacity="0.32" />
          </g>
          <path d={stache} fill={mix(c.skin.deep, c.hair, 0.4)} opacity="0.3" />
        </g>
      );
    default:
      return null;
  }
}
