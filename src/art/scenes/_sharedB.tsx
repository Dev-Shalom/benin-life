// P1-SCENES-B shared helpers (underscore prefix: ignored by the Scene dispatcher).
// Every helper takes `p` (the scene prefix) so ids stay unique per scene.
import type { CSSProperties, ReactNode } from 'react';

export const SCREEN: CSSProperties = { mixBlendMode: 'screen' };
export const MULTIPLY: CSSProperties = { mixBlendMode: 'multiply' };
export const SIGN_FONT = "'Arial Black', 'Arial Rounded MT Bold', Impact, sans-serif";
export const HAND_FONT = "'Comic Sans MS', 'Segoe Print', 'Chalkboard SE', cursive";

/** Deterministic PRNG so server/client markup and every render match. */
export function rng(seed: number) {
  let s = seed % 2147483647;
  if (s <= 0) s += 2147483646;
  return () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

/** Night-tint a hex colour toward moonlit indigo (for shapes that sit in un-shaded sky regions). */
export function dim(hex: string, night: boolean, amt = 0.62) {
  if (!night) return hex;
  const n = parseInt(hex.slice(1), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  const to = [27, 30, 78];
  const out = ch.map((c, i) => Math.round(c * (1 - amt) * 0.9 + to[i] * amt));
  return '#' + out.map((c) => c.toString(16).padStart(2, '0')).join('');
}

/** Sky gradient + celestial body + clouds/stars. Sun is upper-left (scene key light). */
export function Sky({ p, night, sunX = 130, sunY = 70, moonX = 640, moonY = 70, clouds = true }: {
  p: string; night: boolean; sunX?: number; sunY?: number; moonX?: number; moonY?: number; clouds?: boolean;
}) {
  const r = rng(p.length * 97 + 13);
  const stars = night
    ? Array.from({ length: 70 }, () => ({ x: r() * 800, y: r() * 230, s: 0.4 + r() * 1.3, o: 0.35 + r() * 0.65 }))
    : [];
  return (
    <g>
      <defs>
        <linearGradient id={`${p}-sky`} x1="0" y1="0" x2="0" y2="1" colorInterpolation="linearRGB">
          {night ? (
            <>
              <stop offset="0" stopColor="#060b22" />
              <stop offset="0.35" stopColor="#111a45" />
              <stop offset="0.6" stopColor="#24245a" />
              <stop offset="0.8" stopColor="#3f2c5e" />
              <stop offset="1" stopColor="#6a3b55" />
            </>
          ) : (
            <>
              <stop offset="0" stopColor="#4f8fca" />
              <stop offset="0.3" stopColor="#7fb4dc" />
              <stop offset="0.55" stopColor="#bcd6dc" />
              <stop offset="0.75" stopColor="#f1d9a6" />
              <stop offset="1" stopColor="#f2b070" />
            </>
          )}
        </linearGradient>
        <radialGradient id={`${p}-sun`} cx="0.5" cy="0.5" r="0.5">
          {night ? (
            <>
              <stop offset="0" stopColor="#e9ecff" stopOpacity="0.55" />
              <stop offset="0.3" stopColor="#9fa8e8" stopOpacity="0.22" />
              <stop offset="1" stopColor="#3b3f8a" stopOpacity="0" />
            </>
          ) : (
            <>
              <stop offset="0" stopColor="#fffbe8" stopOpacity="1" />
              <stop offset="0.12" stopColor="#fff1c2" stopOpacity="0.95" />
              <stop offset="0.35" stopColor="#ffd98a" stopOpacity="0.4" />
              <stop offset="1" stopColor="#ffb867" stopOpacity="0" />
            </>
          )}
        </radialGradient>
      </defs>
      <rect width="800" height="450" fill={`url(#${p}-sky)`} />
      {night ? (
        <>
          {stars.map((s, i) => (
            <circle key={i} cx={s.x.toFixed(1)} cy={s.y.toFixed(1)} r={s.s.toFixed(2)} fill="#f3f1ff" opacity={s.o.toFixed(2)} />
          ))}
          <circle cx={moonX} cy={moonY} r="110" fill={`url(#${p}-sun)`} />
          <circle cx={moonX} cy={moonY} r="20" fill="#f4f1e0" />
          <circle cx={moonX + 6} cy={moonY - 4} r="18" fill="#fffdf2" opacity="0.6" />
          <circle cx={moonX - 6} cy={moonY + 3} r="4" fill="#d6d2c0" opacity="0.7" />
          <circle cx={moonX + 5} cy={moonY + 8} r="2.6" fill="#d6d2c0" opacity="0.6" />
          <circle cx={moonX + 2} cy={moonY - 9} r="2" fill="#d6d2c0" opacity="0.5" />
        </>
      ) : (
        <>
          <circle cx={sunX} cy={sunY} r="170" fill={`url(#${p}-sun)`} />
          <circle cx={sunX} cy={sunY} r="22" fill="#fffbe9" />
        </>
      )}
      {clouds && <Clouds night={night} seed={p.length * 31 + 7} />}
    </g>
  );
}

export function Clouds({ night, seed }: { night: boolean; seed: number }) {
  const r = rng(seed);
  const list = Array.from({ length: 4 }, (_, i) => ({ x: 60 + i * 200 + r() * 90, y: 40 + r() * 70, w: 70 + r() * 70 }));
  const top = night ? '#3b3c78' : '#fff8ec';
  const mid = night ? '#2b2c62' : '#f4e6d8';
  const bot = night ? '#1d1d4c' : '#c9b9cf';
  return (
    <g opacity={night ? 0.55 : 0.85}>
      {list.map((c, i) => (
        <g key={i} transform={`translate(${c.x.toFixed(0)} ${c.y.toFixed(0)})`}>
          <ellipse cx="0" cy="8" rx={c.w} ry="10" fill={bot} />
          <ellipse cx={-c.w * 0.35} cy="0" rx={c.w * 0.45} ry="13" fill={mid} />
          <ellipse cx={c.w * 0.15} cy="-6" rx={c.w * 0.4} ry="17" fill={mid} />
          <ellipse cx={c.w * 0.05} cy="-9" rx={c.w * 0.3} ry="13" fill={top} />
          <ellipse cx={-c.w * 0.3} cy="-2" rx={c.w * 0.25} ry="9" fill={top} />
        </g>
      ))}
    </g>
  );
}

/** Bumpy bush / treeline silhouette. */
export function Treeline({ y, fill, seed, amp = 18, step = 26, opacity = 1, base = 450 }: {
  y: number; fill: string; seed: number; amp?: number; step?: number; opacity?: number; base?: number;
}) {
  const r = rng(seed);
  let d = `M-20 ${base} L-20 ${y}`;
  let x = -20;
  while (x < 820) {
    const w = step * (0.6 + r() * 0.9);
    const h = amp * (0.4 + r() * 0.8);
    d += ` Q${(x + w / 2).toFixed(0)} ${(y - h * 2).toFixed(0)} ${(x + w).toFixed(0)} ${(y + (r() - 0.5) * amp * 0.4).toFixed(0)}`;
    x += w;
  }
  d += ` L820 ${base} Z`;
  return <path d={d} fill={fill} opacity={opacity} />;
}

/** Feathery palm frond centred at origin pointing +x; caller rotates. */
function frondPath(len: number, droop: number, leaf: number) {
  let spine = 'M0 0';
  let leaves = '';
  const n = 14;
  for (let i = 1; i <= n; i++) {
    const t = i / n;
    const x = t * len;
    const y = -Math.sin(t * Math.PI * 0.55) * len * 0.22 + t * t * droop;
    spine += ` L${x.toFixed(1)} ${y.toFixed(1)}`;
    const l = leaf * Math.sin(Math.PI * Math.min(1, t * 1.1)) + 2;
    leaves += ` M${x.toFixed(1)} ${y.toFixed(1)} l${(-l * 0.35).toFixed(1)} ${(l * 0.95).toFixed(1)}`;
    leaves += ` M${x.toFixed(1)} ${y.toFixed(1)} l${(-l * 0.5).toFixed(1)} ${(-l * 0.55).toFixed(1)}`;
  }
  return { spine, leaves };
}

/** Oil / coconut palm. (x,y) = foot of trunk. */
export function Palm({ x, y, s = 1, night, lean = 8, kind = 'oil', tone = 0 }: {
  x: number; y: number; s?: number; night: boolean; lean?: number; kind?: 'oil' | 'coconut'; tone?: number;
}) {
  const h = kind === 'oil' ? 120 : 165;
  const dark = night ? ['#16243a', '#1d2f45', '#0f1a2e'] : tone ? ['#3f7a3a', '#5d9a45', '#2c5a35'] : ['#2f6b34', '#4f9a3f', '#21492f'];
  const trunk = night ? '#2a2236' : '#6b4a33';
  const trunkHi = night ? '#3a3046' : '#9a7350';
  const angles = kind === 'oil' ? [-160, -130, -100, -70, -40, -10, 15, 200, 180, -150, 30] : [-165, -135, -105, -60, -25, 5, 25, 195];
  const cx = lean;
  const cy = -h;
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="6" cy="2" rx="26" ry="4" fill="#2d1b4e" opacity="0.25" />
      <path d={`M-5 0 Q${lean * 0.2} ${-h * 0.5} ${cx - 3} ${cy} L${cx + 3} ${cy} Q${lean * 0.2 + 7} ${-h * 0.5} 6 0 Z`} fill={trunk} />
      <path d={`M-2 0 Q${lean * 0.2 + 1} ${-h * 0.5} ${cx - 1} ${cy}`} stroke={trunkHi} strokeWidth="2.5" fill="none" opacity="0.7" />
      {kind === 'oil' && (
        <path d={`M-4 -10 l9 -4 M-4 -24 l10 -4 M-3 -38 l10 -4 M-2 -52 l10 -4 M-1 -66 l10 -4 M0 -80 l10 -4 M1 -94 l10 -4`}
          stroke={night ? '#1a1526' : '#4a3222'} strokeWidth="3" strokeLinecap="round" opacity="0.8" />
      )}
      {kind === 'coconut' && (
        <path d={`M-4 -20 h10 M-3 -45 h10 M-2 -70 h10 M-1 -95 h10 M0 -120 h10 M1 -145 h9`}
          stroke={night ? '#1a1526' : '#4a3222'} strokeWidth="1.5" opacity="0.6" />
      )}
      <g transform={`translate(${cx} ${cy})`}>
        {angles.map((a, i) => {
          const len = (kind === 'oil' ? 58 : 66) * (0.8 + ((i * 37) % 10) / 30);
          const f = frondPath(len, kind === 'oil' ? 22 : 38, 13);
          const col = dark[i % 2];
          return (
            <g key={i} transform={`rotate(${a})`}>
              <path d={f.leaves} stroke={i % 3 === 0 ? dark[2] : col} strokeWidth="2.6" strokeLinecap="round" fill="none" />
              <path d={f.spine} stroke={night ? '#26364a' : '#7a8f3a'} strokeWidth="1.6" fill="none" />
            </g>
          );
        })}
        {kind === 'oil' ? (
          <g>
            <circle cx="-4" cy="6" r="7" fill={night ? '#3a1c26' : '#b8361f'} />
            <circle cx="5" cy="7" r="6" fill={night ? '#2e1822' : '#8f2a18'} />
            <circle cx="-5" cy="4" r="2" fill={night ? '#5a3040' : '#f08a3a'} opacity="0.8" />
          </g>
        ) : (
          <g>
            <circle cx="-4" cy="6" r="5" fill={night ? '#253020' : '#5d6b2a'} />
            <circle cx="4" cy="7" r="5" fill={night ? '#1f2a1c' : '#4a5a22'} />
          </g>
        )}
      </g>
    </g>
  );
}

/** Small stylised person. (x,y) = feet. ~56px tall at s=1. Key light from the left. */
export function Person({ x, y, s = 1, skin = '#6b4128', top = '#d2342a', bottom = '#2b3350', hair = '#1a1420', pose = 'stand', facing = 1, headwrap, wrapper, night = false, extra }: {
  x: number; y: number; s?: number; skin?: string; top?: string; bottom?: string; hair?: string;
  pose?: 'stand' | 'sit' | 'walk' | 'work'; facing?: 1 | -1; headwrap?: string; wrapper?: string; night?: boolean; extra?: ReactNode;
}) {
  const shade = night ? 0.4 : 0.25;
  const sit = pose === 'sit';
  const hip = sit ? -17 : -25;
  const sh = sit ? -35 : -42;
  const hy = sh - 9;
  return (
    <g transform={`translate(${x} ${y}) scale(${s * facing} ${s})`}>
      <ellipse cx="2" cy="0" rx="11" ry="2.4" fill="#2d1b4e" opacity="0.35" />
      {sit ? (
        <>
          <path d={`M-3 ${hip} L9 ${hip} L9 -1`} stroke={bottom} strokeWidth="5.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
          <path d={`M-5 ${hip + 1} L6 ${hip + 1} L5 -1`} stroke={bottom} strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" fill="none" opacity="0.8" />
          <ellipse cx="11" cy="-0.5" rx="4" ry="1.6" fill="#2a2030" />
        </>
      ) : wrapper ? (
        <>
          <path d={`M-7 ${hip} Q-9 -10 -8 -1 L8 -1 Q9 -10 7 ${hip} Z`} fill={wrapper} />
          <path d={`M2 ${hip} Q6 -10 6 -1 L8 -1 Q9 -10 7 ${hip} Z`} fill="#2d1b4e" opacity={shade} />
          <path d={`M-6 -8 Q0 -6 7 -8 M-6 -15 Q0 -13 7 -15`} stroke="#fff" strokeWidth="1" opacity="0.3" fill="none" />
          <ellipse cx="-4" cy="-0.5" rx="3.4" ry="1.4" fill="#2a2030" />
          <ellipse cx="4" cy="-0.5" rx="3.4" ry="1.4" fill="#2a2030" />
        </>
      ) : (
        <>
          <path d={pose === 'walk' ? `M-2 ${hip} L-8 -2` : `M-3 ${hip} L-3.5 -2`} stroke={bottom} strokeWidth="5" strokeLinecap="round" />
          <path d={pose === 'walk' ? `M2 ${hip} L7 -2` : `M3 ${hip} L3.5 -2`} stroke={bottom} strokeWidth="5" strokeLinecap="round" />
          <path d={pose === 'walk' ? `M2 ${hip} L7 -2` : `M3 ${hip} L3.5 -2`} stroke="#2d1b4e" strokeWidth="5" strokeLinecap="round" opacity={shade} />
          <ellipse cx={pose === 'walk' ? -9 : -4} cy="-0.5" rx="3.4" ry="1.5" fill="#2a2030" />
          <ellipse cx={pose === 'walk' ? 8 : 4.5} cy="-0.5" rx="3.4" ry="1.5" fill="#2a2030" />
        </>
      )}
      {/* torso */}
      <path d={`M-8 ${sh + 1} Q-9 ${(sh + hip) / 2} -6 ${hip + 1} L6 ${hip + 1} Q9 ${(sh + hip) / 2} 8 ${sh + 1} Q0 ${sh - 2} -8 ${sh + 1} Z`} fill={top} />
      <path d={`M2 ${sh - 1} Q9 ${sh} 8 ${sh + 1} Q9 ${(sh + hip) / 2} 6 ${hip + 1} L2 ${hip + 1} Z`} fill="#2d1b4e" opacity={shade} />
      <path d={`M-7 ${sh + 2} Q-8 ${(sh + hip) / 2} -6 ${hip}`} stroke="#fff" strokeWidth="1.2" opacity="0.25" fill="none" />
      {/* arms */}
      <path d={`M-7.5 ${sh + 2} Q-11 ${sh + 9} -10 ${sh + 17}`} stroke={skin} strokeWidth="3.4" strokeLinecap="round" fill="none" />
      {pose === 'work' || sit ? (
        <path d={`M7.5 ${sh + 2} Q11 ${sh + 9} 16 ${sh + 12}`} stroke={skin} strokeWidth="3.4" strokeLinecap="round" fill="none" />
      ) : (
        <path d={`M7.5 ${sh + 2} Q11 ${sh + 9} 10 ${sh + 17}`} stroke={skin} strokeWidth="3.4" strokeLinecap="round" fill="none" />
      )}
      <path d={`M-7.5 ${sh + 2} Q-10 ${sh + 6} -10.4 ${sh + 9}`} stroke={top} strokeWidth="4.2" strokeLinecap="round" fill="none" />
      <path d={`M7.5 ${sh + 2} Q10 ${sh + 6} 10.4 ${sh + 9}`} stroke={top} strokeWidth="4.2" strokeLinecap="round" fill="none" />
      {/* neck + head */}
      <rect x="-1.8" y={hy + 3} width="3.6" height="6" fill={skin} />
      <circle cx="0" cy={hy} r="5.2" fill={skin} />
      <circle cx="1.8" cy={hy + 1} r="3.8" fill="#2d1b4e" opacity={shade * 0.7} />
      <circle cx="-2" cy={hy - 1.5} r="1.4" fill="#fff" opacity="0.18" />
      {headwrap ? (
        <path d={`M-6 ${hy - 0.5} Q-7 ${hy - 10} 0 ${hy - 10} Q8 ${hy - 11} 7 ${hy - 2} Q9 ${hy - 9} 4 ${hy - 12} Q0 ${hy - 4} -6 ${hy - 0.5} Z`} fill={headwrap} />
      ) : (
        <path d={`M-5.3 ${hy - 0.5} Q-5.6 ${hy - 6.6} 0 ${hy - 6.4} Q5.6 ${hy - 6.6} 5.3 ${hy - 1.5} Q0 ${hy - 4.2} -5.3 ${hy - 0.5} Z`} fill={hair} />
      )}
      {extra}
    </g>
  );
}

/** Warm/cool radial glow gradients. Use with <Glow>. */
export function GlowDefs({ p }: { p: string }) {
  const g = (id: string, c: string, c2: string) => (
    <radialGradient id={`${p}-${id}`} cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stopColor={c} stopOpacity="0.95" />
      <stop offset="0.25" stopColor={c} stopOpacity="0.5" />
      <stop offset="0.6" stopColor={c2} stopOpacity="0.16" />
      <stop offset="1" stopColor={c2} stopOpacity="0" />
    </radialGradient>
  );
  return (
    <defs>
      {g('gw', '#ffd27a', '#ff9a3c')}
      {g('gf', '#ffb347', '#ff5a1f')}
      {g('gc', '#bfe9ff', '#4f7dff')}
      {g('gg', '#9dffb0', '#22c55e')}
    </defs>
  );
}

export function Glow({ p, cx, cy, r, kind = 'gw', o = 1, ry }: { p: string; cx: number; cy: number; r: number; kind?: 'gw' | 'gf' | 'gc' | 'gg'; o?: number; ry?: number }) {
  return <ellipse cx={cx} cy={cy} rx={r} ry={ry ?? r} fill={`url(#${p}-${kind})`} opacity={o} style={SCREEN} />;
}

/** Night darkening (indigo multiply) — draw after the environment, before light sources. */
export function NightShade({ p, top = 0.55, bottom = 0.75, exclude, feather }: {
  p: string; top?: number; bottom?: number; exclude?: string;
  /** With `exclude`: fade the exclusion out between these two y values (soft horizon instead of a hard seam). */
  feather?: [number, number];
}) {
  const clip = exclude && !feather ? `url(#${p}-nsc)` : undefined;
  const mask = exclude && feather ? `url(#${p}-nsm)` : undefined;
  return (
    <g>
      <defs>
        <linearGradient id={`${p}-ns`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1b1f55" stopOpacity={top} />
          <stop offset="1" stopColor="#120f33" stopOpacity={bottom} />
        </linearGradient>
        {exclude && !feather && (
          <clipPath id={`${p}-nsc`}>
            <path d={`M0 0H800V450H0Z ${exclude}`} clipRule="evenodd" />
          </clipPath>
        )}
        {exclude && feather && (
          <>
            <linearGradient id={`${p}-nsf`} gradientUnits="userSpaceOnUse" x1="0" y1={feather[0]} x2="0" y2={feather[1]}>
              <stop offset="0" stopColor="#000" />
              <stop offset="1" stopColor="#fff" />
            </linearGradient>
            <mask id={`${p}-nsm`} maskUnits="userSpaceOnUse" x="0" y="0" width="800" height="450">
              <rect width="800" height="450" fill="#fff" />
              <path d={exclude} fill={`url(#${p}-nsf)`} />
            </mask>
          </>
        )}
      </defs>
      {/* mask/clip go on the blended rects themselves: on a parent <g> they would isolate the blend */}
      <rect width="800" height="450" fill={`url(#${p}-ns)`} style={MULTIPLY} mask={mask} clipPath={clip} />
      <rect width="800" height="450" fill="#232a6e" opacity="0.35" style={MULTIPLY} mask={mask} clipPath={clip} />
    </g>
  );
}

/** Atmospheric haze band between layers. */
export function Haze({ p, y, h, night, o = 0.35 }: { p: string; y: number; h: number; night: boolean; o?: number }) {
  const id = `${p}-hz${y}`;
  return (
    <g>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#4a4a8a' : '#f6e3c4'} stopOpacity="0" />
          <stop offset="0.6" stopColor={night ? '#4a4a8a' : '#f6e3c4'} stopOpacity={o} />
          <stop offset="1" stopColor={night ? '#4a4a8a' : '#f6e3c4'} stopOpacity="0" />
        </linearGradient>
      </defs>
      <rect x="0" y={y} width="800" height={h} fill={`url(#${id})`} />
    </g>
  );
}

/** Film grain + vignette. One per scene, drawn last. */
export function Finish({ p, night }: { p: string; night: boolean }) {
  return (
    <g pointerEvents="none">
      <defs>
        <filter id={`${p}-grain`} x="0" y="0" width="100%" height="100%" colorInterpolationFilters="linearRGB">
          <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" stitchTiles="stitch" seed={p.length} />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <radialGradient id={`${p}-vig`} cx="0.5" cy="0.48" r="0.75">
          <stop offset="0.55" stopColor="#1a1040" stopOpacity="0" />
          <stop offset="1" stopColor="#1a1040" stopOpacity={night ? 0.6 : 0.35} />
        </radialGradient>
      </defs>
      <rect width="800" height="450" filter={`url(#${p}-grain)`} opacity="0.09" style={{ mixBlendMode: 'overlay' }} />
      <rect width="800" height="450" fill={`url(#${p}-vig)`} />
    </g>
  );
}

/** Monobloc plastic chair, front-ish 3/4 view. (x,y) = floor centre. */
export function PlasticChair({ x, y, s = 1, color = '#e8e6e1', shade = '#9b97b0' }: { x: number; y: number; s?: number; color?: string; shade?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="2" cy="0" rx="17" ry="3" fill="#2d1b4e" opacity="0.3" />
      <path d="M-13 0 L-11 -18 M13 0 L11 -18 M-8 -2 L-7 -16 M9 -2 L8 -16" stroke={shade} strokeWidth="3" strokeLinecap="round" />
      <path d="M-14 -18 Q0 -22 14 -18 L12 -14 Q0 -17 -12 -14 Z" fill={color} />
      <path d="M-12 -18 Q-14 -32 -11 -40 Q0 -44 11 -40 Q14 -32 12 -18 Q0 -21 -12 -18 Z" fill={color} />
      <path d="M-8 -36 h16 M-8 -31 h16 M-8 -26 h16" stroke={shade} strokeWidth="1.4" opacity="0.6" />
      <path d="M5 -41 Q14 -32 12 -18 L7 -19 Z" fill={shade} opacity="0.45" />
      <path d="M-11 -39 Q-13 -30 -11 -20" stroke="#fff" strokeWidth="1.2" opacity="0.5" fill="none" />
    </g>
  );
}

/** Plastic bucket. (x,y) = floor centre. */
export function Bucket({ x, y, s = 1, color = '#2f7fd0', dark = '#1d4f8a' }: { x: number; y: number; s?: number; color?: string; dark?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="2" cy="0" rx="13" ry="3" fill="#2d1b4e" opacity="0.3" />
      <path d="M-11 -22 L-8 0 L8 0 L11 -22 Z" fill={color} />
      <path d="M3 -22 L11 -22 L8 0 L3 0 Z" fill={dark} opacity="0.55" />
      <ellipse cx="0" cy="-22" rx="11" ry="3" fill={dark} />
      <ellipse cx="0" cy="-22" rx="9" ry="2" fill="#7ec3ea" opacity="0.8" />
      <path d="M-11 -22 Q0 -38 11 -22" stroke={dark} strokeWidth="1.4" fill="none" />
      <path d="M-8 -18 L-6 -3" stroke="#fff" strokeWidth="1.5" opacity="0.35" />
    </g>
  );
}

/** Small petrol generator ("I better pass my neighbour"). (x,y) = floor centre. */
export function Generator({ p, x, y, s = 1, night, color = '#d2342a' }: { p: string; x: number; y: number; s?: number; night: boolean; color?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="3" cy="1" rx="30" ry="4" fill="#2d1b4e" opacity="0.35" />
      <path d="M-24 0 V-30 H24 V0" stroke="#3b3a46" strokeWidth="3" fill="none" strokeLinejoin="round" />
      <rect x="-21" y="-28" width="42" height="26" rx="4" fill={color} />
      <rect x="4" y="-28" width="17" height="26" rx="3" fill="#2d1b4e" opacity="0.3" />
      <rect x="-18" y="-38" width="30" height="12" rx="5" fill={color} />
      <rect x="-15" y="-36" width="18" height="3" rx="1.5" fill="#fff" opacity="0.35" />
      <circle cx="-9" cy="-14" r="6" fill="#2a2834" />
      <circle cx="-9" cy="-14" r="3.5" fill="#55536a" />
      <rect x="6" y="-20" width="11" height="8" rx="1" fill="#e9e3d0" />
      <path d="M21 -10 h8 v-14" stroke="#4a4858" strokeWidth="3" fill="none" />
      <text x="-19" y="-4" fontSize="5" fontFamily={SIGN_FONT} fill="#fff" opacity="0.85">TIGER</text>
      {night && (
        <g>
          <circle cx="11" cy="-16" r="1.5" fill="#ffe08a" />
          <Glow p={p} cx={11} cy={-16} r={10} o={0.7} />
          <path d="M29 -26 q-6 -10 2 -18 q8 -8 0 -18" stroke="#8d8fb8" strokeWidth="5" fill="none" opacity="0.25" strokeLinecap="round" />
        </g>
      )}
    </g>
  );
}

/** Hanging bare bulb on a wire with optional glow at night. */
export function Bulb({ p, x, y, night, wire = 14, on = true }: { p: string; x: number; y: number; night: boolean; wire?: number; on?: boolean }) {
  return (
    <g>
      <path d={`M${x} ${y - wire} V${y - 4}`} stroke="#2a2232" strokeWidth="1" />
      {night && on && <Glow p={p} cx={x} cy={y} r={70} o={0.9} />}
      <ellipse cx={x} cy={y} rx="3.4" ry="4.4" fill={night && on ? '#fff3c4' : '#e8e2cc'} />
      {night && on && <circle cx={x} cy={y} r="2" fill="#fff" />}
    </g>
  );
}

/** Corrugated zinc roof pattern (rusty galvanised). */
export function ZincPattern({ p, night, rust = true }: { p: string; night: boolean; rust?: boolean }) {
  const a = night ? '#4c4f72' : '#b9bcc4';
  const b = night ? '#2f3152' : '#7d8090';
  return (
    <defs>
      <pattern id={`${p}-zinc`} patternUnits="userSpaceOnUse" width="10" height="40">
        <rect width="10" height="40" fill={a} />
        <rect x="5" width="5" height="40" fill={b} />
        <rect x="2" width="1.5" height="40" fill="#fff" opacity={night ? 0.15 : 0.5} />
      </pattern>
      {rust && (
        <linearGradient id={`${p}-rust`} x1="0" y1="0" x2="1" y2="0.3">
          <stop offset="0" stopColor="#a5502a" stopOpacity={night ? 0.25 : 0.55} />
          <stop offset="0.3" stopColor="#a5502a" stopOpacity="0.05" />
          <stop offset="0.55" stopColor="#8a3d1f" stopOpacity={night ? 0.2 : 0.45} />
          <stop offset="0.8" stopColor="#a5502a" stopOpacity="0.08" />
          <stop offset="1" stopColor="#7a3519" stopOpacity={night ? 0.25 : 0.5} />
        </linearGradient>
      )}
    </defs>
  );
}

/** Side-view car facing right. (x,y) = ground centre. ~175px long at s=1. */
export function Car({ p, x, y, s = 1, color = '#9aa7b8', dark = '#5d6a80', kind = 'sedan', night, flip = false }: {
  p: string; x: number; y: number; s?: number; color?: string; dark?: string; kind?: 'sedan' | 'suv'; night: boolean; flip?: boolean;
}) {
  const suv = kind === 'suv';
  const body = suv
    ? 'M-88 -12 Q-90 -36 -80 -40 L-66 -42 L-56 -70 Q-54 -74 -46 -74 L36 -74 Q46 -73 54 -60 L64 -44 L82 -40 Q90 -36 90 -14 Q89 -8 82 -8 L-82 -8 Q-88 -8 -88 -12 Z'
    : 'M-86 -14 Q-87 -28 -72 -31 L-42 -33 Q-26 -53 4 -53 L30 -52 Q46 -49 62 -34 L80 -31 Q88 -28 88 -15 Q87 -8 80 -8 L-80 -8 Q-86 -8 -86 -14 Z';
  const win1 = suv ? 'M-50 -44 L-42 -68 L-8 -68 L-8 -44 Z' : 'M-34 -34 Q-21 -50 1 -50 L3 -34 Z';
  const win2 = suv ? 'M-3 -44 L-3 -68 L33 -68 Q42 -67 49 -55 L56 -44 Z' : 'M8 -50 L28 -49 Q41 -46 53 -34 L8 -34 Z';
  const wx = suv ? [-54, 58] : [-52, 55];
  const wr = suv ? 16 : 13;
  return (
    <g transform={`translate(${x} ${y}) scale(${flip ? -s : s} ${s})`}>
      <ellipse cx="6" cy="-2" rx="100" ry="8" fill="#2d1b4e" opacity="0.4" />
      <path d={body} fill={color} />
      {/* lower body shade + rocker */}
      <path d={suv ? 'M-88 -22 L90 -22 L90 -14 Q89 -8 82 -8 L-82 -8 Q-88 -8 -88 -12 Z' : 'M-86 -20 L88 -20 L88 -15 Q87 -8 80 -8 L-80 -8 Q-86 -8 -86 -14 Z'} fill={dark} opacity="0.7" />
      <path d={suv ? 'M-84 -38 L86 -38' : 'M-80 -29 L84 -28'} stroke="#fff" strokeWidth="2" opacity="0.45" />
      <path d={win1} fill={night ? '#1d2448' : '#2c3a58'} />
      <path d={win2} fill={night ? '#1d2448' : '#2c3a58'} />
      <path d={suv ? 'M-46 -46 L-40 -66 L-30 -66 L-38 -46 Z' : 'M-28 -36 Q-18 -48 -6 -48 L-14 -36 Z'} fill="#cfe3f5" opacity={night ? 0.15 : 0.45} />
      <path d={suv ? 'M2 -46 L2 -66 L12 -66 L8 -46 Z' : 'M12 -48 L20 -48 L14 -36 L10 -36 Z'} fill="#cfe3f5" opacity={night ? 0.15 : 0.35} />
      <path d={suv ? 'M-5 -42 V-12' : 'M5 -33 V-13'} stroke={dark} strokeWidth="1.2" opacity="0.8" />
      <rect x={suv ? 8 : 14} y={suv ? -34 : -27} width="9" height="2.5" rx="1" fill={dark} />
      <rect x={suv ? -40 : -30} y={suv ? -34 : -27} width="9" height="2.5" rx="1" fill={dark} />
      {/* lights */}
      <path d={suv ? 'M84 -36 h6 v8 h-6 Z' : 'M82 -27 Q88 -25 88 -20 L80 -21 Z'} fill={night ? '#fff6d8' : '#f2efe4'} />
      <path d={suv ? 'M-88 -34 h5 v9 h-5 Z' : 'M-86 -25 L-80 -26 L-80 -20 L-86 -19 Z'} fill="#d2342a" />
      {/* wheels */}
      {wx.map((cx) => (
        <g key={cx}>
          <circle cx={cx} cy={-8} r={wr + 3} fill={dark} />
          <circle cx={cx} cy={-6} r={wr} fill="#1f1d2a" />
          <circle cx={cx} cy={-6} r={wr * 0.55} fill="#a9aec0" />
          <circle cx={cx} cy={-6} r={wr * 0.25} fill="#5c6072" />
          <path d={`M${cx - wr * 0.4} ${-6 - wr * 0.3} a${wr * 0.5} ${wr * 0.5} 0 0 1 ${wr * 0.6} -${wr * 0.15}`} stroke="#fff" strokeWidth="1.2" fill="none" opacity="0.6" />
        </g>
      ))}
      {/* reflected sky on roof */}
      <path d={suv ? 'M-50 -73 L40 -73' : 'M-20 -52 L28 -51'} stroke="#fff" strokeWidth="1.6" opacity="0.5" />
      {night && <Glow p={p} cx={90} cy={-24} r={6} kind="gc" o={0.4} />}
    </g>
  );
}
