// Hairstyles. Each style has an optional back layer (behind head/body) and a front layer.
import type { ReactNode } from 'react';
import type { Ctx } from './ctx';
import { CX, chainAt, r1, smoothClosed, smoothOpen, type P } from './geometry';
import { luma, mix, shade, light } from './color';

const sym = (left: P[]): P[] => left.map(([x, y]) => [200 - x, y] as P).reverse();

function tones(c: Ctx) {
  const h = c.hair;
  const dark = luma(h) < 0.2;
  return {
    base: h,
    dark: shade(h, 0.45),
    deep: mix(shade(h, 0.6), '#0d0812', 0.3),
    mid: dark ? mix(h, '#5a4a66', 0.25) : light(h, 0.12),
    sheen: dark ? mix(h, '#b9c4ea', 0.34) : light(h, 0.45),
    spec: dark ? mix(h, '#e6ecff', 0.55) : light(h, 0.7),
    scalp: mix(c.skin.shadow, h, 0.35),
  };
}

/** Close-crop hair cap following the skull with a hairline. v = volume above the skull. */
function capPath(c: Ctx, v: number, o: { hl?: number; sb?: number; temple?: number } = {}): string {
  const F = c.b.female;
  const hl = o.hl ?? (F ? 37.5 : 38.6);
  const sb = o.sb ?? (F ? 57 : 63);
  const tp = o.temple ?? 0;
  const outerL: P[] = [
    [72.9, sb], [71.2 - v * 0.7, 52], [72.4 - v, 40.5], [78 - v * 0.85, 29.8 - v * 0.55], [88.2 - v * 0.35, 23.9 - v],
  ];
  const top: P = [CX, 22.4 - v];
  const innerR: P[] = [
    [127.1 - 2.6, sb - 1], [125.4, 50 + tp], [121.8 - tp, 44.2], [112.6, 39.6], [CX, hl], [87.4, 39.6],
    [78.2 + tp, 44.2], [74.6, 50 + tp], [72.9 + 2.6, sb - 1],
  ];
  return smoothClosed([...outerL, top, ...sym(outerL), ...innerR], 0.9);
}

function defsFor(c: Ctx) {
  const t = tones(c);
  c.def('hairStip', (id) => (
    <pattern id={id} width="2.4" height="2.4" patternUnits="userSpaceOnUse">
      <circle cx="1.2" cy="1.2" r="0.5" fill={t.sheen} opacity="0.45" />
    </pattern>
  ));
  c.def('hairCurl', (id) => (
    <pattern id={id} width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(25)">
      <path d="M0.5 2.5 q1.2 -2 2.4 0 q1.2 2 2.4 0" stroke={t.sheen} strokeWidth="0.55" fill="none" opacity="0.55" />
      <circle cx="1.6" cy="4.4" r="0.45" fill={t.deep} opacity="0.5" />
    </pattern>
  ));
  c.def('hairSheenV', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="0.3">
      <stop offset="0" stopColor={t.sheen} stopOpacity="0.0" />
      <stop offset="0.25" stopColor={t.sheen} stopOpacity="0.55" />
      <stop offset="0.42" stopColor={t.sheen} stopOpacity="0.05" />
      <stop offset="0.75" stopColor={t.deep} stopOpacity="0.15" />
      <stop offset="1" stopColor={t.deep} stopOpacity="0.5" />
    </linearGradient>
  ));
  return t;
}

/** Bumpy (afro) outline points around an ellipse, from angle a0 to a1 (degrees, 0 = right, -90 = up). */
function puffPts(cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, n: number, amp: number): P[] {
  const pts: P[] = [];
  for (let i = 0; i <= n; i++) {
    const a = ((a0 + ((a1 - a0) * i) / n) * Math.PI) / 180;
    const k = 1 + (i % 2 ? amp : -amp * 0.3);
    pts.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]);
  }
  return pts;
}

/** Rope-like strand (locs / braids / twists) with diagonal texture ticks. */
function rope(pts: P[], t: ReturnType<typeof tones>, w: number, key: string | number, gap = 3.4, taper = true, cuff?: string): ReactNode {
  const d = braidD(pts);
  const ch = pts.map(([x, y]) => ({ x, y, w }));
  const len = pts.slice(1).reduce((a, p, i) => a + Math.hypot(p[0] - pts[i][0], p[1] - pts[i][1]), 0);
  const n = Math.max(2, Math.floor(len / gap));
  let ticks = '';
  for (let k = 1; k < n; k++) {
    const a = chainAt(ch, (k - 0.5) / n);
    const b = chainAt(ch, (k + 0.5) / n);
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const L = Math.hypot(dx, dy) || 1;
    const nx = -dy / L;
    const ny = dx / L;
    const p = chainAt(ch, k / n);
    const ww = w * 0.42;
    ticks += `M${r1(p.x - nx * ww - (dx / L) * 1.1)} ${r1(p.y - ny * ww - (dy / L) * 1.1)} L${r1(p.x + nx * ww + (dx / L) * 0.9)} ${r1(p.y + ny * ww + (dy / L) * 0.9)} `;
  }
  const last = pts[pts.length - 1];
  return (
    <g key={key} fill="none" strokeLinecap="round">
      <path d={d} stroke={t.deep} strokeWidth={w + 1.4} />
      <path d={d} stroke={t.base} strokeWidth={w} />
      <path d={ticks} stroke={t.deep} strokeWidth={Math.max(0.7, w * 0.16)} opacity="0.7" />
      <path d={ticks} stroke={t.sheen} strokeWidth={Math.max(0.6, w * 0.12)} opacity="0.75" transform="translate(-0.5 -0.6)" />
      {taper && !cuff && <circle cx={last[0]} cy={last[1]} r={w * 0.38} fill={t.mid} />}
      {cuff && (
        <g>
          {/* loose tuft below the cuff */}
          <path d={`M${r1(last[0] - w * 0.42)} ${r1(last[1] + 1.4)} Q${r1(last[0] - w * 0.2)} ${r1(last[1] + 6)} ${r1(last[0] + w * 0.1)} ${r1(last[1] + 6.8)} Q${r1(last[0] + w * 0.25)} ${r1(last[1] + 4.6)} ${r1(last[0] + w * 0.42)} ${r1(last[1] + 1.4)}Z`} fill={t.base} stroke={t.deep} strokeWidth="0.5" />
          {/* metal cuff wrapped around the braid end */}
          <rect x={r1(last[0] - w * 0.66)} y={r1(last[1] - 2.6)} width={r1(w * 1.32)} height="4.2" rx="1.5" fill={cuff} stroke={shade(cuff, 0.5)} strokeWidth="0.45" />
          <path d={`M${r1(last[0] - w * 0.44)} ${r1(last[1] - 1.6)} h${r1(w * 0.5)}`} stroke={light(cuff, 0.6)} strokeWidth="0.8" />
          <path d={`M${r1(last[0] - w * 0.6)} ${r1(last[1] + 0.2)} h${r1(w * 1.2)}`} stroke={shade(cuff, 0.3)} strokeWidth="0.35" />
        </g>
      )}
    </g>
  );
}

const braidD = (pts: P[]) => `M${r1(pts[0][0])} ${r1(pts[0][1])}` + smoothOpen(pts);

// ------------------------------------------------------------------ BACK

export function hairBack(c: Ctx): ReactNode {
  const t = defsFor(c);
  switch (c.cfg.hair) {
    case 'dada': {
      const locs: ReactNode[] = [];
      for (let i = 0; i < 9; i++) {
        const x = 69 + i * 7.75;
        const len = 120 + (i % 3) * 6 - Math.abs(i - 4) * 2;
        const sway = (x - CX) * 0.16;
        locs.push(rope([[x * 0.7 + CX * 0.3, 32], [x + sway * 0.6, 70], [x + sway * 1.4, len]], t, 6.6, i, 4));
      }
      return <g>{locs}</g>;
    }
    case 'braids': {
      const bs: ReactNode[] = [];
      const mass = smoothClosed([[CX, 22], [76, 30], [64, 60], [60, 110], [58, 170], [62, 228], [80, 236], [CX, 226], ...sym([[76, 30], [64, 60], [60, 110], [58, 170], [62, 228], [80, 236]]).slice(0)], 0.9);
      bs.push(<path key="m" d={mass} fill={t.dark} />);
      for (let i = 0; i < 16; i++) {
        const x = 62 + i * 5.1;
        const bottom = 222 + Math.sin(i * 1.7) * 9;
        const out = (x - CX) * 0.1;
        bs.push(rope([[x * 0.6 + CX * 0.4, 30], [x + out, 90], [x + out * 1.4, bottom]], t, 4.4, 'b' + i, 3));
      }
      return <g>{bs}</g>;
    }
    case 'bone_straight': {
      const d = smoothClosed([[CX, 21], [80, 26], [67, 44], [63, 90], [62, 150], [64, 192], [76, 197], [CX, 180], [124, 197], [136, 192], [138, 150], [137, 90], [133, 44], [120, 26]], 0.9);
      return (
        <g>
          <path d={d} fill={t.base} />
          <path d={d} fill={c.url('hairSheenV')} />
          {[68, 76, 124, 132].map((x, i) => (
            <path key={i} d={`M${x} 60 Q${x - (x < CX ? 2 : -2)} 130 ${x + (x < CX ? 2 : -2)} 188`} stroke={i % 2 ? t.deep : t.sheen} strokeWidth="1" opacity="0.5" fill="none" />
          ))}
        </g>
      );
    }
    case 'cornrows': {
      const bs: ReactNode[] = [];
      for (const side of [1, -1]) {
        for (let i = 0; i < 3; i++) {
          const x = CX - side * (12 + i * 4.2);
          bs.push(rope([[x, 72], [x - side * (3 + i * 2), 100], [x - side * (8 + i * 4), 128 - i * 4]], t, 3.8, `${side}${i}`, 2.8));
        }
      }
      return <g>{bs}</g>;
    }
    case 'packing_gel': {
      const d = 'M106 18 C134 22 138 60 132 92 C128 116 134 138 128 156 C124 138 120 120 122 96 C126 66 122 36 104 26Z';
      return (
        <g>
          <path d={d} fill={t.base} />
          <path d={d} fill={c.url('hairSheenV')} />
          <path d="M112 26 C130 40 130 80 126 104 C124 122 128 140 128 152" stroke={t.sheen} strokeWidth="1.2" fill="none" opacity="0.6" />
        </g>
      );
    }
    case 'gele': {
      const g = geleColors(c);
      return <path d="M68 40 Q64 56 70 62 L130 62 Q136 54 132 38Z" fill={g.shadow} />;
    }
    default:
      return null;
  }
}

function geleColors(c: Ctx) {
  const base = c.oc;
  const l = luma(base);
  const fabric = l > 0.85 ? '#e9d7a7' : base;
  return {
    fabric,
    shadow: shade(fabric, 0.4),
    light: light(fabric, 0.35),
    gold: l > 0.85 ? '#b8862c' : '#f1c766',
  };
}

// ------------------------------------------------------------------ FRONT

export function hairFront(c: Ctx): ReactNode {
  const t = defsFor(c);
  switch (c.cfg.hair) {
    case 'skin_botcho':
      return (
        <g>
          <ellipse cx="90" cy="32" rx="10" ry="5" fill={c.skin.highlight} opacity="0.55" transform="rotate(-18 90 32)" />
          <ellipse cx="87" cy="31" rx="3.2" ry="1.5" fill="#fff6ea" opacity="0.5" transform="rotate(-18 87 31)" />
        </g>
      );
    case 'low_cut': {
      const d = capPath(c, 1.3);
      return (
        <g>
          <path d={d} fill={t.base} opacity="0.94" />
          <path d={d} fill={c.url('hairStip')} />
          <path d={d} fill={c.url('hairSheenV')} opacity="0.6" />
        </g>
      );
    }
    case 'waves_360': {
      const d = capPath(c, 1.8);
      const clip = c.def('waveclip', (id) => <clipPath id={id}><path d={d} /></clipPath>);
      const waves: ReactNode[] = [];
      for (let i = 0; i < 8; i++) {
        const y = 22 + i * 3.4;
        let p = `M64 ${y}`;
        for (let x = 64; x < 138; x += 6) p += ` q3 ${i % 2 ? 2 : -2} 6 0`;
        waves.push(<path key={i} d={p} stroke={t.sheen} strokeWidth="1.3" fill="none" opacity="0.55" />);
        waves.push(<path key={'d' + i} d={p} stroke={t.deep} strokeWidth="1" fill="none" opacity="0.6" transform="translate(0 1.6)" />);
      }
      return (
        <g>
          <path d={d} fill={t.base} />
          <g clipPath={clip}>{waves}</g>
          <path d={d} fill={c.url('hairSheenV')} opacity="0.5" />
        </g>
      );
    }
    case 'small_afro':
    case 'short_afro': {
      const big = c.cfg.hair === 'small_afro';
      const F = c.b.female;
      const rx = big ? 37 : 33;
      const ry = big ? 29 : 24;
      const cy = big ? 44 : 45;
      const outer = puffPts(CX, cy, rx, ry, 168, 372, 26, big ? 0.045 : 0.03);
      const sb = F ? 56 : 62;
      const inner: P[] = [[126.6, sb], [125, 49], [121, 43.6], [112, 39.6], [CX, F ? 37 : 38.2], [88, 39.6], [79, 43.6], [75, 49], [73.4, sb]];
      const d = smoothClosed([[72.2, sb + 1], ...outer, [127.8, sb + 1], ...inner], 0.95);
      return (
        <g>
          <path d={d} fill={t.base} />
          <path d={d} fill={c.url('hairCurl')} />
          <path d={d} fill={c.url('hairSheenV')} opacity="0.7" />
          <ellipse cx={CX - 12} cy={cy - ry * 0.55} rx={rx * 0.38} ry={ry * 0.22} fill={t.sheen} opacity="0.22" />
        </g>
      );
    }
    case 'high_top': {
      const left: P[] = [[73, 62], [71.2, 50], [70.6, 34], [71.4, 12], [74.5, 4.5], [88, 3.4]];
      const top: P = [CX, 3.2];
      const inner: P[] = [[124.8, 58], [124.8, 49], [121.4, 43.6], [112.4, 39.4], [CX, 38.4], [87.6, 39.4], [78.6, 43.6], [75.2, 49], [75.2, 58]];
      const d = smoothClosed([...left, top, ...sym(left), ...inner], 0.7);
      const fade = c.def('htFade', (id) => (
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={t.base} />
          <stop offset="0.62" stopColor={t.base} />
          <stop offset="1" stopColor={mix(t.base, c.skin.shadow, 0.55)} />
        </linearGradient>
      ));
      const lines: ReactNode[] = [];
      for (let i = 0; i < 12; i++) {
        const x = 76 + i * 4.4;
        lines.push(<path key={i} d={`M${x} 6 l${(x - CX) * 0.02} ${16 + (i % 3) * 4}`} stroke={i % 2 ? t.sheen : t.deep} strokeWidth="0.8" opacity="0.5" />);
      }
      return (
        <g>
          <path d={d} fill={fade} />
          <path d={d} fill={c.url('hairStip')} />
          {lines}
          <path d="M74 6 L126 6 L126 9 L74 9Z" fill={t.sheen} opacity="0.25" />
          <path d={d} fill={c.url('hairSheenV')} opacity="0.5" />
        </g>
      );
    }
    case 'twists': {
      const d = capPath(c, 2.4);
      const tw: ReactNode[] = [];
      const N = 15;
      for (let i = 0; i < N; i++) {
        const a = (-172 + (164 * i) / (N - 1)) * (Math.PI / 180);
        const bx = CX + Math.cos(a) * 25;
        const by = 44 + Math.sin(a) * 19;
        const len = 11 + (i % 3) * 2.5;
        const ex = bx + Math.cos(a) * len * 0.8;
        const ey = by + Math.sin(a) * len - 2;
        tw.push(twist(bx, by, ex, ey, t, i));
      }
      // front row over the hairline
      for (let i = 0; i < 6; i++) {
        const bx = 82 + i * 7.2;
        tw.push(twist(bx, 36, bx + (bx - CX) * 0.25, 26, t, 'f' + i));
      }
      return (
        <g>
          <path d={d} fill={t.base} />
          {tw}
        </g>
      );
    }
    case 'dada': {
      const d = capPath(c, 3.6);
      const locs: ReactNode[] = [];
      // loc roots over the crown, falling back
      for (let i = 0; i < 8; i++) {
        const x = 79 + i * 6;
        const y0 = 33 + Math.abs(x - CX) * 0.28;
        locs.push(rope([[x, y0], [CX + (x - CX) * 1.05, 24 + Math.abs(x - CX) * 0.2], [CX + (x - CX) * 1.25, 18 + Math.abs(x - CX) * 0.45]], t, 6.2, 'r' + i, 3.6, false));
      }
      // framing locs falling forward past the ears
      for (const side of [1, -1]) {
        for (let k = 0; k < 2; k++) {
          const x0 = CX - side * (22 - k * 5);
          locs.push(rope([[x0, 36 + k * 3], [CX - side * (30 + k * 2), 56 + k * 4], [CX - side * (33.5 + k * 2), 92 + k * 6], [CX - side * (36 + k * 3), 122 + k * 4]], t, 6.4, `f${side}${k}`, 4));
        }
      }
      return (
        <g>
          <path d={d} fill={t.base} />
          {locs}
        </g>
      );
    }
    case 'braids': {
      const d = capPath(c, 3, { hl: 36.5, sb: 54 });
      const clip = c.def('braidclip', (id) => <clipPath id={id}><path d={d} /></clipPath>);
      const parts: ReactNode[] = [];
      for (let i = 0; i < 6; i++) parts.push(<path key={'v' + i} d={`M${78 + i * 9} 46 Q${CX + (78 + i * 9 - CX) * 0.5} 26 ${CX + (78 + i * 9 - CX) * 0.2} 14`} stroke={t.scalp} strokeWidth="0.9" fill="none" />);
      for (let j = 0; j < 3; j++) parts.push(<path key={'h' + j} d={`M66 ${30 + j * 7} Q${CX} ${20 + j * 7} 134 ${30 + j * 7}`} stroke={t.scalp} strokeWidth="0.9" fill="none" />);
      const front: ReactNode[] = [];
      // a few braids drape forward over the shoulders, kept to the outer edge of the chest
      // so the outfit stays readable
      for (let k = 0; k < 3; k++) {
        const L = (s: number): P[] => [[CX - s * (25 - k * 1.2), 42 + k], [CX - s * (30.5 + k * 0.6), 72], [CX - s * (29 + k * 1.4), 106], [CX - s * (25 + k * 2.2), 140], [CX - s * (23.5 + k * 2.6), 176 - k * 7]];
        front.push(rope(L(1), t, 4.4, 'L' + k, 3, true, k === 1 ? '#e8b13a' : undefined));
        if (k < 2) front.push(rope(L(-1), t, 4.4, 'R' + k, 3, true, k === 0 ? '#e8b13a' : undefined));
      }
      return (
        <g>
          <path d={d} fill={t.base} />
          <g clipPath={clip}>{parts}</g>
          <path d={d} fill={c.url('hairSheenV')} opacity="0.6" />
          {front}
        </g>
      );
    }
    case 'cornrows': {
      const d = capPath(c, 2.2, { hl: 36.8, sb: 55 });
      const clip = c.def('rowclip', (id) => <clipPath id={id}><path d={d} /></clipPath>);
      const rows: ReactNode[] = [];
      for (let i = 0; i < 9; i++) {
        const x = 72 + i * 7;
        const dd = `M${x} ${48 - Math.abs(x - CX) * -0.1 - 6 + Math.abs(x - CX) * 0.25} Q${CX + (x - CX) * 0.75} 24 ${CX + (x - CX) * 0.35} 12`;
        rows.push(
          <g key={i} fill="none" strokeLinecap="round">
            <path d={dd} stroke={t.deep} strokeWidth="5.6" />
            <path d={dd} stroke={t.base} strokeWidth="4.4" />
            <path d={dd} stroke={t.sheen} strokeWidth="1.6" strokeDasharray="1.4 1.6" opacity="0.8" />
          </g>,
        );
      }
      return (
        <g>
          <path d={d} fill={t.scalp} />
          <g clipPath={clip}>{rows}</g>
          <path d={d} fill={c.url('hairSheenV')} opacity="0.4" />
        </g>
      );
    }
    case 'bone_straight': {
      const L: P[] = [[CX, 23], [86, 25.5], [76, 33], [70.2, 48], [68.6, 80], [69.4, 112], [74, 150], [79, 172], [82, 160], [80.6, 120], [79.6, 86], [78.4, 60], [82, 44], [92, 34]];
      const dL = smoothClosed(L, 0.9);
      const dR = smoothClosed(L.map(([x, y]) => [200 - x, y] as P), 0.9);
      const crown = smoothClosed([[CX, 20.6], [84, 23.5], [74, 32], [70.6, 46], [79, 42], [90, 37], [CX, 35.4], [110, 37], [121, 42], [129.4, 46], [126, 32], [116, 23.5]], 0.9);
      return (
        <g>
          <path d={crown} fill={t.base} />
          <path d={crown} fill={c.url('hairSheenV')} />
          {[dL, dR].map((dd, i) => (
            <g key={i}>
              <path d={dd} fill={t.base} />
              <path d={dd} fill={c.url('hairSheenV')} />
            </g>
          ))}
          <path d="M100 21.5 L100 35" stroke={t.scalp} strokeWidth="0.9" />
          <path d="M77 40 Q73 70 75 110 Q76 140 80 162" stroke={t.spec} strokeWidth="1.5" fill="none" opacity="0.55" strokeLinecap="round" />
          <path d="M82 30 Q90 26 97 25.5" stroke={t.spec} strokeWidth="1.8" fill="none" opacity="0.55" strokeLinecap="round" />
          <path d="M123 40 Q127 70 125 110" stroke={t.sheen} strokeWidth="1.1" fill="none" opacity="0.4" />
        </g>
      );
    }
    case 'bantu_knots': {
      const d = capPath(c, 1.2, { hl: 37, sb: 55 });
      const knots: [number, number, number][] = [[CX, 17, 8.2], [80.5, 25, 7.4], [119.5, 25, 7.4], [70.6, 41, 6.6], [129.4, 41, 6.6]];
      return (
        <g>
          <path d={d} fill={t.base} />
          <path d={d} fill={c.url('hairStip')} />
          <path d="M90 38 L90 24 M110 38 L110 24 M76 34 L86 30 M124 34 L114 30" stroke={t.scalp} strokeWidth="1" />
          {knots.map(([x, y, r], i) => (
            <g key={i}>
              <circle cx={x} cy={y} r={r + 0.8} fill={t.deep} />
              <circle cx={x} cy={y} r={r} fill={t.base} />
              <path d={`M${x - r * 0.75} ${y + r * 0.2} A${r * 0.75} ${r * 0.75} 0 0 1 ${x + r * 0.7} ${y - r * 0.1} A${r * 0.5} ${r * 0.5} 0 0 1 ${x - r * 0.2} ${y + r * 0.35} A${r * 0.25} ${r * 0.25} 0 0 1 ${x + r * 0.15} ${y - r * 0.05}`} stroke={t.sheen} strokeWidth="1" fill="none" opacity="0.8" />
              <path d={`M${x - r * 0.9} ${y + r * 0.25} A${r * 0.92} ${r * 0.92} 0 0 0 ${x + r * 0.85} ${y + r * 0.35}`} stroke={t.deep} strokeWidth="1.2" fill="none" opacity="0.5" />
              <circle cx={x - r * 0.35} cy={y - r * 0.45} r={r * 0.22} fill={t.spec} opacity="0.4" />
            </g>
          ))}
        </g>
      );
    }
    case 'packing_gel': {
      const d = capPath(c, 0.8, { hl: 37, sb: 55 });
      const lines: ReactNode[] = [];
      for (let i = 0; i < 7; i++) {
        const x = 76 + i * 8;
        lines.push(<path key={i} d={`M${x} ${44 - Math.abs(x - CX) * 0.15 - (Math.abs(x - CX) > 18 ? 0 : 4)} Q${CX + (x - CX) * 0.55} 28 ${CX + (x - CX) * 0.2} 20`} stroke={i % 2 ? t.sheen : t.deep} strokeWidth="0.8" fill="none" opacity="0.6" />);
      }
      return (
        <g>
          <path d={d} fill={t.base} />
          {lines}
          <path d={d} fill={c.url('hairSheenV')} />
          {/* puff / bun */}
          <ellipse cx={CX} cy={16} rx={15} ry={10.5} fill={t.deep} />
          <ellipse cx={CX} cy={15.4} rx={14} ry={9.6} fill={t.base} />
          <ellipse cx={CX} cy={15.4} rx={14} ry={9.6} fill={c.url('hairCurl')} />
          <ellipse cx={CX - 4} cy={11.5} rx={6} ry={3} fill={t.sheen} opacity="0.35" />
          <path d="M86 22.4 Q100 27 114 22.4" stroke={c.oc} strokeWidth="2.4" fill="none" strokeLinecap="round" />
          {/* laid edges / baby hair */}
          <path d="M80 43.5 q-2 -3 1 -4.4 q3 -1 2 2.2 M76.2 47 q-2.2 -1.4 -0.6 -3.6 M120 43.5 q2 -3 -1 -4.4 q-3 -1 -2 2.2 M123.8 47 q2.2 -1.4 0.6 -3.6" stroke={t.base} strokeWidth="0.8" fill="none" />
        </g>
      );
    }
    case 'gele':
      return gele(c);
    default:
      return null;
  }
}

function twist(bx: number, by: number, ex: number, ey: number, t: ReturnType<typeof tones>, key: string | number): ReactNode {
  const d = `M${r1(bx)} ${r1(by)} L${r1(ex)} ${r1(ey)}`;
  const dx = ex - bx;
  const dy = ey - by;
  const L = Math.hypot(dx, dy) || 1;
  const nx = -dy / L;
  const ny = dx / L;
  const ticks: string[] = [];
  for (let k = 1; k < 4; k++) {
    const px = bx + dx * (k / 4);
    const py = by + dy * (k / 4);
    ticks.push(`M${r1(px - nx * 2)} ${r1(py - ny * 2)} L${r1(px + nx * 2 + dx / L * 1.5)} ${r1(py + ny * 2 + dy / L * 1.5)}`);
  }
  return (
    <g key={key} strokeLinecap="round" fill="none">
      <path d={d} stroke={t.deep} strokeWidth="5.6" />
      <path d={d} stroke={t.base} strokeWidth="4.3" />
      <path d={ticks.join(' ')} stroke={t.sheen} strokeWidth="0.8" opacity="0.7" />
    </g>
  );
}

function gele(c: Ctx): ReactNode {
  const g = geleColors(c);
  const grad = c.def('geleG', (id) => (
    <linearGradient id={id} x1="0" y1="0" x2="1" y2="0.4">
      <stop offset="0" stopColor={g.shadow} />
      <stop offset="0.25" stopColor={g.light} />
      <stop offset="0.5" stopColor={g.fabric} />
      <stop offset="0.85" stopColor={g.shadow} />
      <stop offset="1" stopColor={shade(g.fabric, 0.6)} />
    </linearGradient>
  ));
  const shimmer = c.def('geleP', (id) => (
    <pattern id={id} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(30)">
      <path d="M0 3 H6" stroke={g.gold} strokeWidth="0.6" opacity="0.45" />
      <circle cx="3" cy="0.8" r="0.45" fill={g.gold} opacity="0.6" />
    </pattern>
  ));
  // band hugging the forehead, wrapping round to the nape
  const band = 'M69.6 58 C68 44 72 33 82 30 C94 27 106 27 118 30 C128 33 132 44 130.4 58 C126 50 122 45 114 42 C104 39 96 39 86 42 C78 45 73 50 69.6 58Z';
  // big sculpted fan
  const fan = 'M70 37 C58 27 61 11 74 7 C82 5 86 12 90 9 C96 4 108 4 112 9 C118 5 130 4 138 11 C148 20 142 32 130 37 C118 31 104 29 100 29 C94 29 82 31 70 37Z';
  const folds = ['M74 31 C70 23 72 14 80 10', 'M86 29 C84 21 88 13 94 10', 'M100 28 C100 21 104 12 110 9.5', 'M112 29 C116 22 122 15 130 12.5', 'M124 33 C132 28 138 21 140 16'];
  return (
    <g>
      <path d={fan} fill={grad} />
      <path d={fan} fill={shimmer} />
      {folds.map((f, i) => (
        <g key={i} fill="none" strokeLinecap="round">
          <path d={f} stroke={g.shadow} strokeWidth="2.2" opacity="0.55" transform="translate(1.6 0.6)" />
          <path d={f} stroke={g.light} strokeWidth="1.2" opacity="0.7" />
        </g>
      ))}
      {/* upturned tail flicks */}
      <path d="M134 12 C140 5 147 3 151 6 C146 8 142 12 138 17Z" fill={g.fabric} stroke={g.shadow} strokeWidth="0.6" />
      <path d={band} fill={grad} />
      <path d={band} fill={shimmer} />
      <path d="M72 50 C80 40 92 37 100 37 C108 37 120 40 128 50" stroke={g.light} strokeWidth="1.2" fill="none" opacity="0.6" />
      <path d="M71 40 C84 33 116 33 129 40" stroke={g.shadow} strokeWidth="1.4" fill="none" opacity="0.5" />
    </g>
  );
}
