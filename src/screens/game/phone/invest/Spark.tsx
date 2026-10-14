// I1: tiny SVG charts. Spark = card sparkline (no axes); LineChart = the big one in sheets, with crosshair + tooltip.
// One series, one colour (green when it ended up, red when down; the delta text always carries the sign), 2px line,
// light area, recessive grid. Points are [epoch seconds, value].
import { useId, useMemo, useRef, useState } from 'react';
import { naira } from '../../../../lib/format';

export type Pt = [number, number];

const UP = '#12924f';
const DOWN = '#c3352a';

function scale(pts: Pt[], w: number, h: number, pad: number) {
  const xs = pts.map((p) => p[0]);
  const ys = pts.map((p) => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs);
  let y0 = Math.min(...ys), y1 = Math.max(...ys);
  if (y1 - y0 < 1e-9) { y0 -= 1; y1 += 1; }
  const padY = (y1 - y0) * 0.08;
  y0 -= padY; y1 += padY;
  const sx = (x: number) => pad + ((x - x0) / Math.max(1, x1 - x0)) * (w - pad * 2);
  const sy = (y: number) => h - pad - ((y - y0) / (y1 - y0)) * (h - pad * 2);
  return { sx, sy, y0, y1, x0, x1 };
}

export function trend(pts: Pt[]): { up: boolean; pct: number } {
  if (pts.length < 2) return { up: true, pct: 0 };
  const a = pts[0][1], b = pts[pts.length - 1][1];
  return { up: b >= a, pct: a ? (b / a - 1) * 100 : 0 };
}

export function Spark({ pts, width = 96, height = 34, label }: { pts: Pt[]; width?: number; height?: number; label?: string }) {
  const id = useId();
  const g = useMemo(() => {
    if (pts.length < 2) return null;
    const s = scale(pts, width, height, 2);
    const line = pts.map((p, i) => `${i ? 'L' : 'M'}${s.sx(p[0]).toFixed(1)},${s.sy(p[1]).toFixed(1)}`).join('');
    const last = pts[pts.length - 1];
    return { line, area: `${line}L${s.sx(last[0]).toFixed(1)},${height}L${s.sx(pts[0][0]).toFixed(1)},${height}Z`, lx: s.sx(last[0]), ly: s.sy(last[1]) };
  }, [pts, width, height]);
  if (!g) return <svg className="inv-spark" width={width} height={height} aria-hidden />;
  const col = trend(pts).up ? UP : DOWN;
  return (
    <svg className="inv-spark" width={width} height={height} viewBox={`0 0 ${width} ${height}`} role="img" aria-label={label ?? 'Price trend'}>
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={col} stopOpacity="0.22" />
          <stop offset="1" stopColor={col} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={g.area} fill={`url(#${id})`} />
      <path d={g.line} fill="none" stroke={col} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={g.lx} cy={g.ly} r="2.6" fill={col} stroke="#fff" strokeWidth="1.5" />
    </svg>
  );
}

function when(t: number): string {
  const d = new Date(t * 1000);
  return d.toLocaleString('en-GB', { timeZone: 'Africa/Lagos', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

export function LineChart({ pts, height = 150, format = (v: number) => naira(Math.round(v)), label }: {
  pts: Pt[]; height?: number; format?: (v: number) => string; label: string;
}) {
  const id = useId();
  const ref = useRef<SVGSVGElement>(null);
  const [hover, setHover] = useState<number | null>(null);
  const W = 340;
  const g = useMemo(() => {
    if (pts.length < 2) return null;
    const s = scale(pts, W, height, 6);
    const line = pts.map((p, i) => `${i ? 'L' : 'M'}${s.sx(p[0]).toFixed(1)},${s.sy(p[1]).toFixed(1)}`).join('');
    return { s, line, area: `${line}L${s.sx(pts[pts.length - 1][0]).toFixed(1)},${height}L${s.sx(pts[0][0]).toFixed(1)},${height}Z` };
  }, [pts, height]);
  if (!g) return <div className="inv-chart inv-chart--empty">Chart is warming up…</div>;
  const col = trend(pts).up ? UP : DOWN;
  const onMove = (e: React.PointerEvent) => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    const fx = ((e.clientX - r.left) / r.width) * W;
    let best = 0, bd = Infinity;
    pts.forEach((p, i) => { const d = Math.abs(g.s.sx(p[0]) - fx); if (d < bd) { bd = d; best = i; } });
    setHover(best);
  };
  const hp = hover != null ? pts[hover] : null;
  const gridY = [0.25, 0.5, 0.75].map((f) => height * f);
  return (
    <div className="inv-chart">
      <svg ref={ref} viewBox={`0 0 ${W} ${height}`} width="100%" height={height} role="img" aria-label={label}
        onPointerMove={onMove} onPointerDown={onMove} onPointerLeave={() => setHover(null)} style={{ touchAction: 'pan-y' }}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={col} stopOpacity="0.2" />
            <stop offset="1" stopColor={col} stopOpacity="0" />
          </linearGradient>
        </defs>
        {gridY.map((y) => <line key={y} x1="0" x2={W} y1={y} y2={y} stroke="rgba(17,32,56,0.07)" strokeWidth="1" />)}
        <path d={g.area} fill={`url(#${id})`} />
        <path d={g.line} fill="none" stroke={col} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
        {hp ? (
          <g>
            <line x1={g.s.sx(hp[0])} x2={g.s.sx(hp[0])} y1="0" y2={height} stroke="rgba(17,32,56,0.3)" strokeWidth="1" />
            <circle cx={g.s.sx(hp[0])} cy={g.s.sy(hp[1])} r="4" fill={col} stroke="#fff" strokeWidth="2" />
          </g>
        ) : (
          <circle cx={g.s.sx(pts[pts.length - 1][0])} cy={g.s.sy(pts[pts.length - 1][1])} r="3.5" fill={col} stroke="#fff" strokeWidth="2" />
        )}
      </svg>
      <div className="inv-chart__axis"><span>{when(pts[0][0])}</span><span>{hp ? '' : 'now'}</span></div>
      {hp && (
        <div className="inv-chart__tip" style={{ left: `${Math.min(78, Math.max(2, (g.s.sx(hp[0]) / W) * 100 - 10))}%` }}>
          <b>{format(hp[1])}</b><span>{when(hp[0])}</span>
        </div>
      )}
    </div>
  );
}
