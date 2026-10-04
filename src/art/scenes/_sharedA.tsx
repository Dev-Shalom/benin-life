// P1-SCENES-A shared scene helpers. Underscore prefix: never loaded as a scene by the dispatcher.
// Every helper takes the scene prefix `p` so DOM ids stay unique when several scenes are mounted.
import type { ReactNode } from 'react';

export const PAL = {
  laterite: '#b5552b',
  lateriteDark: '#7e3418',
  lateriteLight: '#d98457',
  dust: '#d9a77a',
  coral: '#d2342a',
  bronze: '#b0793a',
  gold: '#d9a441',
  ects: '#1f7a3f',
  shadow: '#2d1b4e',
  shadowBlue: '#1a1a4e',
  ink: '#241733',
};

/** Deterministic PRNG so markup is stable between renders (no hydration flicker). */
export function rng(seed: number) {
  let s = seed >>> 0 || 1;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

type GlowKind = 'warm' | 'amber' | 'cool' | 'pink' | 'teal' | 'red' | 'blue' | 'green' | 'sun';
const GLOW: Record<GlowKind, string> = {
  warm: '#ffd27a',
  amber: '#ff9a3c',
  cool: '#cfe6ff',
  pink: '#ff4fc0',
  teal: '#3ff0e0',
  red: '#ff3b3b',
  blue: '#4f86ff',
  green: '#59ff8a',
  sun: '#fff1c4',
};

/** Shared <defs>: sky, glows, haze, vignette, grain, night grade, blur, shadow. */
export function CommonDefs({ p, night }: { p: string; night: boolean }) {
  const sky = night
    ? ['#04071c', '#0b1238', '#1a1d52', '#2e2a63', '#4c3466', '#7a4566']
    : ['#3a78c2', '#5f9ad6', '#93c2e6', '#c9dfe9', '#f0d9b0', '#f3bd84'];
  return (
    <>
      <linearGradient id={`${p}-sky`} x1="0" y1="0" x2="0" y2="1" colorInterpolation="linearRGB">
        {[0, 0.28, 0.5, 0.68, 0.85, 1].map((o, i) => (
          <stop key={o} offset={o} stopColor={sky[i]} />
        ))}
      </linearGradient>
      {(Object.keys(GLOW) as GlowKind[]).map((k) => (
        <radialGradient key={k} id={`${p}-g-${k}`} cx="50%" cy="50%" r="50%">
          <stop offset="0" stopColor={GLOW[k]} stopOpacity="0.95" />
          <stop offset="0.25" stopColor={GLOW[k]} stopOpacity="0.55" />
          <stop offset="0.6" stopColor={GLOW[k]} stopOpacity="0.16" />
          <stop offset="1" stopColor={GLOW[k]} stopOpacity="0" />
        </radialGradient>
      ))}
      <linearGradient id={`${p}-haze`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor={night ? '#3b3a7a' : '#f6e6cc'} stopOpacity="0" />
        <stop offset="0.55" stopColor={night ? '#3b3a7a' : '#f6e6cc'} stopOpacity={night ? 0.35 : 0.5} />
        <stop offset="1" stopColor={night ? '#3b3a7a' : '#f6e6cc'} stopOpacity="0" />
      </linearGradient>
      <radialGradient id={`${p}-vig`} cx="50%" cy="48%" r="72%">
        <stop offset="0.55" stopColor="#1c1035" stopOpacity="0" />
        <stop offset="1" stopColor="#1c1035" stopOpacity={night ? 0.62 : 0.4} />
      </radialGradient>
      <filter id={`${p}-grain`} x="0" y="0" width="100%" height="100%" colorInterpolationFilters="sRGB">
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} seed={7} stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      {/* Night grade: indigo, moonlit, keeps a hint of local colour. Emissive lights are drawn after it. */}
      <filter id={`${p}-night`} x="0" y="0" width="100%" height="100%" colorInterpolationFilters="sRGB">
        <feColorMatrix
          type="matrix"
          values="0.30 0.06 0.02 0 0.005  0.05 0.30 0.07 0 0.012  0.07 0.12 0.50 0 0.05  0 0 0 1 0"
        />
      </filter>
      <filter id={`${p}-soft`} x="-30%" y="-30%" width="160%" height="160%" colorInterpolationFilters="linearRGB">
        <feGaussianBlur stdDeviation="3" />
      </filter>
      <filter id={`${p}-blur`} x="-50%" y="-50%" width="200%" height="200%" colorInterpolationFilters="linearRGB">
        <feGaussianBlur stdDeviation="9" />
      </filter>
      <filter id={`${p}-drop`} x="-20%" y="-20%" width="140%" height="140%" colorInterpolationFilters="linearRGB">
        <feGaussianBlur in="SourceAlpha" stdDeviation="4" result="b" />
        <feOffset in="b" dx="5" dy="4" result="o" />
        <feFlood floodColor="#24154a" floodOpacity="0.35" />
        <feComposite in2="o" operator="in" result="s" />
        <feMerge>
          <feMergeNode in="s" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </>
  );
}

export function Glow({
  p, kind = 'warm', cx, cy, rx, ry, o = 1, blend = true,
}: { p: string; kind?: GlowKind; cx: number; cy: number; rx: number; ry?: number; o?: number; blend?: boolean }) {
  return (
    <ellipse
      cx={cx} cy={cy} rx={rx} ry={ry ?? rx} fill={`url(#${p}-g-${kind})`} opacity={o}
      style={blend ? { mixBlendMode: 'screen' } : undefined}
    />
  );
}

function Cloud({ x, y, s, night }: { x: number; y: number; s: number; night: boolean }) {
  const top = night ? '#3a3d78' : '#fffaf2';
  const mid = night ? '#2c2d63' : '#f3ecef';
  const under = night ? '#211f4d' : '#c9c3dc';
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`} opacity={night ? 0.55 : 0.92}>
      <ellipse cx="0" cy="8" rx="70" ry="13" fill={under} />
      <ellipse cx="-30" cy="0" rx="34" ry="16" fill={mid} />
      <ellipse cx="8" cy="-8" rx="36" ry="22" fill={top} />
      <ellipse cx="42" cy="2" rx="28" ry="14" fill={mid} />
      <ellipse cx="0" cy="6" rx="60" ry="8" fill={under} opacity="0.55" />
      <ellipse cx="0" cy="-14" rx="18" ry="7" fill="#ffffff" opacity={night ? 0.15 : 0.6} />
    </g>
  );
}

/** Sky: gradient, sun (day) or moon + stars (night), clouds, a few kites. */
export function Sky({
  p, night, sun = [130, 82], moon = [655, 72], clouds = [[300, 70, 1], [610, 120, 0.7]], birds = true,
}: {
  p: string; night: boolean; sun?: [number, number]; moon?: [number, number];
  clouds?: [number, number, number][]; birds?: boolean;
}) {
  const r = rng(p.length * 97 + 13);
  const stars: ReactNode[] = [];
  if (night) {
    for (let i = 0; i < 70; i++) {
      const x = r() * 800;
      const y = r() * 220;
      const sz = r() < 0.12 ? 1.5 : 0.5 + r() * 0.8;
      stars.push(<circle key={i} cx={x.toFixed(1)} cy={y.toFixed(1)} r={sz.toFixed(2)} fill="#f4f0ff" opacity={(0.35 + r() * 0.6).toFixed(2)} />);
    }
  }
  return (
    <g>
      <rect width="800" height="450" fill={`url(#${p}-sky)`} />
      {night ? (
        <>
          {stars}
          <Glow p={p} kind="cool" cx={moon[0]} cy={moon[1]} rx={110} o={0.45} />
          <circle cx={moon[0]} cy={moon[1]} r="19" fill="#f6f1da" />
          <circle cx={moon[0] - 5} cy={moon[1] - 4} r="4" fill="#e2dbbd" />
          <circle cx={moon[0] + 6} cy={moon[1] + 5} r="3" fill="#e2dbbd" />
          <circle cx={moon[0] + 3} cy={moon[1] - 8} r="2" fill="#e8e1c4" />
        </>
      ) : (
        <>
          <Glow p={p} kind="sun" cx={sun[0]} cy={sun[1]} rx={170} o={0.85} blend={false} />
          <circle cx={sun[0]} cy={sun[1]} r="24" fill="#fff7dc" />
        </>
      )}
      {clouds.map(([x, y, s], i) => <Cloud key={i} x={x} y={y} s={s} night={night} />)}
      {birds && !night && (
        <g fill="none" stroke="#3a2f4a" strokeWidth="1.3" strokeLinecap="round" opacity="0.6">
          <path d="M470 60 q5 -4 9 0 q4 -4 9 0" />
          <path d="M500 78 q4 -3 7 0 q3 -3 7 0" />
          <path d="M448 84 q3 -2 6 0 q3 -2 6 0" />
        </g>
      )}
    </g>
  );
}

export function Haze({ p, y, h, o = 1 }: { p: string; y: number; h: number; o?: number }) {
  return <rect x="0" y={y} width="800" height={h} fill={`url(#${p}-haze)`} opacity={o} />;
}

/** Final overlays: grain + vignette. */
export function Finish({ p, night }: { p: string; night: boolean }) {
  return (
    <>
      <rect width="800" height="450" filter={`url(#${p}-grain)`} opacity={night ? 0.16 : 0.13} style={{ mixBlendMode: 'overlay' }} />
      <rect width="800" height="450" fill={`url(#${p}-vig)`} />
    </>
  );
}

/* ---------------- figures ---------------- */

export interface PersonProps {
  x: number; y: number; s?: number; flip?: boolean;
  skin?: string; top?: string; bottom?: string;
  wrapper?: boolean; head?: 'none' | 'gele' | 'cap' | 'tray' | 'hair' | 'beret';
  headColor?: string; tray?: string; arm?: 'down' | 'up' | 'out' | 'phone' | 'hold';
  hold?: string;
}

/** Small stylised figure, feet at (x,y), ~60px tall at s=1. Five-zone-ish shading. */
export function Person({
  x, y, s = 1, flip = false, skin = '#6e3b22', top = PAL.coral, bottom = '#2c2f5c',
  wrapper = false, head = 'hair', headColor = '#1b1424', tray = PAL.coral, arm = 'down', hold = '#e8e2d0',
}: PersonProps) {
  const shade = '#2a1a4f';
  const armEnd: Record<string, [number, number]> = {
    down: [-10, -29], up: [-12, -60], out: [-18, -38], phone: [-4, -50], hold: [-13, -32],
  };
  const [ax, ay] = armEnd[arm];
  return (
    <g transform={`translate(${x} ${y}) scale(${flip ? -s : s} ${s})`}>
      <ellipse cx="2" cy="0" rx="11" ry="2.4" fill={shade} opacity="0.4" />
      {wrapper ? (
        <path d="M-7.5 -30 L7.5 -30 L9 -2 L-9 -2 Z" fill={bottom} />
      ) : (
        <>
          <line x1="-3" y1="-28" x2="-3.6" y2="-1.5" stroke={bottom} strokeWidth="4.6" strokeLinecap="round" />
          <line x1="3" y1="-28" x2="3.8" y2="-1.5" stroke={bottom} strokeWidth="4.6" strokeLinecap="round" />
        </>
      )}
      {wrapper && <path d="M2 -30 L7.5 -30 L9 -2 L3 -2 Z" fill={shade} opacity="0.25" />}
      <ellipse cx="-4" cy="-1" rx="3.2" ry="1.6" fill="#2a2030" />
      <ellipse cx="4.2" cy="-1" rx="3.2" ry="1.6" fill="#2a2030" />
      {/* torso */}
      <path d="M-7.5 -47 Q-9 -38 -6.5 -27 L6.5 -27 Q9 -38 7.5 -47 Q0 -50 -7.5 -47 Z" fill={top} />
      <path d="M1.5 -49 Q8.5 -48 7.5 -47 Q9 -38 6.5 -27 L2 -27 Z" fill={shade} opacity="0.28" />
      <path d="M-6.8 -45 Q-7.6 -40 -6.6 -35" stroke="#fff" strokeOpacity="0.35" strokeWidth="1.2" fill="none" />
      {/* arms */}
      <line x1="7" y1="-45" x2="9.5" y2="-30" stroke={top} strokeWidth="3.6" strokeLinecap="round" />
      <circle cx="9.7" cy="-29" r="1.9" fill={skin} />
      <line x1="-7" y1="-45" x2={ax} y2={ay} stroke={top} strokeWidth="3.6" strokeLinecap="round" />
      <circle cx={ax} cy={ay} r="1.9" fill={skin} />
      {arm === 'phone' && <rect x={ax - 2} y={ay - 4} width="3" height="5" rx="0.6" fill="#9fe3ff" />}
      {arm === 'hold' && <rect x={ax - 6} y={ay - 3} width="8" height="6" rx="1" fill={hold} />}
      {/* head */}
      <rect x="-1.6" y="-51.5" width="3.2" height="5" fill={skin} />
      <circle cx="0" cy="-55" r="5.2" fill={skin} />
      <circle cx="1.8" cy="-54" r="4.2" fill={shade} opacity="0.22" />
      <circle cx="-2" cy="-57" r="1.3" fill="#fff" opacity="0.25" />
      {head === 'hair' && <path d="M-5.2 -56 Q-5 -61.5 0 -61.5 Q5 -61.5 5.2 -56 Q3 -59 0 -59 Q-3 -59 -5.2 -56Z" fill={headColor} />}
      {head === 'cap' && (
        <>
          <path d="M-5.4 -56 Q-5 -62.5 0.5 -62 Q5.4 -61.5 5.4 -56 Z" fill={headColor} />
          <path d="M-5.4 -56.5 L-10 -55.5 L-5 -55 Z" fill={headColor} />
        </>
      )}
      {head === 'beret' && <path d="M-5.6 -57 Q-4 -63.5 3 -62 Q7 -60.5 5.4 -57 Z" fill={headColor} />}
      {head === 'gele' && (
        <>
          <path d="M-6.5 -56 Q-8 -64 0 -65 Q8 -64.5 7 -56 Q0 -59 -6.5 -56Z" fill={headColor} />
          <path d="M3 -64 Q9 -66 8.5 -60" stroke={headColor} strokeWidth="2.4" fill="none" />
        </>
      )}
      {head === 'tray' && (
        <>
          <path d="M-6 -57 Q0 -60 6 -57 Q0 -62 -6 -57Z" fill={headColor} />
          <ellipse cx="0" cy="-61" rx="11" ry="2.4" fill="#8a6a3c" />
          <circle cx="-5" cy="-63.5" r="2.6" fill={tray} />
          <circle cx="0" cy="-64.5" r="2.8" fill={tray} />
          <circle cx="5" cy="-63.5" r="2.6" fill={tray} />
          <circle cx="-2.5" cy="-66.5" r="2.4" fill={tray} />
          <circle cx="2.5" cy="-66.8" r="2.4" fill={tray} />
          <circle cx="-1" cy="-67" r="0.9" fill="#fff" opacity="0.5" />
        </>
      )}
    </g>
  );
}

/* ---------------- vegetation ---------------- */

export function Palm({ x, y, s = 1, lean = 1, tone = '#2f7a35' }: { x: number; y: number; s?: number; lean?: number; tone?: string }) {
  const fronds = [-170, -145, -120, -95, -70, -40, -15, 10];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="6" cy="0" rx="16" ry="3" fill={PAL.shadow} opacity="0.3" />
      <path d={`M-4 0 Q${-6 + lean * 8} -60 ${lean * 14} -128 L${lean * 14 + 6} -127 Q${lean * 8 + 2} -60 4 0 Z`} fill="#7a5a3e" />
      <path d={`M1 0 Q${lean * 8 + 2} -60 ${lean * 14 + 6} -127 L${lean * 14 + 3} -127 Q${lean * 6} -60 -1 0Z`} fill="#3d2a40" opacity="0.35" />
      <path d={`M-3 -8 Q${lean * 6} -64 ${lean * 14 + 2} -126`} stroke="#a9845c" strokeWidth="1.4" strokeDasharray="1 5" fill="none" />
      <g transform={`translate(${lean * 14 + 3} -128)`}>
        {fronds.map((a, i) => {
          const rad = (a * Math.PI) / 180;
          const L = 52 + (i % 3) * 8;
          const tx = Math.cos(rad) * L;
          const ty = Math.sin(rad) * L * 0.55 + 18;
          const mx = Math.cos(rad) * L * 0.5;
          const my = Math.sin(rad) * L * 0.5 - 10;
          const nx = -Math.sin(rad) * 7;
          const ny = Math.cos(rad) * 7;
          const col = i % 2 ? tone : '#3f9443';
          return (
            <g key={a}>
              <path d={`M0 0 Q${(mx + nx).toFixed(1)} ${(my + ny).toFixed(1)} ${tx.toFixed(1)} ${ty.toFixed(1)} Q${(mx - nx).toFixed(1)} ${(my - ny).toFixed(1)} 0 0Z`} fill={col} />
              <path d={`M0 0 Q${mx.toFixed(1)} ${my.toFixed(1)} ${tx.toFixed(1)} ${ty.toFixed(1)}`} stroke="#1d4a2a" strokeWidth="9" strokeDasharray="1.2 2.4" fill="none" opacity="0.45" />
              <path d={`M0 0 Q${mx.toFixed(1)} ${my.toFixed(1)} ${tx.toFixed(1)} ${ty.toFixed(1)}`} stroke="#bfe08a" strokeWidth="0.8" fill="none" opacity="0.6" />
            </g>
          );
        })}
        <circle cx="0" cy="2" r="5" fill="#5a3d26" />
      </g>
    </g>
  );
}

/** Broadleaf tree (mango/almond/neem-ish) lit from upper-left. */
export function Tree({ x, y, s = 1, dark = '#1f5a34', mid = '#2f7d3d', light = '#6db04f' }: { x: number; y: number; s?: number; dark?: string; mid?: string; light?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="10" cy="0" rx="34" ry="5" fill={PAL.shadow} opacity="0.3" />
      <path d="M-4 0 L-3 -38 L-14 -54 L-11 -56 L0 -44 L9 -60 L12 -58 L4 -38 L5 0 Z" fill="#5b3f2c" />
      <path d="M1 0 L1 -40 L4 -38 L5 0Z" fill="#2d1b4e" opacity="0.3" />
      <ellipse cx="2" cy="-70" rx="42" ry="28" fill={dark} />
      <ellipse cx="-20" cy="-64" rx="24" ry="18" fill={mid} />
      <ellipse cx="22" cy="-62" rx="24" ry="17" fill={dark} />
      <ellipse cx="-6" cy="-84" rx="28" ry="20" fill={mid} />
      <ellipse cx="-14" cy="-90" rx="16" ry="11" fill={light} opacity="0.85" />
      <ellipse cx="-26" cy="-70" rx="10" ry="7" fill={light} opacity="0.6" />
      <ellipse cx="18" cy="-56" rx="20" ry="9" fill="#173c3a" opacity="0.5" />
    </g>
  );
}

/* ---------------- vehicles (facing left) ---------------- */

function Wheel({ cx, cy, r }: { cx: number; cy: number; r: number }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={r} fill="#1e1a26" />
      <circle cx={cx} cy={cy} r={r * 0.5} fill="#8b8a96" />
      <circle cx={cx - r * 0.15} cy={cy - r * 0.15} r={r * 0.2} fill="#d6d6de" />
    </g>
  );
}

export function Keke({ x, y, s = 1, flip = false, body = '#f2c230', stripe = PAL.ects }: { x: number; y: number; s?: number; flip?: boolean; body?: string; stripe?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${flip ? -s : s} ${s})`}>
      <ellipse cx="34" cy="1" rx="40" ry="4" fill={PAL.shadow} opacity="0.4" />
      {/* canopy */}
      <path d="M10 -40 Q12 -50 22 -50 L62 -50 Q68 -50 68 -44 L68 -40 Z" fill="#1d1a24" />
      <path d="M12 -42 L68 -42 L68 -40 L10 -40Z" fill={stripe} />
      {/* body */}
      <path d="M2 -14 Q2 -26 10 -32 L14 -40 L68 -40 L68 -8 Q68 -5 64 -5 L6 -5 Q2 -5 2 -10 Z" fill={body} />
      <path d="M2 -14 Q4 -24 10 -30 L14 -36 L18 -36 L10 -24 Q6 -18 6 -8 L4 -6Z" fill="#fff4c8" opacity="0.45" />
      {/* openings */}
      <path d="M22 -37 L40 -37 L40 -16 L18 -16 Q18 -30 22 -37Z" fill="#2b2533" />
      <path d="M44 -37 L64 -37 L64 -16 L44 -16Z" fill="#2b2533" />
      <path d="M2 -14 L68 -14 L68 -11 L2 -11Z" fill={stripe} />
      <path d="M46 -40 L68 -40 L68 -5 L50 -5 Z" fill="#2a1a4f" opacity="0.18" />
      <circle cx="5" cy="-17" r="2.2" fill="#fff6c8" />
      <Wheel cx={12} cy={-5} r={5.5} />
      <Wheel cx={56} cy={-5} r={6} />
    </g>
  );
}

export function Car({ x, y, s = 1, flip = false, body = '#c8ccd6', dark = '#5b6170' }: { x: number; y: number; s?: number; flip?: boolean; body?: string; dark?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${flip ? -s : s} ${s})`}>
      <ellipse cx="45" cy="1" rx="50" ry="4.5" fill={PAL.shadow} opacity="0.4" />
      <path d="M2 -12 Q2 -22 12 -24 L26 -26 L36 -38 Q38 -40 44 -40 L68 -40 Q74 -40 78 -34 L84 -25 Q92 -24 92 -16 L92 -8 Q92 -5 88 -5 L6 -5 Q2 -5 2 -9Z" fill={body} />
      <path d="M38 -36 L52 -36 L52 -26 L30 -26Z" fill="#33405a" />
      <path d="M55 -36 L68 -36 Q72 -36 75 -31 L78 -26 L55 -26Z" fill="#33405a" />
      <path d="M40 -35 L46 -35 L38 -27 L33 -27Z" fill="#cfe2ff" opacity="0.35" />
      <path d="M2 -12 L92 -12 L92 -5 L6 -5 Q2 -5 2 -9Z" fill={dark} opacity="0.55" />
      <path d="M12 -24 L84 -24" stroke="#fff" strokeOpacity="0.5" strokeWidth="1" />
      <path d="M50 -40 L92 -16 L92 -5 L60 -5Z" fill="#2a1a4f" opacity="0.12" />
      <rect x="2" y="-20" width="5" height="3" rx="1" fill="#fff4cf" />
      <rect x="88" y="-20" width="4" height="3" rx="1" fill="#e2453b" />
      <Wheel cx={20} cy={-6} r={7} />
      <Wheel cx={74} cy={-6} r={7} />
    </g>
  );
}

/** Danfo-style minibus (yellow + black stripes) or ECTS green bus. */
export function Bus({
  x, y, s = 1, flip = false, body = '#f4c20d', stripe = '#1f1a26', label, labelColor = '#1f1a26',
}: { x: number; y: number; s?: number; flip?: boolean; body?: string; stripe?: string; label?: string; labelColor?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${flip ? -s : s} ${s})`}>
      <ellipse cx="62" cy="1" rx="66" ry="5" fill={PAL.shadow} opacity="0.4" />
      <path d="M4 -14 Q2 -40 12 -52 Q16 -56 24 -56 L118 -56 Q126 -56 126 -48 L126 -8 Q126 -5 122 -5 L8 -5 Q4 -5 4 -10Z" fill={body} />
      <path d="M8 -45 Q12 -52 22 -52 L30 -52 L30 -34 L6 -34 Q6 -40 8 -45Z" fill="#2f3d55" />
      {[34, 56, 78, 100].map((wx) => (
        <rect key={wx} x={wx} y="-52" width="19" height="17" rx="1.5" fill="#2f3d55" />
      ))}
      <path d="M10 -50 L16 -50 L9 -38 L7 -38Z" fill="#d9ecff" opacity="0.35" />
      <rect x="4" y="-30" width="122" height="3.5" fill={stripe} />
      <rect x="4" y="-23" width="122" height="2" fill={stripe} />
      <path d="M70 -56 L126 -56 L126 -5 L90 -5Z" fill="#2a1a4f" opacity="0.13" />
      <path d="M16 -55 L118 -55" stroke="#fff" strokeOpacity="0.45" strokeWidth="1.2" />
      {label && (
        <text x="66" y="-12" textAnchor="middle" fontFamily="Arial, sans-serif" fontWeight="700" fontSize="7" fill={labelColor}>{label}</text>
      )}
      <rect x="3" y="-20" width="5" height="4" rx="1" fill="#fff4cf" />
      <Wheel cx={24} cy={-6} r={7.5} />
      <Wheel cx={104} cy={-6} r={7.5} />
    </g>
  );
}

/** Street lamp; at night adds a bulb flare (pool of light is drawn by the scene via Glow). */
export function LampPost({ x, y, h = 120, night, flip = false }: { x: number; y: number; h?: number; night: boolean; flip?: boolean }) {
  const d = flip ? -1 : 1;
  return (
    <g>
      <rect x={x - 2} y={y - h} width="4" height={h} fill="#4a4a5a" />
      <rect x={x} y={y - h} width="2" height={h} fill="#2a1a4f" opacity="0.4" />
      <path d={`M${x} ${y - h} Q${x} ${y - h - 10} ${x + 20 * d} ${y - h - 10}`} stroke="#4a4a5a" strokeWidth="3" fill="none" />
      <path d={`M${x + 14 * d} ${y - h - 12} L${x + 30 * d} ${y - h - 12} L${x + 27 * d} ${y - h - 7} L${x + 17 * d} ${y - h - 7}Z`} fill="#3b3b48" />
      <rect x={Math.min(x + 18 * d, x + 26 * d)} y={y - h - 7} width="8" height="2" fill={night ? '#fff2c4' : '#d8d8e0'} />
      <rect x={x - 4} y={y - 6} width="8" height="6" fill="#3b3b48" />
    </g>
  );
}

/** Corrugated zinc pattern (rusty/silver). */
export function ZincPattern({ id, base = '#9aa3ad', dark = '#6b7480', light = '#d4dae0', w = 6 }: { id: string; base?: string; dark?: string; light?: string; w?: number }) {
  return (
    <pattern id={id} patternUnits="userSpaceOnUse" width={w} height="40">
      <rect width={w} height="40" fill={base} />
      <rect width={w * 0.33} height="40" fill={light} opacity="0.7" />
      <rect x={w * 0.66} width={w * 0.34} height="40" fill={dark} />
    </pattern>
  );
}

export function Txt({
  x, y, size, children, fill = '#fff', anchor = 'middle', weight = 800, spacing = 0, family = 'Arial Black, Arial, Helvetica, sans-serif', o,
}: { x: number; y: number; size: number; children: ReactNode; fill?: string; anchor?: 'start' | 'middle' | 'end'; weight?: number; spacing?: number; family?: string; o?: number }) {
  return (
    <text x={x} y={y} fontSize={size} fill={fill} textAnchor={anchor} fontWeight={weight} letterSpacing={spacing} fontFamily={family} opacity={o}>
      {children}
    </text>
  );
}
