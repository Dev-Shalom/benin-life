// Accessories + the shared coral-bead renderer (also used by Bini traditional outfits).
import type { ReactNode } from 'react';
import type { Ctx } from './ctx';
import { CX, handGeom, limb, mirrorJoints, r1, type P } from './geometry';
import { handPath } from './body';
import { mix, shade, light, luma } from './color';

export function beadDefs(c: Ctx) {
  const coral = c.def('coralB', (id) => (
    <radialGradient id={id} cx="0.5" cy="0.5" r="0.55" fx="0.34" fy="0.3">
      <stop offset="0" stopColor="#ffc2a4" />
      <stop offset="0.3" stopColor="#f2603f" />
      <stop offset="0.72" stopColor="#c8262a" />
      <stop offset="1" stopColor="#7a1422" />
    </radialGradient>
  ));
  const gold = c.def('goldB', (id) => (
    <radialGradient id={id} cx="0.5" cy="0.5" r="0.55" fx="0.34" fy="0.3">
      <stop offset="0" stopColor="#fff4c2" />
      <stop offset="0.35" stopColor="#f0c04e" />
      <stop offset="0.78" stopColor="#b47e2a" />
      <stop offset="1" stopColor="#6a461c" />
    </radialGradient>
  ));
  return { coral, gold };
}

function shoulderLineY(c: Ctx, dx: number): number {
  const { nw, sh } = c.b;
  if (dx < nw + 1) return 99;
  if (dx < sh - 7) return 99 + ((dx - nw - 1) * 7.5) / Math.max(1, sh - 8 - nw);
  return 106.5 + (dx - sh + 7) * 0.8;
}

interface BeadRow { rx: number; ry: number; y0: number; r: number; gap?: number; goldEvery?: number }

/** Strands of coral beads draped round the neck / over the shoulders. */
export function coralRows(c: Ctx, rows: BeadRow[], fringe = false): ReactNode {
  const { coral, gold } = beadDefs(c);
  const out: ReactNode[] = [];
  rows.forEach((row, ri) => {
    const gap = row.gap ?? row.r * 1.9;
    // sample the half-ellipse (below the neck) by arc length
    const steps = 160;
    let acc = gap / 2;
    let prev: P | null = null;
    let k = 0;
    const thread: P[] = [];
    for (let i = 0; i <= steps; i++) {
      const th = (Math.PI * i) / steps;
      const p: P = [CX + Math.cos(th) * row.rx, row.y0 + Math.sin(th) * row.ry];
      if (prev) acc += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
      prev = p;
      if (acc >= gap) {
        acc = 0;
        const dx = Math.abs(p[0] - CX);
        if (p[1] < shoulderLineY(c, dx) - row.r * 0.6 || dx > c.b.sh + 1) continue;
        thread.push(p);
        const isGold = row.goldEvery ? k % row.goldEvery === row.goldEvery - 1 : false;
        out.push(<circle key={`${ri}-${k}`} cx={r1(p[0])} cy={r1(p[1])} r={isGold ? row.r * 0.8 : row.r} fill={isGold ? gold : coral} />);
        if (fringe && ri === rows.length - 1 && k % 3 === 1) {
          for (let d = 1; d <= 3; d++) out.push(<circle key={`f${k}-${d}`} cx={r1(p[0])} cy={r1(p[1] + d * row.r * 1.8)} r={row.r * (1 - d * 0.12)} fill={d === 3 ? gold : coral} />);
        }
        k++;
      }
    }
    if (thread.length > 1) {
      out.unshift(<path key={'t' + ri} d={'M' + thread.map(([x, y]) => `${r1(x)} ${r1(y)}`).join(' L')} stroke="#5a1a1a" strokeWidth="0.6" fill="none" opacity="0.5" />);
    }
  });
  return <g>{out}</g>;
}

export function coralNecklace(c: Ctx): ReactNode {
  const nw = c.b.nw;
  return coralRows(c, [
    { rx: nw + 3.2, ry: 7.5, y0: 98.6, r: 1.9, goldEvery: 7 },
    { rx: nw + 7, ry: 13, y0: 98.6, r: 2.1, goldEvery: 9 },
    { rx: nw + 10.5, ry: 19, y0: 98.4, r: 2.3, goldEvery: 0 },
  ]);
}

function goldChain(c: Ctx): ReactNode {
  const nw = c.b.nw;
  const d = `M${CX - nw - 2} 101 Q${CX - nw - 3} 124 ${CX} 128 Q${CX + nw + 3} 124 ${CX + nw + 2} 101`;
  const { gold } = beadDefs(c);
  return (
    <g fill="none" strokeLinecap="round">
      <path d={d} stroke="#7a521c" strokeWidth="3.4" />
      <path d={d} stroke="#e6b443" strokeWidth="2.6" />
      <path d={d} stroke="#fff0b0" strokeWidth="1.2" strokeDasharray="1.6 1.4" opacity="0.9" />
      <circle cx={CX} cy={133} r={5} fill={gold} stroke="#7a521c" strokeWidth="0.7" />
      <circle cx={CX} cy={133} r={3.2} fill="none" stroke="#fff0b0" strokeWidth="0.7" opacity="0.8" />
      <path d={`M${CX} 130.6 l1 2.2 2.2 0.2 -1.7 1.4 0.6 2.2 -2.1 -1.2 -2.1 1.2 0.6 -2.2 -1.7 -1.4 2.2 -0.2Z`} fill="#fff6c8" opacity="0.9" />
    </g>
  );
}

function bag(c: Ctx): ReactNode {
  if (c.portrait) {
    // just the strap across the chest
    return <path d={`M${CX - c.b.sh + 6} 108 L${CX + c.b.ch - 2} 150`} stroke="#4a2a1c" strokeWidth="3.4" />;
  }
  const b = c.b;
  const col = c.b.female ? '#b8452e' : '#3b2b26';
  const hx = CX + b.hi + 3;
  const strap = `M${CX - b.sh + 7} 107 L${hx - 4} 196`;
  return (
    <g>
      <path d={strap} stroke={shade(col, 0.4)} strokeWidth="4.2" strokeLinecap="round" />
      <path d={strap} stroke={light(col, 0.15)} strokeWidth="2.6" strokeLinecap="round" />
      <path d={strap} stroke={light(col, 0.5)} strokeWidth="0.6" strokeDasharray="2 1.6" opacity="0.7" />
      <g transform={`translate(${hx - 10} 190)`}>
        <rect x="0" y="0" width="22" height="18" rx="4" fill={col} />
        <rect x="0" y="0" width="22" height="18" rx="4" fill={c.url('shadeH')} />
        <path d="M0 4 Q11 11 22 4 L22 2 Q22 0 18 0 L4 0 Q0 0 0 2Z" fill={shade(col, 0.25)} />
        <rect x="9" y="6" width="4" height="3" rx="0.8" fill="#e8c25a" />
        <path d="M2 15.5 H20" stroke={light(col, 0.4)} strokeWidth="0.5" strokeDasharray="1.4 1" opacity="0.7" />
      </g>
    </g>
  );
}

export function accessoriesBody(c: Ctx): ReactNode {
  const out: ReactNode[] = [];
  const bini = c.cfg.outfit === 'bini_traditional';
  if (c.has('bag')) out.push(<g key="bag">{bag(c)}</g>);
  if (c.has('gold_chain')) out.push(<g key="chain">{goldChain(c)}</g>);
  if (c.has('coral_beads') && !bini) out.push(<g key="coral">{coralNecklace(c)}</g>);
  return out.length ? <g>{out}</g> : null;
}

function watch(c: Ctx): ReactNode {
  const arm = mirrorJoints(c.b.arm);
  const band = limb(arm, { from: 0.9, to: 0.965, pad: 1, start: 'flat', end: 'flat' });
  const { wrist, dir } = handGeom(c.b, -1);
  const fx = wrist.x - dir[0] * 4;
  const fy = wrist.y - dir[1] * 4;
  const { gold } = beadDefs(c);
  return (
    <g>
      <path d={band} fill="#b8862c" />
      <path d={band} fill={c.url('shadeH')} />
      <circle cx={fx} cy={fy} r={4.2} fill={gold} />
      <circle cx={fx} cy={fy} r={3} fill="#1d2a3a" />
      <path d={`M${fx} ${fy} l0 -2 M${fx} ${fy} l1.4 0.6`} stroke="#f4e6b8" strokeWidth="0.5" />
      <path d={`M${fx - 2} ${fy - 1.4} q1 -1 2.4 -1.2`} stroke="#ffffff" strokeWidth="0.6" opacity="0.6" fill="none" />
    </g>
  );
}

function phone(c: Ctx, layer: 'under' | 'over'): ReactNode {
  const { wrist, dir } = handGeom(c.b, 1);
  const ang = (Math.atan2(dir[1], dir[0]) * 180) / Math.PI - 90;
  const len = c.b.handLen;
  const cx = wrist.x + dir[0] * len * 0.55 + 3.5;
  const cy = wrist.y + dir[1] * len * 0.55;
  if (layer === 'under') {
    return (
      <g transform={`translate(${r1(cx)} ${r1(cy)}) rotate(${r1(ang - 8)})`}>
        <rect x="-6" y="-11" width="12" height="22" rx="2.4" fill="#1e1d2b" />
        <rect x="-5" y="-9.8" width="10" height="19.6" rx="1.6" fill="#3d5ad8" />
        <path d="M-5 -2 L5 -9 L5 -5 L-5 2Z" fill="#ffffff" opacity="0.25" />
        <circle cx="-3" cy="-7.8" r="0.7" fill="#0c0c14" />
      </g>
    );
  }
  // fingers wrapping over the phone edge
  const h = handPath(c, 1);
  return <path d={h.thumb} fill={mix(c.skin.base, c.skin.highlight, 0.25)} stroke={c.skin.shadow} strokeWidth="0.6" />;
}

export function accessoriesHand(c: Ctx, layer: 'under' | 'over'): ReactNode {
  const out: ReactNode[] = [];
  if (c.has('phone_in_hand')) out.push(<g key="ph">{phone(c, layer)}</g>);
  if (layer === 'over' && c.has('wristwatch')) out.push(<g key="w">{watch(c)}</g>);
  return out.length ? <g>{out}</g> : null;
}

function sunglasses(c: Ctx): ReactNode {
  const lens = c.def('lens', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stopColor="#3a2f5e" />
      <stop offset="0.5" stopColor="#141226" />
      <stop offset="0.85" stopColor="#2b1f3a" />
      <stop offset="1" stopColor="#7a4a6a" />
    </linearGradient>
  ));
  const one = (x: number) => `M${x - 9} 55.5 Q${x} 53.5 ${x + 9} 55.5 Q${x + 9.6} 64 ${x + 4} 66.4 Q${x} 67.4 ${x - 4} 66.4 Q${x - 9.6} 64 ${x - 9} 55.5Z`;
  return (
    <g>
      <path d="M71.6 57 L79 56 M121 56 L128.4 57" stroke="#1d1a24" strokeWidth="1.6" />
      <path d="M97 57.4 Q100 55.6 103 57.4" stroke="#1d1a24" strokeWidth="1.8" fill="none" />
      {[88.4, 111.6].map((x) => (
        <g key={x}>
          <path d={one(x)} fill={lens} stroke="#1d1a24" strokeWidth="1.4" />
          <path d={`M${x - 6} 58 L${x - 1} 57 L${x - 6.5} 63Z`} fill="#ffffff" opacity="0.28" />
        </g>
      ))}
    </g>
  );
}

function cap(c: Ctx): ReactNode {
  const col = luma(c.oc) > 0.85 ? '#2c3e66' : c.oc;
  const tall = ['small_afro', 'high_top', 'bantu_knots', 'packing_gel', 'dada', 'twists', 'braids', 'bone_straight'].includes(c.cfg.hair);
  const dy = tall ? -4 : 0;
  const crown = `M70.4 ${48 + dy} C69 ${26 + dy} 84 ${15 + dy} 100 ${15 + dy} C116 ${15 + dy} 131 ${26 + dy} 129.6 ${48 + dy} Q100 ${41 + dy} 70.4 ${48 + dy}Z`;
  const brim = `M69 ${47 + dy} Q100 ${38 + dy} 131 ${47 + dy} Q134 ${51 + dy} 128 ${53 + dy} Q100 ${47 + dy} 72 ${53 + dy} Q66 ${51 + dy} 69 ${47 + dy}Z`;
  return (
    <g>
      <path d={crown} fill={col} />
      <path d={crown} fill={c.url('shadeH')} />
      <path d={`M100 ${15.5 + dy} L100 ${42.5 + dy} M85 ${18.5 + dy} Q80 ${30 + dy} 82 ${44 + dy} M115 ${18.5 + dy} Q120 ${30 + dy} 118 ${44 + dy}`} stroke={shade(col, 0.35)} strokeWidth="0.8" fill="none" />
      <circle cx="100" cy={15.6 + dy} r="1.6" fill={shade(col, 0.3)} />
      <path d={brim} fill={shade(col, 0.15)} />
      <path d={`M72 ${51.5 + dy} Q100 ${45 + dy} 128 ${51.5 + dy}`} stroke={light(col, 0.4)} strokeWidth="0.8" fill="none" opacity="0.7" />
      <path d={`M90 ${30 + dy} q10 -4 20 0 q-10 6 -20 0Z`} fill={light(col, 0.75)} opacity="0.9" />
      <text x="100" y={33.2 + dy} fontSize="4.2" fontWeight="900" fontFamily="Arial Black, Arial, sans-serif" textAnchor="middle" fill={shade(col, 0.4)}>BC</text>
    </g>
  );
}

function earrings(c: Ctx): ReactNode {
  if (!c.b.female) return null;
  const { gold } = beadDefs(c);
  return (
    <g>
      {[70.6, 129.4].map((x) => (
        <g key={x}>
          <circle cx={x} cy={77.5} r={5.2} fill="none" stroke="#7a521c" strokeWidth="2" />
          <circle cx={x} cy={77.5} r={5.2} fill="none" stroke="#efc04e" strokeWidth="1.3" />
          <circle cx={x} cy={72.4} r={1.4} fill={gold} />
        </g>
      ))}
    </g>
  );
}

export function accessoriesHead(c: Ctx): ReactNode {
  const out: ReactNode[] = [];
  if (c.has('earrings')) out.push(<g key="e">{earrings(c)}</g>);
  if (c.has('sunglasses')) out.push(<g key="s">{sunglasses(c)}</g>);
  if (c.has('cap') && c.cfg.hair !== 'gele') out.push(<g key="c">{cap(c)}</g>);
  return out.length ? <g>{out}</g> : null;
}
