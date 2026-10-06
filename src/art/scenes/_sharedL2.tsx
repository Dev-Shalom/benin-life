// L2 shared bits for the landmark scene headers (mall, cinema, hotel, zoo, stadium, monument, car_dealer).
// Underscore prefix: never loaded as a scene by the dispatcher. Built on the P1-SCENES-A helpers.
import type { ReactNode } from 'react';
import { CommonDefs, Finish, Glow, Haze, Sky, Txt, PAL } from './_sharedA';

/** Paved forecourt + kerb + road strip, with soft shadows. */
export function Ground({ p, y = 318, tone = '#c8b49a', road = true }: { p: string; y?: number; tone?: string; road?: boolean }) {
  return (
    <g>
      <rect x="0" y={y} width="800" height={450 - y} fill={tone} />
      <rect x="0" y={y} width="800" height="6" fill="#2d1b4e" opacity="0.12" />
      {Array.from({ length: 20 }, (_, i) => (
        <rect key={i} x={i * 42} y={y + 10} width="1" height={road ? 380 - y - 10 : 120} fill="#2d1b4e" opacity="0.07" />
      ))}
      {road && (
        <g>
          <rect x="0" y="384" width="800" height="8" fill="#e9e2d6" />
          <rect x="0" y="392" width="800" height="58" fill="#4a4652" />
          {Array.from({ length: 10 }, (_, i) => (
            <rect key={i} x={i * 90 + 20} y="419" width="44" height="4" fill="#f2efe6" opacity="0.85" />
          ))}
          <rect x="0" y="392" width="800" height="6" fill="#2d1b4e" opacity="0.25" />
        </g>
      )}
      <Haze p={p} y={y - 60} h={90} o={0.5} />
    </g>
  );
}

/** A sign board: night adds a soft glow behind it. */
export function SignBoard({ p, x, y, w, h, bg, ink, text, size, night, glow = 'warm', sub }: {
  p: string; x: number; y: number; w: number; h: number; bg: string; ink: string; text: string; size: number; night: boolean;
  glow?: 'warm' | 'pink' | 'teal' | 'red' | 'blue' | 'green'; sub?: string;
}) {
  return (
    <g>
      {night && <Glow p={p} kind={glow} cx={x + w / 2} cy={y + h / 2} rx={w * 0.7} ry={h * 1.8} o={0.7} />}
      <rect x={x} y={y} width={w} height={h} rx="4" fill={bg} />
      <rect x={x} y={y} width={w} height={h * 0.18} rx="4" fill="#fff" opacity="0.12" />
      <Txt x={x + w / 2} y={y + h / 2 + size * 0.36 - (sub ? size * 0.25 : 0)} size={size} fill={ink} spacing={1}>{text}</Txt>
      {sub && <Txt x={x + w / 2} y={y + h - 6} size={size * 0.42} fill={ink} weight={700} family="Arial, sans-serif" o={0.85}>{sub}</Txt>}
    </g>
  );
}

/** Scene frame: defs + sky, a night-graded body, emissive lights on top, grain + vignette. */
export function Frame({ p, night, label, defs, body, lights, sun, moon }: {
  p: string; night: boolean; label: string; defs?: ReactNode; body: ReactNode; lights?: ReactNode;
  sun?: [number, number]; moon?: [number, number];
}) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label={label}>
      <defs>
        <CommonDefs p={p} night={night} />
        {defs}
      </defs>
      <Sky p={p} night={night} sun={sun} moon={moon} />
      <g filter={night ? `url(#${p}-night)` : undefined}>{body}</g>
      {lights}
      <Finish p={p} night={night} />
    </svg>
  );
}

/** Lit window: warm at night, sky-blue by day. */
export function Win({ x, y, w, h, night, lit = true }: { x: number; y: number; w: number; h: number; night: boolean; lit?: boolean }) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} fill={night ? (lit ? '#ffd88a' : '#2a2f52') : '#7fa8d6'} />
      {!night && <path d={`M${x} ${y + h} L${x + w * 0.5} ${y} L${x + w * 0.75} ${y} L${x + w * 0.25} ${y + h}Z`} fill="#fff" opacity="0.18" />}
    </g>
  );
}

export { PAL };
