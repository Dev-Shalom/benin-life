// The drive's mini-map: the route from the city map's own road data, a dot for the car. Tap to open it bigger and tap again to close it.
// Small by default (top-left under the route chip) so the road stays clear. Tokens only, so Light and Dark both work.
import { memo, useMemo } from 'react';
import { RING, ROADS } from '../map/mapGeo';
import type { Track } from './track';

interface Props {
  track: Track;
  /** Metres along the track (the car). */
  s: number;
  open: boolean;
  onToggle: () => void;
  fromName: string;
  toName: string;
}

function MiniMapBase({ track, s, open, onToggle, fromName, toName }: Props) {
  const geo = useMemo(() => {
    const pts = track.mapPts;
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    for (const [x, y] of pts) {
      x0 = Math.min(x0, x);
      y0 = Math.min(y0, y);
      x1 = Math.max(x1, x);
      y1 = Math.max(y1, y);
    }
    const pad = 38;
    let w = x1 - x0 + pad * 2;
    let h = y1 - y0 + pad * 2;
    const side = Math.max(w, h, 150);
    const cx = (x0 + x1) / 2;
    const cy = (y0 + y1) / 2;
    w = h = side;
    const vb = [cx - side / 2, cy - side / 2, side, side] as const;
    const inView = (px: number, py: number) => px > vb[0] - 60 && px < vb[0] + side + 60 && py > vb[1] - 60 && py < vb[1] + side + 60;
    const roads = ROADS.filter((r) => r.pts.some(([px, py]) => inView(px, py))).map((r) => ({
      id: r.id,
      kind: r.kind,
      d: 'M' + r.pts.map((p) => `${p[0].toFixed(0)},${p[1].toFixed(0)}`).join('L'),
    }));
    const ring = inView(RING.x, RING.y);
    const route = 'M' + pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('L');
    return { vb, roads, ring, route, side };
  }, [track]);

  const dot = track.mapAt(s);
  // the part already driven: the route points up to the car
  const driven = useMemo(() => {
    const pts = track.mapPts;
    let best = 0;
    let bd = Infinity;
    pts.forEach((p, i) => {
      const d = (p[0] - dot[0]) ** 2 + (p[1] - dot[1]) ** 2;
      if (d < bd) {
        bd = d;
        best = i;
      }
    });
    return 'M' + pts.slice(0, best + 1).map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('L') + `L${dot[0].toFixed(1)},${dot[1].toFixed(1)}`;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [track, Math.round(dot[0] / 2), Math.round(dot[1] / 2)]);

  const start = track.mapPts[0];
  const end = track.mapPts[track.mapPts.length - 1];
  const u = geo.side / 100; // one "pixel" of a 100 px map, so strokes keep their look at any route size
  return (
    <button type="button" className={`drive-mini${open ? ' is-open' : ''}`} onClick={onToggle} aria-label={open ? 'Close the mini-map' : 'Open the mini-map'} aria-expanded={open}>
      <svg viewBox={geo.vb.join(' ')} preserveAspectRatio="xMidYMid meet" role="img" aria-hidden="true">
        {geo.ring && <circle className="mm-road mm-road--main" cx={RING.x} cy={RING.y} r={RING.r} strokeWidth={u * 1.7} fill="none" />}
        {geo.roads.map((r) => (
          <path key={r.id} className={`mm-road mm-road--${r.kind}`} d={r.d} fill="none" strokeWidth={u * (r.kind === 'express' ? 2 : r.kind === 'main' ? 1.6 : 1)} strokeLinecap="round" strokeLinejoin="round" />
        ))}
        <path className="mm-route" d={geo.route} fill="none" strokeWidth={u * 3.4} strokeLinecap="round" strokeLinejoin="round" />
        <path className="mm-driven" d={driven} fill="none" strokeWidth={u * 3.4} strokeLinecap="round" strokeLinejoin="round" />
        <circle className="mm-from" cx={start[0]} cy={start[1]} r={u * 3.4} strokeWidth={u * 1.6} />
        <g transform={`translate(${end[0]} ${end[1]})`}>
          <path className="mm-to" d={`M0 0 C ${-u * 4} ${-u * 5} ${-u * 4.6} ${-u * 10} 0 ${-u * 10.6} C ${u * 4.6} ${-u * 10} ${u * 4} ${-u * 5} 0 0Z`} />
          <circle className="mm-to-dot" cx={0} cy={-u * 6.6} r={u * 1.8} />
        </g>
        <circle className="mm-car-halo" cx={dot[0]} cy={dot[1]} r={u * 6.4} />
        <circle className="mm-car" cx={dot[0]} cy={dot[1]} r={u * 3.5} strokeWidth={u * 1.5} />
      </svg>
      {open && (
        <span className="drive-mini__names">
          <span>{fromName}</span>
          <span>{toName}</span>
        </span>
      )}
    </button>
  );
}

export const MiniMap = memo(MiniMapBase);
