// P1-MAP — interactive overlays: location pins (re-render only on prop / committed-zoom change)
// and the travel route. Pins counter-scale with zoom so they stay thumb-sized on phones.
import { memo, useMemo } from 'react';
import type { Location } from '../../lib/types';
import { PIN_META, r1, shortName, type LabelSide } from './mapGeo';
import { PIN_STYLE, PinGlyph, SCENES } from './pinIcons';

const FONT = "'Figtree', 'Segoe UI', system-ui, -apple-system, sans-serif";
const BADGE_Y = -24;
const BADGE_R = 13;
const LABEL_FS = 11.5;
const PIN_D = `M0,0C-3,-6 -${BADGE_R},-14 -${BADGE_R},${BADGE_Y}A${BADGE_R},${BADGE_R} 0 1,1 ${BADGE_R},${BADGE_Y}C${BADGE_R},-14 3,-6 0,0Z`;

/** Pin scale (map units) for a given zoom: pins grow only gently when you zoom in. */
export const pinScaleFor = (zoom: number) => Math.min(2.4, Math.max(0.36, Math.pow(zoom, -0.72)));

export const isNightRisky = (l: Location) => l.risk * l.night_risk_mult >= 1.2;

type Box = [number, number, number, number];
const overlap = (a: Box, b: Box) => a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1];

function labelBox(l: Location, side: LabelSide, text: string, ps: number): Box {
  const w = text.length * LABEL_FS * 0.56 * ps;
  const h = LABEL_FS * ps; // cap top to descender of the 11.5px label
  const { x, y } = l;
  switch (side) {
    case 'r':
      return [x + 15 * ps, y + (BADGE_Y - 7) * ps, x + 15 * ps + w, y + (BADGE_Y - 7) * ps + h];
    case 'l':
      return [x - 15 * ps - w, y + (BADGE_Y - 7) * ps, x - 15 * ps, y + (BADGE_Y - 7) * ps + h];
    case 't':
      return [x - w / 2, y - 52 * ps, x + w / 2, y - 52 * ps + h];
    default:
      return [x - w / 2, y + 4 * ps, x + w / 2, y + 4 * ps + h];
  }
}

/** Greedy label placement in map space: priority selected > current > landmarks > the rest. */
export function layoutLabels(locs: Location[], zoom: number, currentId?: string, selectedId?: string): Map<string, LabelSide> {
  const ps = pinScaleFor(zoom);
  const out = new Map<string, LabelSide>();
  const badges = new Map<string, Box>(
    // badge circle + tail; the circle's bbox corners are empty, so trim the sides a little
    locs.map((l) => [l.id, [l.x - BADGE_R * 0.85 * ps, l.y + (BADGE_Y - BADGE_R) * ps, l.x + BADGE_R * 0.85 * ps, l.y + 2 * ps] as Box]),
  );
  const taken: Box[] = [];
  // the "You dey here" tag floats above the current pin (body scaled ×1.12)
  const cur = currentId ? locs.find((l) => l.id === currentId) : undefined;
  if (cur) taken.push([cur.x - 39 * ps, cur.y - 63.5 * ps, cur.x + 39 * ps, cur.y - 42 * ps]);
  const prio = (l: Location) => (l.id === selectedId ? 0 : l.id === currentId ? 1 : (PIN_META[l.id]?.tier ?? 2) + 1);
  const order = [...locs].sort((a, b) => prio(a) - prio(b) || a.sort - b.sort);
  for (const l of order) {
    const must = l.id === selectedId || l.id === currentId;
    const tier = PIN_META[l.id]?.tier ?? 2;
    if (!must && tier === 2 && zoom < 0.95) continue;
    if (!must && zoom < 0.5) continue;
    const text = shortName(l.id, l.name);
    const pref = PIN_META[l.id]?.side ?? 'b';
    const sides: LabelSide[] = [pref, ...(['b', 'r', 'l', 't'] as LabelSide[]).filter((s) => s !== pref)];
    let placed: LabelSide | null = null;
    for (const s of sides) {
      // 't' is reserved for the "You dey here" tag on the current pin
      if (s === 't' && l.id === currentId) continue;
      const box = labelBox(l, s, text, ps);
      if (box[0] < 2 || box[2] > 998 || box[1] < 2 || box[3] > 998) continue;
      if (taken.some((t) => overlap(t, box))) continue;
      let hit = false;
      for (const [id, b] of badges) if (id !== l.id && overlap(b, box)) hit = true;
      if (hit) continue;
      placed = s;
      taken.push(box);
      break;
    }
    if (!placed && must) {
      placed = pref === 't' && l.id === currentId ? 'b' : pref;
      taken.push(labelBox(l, placed, text, ps));
    }
    if (placed) out.set(l.id, placed);
  }
  return out;
}

/* ------------------------------------------------------------------ */
export function PinDefs() {
  return (
    <defs>
      {SCENES.map((s) => (
        <linearGradient key={s} id={`map-pin-${s}`} x1="0" y1="0" x2="0.35" y2="1" colorInterpolation="linearRGB">
          <stop offset="0%" stopColor={PIN_STYLE[s].c1} />
          <stop offset="55%" stopColor={PIN_STYLE[s].c2} stopOpacity={0.85} />
          <stop offset="100%" stopColor={PIN_STYLE[s].c2} />
        </linearGradient>
      ))}
      <radialGradient id="map-sel-glow">
        <stop offset="0%" stopColor="#ff8a66" stopOpacity={0.95} />
        <stop offset="45%" stopColor="#f06a55" stopOpacity={0.55} />
        <stop offset="100%" stopColor="#d2342a" stopOpacity={0} />
      </radialGradient>
      <radialGradient id="map-danger">
        <stop offset="0%" stopColor="#ff4a3b" stopOpacity={0.85} />
        <stop offset="45%" stopColor="#ff2a3a" stopOpacity={0.5} />
        <stop offset="75%" stopColor="#e0142a" stopOpacity={0.2} />
        <stop offset="100%" stopColor="#9c0f1f" stopOpacity={0} />
      </radialGradient>
      <radialGradient id="map-pin-shine" cx="35%" cy="25%" r="60%">
        <stop offset="0%" stopColor="#ffffff" stopOpacity={0.55} />
        <stop offset="100%" stopColor="#ffffff" stopOpacity={0} />
      </radialGradient>
    </defs>
  );
}

interface PinsProps {
  locations: Location[];
  currentId?: string;
  selectedId?: string;
  night: boolean;
  crowd?: Record<string, number>;
  zoom: number;
  onSelect: (id: string) => void;
}

export const MapPins = memo(function MapPins({ locations, currentId, selectedId, night, crowd, zoom, onSelect }: PinsProps) {
  const ps = pinScaleFor(zoom);
  const labels = useMemo(() => layoutLabels(locations, zoom, currentId, selectedId), [locations, zoom, currentId, selectedId]);
  // Draw selected/current last so they sit on top.
  const ordered = useMemo(() => {
    const rank = (l: Location) => (l.id === selectedId ? 2 : l.id === currentId ? 1 : 0);
    return [...locations].sort((a, b) => rank(a) - rank(b) || a.y - b.y);
  }, [locations, currentId, selectedId]);

  return (
    <g className="map-pins" fontFamily={FONT}>
      {ordered.map((l) => (
        <Pin
          key={l.id}
          loc={l}
          ps={ps}
          side={labels.get(l.id)}
          current={l.id === currentId}
          selected={l.id === selectedId}
          night={night}
          count={crowd?.[l.id] ?? 0}
          onSelect={onSelect}
        />
      ))}
    </g>
  );
});

interface PinProps {
  loc: Location;
  ps: number;
  side?: LabelSide;
  current: boolean;
  selected: boolean;
  night: boolean;
  count: number;
  onSelect: (id: string) => void;
}

function Pin({ loc, ps, side, current, selected, night, count, onSelect }: PinProps) {
  const text = shortName(loc.id, loc.name);
  const danger = night && isNightRisky(loc);
  const bodyScale = selected ? 1.3 : current ? 1.12 : 1;
  const k = bodyScale; // label offsets follow the body size
  const labelProps = (() => {
    switch (side) {
      case 'r':
        return { x: 15 * k, y: (BADGE_Y + 2) * k, textAnchor: 'start' as const };
      case 'l':
        return { x: -15 * k, y: (BADGE_Y + 2) * k, textAnchor: 'end' as const };
      case 't':
        return { x: 0, y: -42 * k, textAnchor: 'middle' as const };
      default:
        return { x: 0, y: 13, textAnchor: 'middle' as const };
    }
  })();
  const countText = count > 99 ? '99+' : String(count);
  const bubbleW = countText.length > 1 ? 7 + countText.length * 5.2 : 15;

  return (
    <g
      className={`map-pin${selected ? ' is-selected' : ''}${current ? ' is-current' : ''}`}
      data-pin-id={loc.id}
      role="button"
      tabIndex={0}
      aria-label={`${loc.name}${current ? ' — you dey here' : ''}${count > 0 ? `, ${count} people` : ''}`}
      style={{ transform: `translate(${r1(loc.x)}px, ${r1(loc.y)}px) scale(${ps.toFixed(3)})` }}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onSelect(loc.id);
        }
      }}
    >
      {danger && (
        <g className="map-danger">
          <circle cy={BADGE_Y} r={40} fill="url(#map-danger)" />
          <circle cy={BADGE_Y} r={27} fill="none" stroke="#ff5a4a" strokeOpacity={0.7} strokeWidth={1.4} strokeDasharray="4 3.5" />
        </g>
      )}
      {selected && <circle className="map-sel-glow" cy={BADGE_Y * 1.3} r={40} fill="url(#map-sel-glow)" />}
      <ellipse cx={1.5} cy={0.5} rx={selected ? 9 : 6.5} ry={selected ? 3.4 : 2.6} fill={selected ? '#d2342a' : '#2a1030'} opacity={selected ? 0.55 : 0.35} />
      {current && (
        <g>
          <ellipse rx={11} ry={4.2} fill="none" stroke="#2ee07a" strokeWidth={2} className="map-pulse" />
          <circle cy={BADGE_Y * k} r={BADGE_R * k + 3} fill="none" stroke="#2ee07a" strokeWidth={2.4} className="map-pulse" />
        </g>
      )}
      <g className="map-pin-body" style={{ transform: `scale(${bodyScale})` }}>
        <circle cy={BADGE_Y + 1} r={21} fill="transparent" className="map-pin-hit" />
        <path d={PIN_D} fill={`url(#map-pin-${loc.scene})`} stroke={current ? '#2ee07a' : selected ? '#fff3e6' : '#fffaf0'} strokeWidth={current ? 2.6 : 2} className="map-pin-rim" />
        <circle cy={BADGE_Y} r={BADGE_R - 2.6} fill="none" stroke="#ffffff" strokeOpacity={0.28} strokeWidth={0.8} />
        <circle cx={-3} cy={BADGE_Y - 4} r={8} fill="url(#map-pin-shine)" />
        <g transform={`translate(0 ${BADGE_Y}) scale(0.92)`}>
          <PinGlyph scene={loc.scene} />
        </g>
        {count > 0 && (
          <g transform={`translate(${BADGE_R - 2} ${BADGE_Y - BADGE_R + 1})`}>
            <rect x={-bubbleW / 2} y={-7} width={bubbleW} height={14} rx={7} fill={night ? '#f3d28a' : '#2a2d5c'} stroke="#fffaf0" strokeWidth={1.5} />
            <text y={3.4} textAnchor="middle" fontSize={9.5} fontWeight={800} fill={night ? '#2a160d' : '#fffaf0'}>
              {countText}
            </text>
          </g>
        )}
      </g>
      {current && (
        <g transform={`translate(0 ${r1(BADGE_Y * k - BADGE_R * k - 13)})`} className="map-here">
          <path d="M-36,-9H36A3,3 0 0 1 39,-6V5A3,3 0 0 1 36,8H4L0,12L-4,8H-36A3,3 0 0 1 -39,5V-6A3,3 0 0 1 -36,-9Z" fill="#1f7a3f" stroke="#fffaf0" strokeWidth={1.4} />
          <text y={3} textAnchor="middle" fontSize={10.5} fontWeight={800} fill="#fffaf0" letterSpacing={0.2}>
            You dey here
          </text>
        </g>
      )}
      {side && (
        <text
          {...labelProps}
          fontSize={LABEL_FS}
          fontWeight={800}
          fill={selected ? (night ? '#ffb39f' : '#9c1f19') : night ? '#fbf0dc' : '#2a160d'}
          stroke={night ? '#141634' : '#fff8ea'}
          strokeWidth={3.6}
          strokeLinejoin="round"
          paintOrder="stroke"
          className="map-pin-label"
        >
          {text}
        </text>
      )}
    </g>
  );
}

/* ------------------------------------------------------------------ */
/* Travel route                                                         */
/* ------------------------------------------------------------------ */
interface TravelProps {
  from: Location;
  to: Location;
  progress: number;
  zoom: number;
}

export function TravelLayer({ from, to, progress, zoom }: TravelProps) {
  const ps = pinScaleFor(zoom);
  const t = Math.max(0, Math.min(1, progress));
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const dist = Math.hypot(dx, dy) || 1;
  const bow = Math.min(90, dist * 0.2);
  const cx = (from.x + to.x) / 2 - (dy / dist) * bow;
  const cy = (from.y + to.y) / 2 + (dx / dist) * bow;
  const bez = (u: number) => {
    const v = 1 - u;
    return [v * v * from.x + 2 * v * u * cx + u * u * to.x, v * v * from.y + 2 * v * u * cy + u * u * to.y];
  };
  const [px, py] = bez(t);
  const [ax, ay] = bez(Math.min(1, t + 0.01));
  const [bx, by] = bez(Math.max(0, t - 0.01));
  const ang = (Math.atan2(ay - by, ax - bx) * 180) / Math.PI;
  const d = `M${r1(from.x)},${r1(from.y)}Q${r1(cx)},${r1(cy)} ${r1(to.x)},${r1(to.y)}`;
  const w = Math.max(2.2, 3.6 * ps);
  const flip = Math.abs(ang) > 90;
  return (
    <g className="map-travel" pointerEvents="none">
      <path d={d} fill="none" stroke="#2a1030" strokeOpacity={0.35} strokeWidth={w + 3.5} strokeLinecap="round" />
      <path d={d} fill="none" stroke="#fffaf0" strokeWidth={w + 1.6} strokeLinecap="round" />
      <path d={d} fill="none" stroke="#d2342a" strokeWidth={w} strokeLinecap="round" strokeDasharray={`${r1(w * 2.4)} ${r1(w * 1.8)}`} className="map-route-dash" />
      <path d={d} fill="none" stroke="#1f7a3f" strokeWidth={w} strokeLinecap="round" pathLength={1} strokeDasharray={`${t.toFixed(4)} 2`} />
      <g style={{ transform: `translate(${r1(to.x)}px, ${r1(to.y)}px) scale(${ps.toFixed(3)})` }}>
        <ellipse rx={16} ry={6} fill="none" stroke="#d2342a" strokeWidth={2.4} className="map-pulse" />
      </g>
      <g style={{ transform: `translate(${r1(px)}px, ${r1(py)}px) scale(${ps.toFixed(3)})` }}>
        <circle r={13} fill="#fffaf0" stroke="#1f7a3f" strokeWidth={2.6} />
        <g transform={`rotate(${r1(flip ? ang + 180 : ang)}) scale(${flip ? -1 : 1} 1)`}>
          <rect x={-8} y={-4.4} width={16} height={8.8} rx={2.6} fill="#f2c230" stroke="#6b520c" strokeWidth={0.8} />
          <rect x={2.4} y={-3.4} width={3.2} height={6.8} rx={0.8} fill="#2a3a55" />
          <rect x={-6} y={-3.4} width={2.4} height={6.8} rx={0.6} fill="#2a3a55" opacity={0.8} />
          <rect x={-2.6} y={-3.6} width={4.4} height={7.2} fill="#1f7a3f" opacity={0.9} />
        </g>
      </g>
    </g>
  );
}

export const MAP_CSS = `
.map-pin{cursor:pointer;outline:none}
.map-pin,.map-travel>g{transition:transform .22s cubic-bezier(.22,1,.36,1)}
.map-pin-body{transition:transform .22s cubic-bezier(.34,1.4,.64,1)}
.map-pin:focus-visible .map-pin-rim{stroke:#f3d28a;stroke-width:3.4}
.map-pulse{transform-box:fill-box;transform-origin:center;animation:map-pulse 1.9s ease-out infinite}
@keyframes map-pulse{0%{transform:scale(.75);opacity:.95}100%{transform:scale(1.9);opacity:0}}
.map-danger{animation:map-danger 2.6s ease-in-out infinite}
@keyframes map-danger{0%,100%{opacity:.5}50%{opacity:1}}
.map-sel-glow{transform-box:fill-box;transform-origin:center;animation:map-breathe 2.2s ease-in-out infinite}
@keyframes map-breathe{0%,100%{transform:scale(.92);opacity:.85}50%{transform:scale(1.08);opacity:1}}
.map-route-dash{animation:map-dash .9s linear infinite}
@keyframes map-dash{to{stroke-dashoffset:-20}}
@media (prefers-reduced-motion:reduce){.map-pulse,.map-danger,.map-sel-glow,.map-route-dash{animation:none}.map-pin,.map-pin-body,.map-travel>g{transition:none}}
`;
