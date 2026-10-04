// Outfits — each returns layered pieces that Avatar.tsx interleaves with the body.
import type { ReactNode } from 'react';
import type { Ctx } from './ctx';
import { fab } from './ctx';
import { CX, limb, mirrorJoints, r1, sideAt, smoothOpen, smoothClosed, type Joint, type P } from './geometry';
import { accentFor, deepOf, light, luma, mix, shade } from './color';
import { coralRows } from './accessories';
import { foot } from './body';

export interface OutfitLayers {
  back?: ReactNode;
  lower?: ReactNode;
  shoes?: ReactNode;
  upper?: ReactNode;
  collar?: ReactNode;
  sleeves?: ReactNode;
  overHands?: ReactNode;
  head?: ReactNode;
  bareChest?: boolean;
  bareFeet?: boolean;
  hideLegs?: boolean;
}

// ------------------------------------------------------------------ geometry helpers

const armOf = (c: Ctx, side: number): Joint[] => (side === 1 ? c.b.arm : mirrorJoints(c.b.arm));
const legOf = (c: Ctx, side: number): Joint[] => (side === 1 ? c.b.leg : mirrorJoints(c.b.leg));
const mirrorP = (pts: P[]): P[] => pts.map(([x, y]) => [200 - x, y] as P).reverse();
const pp = (p: P) => `${r1(p[0])} ${r1(p[1])}`;

interface TopOpts {
  hem: number;
  pad?: number;
  loose?: number; // 0..1, 1 = falls straight from the shoulders
  flare?: number; // extra half-width gained by the hem
  neck?: 'crew' | 'v' | 'scoop' | 'high' | 'off';
  nd?: number; // neck depth
  nwx?: number; // neck opening beyond neck half-width
  hemCurve?: number;
  tuck?: number; // pull in at the waist (fitted)
}

function widthAt(c: Ctx, y: number, o: TopOpts): number {
  let w = sideAt(c.b, y);
  if (o.loose) w += (Math.max(c.b.sh - 1, w) - w) * o.loose;
  if (o.flare && y > 165) w += (o.flare * (y - 165)) / Math.max(1, o.hem - 165);
  if (o.tuck && y > 150 && y < 200) w -= o.tuck * Math.sin(((y - 150) / 50) * Math.PI);
  return w + (o.pad ?? 2.4);
}

/** Torso garment outline (shoulders → hem) with a neckline. */
function topPath(c: Ctx, o: TopOpts): string {
  const b = c.b;
  const pad = o.pad ?? 2.4;
  const nwx = b.nw + (o.nwx ?? 2.2);
  const yN = o.neck === 'high' ? 97 : 100.2;
  const left: P[] = [[CX - nwx, yN], [CX - b.sh + 6 - pad * 0.3, 106.2], [CX - b.sh - pad * 0.55, 112.6]];
  for (const y of [124, 138, 152, 166, 180, 194, 208, 224, 242, 262, 284, 306, 330, 352]) {
    if (y >= o.hem - 5) break;
    left.push([CX - widthAt(c, y, o), y]);
  }
  const hemL: P = [CX - widthAt(c, o.hem, o), o.hem];
  left.push(hemL);
  const right = mirrorP(left);
  const nd = o.nd ?? 4;
  let d = `M${pp(left[0])}` + smoothOpen(left);
  d += ` Q${CX} ${r1(o.hem + (o.hemCurve ?? 2) * 2)} ${pp(right[0])}`;
  d += smoothOpen(right);
  if (o.neck === 'v') d += ` L${CX} ${r1(yN + nd)}Z`;
  else d += ` Q${CX} ${r1(yN + nd * 2)} ${pp(left[0])}Z`;
  return d;
}

function sleevePair(c: Ctx, o: { to: number; pad?: number; flare?: number; end?: 'curve' | 'flat' }, fill: string, cuff?: string): ReactNode {
  return (
    <g>
      {[1, -1].map((side) => {
        const arm = armOf(c, side);
        const d = limb(arm, { from: 0.035, to: o.to, pad: o.pad ?? 2.2, flare: o.flare ?? 0, start: 'round', end: o.end ?? 'curve' });
        const end = limb(arm, { from: o.to - 0.05, to: o.to, pad: (o.pad ?? 2.2) + (o.flare ?? 0) + 0.3, start: 'flat', end: o.end ?? 'curve' });
        return (
          <g key={side}>
            {fab(c, d, fill)}
            {cuff && <path d={end} fill={cuff} />}
            {/* elbow / armpit fold */}
            <path d={`M${r1(arm[1].x + side * 3)} ${r1(arm[1].y - 6)} q${side * 2} 5 ${side * 1} 10`} stroke={shade(c.oc, 0.5)} strokeWidth="0.8" fill="none" opacity="0.35" />
          </g>
        );
      })}
    </g>
  );
}

function pantsPath(c: Ctx, side: number, o: { pad?: number; flare?: number; to?: number }): string {
  return limb(legOf(c, side), { from: 0, to: o.to ?? 0.975, pad: o.pad ?? 2.2, flare: o.flare ?? 0, start: 'round', end: 'flat' });
}

function hipsPath(c: Ctx, top: number, pad: number): string {
  const b = c.b;
  const left: P[] = [[CX - sideAt(b, top) - pad, top], [CX - b.hi - pad, b.hipY], [CX - b.hi - pad + 0.8, 226]];
  const d = `M${pp(left[0])}` + smoothOpen(left) + ` Q${CX - 8} 236 ${CX} 238 Q${CX + 8} 236 ${r1(200 - left[2][0])} ${r1(left[2][1])}` + smoothOpen(mirrorP(left)) + 'Z';
  return d;
}

function trousers(c: Ctx, fill: string, o: { pad?: number; flare?: number; top?: number; crease?: boolean; to?: number } = {}): ReactNode {
  const pad = o.pad ?? 2.2;
  return (
    <g>
      {[1, -1].map((s) => <g key={s}>{fab(c, pantsPath(c, s, o), fill)}</g>)}
      {fab(c, hipsPath(c, o.top ?? c.b.waistY - 2, pad + 0.4), fill)}
      {o.crease !== false && [1, -1].map((s) => {
        const L = legOf(c, s);
        return <path key={'cr' + s} d={`M${r1(L[0].x + s * 2)} 236 L${r1(L[2].x + s * 0.8)} 300 L${r1(L[4].x)} 364`} stroke={light(fill.startsWith('#') ? fill : '#888888', 0.3)} strokeWidth="0.7" opacity="0.35" fill="none" />;
      })}
      <path d={`M${CX} 214 L${CX} 236`} stroke={shade(fill.startsWith('#') ? fill : '#666666', 0.5)} strokeWidth="0.8" opacity="0.5" />
    </g>
  );
}

/** Skirt / wrapper from `top` to `hem` (half-width at hem). */
function skirtPath(c: Ctx, top: number, hem: number, hemHalf: number, pad = 2.4): string {
  const b = c.b;
  const left: P[] = [[CX - sideAt(b, top) - pad, top]];
  if (top < b.hipY - 6) left.push([CX - b.hi - pad, b.hipY]);
  left.push([CX - Math.max(b.hi + pad, hemHalf) + 0.5, Math.min(hem - 8, (b.hipY + hem) / 2 + 10)]);
  left.push([CX - hemHalf, hem]);
  const right = mirrorP(left);
  return `M${pp(left[0])}` + smoothOpen(left) + ` Q${CX} ${hem + 3} ${pp(right[0])}` + smoothOpen(right) + ` Q${CX} ${top + 2} ${pp(left[0])}Z`;
}

function belt(c: Ctx, y: number, col: string, buckle = '#d9b45a', pad = 2.8): ReactNode {
  const w = sideAt(c.b, y) + pad;
  return (
    <g>
      <path d={`M${CX - w} ${y - 2.4} Q${CX} ${y - 0.6} ${CX + w} ${y - 2.4} L${CX + w} ${y + 2.2} Q${CX} ${y + 4} ${CX - w} ${y + 2.2}Z`} fill={col} />
      <rect x={CX - 3.6} y={y - 2.2} width={7.2} height={5.6} rx={1} fill="none" stroke={buckle} strokeWidth="1.3" />
    </g>
  );
}

// ------------------------------------------------------------------ fabrics / patterns

function ankaraPattern(c: Ctx, base: string, name = 'ankara'): string {
  const acc = accentFor(base);
  const deep = deepOf(base);
  const cream = '#f7ead0';
  return c.def(name, (id) => (
    <pattern id={id} width="16" height="16" patternUnits="userSpaceOnUse" patternTransform="rotate(-8)">
      <rect width="16" height="16" fill={base} />
      <path d="M0 0 L4 0 L0 4Z M16 0 L12 0 L16 4Z M0 16 L4 16 L0 12Z M16 16 L12 16 L16 12Z" fill={deep} />
      <circle cx="8" cy="8" r="5.6" fill={acc} />
      <circle cx="8" cy="8" r="4.2" fill={deep} />
      <circle cx="8" cy="8" r="2.8" fill={cream} />
      <circle cx="8" cy="8" r="1.3" fill={base} />
      <path d="M8 0.4 L9.2 2 L8 3.6 L6.8 2Z M8 12.4 L9.2 14 L8 15.6 L6.8 14Z M0.4 8 L2 6.8 L3.6 8 L2 9.2Z M12.4 8 L14 6.8 L15.6 8 L14 9.2Z" fill={cream} />
      <circle cx="0" cy="8" r="0.7" fill={acc} />
      <circle cx="16" cy="8" r="0.7" fill={acc} />
    </pattern>
  ));
}

function wrapperPattern(c: Ctx, base: string, name = 'wrapP'): string {
  const acc = accentFor(base);
  const deep = deepOf(base);
  return c.def(name, (id) => (
    <pattern id={id} width="14" height="12" patternUnits="userSpaceOnUse">
      <rect width="14" height="12" fill={base} />
      <path d="M0 3 L3.5 0 L7 3 L10.5 0 L14 3" stroke={acc} strokeWidth="1.3" fill="none" />
      <path d="M0 9 L3.5 6 L7 9 L10.5 6 L14 9" stroke={deep} strokeWidth="1.6" fill="none" />
      <circle cx="3.5" cy="4.6" r="0.8" fill="#f7ead0" />
      <circle cx="10.5" cy="10.6" r="0.8" fill="#f7ead0" />
    </pattern>
  ));
}

function denim(c: Ctx, base: string, name = 'denim'): string {
  return c.def(name, (id) => (
    <pattern id={id} width="3" height="3" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
      <rect width="3" height="3" fill={base} />
      <path d="M0 0.75 H3" stroke={light(base, 0.25)} strokeWidth="0.6" opacity="0.6" />
      <path d="M0 2.2 H3" stroke={shade(base, 0.2)} strokeWidth="0.5" opacity="0.5" />
    </pattern>
  ));
}

function lace(c: Ctx, base: string): string {
  return c.def('lace', (id) => (
    <pattern id={id} width="7" height="7" patternUnits="userSpaceOnUse">
      <rect width="7" height="7" fill={base} />
      <circle cx="3.5" cy="3.5" r="1.6" fill="none" stroke={shade(base, 0.18)} strokeWidth="0.5" />
      <circle cx="3.5" cy="3.5" r="0.5" fill={shade(base, 0.2)} />
      <circle cx="0" cy="0" r="0.9" fill="none" stroke={shade(base, 0.15)} strokeWidth="0.4" />
      <circle cx="7" cy="7" r="0.9" fill="none" stroke={shade(base, 0.15)} strokeWidth="0.4" />
    </pattern>
  ));
}

function embroidery(c: Ctx, col: string): string {
  return c.def('embr', (id) => (
    <pattern id={id} width="5" height="5" patternUnits="userSpaceOnUse">
      <path d="M2.5 0.4 L4.6 2.5 L2.5 4.6 L0.4 2.5Z" fill="none" stroke={col} strokeWidth="0.7" />
      <circle cx="2.5" cy="2.5" r="0.7" fill={col} />
    </pattern>
  ));
}

/** Fabric fold lines: dark crease + soft light edge. */
function folds(paths: string[], base: string, o = 0.4): ReactNode {
  return (
    <g fill="none" strokeLinecap="round">
      {paths.map((d, i) => (
        <g key={i}>
          <path d={d} stroke={shade(base, 0.55)} strokeWidth="1.1" opacity={o} />
          <path d={d} stroke={light(base, 0.5)} strokeWidth="0.8" opacity={o * 0.7} transform="translate(-1.1 0.2)" />
        </g>
      ))}
    </g>
  );
}

// ------------------------------------------------------------------ shoes

type ShoeStyle = 'sneaker' | 'chunky' | 'loafer' | 'boot' | 'heel' | 'clog' | 'sandal' | 'slipper';

function shoe(c: Ctx, side: number, style: ShoeStyle, col: string, accent: string): ReactNode {
  const L = legOf(c, side);
  const x = L[4].x;
  const out = side === 1 ? -1 : 1; // outward direction (x)
  const X = (dx: number) => x + dx * -out; // dx authored for left foot (+ = inward)
  const big = style === 'chunky' ? 1.15 : 1;
  const upperPts: P[] = [
    [X(5.6 * big), 362], [X(-5.6 * big), 362], [X(-8.6 * big), 373.5], [X(-9.4 * big), 382.5],
    [X(-4.5 * big), 386.2], [X(3.6 * big), 386.2], [X(7.4 * big), 382], [X(7.6 * big), 371],
  ];
  const sole = `M${r1(X(-10 * big))} 382.4 Q${r1(X(-10.4 * big))} 388.6 ${r1(X(-4 * big))} 388.8 L${r1(X(4 * big))} 388.8 Q${r1(X(8.6 * big))} 388.6 ${r1(X(8.2 * big))} 382 Z`;
  const upper = smoothClosed(upperPts, 0.85);
  switch (style) {
    case 'sneaker':
    case 'chunky':
      return (
        <g key={side}>
          {fab(c, upper, col)}
          <path d={`M${r1(X(-8.6 * big))} 378 Q${r1(X(-2))} 371 ${r1(X(6.6 * big))} 373 Q${r1(X(0))} 376 ${r1(X(-8 * big))} 381Z`} fill={accent} />
          <path d={`M${r1(X(-3))} 366 L${r1(X(3))} 366 M${r1(X(-3.2))} 368.6 L${r1(X(3.2))} 368.6 M${r1(X(-3.4))} 371.2 L${r1(X(3.4))} 371.2`} stroke={shade(col, 0.4)} strokeWidth="0.9" />
          <path d={sole} fill={style === 'chunky' ? '#f6f2ea' : '#ece7de'} />
          <path d={sole} fill={c.url('shadeH')} />
          {style === 'chunky' && <path d={`M${r1(X(-9.6 * big))} 385.4 L${r1(X(8 * big))} 385.4`} stroke={accent} strokeWidth="1.2" />}
        </g>
      );
    case 'loafer':
    case 'heel': {
      const low: P[] = style === 'heel'
        ? [[X(5), 374], [X(-6), 373.5], [X(-8.6), 380], [X(-7), 386.2], [X(-1), 388.4], [X(4), 386.8], [X(7.2), 380.5]]
        : [[X(6), 369], [X(-6.4), 368.6], [X(-9), 376], [X(-9.4), 383.2], [X(-4.5), 387.6], [X(3.6), 387.6], [X(7.6), 383], [X(7.8), 374]];
      const d = smoothClosed(low, 0.85);
      return (
        <g key={side}>
          {style === 'heel' && foot(c, side)}
          {fab(c, d, col)}
          <ellipse cx={X(-3)} cy={style === 'heel' ? 378.5 : 375} rx="3" ry="1.4" fill="#ffffff" opacity="0.35" />
          {style === 'loafer' && <path d={`M${r1(X(-5))} 371.5 Q${r1(X(0))} 374 ${r1(X(5))} 371.5`} stroke={light(col, 0.3)} strokeWidth="0.9" fill="none" />}
          {style === 'loafer' && <path d={`M${r1(X(-9.6))} 384.5 Q${r1(X(-4))} 389.5 ${r1(X(8))} 384`} stroke={shade(col, 0.5)} strokeWidth="1.4" fill="none" />}
        </g>
      );
    }
    case 'boot': {
      const shaft = limb(L, { from: 0.86, to: 1, pad: 2.2, start: 'flat', end: 'flat' });
      return (
        <g key={side}>
          {fab(c, shaft, col)}
          {fab(c, upper, col)}
          <path d={sole} fill="#141218" />
          <path d={`M${r1(X(-2.6))} 352 L${r1(X(2.6))} 352 M${r1(X(-2.8))} 356 L${r1(X(2.8))} 356 M${r1(X(-3))} 360 L${r1(X(3))} 360 M${r1(X(-3.2))} 364 L${r1(X(3.2))} 364`} stroke="#5a5866" strokeWidth="0.8" />
          <ellipse cx={X(-4)} cy={377} rx="2.6" ry="1.4" fill="#ffffff" opacity="0.3" />
        </g>
      );
    }
    case 'clog':
      return (
        <g key={side}>
          {fab(c, upper, col)}
          <path d={sole} fill={shade(col, 0.15)} />
          {[[-3, 377], [1, 377], [-1, 381], [3, 381], [-5, 381]].map(([dx, y], i) => <circle key={i} cx={X(dx)} cy={y} r="0.9" fill={shade(col, 0.4)} />)}
        </g>
      );
    case 'sandal':
    case 'slipper':
    default:
      return (
        <g key={side}>
          <path d={`M${r1(X(-9))} 386.2 Q${r1(X(-9.6))} 389.4 ${r1(X(-3))} 389.4 L${r1(X(4))} 389.4 Q${r1(X(8.6))} 389 ${r1(X(7.8))} 385.6Z`} fill={shade(col, 0.3)} />
          {foot(c, side)}
          {style === 'slipper'
            ? <path d={`M${r1(X(-7.4))} 374 Q${r1(X(0))} 371 ${r1(X(6.6))} 373.4 L${r1(X(7))} 379.4 Q${r1(X(0))} 377 ${r1(X(-8))} 380.6Z`} fill={col} />
            : <g>
              <path d={`M${r1(X(-7))} 376 Q${r1(X(0))} 373.4 ${r1(X(6.4))} 375.4`} stroke={col} strokeWidth="2.4" fill="none" />
              <path d={`M${r1(X(-5))} 366.6 Q${r1(X(0))} 368.6 ${r1(X(5))} 366.6`} stroke={accent} strokeWidth="1.8" strokeDasharray="1.6 0.6" fill="none" />
            </g>}
        </g>
      );
  }
}

function shoes(c: Ctx, style: ShoeStyle, col: string, accent = '#d2342a'): ReactNode {
  return <g>{shoe(c, 1, style, col, accent)}{shoe(c, -1, style, col, accent)}</g>;
}

// ------------------------------------------------------------------ collars

function shirtCollar(c: Ctx, col: string, spread = 1): ReactNode {
  const nw = c.b.nw;
  const l = `M${CX - 1} 104.5 L${CX - nw - 4.5 * spread} 99 L${CX - nw - 2} 95.6 L${CX - nw + 2} 97 Z`;
  const r = `M${CX + 1} 104.5 L${CX + nw + 4.5 * spread} 99 L${CX + nw + 2} 95.6 L${CX + nw - 2} 97 Z`;
  return (
    <g>
      <path d={`M${CX - nw - 2} 96 Q${CX} 92.4 ${CX + nw + 2} 96 L${CX + nw} 99.5 Q${CX} 97 ${CX - nw} 99.5Z`} fill={shade(col, 0.25)} />
      <path d={l} fill={light(col, 0.08)} stroke={shade(col, 0.35)} strokeWidth="0.6" />
      <path d={r} fill={shade(col, 0.1)} stroke={shade(col, 0.4)} strokeWidth="0.6" />
    </g>
  );
}

function mandarin(c: Ctx, col: string, trim?: string): ReactNode {
  const nw = c.b.nw;
  return (
    <g>
      <path d={`M${CX - nw - 1.6} 95.4 Q${CX} 98 ${CX + nw + 1.6} 95.4 L${CX + nw + 2.2} 100.6 Q${CX} 104.6 ${CX - nw - 2.2} 100.6Z`} fill={col} />
      <path d={`M${CX - nw - 1.6} 95.4 Q${CX} 98 ${CX + nw + 1.6} 95.4 L${CX + nw + 2.2} 100.6 Q${CX} 104.6 ${CX - nw - 2.2} 100.6Z`} fill={c.url('shadeH')} />
      {trim && <path d={`M${CX - nw - 2} 99.6 Q${CX} 103.4 ${CX + nw + 2} 99.6`} stroke={trim} strokeWidth="0.9" fill="none" />}
    </g>
  );
}

// ------------------------------------------------------------------ outfits

export function outfit(c: Ctx): OutfitLayers {
  switch (c.cfg.outfit) {
    case 'bini_traditional': return c.b.female ? biniFemale(c) : biniMale(c);
    case 'agbada': return agbada(c);
    case 'senator': return senator(c);
    case 'student': return student(c);
    case 'keke_rider': return keke(c);
    case 'market_woman': return marketWoman(c);
    case 'corporate': return corporate(c);
    case 'yahoo_drip': return drip(c);
    case 'nurse': return nurse(c);
    case 'police': return police(c);
    case 'hoodie': return hoodie(c);
    case 'ankara':
    default:
      return ankara(c);
  }
}

const WHITE_CLOTH = '#f3eee4';

function biniMale(c: Ctx): OutfitLayers {
  const b = c.b;
  const trim = luma(c.oc) > 0.85 ? '#d2342a' : c.oc;
  const top = b.waistY - 6;
  const hemHalf = b.hi + 9;
  const wrap = skirtPath(c, top, 372, hemHalf, 3.4);
  const lw = sideAt(b, top) + 3.4;
  return {
    bareChest: true,
    bareFeet: true,
    hideLegs: true,
    shoes: <g>{shoes(c, 'sandal', '#6b3a1f', '#d2342a')}</g>,
    lower: (
      <g>
        {fab(c, wrap, WHITE_CLOTH)}
        {/* overlapping front edge with border stripe */}
        <path d={`M${CX + 10} ${top + 3} Q${CX + 6} 260 ${CX + 14} 373`} stroke={trim} strokeWidth="2.6" fill="none" />
        <path d={`M${CX + 12.4} ${top + 3} Q${CX + 8.4} 260 ${CX + 16.4} 373`} stroke={shade(WHITE_CLOTH, 0.35)} strokeWidth="1.2" fill="none" opacity="0.6" />
        <path d={`M${CX - hemHalf + 1} 366 Q${CX} 373 ${CX + hemHalf - 1} 366`} stroke={trim} strokeWidth="2.2" fill="none" />
        {folds([`M${CX - 14} ${top + 12} Q${CX - 17} 280 ${CX - 22} 360`, `M${CX - 2} ${top + 18} Q${CX - 3} 280 ${CX - 6} 362`, `M${CX + 22} ${top + 14} Q${CX + 24} 290 ${CX + 26} 360`], WHITE_CLOTH, 0.5)}
        {/* rolled waist band + knot */}
        <path d={`M${CX - lw} ${top - 1} Q${CX} ${top + 4} ${CX + lw} ${top - 1} L${CX + lw} ${top + 5} Q${CX} ${top + 10} ${CX - lw} ${top + 5}Z`} fill={light(WHITE_CLOTH, 0.3)} />
        <path d={`M${CX - lw} ${top + 5} Q${CX} ${top + 10} ${CX + lw} ${top + 5}`} stroke={shade(WHITE_CLOTH, 0.4)} strokeWidth="1" fill="none" />
        <path d={`M${CX + 6} ${top + 3} q5 -2 8 2 q-2 6 -8 5 q-3 -4 0 -7Z`} fill={WHITE_CLOTH} stroke={shade(WHITE_CLOTH, 0.4)} strokeWidth="0.8" />
      </g>
    ),
    collar: coralRows(c, [
      { rx: b.nw + 3, ry: 7.4, y0: 98.4, r: 2.1, goldEvery: 6 },
      { rx: b.nw + 7.2, ry: 13, y0: 98.4, r: 2.3, goldEvery: 0 },
      { rx: b.nw + 11.4, ry: 19, y0: 98.2, r: 2.4, goldEvery: 8 },
      { rx: b.nw + 15.6, ry: 25.5, y0: 98, r: 2.5, goldEvery: 0 },
    ]),
    overHands: wristBeads(c),
  };
}

function wristBeads(c: Ctx): ReactNode {
  const out: ReactNode[] = [];
  for (const side of [1, -1]) {
    const arm = armOf(c, side);
    const w = arm[arm.length - 1];
    const e = arm[arm.length - 2];
    const L = Math.hypot(w.x - e.x, w.y - e.y);
    const dx = (w.x - e.x) / L;
    const dy = (w.y - e.y) / L;
    for (let k = 0; k < 2; k++) {
      const cx = w.x - dx * (3 + k * 3.2);
      const cy = w.y - dy * (3 + k * 3.2);
      for (let i = -2; i <= 2; i++) {
        out.push(<circle key={`${side}${k}${i}`} cx={r1(cx + i * 2.1 * dy * -1 + i * 0.0)} cy={r1(cy + i * 2.1 * dx + Math.abs(i) * -0.3)} r="1.25" fill={c.url('coralB')} />);
      }
    }
  }
  return <g>{out}</g>;
}

function biniFemale(c: Ctx): OutfitLayers {
  const b = c.b;
  const wrapCol = luma(c.oc) > 0.85 ? '#d2342a' : c.oc;
  const blouse = WHITE_CLOTH;
  const wrap = skirtPath(c, b.waistY - 4, 374, b.hi + 7, 3);
  const top2 = skirtPath(c, b.waistY - 6, 268, b.hi + 9, 3.6);
  return {
    hideLegs: true,
    shoes: shoes(c, 'heel', '#c99a3a'),
    lower: (
      <g>
        {fab(c, wrap, wrapperPattern(c, wrapCol))}
        {folds([`M${CX - 8} 270 Q${CX - 10} 320 ${CX - 14} 370`, `M${CX + 12} 270 Q${CX + 13} 320 ${CX + 18} 370`], wrapCol, 0.5)}
        {fab(c, top2, shade(wrapCol, 0.05))}
        <path d={top2} fill={embroidery(c, '#f1c766')} opacity="0.45" />
        <path d={`M${CX - b.hi - 8} 262 Q${CX} 272 ${CX + b.hi + 8} 262`} stroke="#f1c766" strokeWidth="1.6" fill="none" />
        <path d={`M${CX + 6} ${b.waistY - 2} Q${CX + 2} 230 ${CX + 9} 268`} stroke={light(wrapCol, 0.4)} strokeWidth="1.4" fill="none" />
      </g>
    ),
    upper: (
      <g>
        {fab(c, topPath(c, { hem: b.waistY + 2, pad: 2.6, neck: 'scoop', nd: 6, nwx: 4 }), lace(c, blouse))}
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.34, pad: 3.6, flare: 1.8 }, lace(c, blouse)),
    collar: coralRows(c, [
      { rx: b.nw + 3, ry: 7, y0: 98.4, r: 1.9 },
      { rx: b.nw + 6.8, ry: 11.5, y0: 98.6, r: 1.9, goldEvery: 5 },
      { rx: b.nw + 10.6, ry: 16, y0: 99, r: 1.9 },
      { rx: b.nw + 14.4, ry: 20.5, y0: 99.4, r: 1.9, goldEvery: 5 },
      { rx: b.nw + 18.2, ry: 25, y0: 100, r: 1.9 },
      { rx: b.nw + 22, ry: 29.5, y0: 100.6, r: 1.9, goldEvery: 4 },
    ], true),
    overHands: wristBeads(c),
  };
}

function agbada(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const col = c.oc;
  const gold = luma(col) > 0.7 ? '#b8862c' : '#f0c766';
  const hem = F ? 374 : 326;
  const spread = b.sh + 30 + b.t * 2;
  const left: P[] = [
    [CX - b.nw - 2.5, 100], [CX - b.sh + 5, 106.5], [CX - b.sh - 3, 114], [CX - b.sh - 12, 140],
    [CX - spread + 4, 184], [CX - spread, 222], [CX - spread + 7, 236], [CX - b.hi - 10, 262], [CX - b.hi - (F ? 12 : 9), hem],
  ];
  const right = mirrorP(left);
  const robe = `M${pp(left[0])}` + smoothOpen(left) + ` Q${CX} ${hem + 4} ${pp(right[0])}` + smoothOpen(right) + ` Q${CX} 108 ${pp(left[0])}Z`;
  const inner = topPath(c, { hem: F ? 372 : 300, pad: 3, loose: 0.3, neck: 'crew' });
  const emb = `M${CX - b.nw - 3} 101 Q${CX - 16} 132 ${CX - 10} 160 L${CX} 170 L${CX + 10} 160 Q${CX + 16} 132 ${CX + b.nw + 3} 101 Q${CX} 110 ${CX - b.nw - 3} 101Z`;
  return {
    hideLegs: F,
    lower: F ? undefined : trousers(c, shade(col, 0.08), { pad: 2.6, crease: false }),
    shoes: shoes(c, F ? 'heel' : 'loafer', F ? '#c99a3a' : '#3a2418'),
    upper: <g>{fab(c, inner, light(col, 0.12))}</g>,
    overHands: undefined,
    sleeves: (
      <g>
        {fab(c, robe, col)}
        {folds([
          `M${CX - b.sh - 4} 116 Q${CX - b.sh - 14} 170 ${CX - spread + 6} 218`,
          `M${CX - b.sh + 2} 124 Q${CX - b.sh - 6} 190 ${CX - spread + 14} 232`,
          `M${CX + b.sh + 4} 116 Q${CX + b.sh + 14} 170 ${CX + spread - 6} 218`,
          `M${CX + b.sh - 2} 124 Q${CX + b.sh + 6} 190 ${CX + spread - 14} 232`,
          `M${CX - b.hi - 2} 250 Q${CX - b.hi} 290 ${CX - b.hi - 4} ${hem - 4}`,
          `M${CX + b.hi + 2} 250 Q${CX + b.hi} 290 ${CX + b.hi + 4} ${hem - 4}`,
        ], col, 0.55)}
        <path d={emb} fill={embroidery(c, gold)} />
        <path d={emb} fill="none" stroke={gold} strokeWidth="1.3" />
        <path d={`M${CX - 7} 150 Q${CX} 156 ${CX + 7} 150`} stroke={gold} strokeWidth="1" fill="none" />
        <path d={`M${CX - spread + 7} 236 Q${CX - b.hi - 14} 244 ${CX - b.hi - 10} 262`} stroke={shade(col, 0.5)} strokeWidth="1.2" fill="none" opacity="0.6" />
        <path d={`M${CX + spread - 7} 236 Q${CX + b.hi + 14} 244 ${CX + b.hi + 10} 262`} stroke={shade(col, 0.5)} strokeWidth="1.2" fill="none" opacity="0.6" />
        {/* sleeve openings where the hands come out */}
        {[1, -1].map((s) => {
          const w = armOf(c, s)[4];
          return <ellipse key={s} cx={w.x} cy={w.y - 1} rx="7" ry="3" fill={shade(col, 0.45)} />;
        })}
      </g>
    ),
  };
}

function senator(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const col = c.oc;
  const trim = luma(col) > 0.7 ? shade(col, 0.45) : light(col, 0.45);
  const hem = F ? 372 : 268;
  const tunic = topPath(c, { hem, pad: 2.8, loose: F ? 0 : 0.35, flare: F ? 14 : 2, neck: 'crew', nd: 3, tuck: F ? 2 : 0 });
  return {
    hideLegs: F,
    lower: F ? undefined : trousers(c, col, { pad: 2.4 }),
    shoes: shoes(c, F ? 'heel' : 'loafer', F ? '#2a2230' : '#2b1c16'),
    upper: (
      <g>
        {fab(c, tunic, col)}
        <path d={`M${CX + 5} 103 L${CX + 5} 150`} stroke={trim} strokeWidth="1.1" />
        <path d={`M${CX + 2.5} 104 L${CX + 2.5} 150 M${CX + 7.5} 104 L${CX + 7.5} 150`} stroke={trim} strokeWidth="0.5" strokeDasharray="1.2 1" />
        {[110, 120, 130, 140].map((y) => <circle key={y} cx={CX + 5} cy={y} r="0.9" fill={trim} />)}
        <path d={`M${CX - 20} 118 L${CX - 9} 118 L${CX - 9} 124 L${CX - 20} 124Z`} fill="none" stroke={trim} strokeWidth="0.6" opacity="0.7" />
        {!F && <path d={`M${CX - sideAt(b, hem) - 4} ${hem - 14} l1 13 M${CX + sideAt(b, hem) + 4} ${hem - 14} l-1 13`} stroke={shade(col, 0.5)} strokeWidth="0.9" opacity="0.6" />}
        {folds([`M${CX - 12} 190 Q${CX - 14} ${hem - 30} ${CX - 16} ${hem - 4}`, `M${CX + 14} 196 Q${CX + 15} ${hem - 30} ${CX + 18} ${hem - 4}`], col, 0.35)}
      </g>
    ),
    collar: mandarin(c, col, trim),
    sleeves: sleevePair(c, { to: 0.96, pad: 2.4, flare: 0.6 }, col, shade(col, 0.12)),
  };
}

function ankara(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const print = ankaraPattern(c, c.oc);
  if (F) {
    const bodice = topPath(c, { hem: b.waistY + 4, pad: 2.2, neck: 'scoop', nd: 5, nwx: 4 });
    const skirt = skirtPath(c, b.waistY - 2, 290, b.hi + 16, 2.6);
    return {
      shoes: shoes(c, 'heel', '#c99a3a'),
      lower: (
        <g>
          {fab(c, skirt, print)}
          {folds([`M${CX - 10} 214 Q${CX - 14} 250 ${CX - 22} 288`, `M${CX + 4} 216 Q${CX + 6} 250 ${CX + 8} 290`, `M${CX + 16} 214 Q${CX + 22} 250 ${CX + 30} 286`], c.oc, 0.6)}
        </g>
      ),
      upper: (
        <g>
          {fab(c, bodice, print)}
          {belt(c, b.waistY, deepOf(c.oc), accentFor(c.oc), 2.6)}
        </g>
      ),
      sleeves: sleevePair(c, { to: 0.3, pad: 4.4, flare: 1.5 }, print),
    };
  }
  const shirt = topPath(c, { hem: 214, pad: 3, loose: 0.25, neck: 'v', nd: 6, nwx: 2 });
  const pants = '#2b2a35';
  return {
    lower: trousers(c, pants),
    shoes: shoes(c, 'loafer', '#3a2418'),
    upper: (
      <g>
        {fab(c, shirt, print)}
        <path d={`M${CX} 106 L${CX} 214`} stroke={shade(c.oc, 0.5)} strokeWidth="1" />
        {[118, 134, 150, 166, 182, 198].map((y) => <circle key={y} cx={CX + 1.8} cy={y} r="1" fill="#f7ead0" stroke={shade(c.oc, 0.5)} strokeWidth="0.4" />)}
        <path d={`M${CX - 22} 126 L${CX - 9} 126 L${CX - 9} 138 Q${CX - 15.5} 141 ${CX - 22} 138Z`} fill={print} stroke={shade(c.oc, 0.5)} strokeWidth="0.6" />
      </g>
    ),
    collar: shirtCollar(c, c.oc),
    sleeves: sleevePair(c, { to: 0.36, pad: 3.2, flare: 1.2 }, print),
  };
}

function student(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const col = c.oc;
  const jeans = denim(c, '#3d5a8c');
  const top = F
    ? topPath(c, { hem: 206, pad: 2, neck: 'crew', nd: 3.5, tuck: 1 })
    : topPath(c, { hem: 212, pad: 2.8, loose: 0.2, neck: 'crew', nd: 2 });
  const strap = '#2f3340';
  return {
    back: c.portrait ? undefined : <path d={`M${CX - b.sh + 2} 112 Q${CX} 100 ${CX + b.sh - 2} 112 L${CX + b.sh} 128 L${CX - b.sh} 128Z`} fill={shade('#4a5568', 0.2)} />,
    lower: trousers(c, jeans, { pad: F ? 1.6 : 2.4 }),
    shoes: shoes(c, 'sneaker', '#f3f0ea', col === '#f4f1ea' ? '#2346a8' : col),
    upper: (
      <g>
        {fab(c, top, col)}
        {!F && <path d={`M${CX - 2.5} 100 L${CX - 2.5} 118 L${CX + 2.5} 118 L${CX + 2.5} 100`} fill="none" stroke={shade(col, 0.4)} strokeWidth="0.8" />}
        {!F && [106, 113].map((y) => <circle key={y} cx={CX} cy={y} r="0.9" fill={shade(col, 0.3)} />)}
        {F && <text x={CX} y="152" fontSize="7" fontWeight="900" fontFamily="Arial Black, Arial, sans-serif" textAnchor="middle" fill={luma(col) > 0.6 ? '#2346a8' : '#f7ead0'} opacity="0.92">UNIBEN</text>}
        {/* backpack straps */}
        {[1, -1].map((s) => (
          <g key={s}>
            <path d={`M${CX - s * (b.nw + 7)} 103 Q${CX - s * (b.sh - 6)} 140 ${CX - s * (b.ch - 3)} 178`} stroke={strap} strokeWidth="5" fill="none" strokeLinecap="round" />
            <path d={`M${CX - s * (b.nw + 7)} 103 Q${CX - s * (b.sh - 6)} 140 ${CX - s * (b.ch - 3)} 178`} stroke="#59607a" strokeWidth="1" fill="none" opacity="0.6" transform={`translate(${-s} 0)`} />
            <rect x={CX - s * (b.sh - 8.5) - 3.2} y="142" width="6.4" height="4" rx="1" fill="#9aa3b8" />
          </g>
        ))}
      </g>
    ),
    collar: F ? undefined : shirtCollar(c, col, 0.8),
    sleeves: sleevePair(c, { to: F ? 0.28 : 0.34, pad: F ? 2 : 2.8, flare: 1 }, col, shade(col, 0.15)),
  };
}

function keke(c: Ctx): OutfitLayers {
  const b = c.b;
  const col = c.oc;
  const vest = '#d5ec2c';
  const tee = topPath(c, { hem: 212, pad: 2.6, loose: 0.2, neck: 'crew', nd: 3 });
  const v = topPath(c, { hem: 206, pad: 3.6, loose: 0.25, neck: 'v', nd: 26, nwx: 5 });
  const cargo = '#7a6e4e';
  return {
    lower: (
      <g>
        {trousers(c, cargo, { pad: 3, crease: false })}
        {[1, -1].map((s) => {
          const L = legOf(c, s);
          return <rect key={s} x={L[1].x - 6} y={262} width="12" height="14" rx="2" fill={shade(cargo, 0.15)} stroke={shade(cargo, 0.4)} strokeWidth="0.6" />;
        })}
      </g>
    ),
    shoes: shoes(c, 'slipper', '#2d63c8'),
    upper: (
      <g>
        {fab(c, tee, col)}
        {fab(c, v, vest)}
        {[150, 172].map((y) => (
          <g key={y}>
            <path d={`M${CX - sideAt(b, y) - 3.6} ${y} L${CX - 8} ${y} M${CX + 8} ${y} L${CX + sideAt(b, y) + 3.6} ${y}`} stroke="#c9ccd6" strokeWidth="3.4" />
            <path d={`M${CX - sideAt(b, y) - 3.6} ${y - 0.8} L${CX - 8} ${y - 0.8} M${CX + 8} ${y - 0.8} L${CX + sideAt(b, y) + 3.6} ${y - 0.8}`} stroke="#ffffff" strokeWidth="1" opacity="0.8" />
          </g>
        ))}
        <text x={CX - 17} y="138" fontSize="4.6" fontWeight="900" fontFamily="Arial Black, Arial, sans-serif" textAnchor="middle" fill="#2a3a14">KEKE</text>
        <rect x={CX + 10} y="131" width="12" height="7" rx="1" fill="#f7f4ea" stroke="#2a3a14" strokeWidth="0.5" />
        <text x={CX + 16} y="136.4" fontSize="4" fontWeight="700" fontFamily="Arial, sans-serif" textAnchor="middle" fill="#2a3a14">027</text>
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.33, pad: 2.8, flare: 1 }, col, shade(col, 0.15)),
  };
}

function marketWoman(c: Ctx): OutfitLayers {
  const b = c.b;
  const col = c.oc;
  const wrapBase = luma(col) > 0.5 ? '#1f5f8b' : '#d9a128';
  const blouse = topPath(c, { hem: b.waistY + 14, pad: 3.2, loose: 0.3, neck: 'scoop', nd: 4, nwx: 3 });
  const wrap = skirtPath(c, b.waistY - 2, 372, b.hi + 8, 3.4);
  const scarfCol = luma(col) > 0.5 ? '#d2342a' : '#f0c766';
  const noScarf = ['gele'].includes(c.cfg.hair);
  return {
    hideLegs: true,
    shoes: shoes(c, 'slipper', '#d2342a'),
    lower: (
      <g>
        {fab(c, wrap, wrapperPattern(c, wrapBase))}
        <path d={`M${CX - 10} ${b.waistY} Q${CX - 6} 280 ${CX - 12} 372`} stroke={shade(wrapBase, 0.5)} strokeWidth="1.4" fill="none" />
        {folds([`M${CX + 12} 230 Q${CX + 14} 300 ${CX + 20} 368`, `M${CX - 22} 240 Q${CX - 24} 300 ${CX - 26} 366`], wrapBase, 0.5)}
      </g>
    ),
    upper: (
      <g>
        {fab(c, blouse, ankaraPattern(c, col, 'mwP'))}
        {/* money pouch (akpo) at the waist */}
        <path d={`M${CX - 16} ${b.waistY + 8} L${CX + 4} ${b.waistY + 8} L${CX + 2} ${b.waistY + 26} Q${CX - 6} ${b.waistY + 30} ${CX - 14} ${b.waistY + 26}Z`} fill="#3f6f3a" stroke="#244222" strokeWidth="0.7" />
        <path d={`M${CX - 15} ${b.waistY + 14} L${CX + 3} ${b.waistY + 14}`} stroke="#244222" strokeWidth="0.7" />
        <path d={`M${CX - sideAt(b, b.waistY + 8) - 3} ${b.waistY + 7} Q${CX} ${b.waistY + 11} ${CX + sideAt(b, b.waistY + 8) + 3} ${b.waistY + 7}`} stroke="#244222" strokeWidth="1.4" fill="none" />
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.36, pad: 3.8, flare: 1.6 }, ankaraPattern(c, col, 'mwP')),
    head: noScarf ? undefined : (
      <g>
        <path d="M70.6 46 C70 28 84 18.5 100 18.5 C116 18.5 130 28 129.4 46 C120 40 110 38 100 38.4 C90 38 80 40 70.6 46Z" fill={scarfCol} />
        <path d="M70.6 46 C70 28 84 18.5 100 18.5 C116 18.5 130 28 129.4 46 C120 40 110 38 100 38.4 C90 38 80 40 70.6 46Z" fill={c.url('shadeH')} />
        <path d="M78 30 Q100 24 122 30 M74 38 Q100 30 126 38" stroke={shade(scarfCol, 0.35)} strokeWidth="0.9" fill="none" opacity="0.7" />
        <path d="M112 20 q8 -6 14 -2 q-3 6 -10 6Z M112 20 q2 -8 9 -9 q1 6 -5 10Z" fill={scarfCol} stroke={shade(scarfCol, 0.4)} strokeWidth="0.7" />
      </g>
    ),
  };
}

function corporate(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const col = c.oc;
  const suit = luma(col) > 0.85 ? '#2b3550' : luma(col) < 0.15 ? '#25232c' : mix(col, '#1d2233', 0.62);
  const shirt = F ? light(col, luma(col) > 0.85 ? 0 : 0.78) : '#f6f6f2';
  const tie = luma(col) < 0.15 ? '#a8242a' : col;
  const jHem = F ? 210 : 226;
  const inner = topPath(c, { hem: jHem - 4, pad: 2, neck: F ? 'v' : 'high', nd: F ? 10 : 2 });
  const jacket = topPath(c, { hem: jHem, pad: 3.2, loose: F ? 0 : 0.25, neck: 'v', nd: F ? 30 : 46, nwx: 3.5, tuck: F ? 2.4 : 0.6, hemCurve: 1 });
  const lapel = (s: number) => `M${CX - s * (b.nw + 3.5)} 100.4 L${CX - s * (b.nw + 7)} 108 L${CX - s * (b.nw + 4)} 113 L${CX - s * 3} ${F ? 130 : 146} L${CX - s * 0.4} ${F ? 130 : 146} Z`;
  return {
    lower: F
      ? fab(c, skirtPath(c, b.waistY - 2, 286, b.hi + 3, 2.2), suit)
      : trousers(c, suit, { pad: 2.6 }),
    shoes: shoes(c, F ? 'heel' : 'loafer', F ? '#1d1a24' : '#1f1a1e'),
    upper: (
      <g>
        {fab(c, inner, shirt)}
        {!F && (
          <g>
            <path d={`M${CX - 3} 103 L${CX + 3} 103 L${CX + 2.4} 107 L${CX - 2.4} 107Z`} fill={shade(tie, 0.15)} />
            <path d={`M${CX - 2.4} 107 L${CX + 2.4} 107 L${CX + 4.4} 140 L${CX} 145 L${CX - 4.4} 140Z`} fill={tie} />
            <path d={`M${CX - 1.6} 112 L${CX + 3} 118 M${CX - 3} 124 L${CX + 3.6} 131`} stroke={light(tie, 0.4)} strokeWidth="1" opacity="0.6" />
          </g>
        )}
        {fab(c, jacket, suit)}
        {[1, -1].map((s) => <path key={s} d={lapel(s)} fill={shade(suit, 0.12)} stroke={light(suit, 0.25)} strokeWidth="0.5" />)}
        <circle cx={CX + 2.4} cy={F ? 150 : 166} r="1.3" fill={light(suit, 0.35)} />
        {!F && <circle cx={CX + 2.4} cy={184} r="1.3" fill={light(suit, 0.35)} />}
        <path d={`M${CX + b.ch - 14} 128 l9 -1`} stroke={light(suit, 0.3)} strokeWidth="1" />
        <path d={`M${CX + b.ch - 13} 127.4 l2 -3.4 l2 3`} fill="#f6f6f2" />
        {!F && <path d={`M${CX - b.wa - 2} 196 l11 0 M${CX + b.wa + 2} 196 l-11 0`} stroke={shade(suit, 0.45)} strokeWidth="0.9" />}
      </g>
    ),
    collar: F ? undefined : shirtCollar(c, shirt, 0.7),
    sleeves: sleevePair(c, { to: 0.94, pad: 2.6, flare: 0.4 }, suit, F ? undefined : shirt),
  };
}

function drip(c: Ctx): OutfitLayers {
  const b = c.b;
  const F = b.female;
  const col = c.oc;
  const ink = luma(col) > 0.6 ? '#1d1a24' : '#f7f3ea';
  const hem = F ? 196 : 228;
  const tee = topPath(c, { hem, pad: 6, loose: 0.75, neck: 'crew', nd: 3, nwx: 1.6 });
  const jeans = denim(c, '#8fb0d6', 'denimL');
  const goldTxt = c.def('dripTxt', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stopColor="#fff1a6" />
      <stop offset="0.5" stopColor="#f0b93a" />
      <stop offset="1" stopColor="#b8762a" />
    </linearGradient>
  ));
  const rips = (side: number) => {
    const L = legOf(c, side);
    return (
      <g key={side}>
        <path d={`M${L[2].x - 5} 295 q5 -3 10 0 q-5 6 -10 0Z`} fill={c.url('skinL')} />
        <path d={`M${L[2].x - 6} 292 h12 M${L[2].x - 5} 299 h10 M${L[1].x - 4} 256 h8 M${L[1].x - 3.5} 259 h7`} stroke="#f1f4f8" strokeWidth="0.9" />
      </g>
    );
  };
  return {
    lower: (
      <g>
        {trousers(c, jeans, { pad: F ? 1.4 : 1.8, crease: false, top: F ? b.waistY - 6 : undefined })}
        {[1, -1].map(rips)}
      </g>
    ),
    shoes: shoes(c, 'chunky', '#f7f4ee', col === '#f4f1ea' ? '#d2342a' : col),
    upper: (
      <g>
        {fab(c, tee, col)}
        {folds([`M${CX - b.sh - 2} 130 Q${CX - b.sh + 4} 170 ${CX - b.sh} ${hem - 4}`, `M${CX + b.sh + 2} 132 Q${CX + b.sh - 4} 172 ${CX + b.sh} ${hem - 4}`], col, 0.45)}
        <text x={CX} y="145" fontSize="7" fontWeight="900" fontFamily="Arial Black, Impact, Arial, sans-serif" textAnchor="middle" textLength="30" lengthAdjust="spacingAndGlyphs" fill={goldTxt} stroke={shade('#b8762a', 0.4)} strokeWidth="0.3">B-CITY</text>
        <text x={CX} y="151" fontSize="2.9" fontWeight="700" fontFamily="Arial, sans-serif" textAnchor="middle" textLength="20" lengthAdjust="spacingAndGlyphs" fill={ink}>EDO · 1440</text>
        <path d={`M${CX - 6} 131 l6 -5 6 5 -6 5Z`} fill="none" stroke={goldTxt} strokeWidth="1.2" />
        <path d={`M${CX - 2.6} 131 l2.6 -2.2 2.6 2.2 -2.6 2.2Z`} fill={goldTxt} />
        {F && <path d={`M${CX + 10} ${hem - 4} q6 6 2 12 q-4 -4 -6 -2 q2 -6 4 -10Z`} fill={shade(col, 0.15)} />}
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.48, pad: 5.4, flare: 2 }, col),
  };
}

function nurse(c: Ctx): OutfitLayers {
  const b = c.b;
  const col = luma(c.oc) < 0.15 ? '#2a5c8f' : c.oc;
  const top = topPath(c, { hem: 214, pad: 3, loose: 0.3, neck: 'v', nd: 15, nwx: 2.4 });
  return {
    lower: trousers(c, shade(col, 0.06), { pad: 3.2, crease: false }),
    shoes: shoes(c, 'clog', '#f2f0ec'),
    upper: (
      <g>
        {fab(c, top, col)}
        <path d={`M${CX + 9} 128 L${CX + 22} 128 L${CX + 22} 142 L${CX + 9} 142Z`} fill={shade(col, 0.08)} stroke={shade(col, 0.4)} strokeWidth="0.6" />
        <rect x={CX + 12} y="122" width="1.6" height="9" rx="0.6" fill="#2b3a8f" />
        <rect x={CX + 15.5} y="123" width="1.6" height="8" rx="0.6" fill="#d2342a" />
        <path d={`M${CX - 22} 186 L${CX - 8} 186 L${CX - 8} 202 L${CX - 22} 202Z M${CX + 8} 186 L${CX + 22} 186 L${CX + 22} 202 L${CX + 8} 202Z`} fill="none" stroke={shade(col, 0.4)} strokeWidth="0.6" />
        <rect x={CX - 22} y="126" width="11" height="6" rx="1" fill="#f7f4ea" />
        <path d={`M${CX - 20} 129 h7`} stroke="#2346a8" strokeWidth="0.8" />
      </g>
    ),
    collar: (
      <g fill="none" strokeLinecap="round">
        {/* stethoscope */}
        <path d={`M${CX - b.nw - 1} 97 Q${CX - b.nw - 8} 128 ${CX - 6} 140`} stroke="#4a4f5c" strokeWidth="2" />
        <path d={`M${CX + b.nw + 1} 97 Q${CX + b.nw + 6} 120 ${CX + 9} 120`} stroke="#4a4f5c" strokeWidth="2" />
        <circle cx={CX - 4.6} cy={143} r="3.4" fill="#c9ccd6" stroke="#6a6f7c" strokeWidth="1" />
        <circle cx={CX - 5.4} cy={142} r="1" fill="#ffffff" opacity="0.8" />
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.33, pad: 3, flare: 1.2 }, col),
  };
}

function police(c: Ctx): OutfitLayers {
  const b = c.b;
  const shirt = '#262b38';
  const pants = '#1f232e';
  const top = topPath(c, { hem: 214, pad: 2.6, loose: 0.15, neck: 'v', nd: 7, nwx: 2 });
  const stripe = luma(c.oc) > 0.85 || luma(c.oc) < 0.15 ? '#d9a128' : c.oc;
  return {
    lower: (
      <g>
        {trousers(c, pants, { pad: 2.6 })}
      </g>
    ),
    shoes: shoes(c, 'boot', '#1b1a20'),
    upper: (
      <g>
        {fab(c, top, shirt)}
        {[1, -1].map((s) => (
          <g key={s}>
            <path d={`M${CX - s * 22} 124 L${CX - s * 9} 124 L${CX - s * 9} 141 L${CX - s * 22} 141Z`} fill="none" stroke="#404759" strokeWidth="0.8" />
            <path d={`M${CX - s * 22.6} 122 L${CX - s * 8.4} 122 L${CX - s * 8.4} 128 L${CX - s * 15.5} 130 L${CX - s * 22.6} 128Z`} fill="#30364a" stroke="#4a5266" strokeWidth="0.6" />
            {/* epaulette */}
            <path d={`M${CX - s * (b.nw + 4)} 103 L${CX - s * (b.sh - 1)} 109.6 L${CX - s * (b.sh - 2)} 114 L${CX - s * (b.nw + 3)} 107.4Z`} fill="#1a1d27" stroke="#4a5266" strokeWidth="0.5" />
            <path d={`M${CX - s * (b.nw + 9)} 106.2 L${CX - s * (b.nw + 12)} 107.6`} stroke={stripe} strokeWidth="1.6" />
          </g>
        ))}
        <path d={`M${CX + 15.5} 116 l1.6 3.4 3.7 0.4 -2.8 2.4 0.9 3.6 -3.4 -2 -3.4 2 0.9 -3.6 -2.8 -2.4 3.7 -0.4Z`} fill="#e3b94e" stroke="#8a6a20" strokeWidth="0.4" />
        <rect x={CX - 22} y="145" width="12" height="3.6" rx="0.6" fill="#e9e6dc" />
        {[118, 134, 150, 166, 182, 198].map((y) => <circle key={y} cx={CX} cy={y} r="0.9" fill="#8a91a6" />)}
        <path d={`M${CX} 106 L${CX} 214`} stroke="#141721" strokeWidth="0.8" />
        {belt(c, 210, '#141721', '#c9ccd6', 3)}
        <text x={CX - 16} y="164" fontSize="5" fontWeight="900" fontFamily="Arial Black, Arial, sans-serif" textAnchor="middle" fill="#c9ccd6" opacity="0.85">POLICE</text>
      </g>
    ),
    collar: shirtCollar(c, shirt, 0.9),
    sleeves: sleevePair(c, { to: 0.35, pad: 2.8, flare: 0.8 }, shirt, '#1a1d27'),
  };
}

function hoodie(c: Ctx): OutfitLayers {
  const b = c.b;
  const col = c.oc;
  const body = topPath(c, { hem: 222, pad: 4, loose: 0.45, neck: 'crew', nd: 4, nwx: 2.6 });
  const jog = '#3a3b46';
  const band = (y: number) => `M${CX - widthAt(c, y, { hem: 222, pad: 4, loose: 0.45 })} ${y - 6} Q${CX} ${y - 3.6} ${CX + widthAt(c, y, { hem: 222, pad: 4, loose: 0.45 })} ${y - 6} L${CX + widthAt(c, y, { hem: 222, pad: 4, loose: 0.45 })} ${y} Q${CX} ${y + 2.4} ${CX - widthAt(c, y, { hem: 222, pad: 4, loose: 0.45 })} ${y}Z`;
  return {
    back: <path d={`M${CX - b.nw - 12} 108 Q${CX - b.nw - 14} 90 ${CX} 88 Q${CX + b.nw + 14} 90 ${CX + b.nw + 12} 108Z`} fill={shade(col, 0.35)} />,
    lower: (
      <g>
        {trousers(c, jog, { pad: 3.2, crease: false, to: 0.96 })}
        {[1, -1].map((s) => {
          const L = legOf(c, s);
          return <path key={s} d={limb(L, { from: 0.9, to: 0.975, pad: 1.4, start: 'flat', end: 'flat' })} fill={shade(jog, 0.25)} />;
        })}
        {[1, -1].map((s) => <path key={'st' + s} d={`M${CX - s * (b.hi + 3)} 214 L${legOf(c, s)[4].x - s * 6} 360`} stroke="#f2f0ea" strokeWidth="1.1" opacity="0.7" />)}
      </g>
    ),
    shoes: shoes(c, 'sneaker', '#f3f0ea', '#1d1a24'),
    upper: (
      <g>
        {fab(c, body, col)}
        <path d={band(222)} fill={shade(col, 0.15)} />
        <path d={`M${CX - 20} 186 L${CX + 20} 186 L${CX + 26} 214 L${CX - 26} 214Z`} fill={shade(col, 0.06)} stroke={shade(col, 0.4)} strokeWidth="0.8" />
        <path d={`M${CX - 20} 186 L${CX - 26} 214 M${CX + 20} 186 L${CX + 26} 214`} stroke={light(col, 0.3)} strokeWidth="0.6" opacity="0.5" />
        {folds([`M${CX - b.sh + 4} 140 Q${CX - b.sh + 8} 170 ${CX - b.sh + 6} 200`, `M${CX + b.sh - 4} 142 Q${CX + b.sh - 8} 172 ${CX + b.sh - 6} 200`], col, 0.4)}
      </g>
    ),
    collar: (
      <g>
        <path d={`M${CX - b.nw - 7} 104 Q${CX - b.nw - 6} 95 ${CX} 96 Q${CX + b.nw + 6} 95 ${CX + b.nw + 7} 104 Q${CX} 112 ${CX - b.nw - 7} 104Z`} fill={shade(col, 0.1)} />
        <path d={`M${CX - b.nw - 7} 104 Q${CX} 112 ${CX + b.nw + 7} 104`} stroke={shade(col, 0.45)} strokeWidth="1.2" fill="none" />
        <path d={`M${CX - 4} 107 L${CX - 5} 128 M${CX + 4} 107 L${CX + 5} 126`} stroke="#f2f0ea" strokeWidth="1.2" strokeLinecap="round" />
        <circle cx={CX - 5} cy={129} r="1.2" fill="#c9ccd6" />
        <circle cx={CX + 5} cy={127} r="1.2" fill="#c9ccd6" />
      </g>
    ),
    sleeves: sleevePair(c, { to: 0.97, pad: 3.4, flare: 0.6 }, col, shade(col, 0.2)),
  };
}
