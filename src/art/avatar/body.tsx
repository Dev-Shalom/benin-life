// Skin layers: legs, torso, arms, hands, neck, head base, ears.
import type { ReactNode } from 'react';
import type { Ctx } from './ctx';
import { CX, limb, mirrorJoints, smoothClosed, handGeom, r1, type P } from './geometry';
import { mix } from './color';

export const HEAD_TOP = 23.5;
export const CHIN_Y = 91.5;

/** Head silhouette (no hair). */
export function headPath(c: Ctx): string {
  const F = c.b.female;
  const left: P[] = F
    ? [[88.5, 25], [79, 31], [73.4, 42], [72, 55], [73, 66], [76.5, 75.5], [82.5, 83.5], [90.5, 89]]
    : [[88, 25], [78.5, 31], [72.8, 42], [71.4, 55], [72.2, 66], [75.4, 76], [81.5, 84.5], [90, 90]];
  const bottom: P = [CX, F ? 90.8 : 91.6];
  const right = left.map(([x, y]) => [200 - x, y] as P).reverse();
  return smoothClosed([[CX, HEAD_TOP], ...left, bottom, ...right]);
}

export function headHalfW(c: Ctx) {
  return c.b.female ? 28 : 28.6;
}

export function legs(c: Ctx, opts: { feet?: boolean } = {}): ReactNode {
  if (c.portrait) return null;
  const s = c.skin;
  const L = c.b.leg;
  const R = mirrorJoints(L);
  return (
    <g>
      {[L, R].map((leg, i) => (
        <g key={i}>
          <path d={limb(leg, { end: 'round' })} fill={c.url('skinL')} />
          {/* knee crease + shin highlight */}
          <path d={`M${r1(leg[2].x - 3.5)} ${r1(leg[2].y + 1)} q3.5 2.5 7 0`} stroke={s.shadow} strokeWidth="0.9" fill="none" opacity="0.6" strokeLinecap="round" />
          <path d={`M${r1(leg[3].x - 2.5)} ${r1(leg[3].y - 4)} L${r1(leg[4].x - 1.5)} ${r1(leg[4].y - 10)}`} stroke={s.highlight} strokeWidth="1.6" opacity="0.35" strokeLinecap="round" />
          {opts.feet && foot(c, i === 0 ? 1 : -1)}
        </g>
      ))}
    </g>
  );
}

/** Bare foot (front view), used under sandals. */
export function foot(c: Ctx, side: number): ReactNode {
  const a = c.b.leg[c.b.leg.length - 1];
  const x = a.x;
  const left: P[] = [
    [x + 5.2, 364], [x - 5.2, 364], [x - 7.6, 377], [x - 7.4, 385.6], [x - 2, 387.6],
    [x + 5.4, 386.6], [x + 6.4, 379],
  ];
  const pts = side === 1 ? left : left.map(([px, py]) => [200 - px, py] as P).reverse();
  const xs = side === 1 ? x : 200 - x;
  const out = -side;
  return (
    <g>
      <path d={smoothClosed(pts)} fill={c.url('skinL')} />
      {[0, 1, 2, 3].map((k) => (
        <path key={k} d={`M${r1(xs + out * (5.2 - k * 2.6))} ${r1(383.6 + Math.abs(k - 1) * 0.5)} v3`} stroke={c.skin.shadow} strokeWidth="0.7" opacity="0.7" />
      ))}
    </g>
  );
}

export function torso(c: Ctx, opts: { chest?: boolean } = {}): ReactNode {
  const b = c.b;
  const s = c.skin;
  const left: P[] = [
    [CX - b.nw - 1, 99.5], [CX - b.sh + 7, 106.5], [CX - b.sh + 1.2, 111], [CX - b.sh, 118],
    [CX - b.sh + 2.5, 131], [CX - b.ch, 143], [CX - b.wa - b.belly * 0.4, 177], [CX - b.hi, 207], [CX - b.hi + 1, 228],
  ];
  const right = left.map(([x, y]) => [200 - x, y] as P).reverse();
  const d = smoothClosed([[CX, 99], ...left, [CX, 237], ...right]);
  return (
    <g>
      <path d={d} fill={c.url('skinT')} />
      {opts.chest && (
        <g fill="none" strokeLinecap="round">
          {/* collarbones */}
          <path d={`M${CX - 4} 106.5 q-9 -1.5 -18 1.5`} stroke={s.shadow} strokeWidth="1" opacity="0.55" />
          <path d={`M${CX + 4} 106.5 q9 -1.5 18 1.5`} stroke={s.shadow} strokeWidth="1" opacity="0.55" />
          <path d={`M${CX - 3} 104 q-8 -2 -16 1`} stroke={s.highlight} strokeWidth="1.2" opacity="0.35" />
          {/* pecs */}
          <path d={`M${CX - b.ch + 6} 138 q10 7 ${b.ch - 7} 1.5`} stroke={s.shadow} strokeWidth="1.5" opacity="0.5" />
          <path d={`M${CX + b.ch - 6} 138 q-10 7 ${-(b.ch - 7)} 1.5`} stroke={s.shadow} strokeWidth="1.5" opacity="0.6" />
          <ellipse cx={CX - b.ch * 0.52} cy={127} rx={b.ch * 0.3} ry={5} fill={s.highlight} opacity="0.22" />
          <path d={`M${CX} 145 v22`} stroke={s.shadow} strokeWidth="1" opacity="0.35" />
          <path d={`M${CX - 1.2} 168.5 q1.2 1.6 2.4 0`} stroke={s.deep} strokeWidth="1.1" opacity="0.6" />
        </g>
      )}
    </g>
  );
}

/** Arms. 'under' = full arm drawn beneath the torso (smooth shoulders);
 *  'over' = from below the armpit down, drawn above the top garment. */
export function arms(c: Ctx, layer: 'under' | 'over' = 'under'): ReactNode {
  if (c.portrait && layer === 'over') return null;
  const L = c.b.arm;
  const R = mirrorJoints(L);
  const from = layer === 'over' ? 0.24 : 0;
  return (
    <g>
      {[L, R].map((arm, i) => (
        <g key={i}>
          <path d={limb(arm, { from, start: from ? 'flat' : 'round', end: 'round' })} fill={c.url('skinL')} />
          {layer === 'over' && <path d={`M${r1(arm[2].x + (i ? -1 : 1) * 1.5)} ${r1(arm[2].y - 1)} q${i ? -1.5 : 1.5} 2 0 4`} stroke={c.skin.shadow} strokeWidth="0.8" fill="none" opacity="0.5" />}
        </g>
      ))}
    </g>
  );
}

/** Hand at the end of an arm. side 1 = viewer's left. */
export function handPath(c: Ctx, side: number): { d: string; thumb: string; lines: string } {
  const { wrist, dir } = handGeom(c.b, side);
  const n: P = [-dir[1], dir[0]];
  const tb: P = [-n[0] * side, -n[1] * side]; // toward body
  const hw = c.b.handW;
  const len = c.b.handLen;
  const at = (u: number, v: number): P => [wrist.x + dir[0] * u + tb[0] * v, wrist.y + dir[1] * u + tb[1] * v];
  const outline = [
    at(-2, -hw * 0.85), at(len * 0.3, -hw * 1.08), at(len * 0.66, -hw * 1.0), at(len * 0.9, -hw * 0.62),
    at(len, -hw * 0.05), at(len * 0.94, hw * 0.55), at(len * 0.66, hw * 0.92), at(len * 0.3, hw * 1.0), at(-2, hw * 0.85),
  ];
  const thumbPts = [at(len * 0.18, hw * 0.55), at(len * 0.42, hw * 1.25), at(len * 0.66, hw * 0.98), at(len * 0.6, hw * 0.4), at(len * 0.36, hw * 0.25)];
  const l1 = [at(len * 0.62, -hw * 0.3), at(len * 0.95, -hw * 0.25)];
  const l2 = [at(len * 0.6, hw * 0.12), at(len * 0.92, hw * 0.2)];
  const ln = (a: P[]) => `M${r1(a[0][0])} ${r1(a[0][1])} L${r1(a[1][0])} ${r1(a[1][1])}`;
  return { d: smoothClosed(outline), thumb: smoothClosed(thumbPts), lines: ln(l1) + ' ' + ln(l2) };
}

export function hands(c: Ctx): ReactNode {
  if (c.portrait) return null;
  const s = c.skin;
  return (
    <g>
      {[1, -1].map((side) => {
        const h = handPath(c, side);
        return (
          <g key={side}>
            <path d={h.d} fill={c.url('skinL')} />
            <path d={h.thumb} fill={mix(s.base, s.highlight, 0.25)} stroke={s.shadow} strokeWidth="0.6" strokeOpacity="0.6" />
            <path d={h.lines} stroke={s.shadow} strokeWidth="0.7" opacity="0.65" strokeLinecap="round" />
          </g>
        );
      })}
    </g>
  );
}

export function neck(c: Ctx): ReactNode {
  const nw = c.b.nw;
  const s = c.skin;
  const left: P[] = [[CX - nw + 0.5, 76], [CX - nw, 92], [CX - nw - 1.5, 101], [CX - nw - 6, 106]];
  const right = left.map(([x, y]) => [200 - x, y] as P).reverse();
  const d = smoothClosed([...left, [CX, 109], ...right], 0.8);
  return (
    <g>
      <path d={d} fill={c.url('skinT')} />
      {/* chin cast shadow (coloured, not black) */}
      <path d={`M${CX - nw - 0.5} 84 Q${CX} 99 ${CX + nw + 0.5} 84 L${CX + nw + 0.5} 80 Q${CX} 90 ${CX - nw - 0.5} 80Z`} fill={s.shadow} opacity="0.55" />
      <path d={`M${CX - 3} 99 q3 2.5 6 0`} stroke={s.shadow} strokeWidth="0.9" fill="none" opacity="0.5" />
      {!c.b.female && <path d={`M${CX - 1.5} 93 q1.5 2.5 3 0`} stroke={s.shadow} strokeWidth="0.8" fill="none" opacity="0.4" />}
    </g>
  );
}

export function ears(c: Ctx): ReactNode {
  const s = c.skin;
  const hw = headHalfW(c);
  return (
    <g>
      {[1, -1].map((side) => {
        const x0 = CX - side * (hw - 1.5);
        const o = -side;
        const pts: P[] = [[x0, 54.5], [x0 + o * 4.2, 54], [x0 + o * 5.6, 59], [x0 + o * 4.5, 66], [x0 + o * 1.5, 71.5], [x0 - o * 0.8, 68]];
        return (
          <g key={side}>
            <path d={smoothClosed(pts)} fill={side === 1 ? mix(s.base, s.highlight, 0.2) : s.shadow} />
            <path d={`M${r1(x0 + o * 1)} 58 q${o * 3.4} 0.6 ${o * 2.6} 6 q${-o * 0.6} 2.5 ${-o * 2} 3`} stroke={s.deep} strokeWidth="1.1" fill="none" opacity="0.55" strokeLinecap="round" />
          </g>
        );
      })}
    </g>
  );
}

export function head(c: Ctx): ReactNode {
  const s = c.skin;
  return (
    <g>
      <path d={headPath(c)} fill={c.url('skinFace')} />
      {/* jaw shadow */}
      <path d={`M${CX + 18} 80 Q${CX + 8} 91 ${CX} 91.5 Q${CX + 14} 89 ${CX + 22} 74Z`} fill={s.shadow} opacity="0.35" />
      {/* forehead sheen */}
      <ellipse cx={CX - 7} cy={41} rx={9} ry={5} fill={s.highlight} opacity="0.32" />
    </g>
  );
}
