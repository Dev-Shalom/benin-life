// P1-MAP — static illustrated layers. Memoised: rendered once, never re-rendered on pan/zoom.
import { memo, useMemo } from 'react';
import {
  AIRPORT, BRIDGE, CAMPUS, DISTRICT_LABELS, DISTRICT_TINTS, EXITS, FARMLAND, GO_SLOW, KINGS_SQUARE, NIGHT_GLOWS,
  PALACE, POLICE, RAMAT, RING, RUNWAY, STADIUM, TERMINAL, UBTH, UBTH_SIGN, bbox, blobD, circleD, inPoly, labelPath,
  polyD, r1, rng, type Pt,
} from './mapGeo';
import { getMapModel, ROOF_BUCKETS, type RoofBucket, type Vehicle } from './mapModel';

const ROOF: Record<RoofBucket, [string, string, string]> = {
  rust: ['#d07c4e', '#a95b36', '#7c3d26'],
  zinc: ['#d6dce1', '#a9b2bb', '#79838f'],
  red: ['#d4563d', '#ac3a2b', '#7a2520'],
  teal: ['#6aa3ac', '#4a7f89', '#305a66'],
  white: ['#f6f1e6', '#ddd4c4', '#b4a996'],
  thatch: ['#dcb56b', '#b99050', '#8a6837'],
};

const FONT = "'Bricolage Grotesque', 'Trebuchet MS', 'Segoe UI', system-ui, sans-serif";

/* ------------------------------------------------------------------ */
/* Farm fields (computed once)                                          */
/* ------------------------------------------------------------------ */
let fieldsCache: string[] | null = null;
function farmFields(): string[] {
  const rand = rng(77);
  const out = ['', '', '', ''];
  const [x0, y0, x1, y1] = bbox(FARMLAND);
  for (let y = y0; y < y1; y += 38)
    for (let x = x0; x < x1; x += 46) {
      const j = () => (rand() - 0.5) * 8;
      const q: Pt[] = [[x + 2 + j(), y + 2 + j()], [x + 44 + j(), y + 2 + j()], [x + 44 + j(), y + 36 + j()], [x + 2 + j(), y + 36 + j()]];
      const cx = x + 23;
      const cy = y + 19;
      if (!inPoly(cx, cy, FARMLAND)) continue;
      if (!q.every(([px, py]) => inPoly(px, py, FARMLAND))) continue;
      out[Math.floor(rand() * 4)] += polyD(q);
    }
  return out;
}

/* ------------------------------------------------------------------ */
/* Vehicles                                                             */
/* ------------------------------------------------------------------ */
function VehicleG({ v }: { v: Vehicle }) {
  const t = `translate(${r1(v.x)} ${r1(v.y)}) rotate(${r1(v.a)})`;
  if (v.kind === 'bus')
    return (
      <g transform={t}>
        <rect x={-6.2} y={-2.1} width={12.4} height={4.2} rx={1} fill={v.color} stroke="#0f3b22" strokeWidth={0.4} />
        <rect x={-5.4} y={-0.4} width={10.6} height={0.8} fill="#f4f1e6" />
        <rect x={4.2} y={-1.7} width={1.4} height={3.4} fill="#203247" />
      </g>
    );
  if (v.kind === 'danfo')
    return (
      <g transform={t}>
        <rect x={-4.4} y={-1.9} width={8.8} height={3.8} rx={1} fill={v.color} stroke="#7a5a10" strokeWidth={0.35} />
        <path d="M-3.6,-1.9V1.9M-1.6,-1.9V1.9" stroke="#2a2216" strokeWidth={0.45} />
        <rect x={2.6} y={-1.5} width={1.3} height={3} fill="#203247" />
      </g>
    );
  if (v.kind === 'keke')
    return (
      <g transform={t}>
        <path d="M-2,-1.5L1.6,-1.5L2.6,0L1.6,1.5L-2,1.5Z" fill={v.color} stroke="#6b520c" strokeWidth={0.3} />
        <rect x={-1.6} y={-1.2} width={2.4} height={2.4} rx={0.5} fill="#1f7a3f" />
      </g>
    );
  return (
    <g transform={t}>
      <rect x={-3.3} y={-1.75} width={6.6} height={3.5} rx={1.1} fill={v.color} stroke="#2b2433" strokeWidth={0.35} />
      <rect x={0.9} y={-1.35} width={1.4} height={2.7} rx={0.4} fill="#2a3a55" />
      <rect x={-2.6} y={-1.3} width={1} height={2.6} rx={0.3} fill="#2a3a55" opacity={0.8} />
    </g>
  );
}

/* ------------------------------------------------------------------ */
/* Oba's Palace — walled compound with long laterite-red roofs          */
/* ------------------------------------------------------------------ */
function Palace() {
  const n = PALACE.length;
  const cx = PALACE.reduce((a, p) => a + p[0], 0) / n;
  const cy = PALACE.reduce((a, p) => a + p[1], 0) / n;
  const inner: Pt[] = PALACE.map(([x, y]) => [cx + (x - cx) * 0.42, cy + (y - cy) * 0.42]);
  let light = '';
  let dark = '';
  let shadow = '';
  let ridge = '';
  PALACE.forEach(([ax, ay], i) => {
    const [bx, by] = PALACE[(i + 1) % n];
    const L = Math.hypot(bx - ax, by - ay);
    const ux = (bx - ax) / L;
    const uy = (by - ay) / L;
    // inward normal
    let nx = -uy;
    let ny = ux;
    const mx = (ax + bx) / 2;
    const my = (ay + by) / 2;
    if ((cx - mx) * nx + (cy - my) * ny < 0) {
      nx = -nx;
      ny = -ny;
    }
    const w = L * 0.36;
    const d = 3.4;
    const o = 3.4;
    const P = (s: number, t: number): [number, number] => [mx + ux * s + nx * (o + t), my + uy * s + ny * (o + t)];
    const q = (pts: [number, number][]) => 'M' + pts.map((p) => `${r1(p[0])},${r1(p[1])}`).join('L') + 'Z';
    const outer = q([P(-w, 0), P(w, 0), P(w, d), P(-w, d)]);
    const innerHalf = q([P(-w, d), P(w, d), P(w, 2 * d), P(-w, 2 * d)]);
    shadow += q([P(-w, 0), P(w, 0), P(w, 2 * d), P(-w, 2 * d)].map(([x, y]) => [x + 1.6, y + 2] as [number, number]));
    // lit side = the half facing north-west
    const litOuter = -nx * 0.62 - ny * 0.78 > 0;
    if (litOuter) {
      light += outer;
      dark += innerHalf;
    } else {
      dark += outer;
      light += innerHalf;
    }
    const r0 = P(-w, d);
    const r2 = P(w, d);
    ridge += `M${r1(r0[0])},${r1(r0[1])}L${r1(r2[0])},${r1(r2[1])}`;
  });
  return (
    <g className="map-palace">
      <path d={polyD(PALACE)} fill="#e8c493" />
      <path d={polyD(inner)} fill="#f3dcb2" stroke="#c98a55" strokeWidth={0.6} />
      <circle cx={cx} cy={cy} r={3.2} fill="#3f8a3c" />
      <circle cx={cx - 1} cy={cy - 1} r={1.6} fill="#78b856" />
      <path d={shadow} fill="#3b1d36" opacity={0.3} />
      <path d={light} fill="#c4573a" />
      <path d={dark} fill="#8a3420" />
      <path d={ridge} stroke="#f2d0a8" strokeWidth={0.5} opacity={0.7} />
      <path d={polyD(PALACE)} fill="none" stroke="#8a361b" strokeWidth={3.4} strokeLinejoin="round" />
      <path d={polyD(PALACE)} fill="none" stroke="#c9683a" strokeWidth={1.1} strokeLinejoin="round" transform="translate(-0.5 -0.6)" />
    </g>
  );
}

/* ------------------------------------------------------------------ */
/* Defs                                                                 */
/* ------------------------------------------------------------------ */
function Defs() {
  return (
    <defs>
      <radialGradient id="map-ground" cx="50%" cy="48%" r="72%" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#e6b07c" />
        <stop offset="35%" stopColor="#dca171" />
        <stop offset="70%" stopColor="#c98a5a" />
        <stop offset="100%" stopColor="#b57447" />
      </radialGradient>
      <filter id="map-grain-f" x="0" y="0" width="100%" height="100%" colorInterpolationFilters="linearRGB">
        <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} seed={3} stitchTiles="stitch" result="n" />
        <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.2  0 0 0 0 0.09  0 0 0 0 0.05  2.4 0 0 0 -1.05" />
      </filter>
      <pattern id="map-grain" patternUnits="userSpaceOnUse" width="128" height="128">
        <rect width="128" height="128" filter="url(#map-grain-f)" />
      </pattern>
      <filter id="map-mottle-f" x="0" y="0" width="100%" height="100%" colorInterpolationFilters="linearRGB">
        <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves={2} seed={9} stitchTiles="stitch" result="n" />
        <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.45  0 0 0 0 0.16  0 0 0 0 0.06  1.9 0 0 0 -0.82" />
      </filter>
      <pattern id="map-mottle" patternUnits="userSpaceOnUse" width="256" height="256">
        <rect width="256" height="256" filter="url(#map-mottle-f)" />
      </pattern>
      {DISTRICT_TINTS.map(([, , , , c], i) => (
        <radialGradient key={i} id={`map-tint-${i}`}>
          <stop offset="0%" stopColor={c} stopOpacity={0.62} />
          <stop offset="55%" stopColor={c} stopOpacity={0.4} />
          <stop offset="100%" stopColor={c} stopOpacity={0} />
        </radialGradient>
      ))}
      <pattern id="map-corr" patternUnits="userSpaceOnUse" width="1.6" height="1.6">
        <rect width="0.55" height="1.6" fill="#3a1f2e" opacity="0.16" />
      </pattern>
      <pattern id="map-crop-0" patternUnits="userSpaceOnUse" width="5" height="5" patternTransform="rotate(18)">
        <rect width="5" height="5" fill="#86ad4c" />
        <rect width="5" height="2" fill="#4f8233" />
      </pattern>
      <pattern id="map-crop-1" patternUnits="userSpaceOnUse" width="6" height="6" patternTransform="rotate(-10)">
        <rect width="6" height="6" fill="#c39561" />
        <circle cx="3" cy="3" r="1.7" fill="#8c5d33" />
        <circle cx="2.5" cy="2.4" r="0.7" fill="#5f8a36" />
      </pattern>
      <pattern id="map-crop-2" patternUnits="userSpaceOnUse" width="4" height="4" patternTransform="rotate(-32)">
        <rect width="4" height="4" fill="#cdc56a" />
        <rect width="4" height="1.3" fill="#8e9a3c" />
      </pattern>
      <pattern id="map-crop-3" patternUnits="userSpaceOnUse" width="7" height="7" patternTransform="rotate(40)">
        <rect width="7" height="7" fill="#9fbd5f" />
        <circle cx="2" cy="2" r="1.4" fill="#5c8e3b" />
        <circle cx="5.5" cy="5" r="1.1" fill="#6f9e44" />
      </pattern>
      <linearGradient id="map-water" x1="0" y1="0" x2="1" y2="1" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#2e7ea6" />
        <stop offset="45%" stopColor="#3a92b5" />
        <stop offset="100%" stopColor="#2a6f97" />
      </linearGradient>
      <radialGradient id="map-sun" cx="18%" cy="12%" r="85%" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#fff2c2" stopOpacity={0.34} />
        <stop offset="45%" stopColor="#ffe3a3" stopOpacity={0.1} />
        <stop offset="100%" stopColor="#ffd38a" stopOpacity={0} />
      </radialGradient>
      <radialGradient id="map-vignette" cx="50%" cy="50%" r="72%">
        <stop offset="62%" stopColor="#4a1f12" stopOpacity={0} />
        <stop offset="100%" stopColor="#4a1f12" stopOpacity={0.38} />
      </radialGradient>
      <radialGradient id="map-museum-roof" cx="40%" cy="38%" r="65%" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#e9c88f" />
        <stop offset="40%" stopColor="#b98349" />
        <stop offset="80%" stopColor="#8a5530" />
        <stop offset="100%" stopColor="#6b3d22" />
      </radialGradient>
      <radialGradient id="map-island" cx="42%" cy="40%" r="62%" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#9ccb66" />
        <stop offset="70%" stopColor="#6aa64a" />
        <stop offset="100%" stopColor="#4e8a3c" />
      </radialGradient>
      <radialGradient id="map-moon" cx="86%" cy="10%" r="70%" colorInterpolation="linearRGB">
        <stop offset="0%" stopColor="#a9b9ff" stopOpacity={0.3} />
        <stop offset="40%" stopColor="#7d8fe0" stopOpacity={0.1} />
        <stop offset="100%" stopColor="#6d7fd6" stopOpacity={0} />
      </radialGradient>
      <radialGradient id="map-night-vig" cx="50%" cy="50%" r="72%">
        <stop offset="55%" stopColor="#05061a" stopOpacity={0} />
        <stop offset="100%" stopColor="#05061a" stopOpacity={0.5} />
      </radialGradient>
      <radialGradient id="map-glow-warm">
        <stop offset="0%" stopColor="#ffd98a" stopOpacity={0.55} />
        <stop offset="40%" stopColor="#ffb85a" stopOpacity={0.2} />
        <stop offset="100%" stopColor="#ff9a40" stopOpacity={0} />
      </radialGradient>
    </defs>
  );
}

/* ------------------------------------------------------------------ */
/* Day art                                                              */
/* ------------------------------------------------------------------ */
const ROAD_STYLE = {
  express: { casing: '#4b2a2a', edge: '#efe6d4', fill: '#5d5866', dash: '#f3cf5e' },
  main: { casing: '#56302a', edge: '#e7dccb', fill: '#6a6370', dash: '#f1e6cf' },
};

export const MapArt = memo(function MapArt() {
  const m = getMapModel();
  const fields = (fieldsCache ??= farmFields());
  const paved = m.roads.filter((r) => r.kind === 'express' || r.kind === 'main');
  const minor = m.roads.filter((r) => r.kind === 'minor');
  const dirt = m.roads.filter((r) => r.kind === 'dirt');
  const rw = RUNWAY;
  const rwA = (Math.atan2(rw.y2 - rw.y1, rw.x2 - rw.x1) * 180) / Math.PI;
  const rwL = Math.hypot(rw.x2 - rw.x1, rw.y2 - rw.y1);
  const ringD = circleD(RING.x, RING.y, RING.r);

  return (
    <g className="map-art">
      <Defs />
      {/* L1 ground */}
      <rect width="1000" height="1000" fill="url(#map-ground)" />
      <rect width="1000" height="1000" fill="url(#map-mottle)" opacity={0.55} />
      {DISTRICT_TINTS.map(([x, y, rx, ry], i) => (
        <ellipse key={i} cx={x} cy={y} rx={rx} ry={ry} fill={`url(#map-tint-${i})`} />
      ))}

      <path d={m.grass[0]} fill="#a3b55a" opacity={0.42} />
      <path d={m.grass[1]} fill="#c2b763" opacity={0.36} />

      {/* L2 farmland */}
      <path d={blobD(FARMLAND)} fill="#9cb862" />
      {fields.map((d, i) => (
        <path key={i} d={d} fill={`url(#map-crop-${i})`} stroke="#6f5530" strokeWidth={0.8} strokeOpacity={0.45} />
      ))}

      {/* L3 airport grounds */}
      <path d={polyD(AIRPORT)} fill="#bcd08a" stroke="#f3ead2" strokeWidth={1.4} strokeDasharray="3 2.5" />

      {/* L4 river with lush banks */}
      <g className="map-river" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d={m.river.d} stroke="#5f9b45" strokeWidth={62} opacity={0.5} />
        <path d={m.river.d} stroke="#3f7f39" strokeWidth={40} opacity={0.75} />
        <path d={m.river.d} stroke="#8c7c4e" strokeWidth={22} />
        <path d={m.river.d} stroke="url(#map-water)" strokeWidth={17} />
        <path d={m.river.d} stroke="#6fc3de" strokeWidth={6} opacity={0.5} transform="translate(-2.5 -1.5)" />
        <path d={m.river.d} stroke="#e8f8ff" strokeWidth={1.1} strokeDasharray="3 15" opacity={0.75} />
      </g>

      {/* L5 bush masses */}
      <path d={m.bush.shadow} fill="#1f3f37" opacity={0.3} />
      <path d={m.bush.base} fill="#3f7d3a" />
      <path d={m.bush.mid} fill="#4f9143" />
      <path d={m.bush.hi} fill="#7fb85a" opacity={0.9} />

      {/* L6 landmark grounds */}
      <path d={polyD(CAMPUS)} fill="#a9c97a" stroke="#f4ead2" strokeWidth={1.6} />
      <g transform={`translate(${STADIUM.x} ${STADIUM.y}) rotate(-8)`}>
        <ellipse rx={16} ry={10} fill="#c2593a" />
        <ellipse rx={12.5} ry={6.8} fill="#6fae4f" />
        <path d="M-12.5,0H12.5" stroke="#e9f2dc" strokeWidth={0.5} />
      </g>
      <path d={polyD(UBTH)} fill="#d8e3cf" stroke="#f6f1e4" strokeWidth={1.4} />
      <g transform={`translate(${UBTH_SIGN.x} ${UBTH_SIGN.y})`}>
        <circle r={6} fill="#5d6a74" />
        <path d="M-2.4,-3V3M2.4,-3V3M-2.4,0H2.4" stroke="#f6f1e4" strokeWidth={1.1} />
      </g>
      <path d={polyD(POLICE)} fill="#d9cdb0" stroke="#3c4a7a" strokeWidth={1.3} />

      {/* L7 unpaved & minor streets */}
      <g fill="none" strokeLinecap="round" strokeLinejoin="round">
        {dirt.map((r) => <path key={r.id} d={r.d} stroke="#a8673f" strokeWidth={r.hw * 2 + 1.2} opacity={0.55} />)}
        {dirt.map((r) => <path key={r.id + 'f'} d={r.d} stroke="#e2b07a" strokeWidth={r.hw * 2} strokeDasharray="7 2" />)}
        <path d={m.spurs} stroke="#a4643f" strokeWidth={6.6} opacity={0.5} />
        {minor.map((r) => <path key={r.id} d={r.d} stroke="#9c5d3a" strokeWidth={r.hw * 2 + 1.6} opacity={0.55} />)}
        <path d={m.spurs} stroke="#ecd0a2" strokeWidth={5.2} />
        {minor.map((r) => <path key={r.id + 'f'} d={r.d} stroke="#f0d8ad" strokeWidth={r.hw * 2} />)}
      </g>

      {/* L8 market stalls */}
      <path d={m.stallShade} fill="#3a1f2e" opacity={0.25} transform="translate(0.8 1)" />
      {['#d2342a', '#f2b632', '#2f7fc1', '#1f7a3f', '#f4ead6'].map((c, i) => (
        <path key={c} d={m.stalls[i]} fill={c} stroke="#5a2f1f" strokeWidth={0.25} />
      ))}
      <path d={m.stallShade} fill="#2a1a3a" opacity={0.18} />

      {/* L9 buildings */}
      <path d={m.compound} fill="#ecc89a" fillOpacity={0.55} stroke="#f3e2c2" strokeWidth={0.9} strokeOpacity={0.9} />
      <path d={m.roofAll} fill="#3b1d36" opacity={0.3} transform="translate(2.2 2.6)" />
      {ROOF_BUCKETS.map((b) => (
        <g key={b}>
          <path d={m.roofs[b][0]} fill={ROOF[b][0]} />
          <path d={m.roofs[b][1]} fill={ROOF[b][1]} />
          <path d={m.roofs[b][2]} fill={ROOF[b][2]} />
        </g>
      ))}
      <path d={m.roofAll} fill="url(#map-corr)" />
      <path d={m.ridges} stroke="#fff6e4" strokeWidth={0.5} opacity={0.55} />

      <Palace />

      {/* L10 paved roads */}
      <g fill="none" strokeLinecap="round" strokeLinejoin="round">
        {paved.map((r) => <path key={r.id + 'c'} d={r.d} stroke={ROAD_STYLE[r.kind as 'main'].casing} strokeWidth={r.hw * 2 + 3} opacity={0.6} />)}
        <path d={ringD} stroke="#4b2a2a" strokeWidth={RING.hw * 2 + 3} opacity={0.6} />
        {paved.map((r) => <path key={r.id + 'e'} d={r.d} stroke={ROAD_STYLE[r.kind as 'main'].edge} strokeWidth={r.hw * 2} />)}
        <path d={ringD} stroke="#efe6d4" strokeWidth={RING.hw * 2} />
        {paved.map((r) => <path key={r.id + 'f'} d={r.d} stroke={ROAD_STYLE[r.kind as 'main'].fill} strokeWidth={r.hw * 2 - 2} />)}
        <path d={ringD} stroke="#5d5866" strokeWidth={RING.hw * 2 - 2} />
        {paved.map((r) => (
          <path key={r.id + 'd'} d={r.d} stroke={ROAD_STYLE[r.kind as 'main'].dash} strokeWidth={r.kind === 'express' ? 1.1 : 0.8} strokeDasharray={r.kind === 'express' ? '7 5' : '5 6'} />
        ))}
        <path d={ringD} stroke="#f3cf5e" strokeWidth={0.8} transform="translate(0 0)" />
        <path d={circleD(RING.x, RING.y, RING.r - 1.4)} stroke="#f3cf5e" strokeWidth={0.8} />
      </g>

      {/* Bridge over the Ikpoba River */}
      <g transform={`translate(${BRIDGE.x} ${BRIDGE.y}) rotate(${r1((BRIDGE.a * 180) / Math.PI)})`}>
        <rect x={-17} y={-10} width={34} height={20} fill="#1d3b4f" opacity={0.35} transform="translate(2 3)" />
        <rect x={-17} y={-8.6} width={34} height={17.2} rx={1} fill="#cfc6b8" stroke="#6d6258" strokeWidth={0.8} />
        <rect x={-17} y={-6.2} width={34} height={12.4} fill="#5d5866" />
        <path d="M-17,0H17" stroke="#f3cf5e" strokeWidth={0.9} strokeDasharray="4 3" />
        <path d="M-17,-8.2H17M-17,8.2H17" stroke="#f6f1e6" strokeWidth={1.3} />
        {[-14, -7, 0, 7, 14].map((x) => (
          <path key={x} d={`M${x},-8.6V-7.4M${x},7.4V8.6`} stroke="#6d6258" strokeWidth={1} />
        ))}
      </g>

      {/* Ramat Park roundabout + the (nearly finished) flyover */}
      <g transform={`translate(${RAMAT.x} ${RAMAT.y})`}>
        <circle r={15} fill="#5d5866" stroke="#efe6d4" strokeWidth={1.4} />
        <circle r={7.5} fill="#78ac53" stroke="#f3e2c2" strokeWidth={1} />
        <circle r={2.2} fill="#d9a441" />
      </g>
      <g className="map-flyover" transform={`translate(${RAMAT.x} ${RAMAT.y}) rotate(7)`}>
        <rect x={-34} y={-6.5} width={68} height={13} fill="#2b1f3a" opacity={0.3} transform="translate(2.5 3.5)" />
        <rect x={-34} y={-5.5} width={30} height={11} fill="#d9d3c9" stroke="#7a7067" strokeWidth={0.8} />
        <rect x={4} y={-5.5} width={30} height={11} fill="#d9d3c9" stroke="#7a7067" strokeWidth={0.8} />
        <path d="M-34,-4.8H-4M4,-4.8H34M-34,4.8H-4M4,4.8H34" stroke="#ee7a2a" strokeWidth={1.1} strokeDasharray="2 1.6" />
        <rect x={-4} y={-4.5} width={8} height={9} fill="none" stroke="#ee7a2a" strokeWidth={0.6} strokeDasharray="1 1" />
        {/* crane */}
        <path d="M14,-14V2M14,-14L-10,-22M14,-14L22,-12" stroke="#f2b632" strokeWidth={1.4} strokeLinecap="round" />
        <path d="M-6,-20.6V-12" stroke="#4a4050" strokeWidth={0.5} />
        <rect x={12} y={-2} width={4} height={4} fill="#4a4050" />
      </g>
      <g transform={`translate(${GO_SLOW.x} ${GO_SLOW.y})`} className="map-goslow">
        <path d="M-17,-7H17V5H4L0,10L-4,5H-17Z" fill="#d2342a" stroke="#fff6e4" strokeWidth={1.1} strokeLinejoin="round" />
        <text y={2.4} textAnchor="middle" fontSize={7.4} fontWeight={800} fill="#fff6e4" fontFamily={FONT} letterSpacing={0.4}>GO-SLOW!</text>
      </g>

      {/* King's Square + National Museum (circular building) */}
      <g>
        <circle cx={KINGS_SQUARE.x} cy={KINGS_SQUARE.y} r={KINGS_SQUARE.r} fill="url(#map-island)" />
        <circle cx={500} cy={500} r={34} fill="none" stroke="#efe1c3" strokeWidth={3.2} />
        <path d="M500,451V549M451,500H549" stroke="#efe1c3" strokeWidth={3.4} />
        <circle cx={500} cy={500} r={21} fill="#efe1c3" />
        {Array.from({ length: 10 }, (_, i) => {
          const a = (i / 10) * Math.PI * 2 + 0.3;
          return <circle key={i} cx={r1(500 + Math.cos(a) * 42)} cy={r1(500 + Math.sin(a) * 42)} r={3.4} fill="#3f8a3c" stroke="#2c6a33" strokeWidth={0.5} />;
        })}
        <circle cx={502.5} cy={503} r={15} fill="#3b1d36" opacity={0.3} />
        <circle cx={500} cy={500} r={15} fill="#d8c3a0" stroke="#8a5530" strokeWidth={0.9} />
        <circle cx={500} cy={500} r={12.5} fill="url(#map-museum-roof)" />
        <path
          d={Array.from({ length: 12 }, (_, i) => {
            const a = (i / 12) * Math.PI * 2;
            return `M${r1(500 + Math.cos(a) * 4)},${r1(500 + Math.sin(a) * 4)}L${r1(500 + Math.cos(a) * 12.5)},${r1(500 + Math.sin(a) * 12.5)}`;
          }).join('')}
          stroke="#5c341d"
          strokeWidth={0.5}
          opacity={0.6}
        />
        <circle cx={500} cy={500} r={4} fill="#e7d3a6" stroke="#7a4a28" strokeWidth={0.6} />
      </g>

      {/* Airport runway, apron, terminal */}
      <g>
        <g transform={`translate(${rw.x1} ${rw.y1}) rotate(${r1(rwA)})`}>
          <rect x={-2} y={-rw.w / 2 - 1.5} width={rwL + 4} height={rw.w + 3} fill="#3b2533" opacity={0.25} transform="translate(1.5 2)" />
          <rect x={-2} y={-rw.w / 2} width={rwL + 4} height={rw.w} fill="#4c4855" />
          <path d={`M10,0H${r1(rwL - 10)}`} stroke="#f4f1e6" strokeWidth={0.9} strokeDasharray="6 5" />
          <path d={`M2,${-rw.w / 2 + 1}H${r1(rwL + 1)}M2,${rw.w / 2 - 1}H${r1(rwL + 1)}`} stroke="#f4f1e6" strokeWidth={0.5} />
          {[-3.6, -1.8, 0, 1.8, 3.6].map((y) => (
            <path key={y} d={`M2,${y}H7M${r1(rwL - 5)},${y}H${r1(rwL)}`} stroke="#f4f1e6" strokeWidth={0.9} />
          ))}
        </g>
        {/* taxiway, apron, terminal and a parked plane, laid out relative to TERMINAL */}
        <g transform={`translate(${TERMINAL.x} ${TERMINAL.y})`}>
          <path d="M-22,0L-6,10" stroke="#4c4855" strokeWidth={5} strokeLinecap="round" />
          <path d="M-12,4L14,-8L18,14L-6,20Z" fill="#8f8b97" />
          <rect x={4} y={-24} width={24} height={9} rx={1} fill="#e9e4dc" stroke="#7a7486" strokeWidth={0.6} transform="rotate(-34 16 -19)" />
          <rect x={4} y={-24} width={24} height={3.4} fill="#6aa3ac" transform="rotate(-34 16 -19)" />
        </g>
        <g transform={`translate(${TERMINAL.x + 2} ${TERMINAL.y + 8}) rotate(-34)`}>
          <path d="M-7,0L7,0M-1,-6.5L1.5,0L-1,6.5M-6,-2.5L-5,0L-6,2.5" stroke="#f7f7f2" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" fill="none" />
          <path d="M-7,0L7,0" stroke="#2f7fc1" strokeWidth={0.6} />
        </g>
      </g>

      {/* L11 vegetation */}
      <path d={m.trees.shadow} fill="#1f3a3d" opacity={0.3} />
      <path d={m.trees.base[0]} fill="#3f8a3c" />
      <path d={m.trees.base[1]} fill="#2f7a3a" />
      <path d={m.trees.base[2]} fill="#5a9a3e" />
      <path d={m.trees.hi[0]} fill="#78b856" />
      <path d={m.trees.hi[1]} fill="#5aa458" />
      <path d={m.trees.hi[2]} fill="#9ccc62" />
      <path d={m.palms.shadow} fill="#1f3a3d" opacity={0.28} />
      <path d={m.palms.frond} fill="#3d8a3a" stroke="#2a6a30" strokeWidth={0.35} />
      <path d={m.palms.frondHi} stroke="#a6d46a" strokeWidth={0.6} fill="none" />

      {/* L12 traffic */}
      <g className="map-traffic">
        {m.vehicles.map((v, i) => (
          <VehicleG key={i} v={v} />
        ))}
      </g>

      {/* L13 texture + light */}
      <rect width="1000" height="1000" fill="url(#map-grain)" opacity={0.55} pointerEvents="none" />
    </g>
  );
});

/* ------------------------------------------------------------------ */
/* Lighting (day sun / night grade)                                     */
/* ------------------------------------------------------------------ */
export const MapLight = memo(function MapLight({ night }: { night: boolean }) {
  const m = getMapModel();
  if (!night)
    return (
      <g pointerEvents="none">
        <rect width="1000" height="1000" fill="url(#map-sun)" />
        <rect width="1000" height="1000" fill="url(#map-vignette)" />
      </g>
    );
  const lampGlow = m.lampPts.map(([x, y]) => circleD(x, y, 11)).join('');
  const lampMid = m.lampPts.map(([x, y]) => circleD(x, y, 4.5)).join('');
  const lampCore = m.lampPts.map(([x, y]) => circleD(x, y, 1.3)).join('');
  const winGlow = m.windowPts.map(([x, y]) => circleD(x, y, 4.2)).join('');
  const win = m.windowPts.map(([x, y]) => `M${r1(x - 0.9)},${r1(y - 0.9)}h1.8v1.8h-1.8Z`).join('');
  const rw = RUNWAY;
  let runwayLights = '';
  for (let t = 0; t <= 1.0001; t += 1 / 14) {
    const x = rw.x1 + (rw.x2 - rw.x1) * t;
    const y = rw.y1 + (rw.y2 - rw.y1) * t;
    const L = Math.hypot(rw.x2 - rw.x1, rw.y2 - rw.y1);
    const nx = (-(rw.y2 - rw.y1) / L) * (rw.w / 2 + 1);
    const ny = ((rw.x2 - rw.x1) / L) * (rw.w / 2 + 1);
    runwayLights += circleD(x + nx, y + ny, 0.9) + circleD(x - nx, y - ny, 0.9);
  }
  return (
    <g pointerEvents="none" className="map-night">
      <rect width="1000" height="1000" fill="#0c1036" opacity={0.6} />
      <rect width="1000" height="1000" fill="url(#map-moon)" />
      <path d={m.river.d} stroke="#c9dcff" strokeWidth={1.4} strokeDasharray="2 11" fill="none" opacity={0.55} />
      <path d={winGlow} fill="#ffb24a" opacity={0.16} />
      <path d={win} fill="#ffd77e" />
      <path d={lampGlow} fill="#ffcf73" opacity={0.12} />
      <path d={lampMid} fill="#ffd98c" opacity={0.28} />
      <path d={lampCore} fill="#fff6d6" />
      <path d={runwayLights} fill="#bfe2ff" />
      {NIGHT_GLOWS.map(([x, y, r, o]) => (
        <circle key={`${x},${y}`} cx={x} cy={y} r={r} fill="url(#map-glow-warm)" opacity={o} />
      ))}
      <rect width="1000" height="1000" fill="url(#map-night-vig)" />
    </g>
  );
});

/* ------------------------------------------------------------------ */
/* Labels (district names, road names, exits, compass, cartouche)       */
/* ------------------------------------------------------------------ */
export const MapLabels = memo(function MapLabels({ night }: { night: boolean }) {
  const m = getMapModel();
  const riverLabel = useMemo(() => labelPath(m.river, 60, 190), [m]);
  const dFill = night ? '#f4dfbd' : '#6a2c12';
  const dHalo = night ? '#141634' : '#fbeed6';
  return (
    <g className="map-labels" pointerEvents="none" fontFamily={FONT}>
      <defs>
        {m.roadLabels.map((l) => (
          <path key={l.id} id={`map-rl-${l.id}`} d={l.d} />
        ))}
        <path id="map-rl-river" d={riverLabel} />
      </defs>
      {DISTRICT_LABELS.map((l) => (
        <text
          key={l.t}
          x={l.x}
          y={l.y}
          transform={l.rot ? `rotate(${l.rot} ${l.x} ${l.y})` : undefined}
          textAnchor="middle"
          fontSize={l.size ?? 18}
          fontWeight={800}
          letterSpacing={(l.size ?? 18) * 0.22}
          fill={dFill}
          fillOpacity={night ? 0.62 : 0.6}
          stroke={dHalo}
          strokeOpacity={0.65}
          strokeWidth={3}
          paintOrder="stroke"
          strokeLinejoin="round"
        >
          {l.t}
        </text>
      ))}
      {m.roadLabels.map((l) => (
        <text key={l.id} fontSize={9.6} fontWeight={700} fill="#fff8ea" stroke="#3a2833" strokeWidth={2.6} paintOrder="stroke" strokeLinejoin="round" dy={3.3} letterSpacing={0.3}>
          <textPath href={`#map-rl-${l.id}`} startOffset="50%" textAnchor="middle">
            {l.text}
          </textPath>
        </text>
      ))}
      <text fontSize={10} fontStyle="italic" fontWeight={700} fill={night ? '#cfe6ff' : '#1d5a7c'} stroke={night ? '#141634' : '#e6f4f2'} strokeWidth={2.4} paintOrder="stroke" dy={-12}>
        <textPath href="#map-rl-river" startOffset="50%" textAnchor="middle">
          Ikpoba River
        </textPath>
      </text>
      {EXITS.map((e) => (
        <ExitSign key={e.text} {...e} />
      ))}
      <Compass night={night} />
      <g transform="translate(905 960)">
        <rect x={-88} y={-26} width={176} height={46} rx={7} fill={night ? '#1b1e46' : '#fbf0dc'} stroke="#b0793a" strokeWidth={2} opacity={0.94} />
        <rect x={-84} y={-22} width={168} height={38} rx={5} fill="none" stroke="#d2342a" strokeWidth={0.8} strokeDasharray="1.5 2.5" />
        <text y={-3} textAnchor="middle" fontSize={17} fontWeight={800} letterSpacing={3} fill={night ? '#f3d28a' : '#7a2e14'}>
          BENIN CITY
        </text>
        <text y={11} textAnchor="middle" fontSize={7.6} fontWeight={600} letterSpacing={1.4} fill={night ? '#c9b9a6' : '#8a5a3a'}>
          EDO STATE · NIGERIA
        </text>
      </g>
    </g>
  );
});

function ExitSign({ text, sub, x, y, arrow }: (typeof EXITS)[number]) {
  const w = 74;
  const arrowD = {
    l: 'M-30,0L-22,-6V-2.5H-15V2.5H-22V6Z',
    r: 'M30,0L22,-6V-2.5H15V2.5H22V6Z',
    d: 'M-26,6L-32,-1H-28.5V-7H-23.5V-1H-20Z',
    u: 'M-26,-7L-32,0H-28.5V6H-23.5V0H-20Z',
  }[arrow];
  const tx = arrow === 'r' ? -6 : 6;
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x={-w / 2 + 1.5} y={-11} width={w} height={26} rx={4} fill="#13281b" opacity={0.3} />
      <rect x={-w / 2} y={-13} width={w} height={26} rx={4} fill="#1f7a3f" stroke="#f6f1e4" strokeWidth={1.4} />
      <path d={arrowD} fill="#f6f1e4" />
      <text x={tx} y={-1} textAnchor="middle" fontSize={10.5} fontWeight={800} fill="#f6f1e4" letterSpacing={0.8}>
        {text}
      </text>
      {sub && (
        <text x={tx} y={9} textAnchor="middle" fontSize={7} fontWeight={600} fill="#cfe8d4">
          {sub}
        </text>
      )}
    </g>
  );
}

function Compass({ night }: { night: boolean }) {
  return (
    <g transform="translate(958 46)">
      <circle r={24} fill={night ? '#1b1e46' : '#fbf0dc'} opacity={0.9} stroke="#b0793a" strokeWidth={1.6} />
      <circle r={19} fill="none" stroke="#b0793a" strokeWidth={0.6} strokeDasharray="1 2" />
      <path d="M0,-18L4,0L0,18L-4,0Z" fill={night ? '#c9b9a6' : '#7a4d1f'} />
      <path d="M0,-18L4,0H-4Z" fill="#d2342a" />
      <path d="M-14,0L0,3L14,0L0,-3Z" fill={night ? '#8a85a8' : '#b0793a'} opacity={0.7} />
      <text y={-25.5} textAnchor="middle" fontSize={9} fontWeight={800} fill="#d2342a" stroke={night ? '#1b1e46' : '#fbf0dc'} strokeWidth={2} paintOrder="stroke">
        N
      </text>
    </g>
  );
}
