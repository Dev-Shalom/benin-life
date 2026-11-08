// Free roam mini-map: the area from the same map data as the city map (roads, building outlines, King's Square), a moving
// arrow for the player, the GPS route and the place pins. Tap to open it big; tap a pin to walk there. The viewBox and the
// arrow move through refs (no React render per frame).
import { memo, useEffect, useMemo, useRef, type MutableRefObject } from 'react';
import { RING, ROADS } from '../map/mapGeo';
import { AREA } from './area';
import type { RoamLive } from './engine/RoamScene';
import type { RoamWorld } from './world';

interface Props {
  world: RoamWorld;
  live: MutableRefObject<RoamLive>;
  open: boolean;
  onToggle: () => void;
  destId: string | null;
  onPick: (id: string) => void;
}

const SMALL = 64; // metres each side of the player in the small map (on foot)
const SMALL_DRIVE = 130; // and in the car

function MiniBase({ world, live, open, onToggle, destId, onPick }: Props) {
  const svg = useRef<SVGSVGElement>(null);
  const me = useRef<SVGGElement>(null);
  const carMark = useRef<SVGRectElement>(null);
  const route = useRef<SVGPolylineElement>(null);
  const openRef = useRef(open);
  openRef.current = open;

  const geo = useMemo(() => {
    const pad = 22;
    const x0 = AREA.x0 - pad, y0 = AREA.y0 - pad, x1 = AREA.x1 + pad, y1 = AREA.y1 + pad;
    const inView = (px: number, py: number) => px > x0 - 30 && px < x1 + 30 && py > y0 - 30 && py < y1 + 30;
    const roads = ROADS.filter((r) => r.pts.some(([px, py]) => inView(px, py))).map((r) => ({
      id: r.id,
      kind: r.kind,
      d: 'M' + r.pts.map((p) => `${p[0].toFixed(0)},${p[1].toFixed(0)}`).join('L'),
    }));
    let b = '';
    for (const bl of world.buildings) {
      if (bl.detail !== 1 || bl.lm) continue;
      b += 'M' + bl.poly.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('L') + 'Z';
    }
    // landmark footprints (palace compound, museum) as outlines too
    return { x0, y0, x1, y1, roads, b };
  }, [world]);

  useEffect(() => {
    let raf = 0;
    let last = 0;
    const tick = (now: number) => {
      raf = requestAnimationFrame(tick);
      if (now - last < 90) return;
      last = now;
      const L = live.current;
      const el = svg.current;
      if (!el) return;
      if (openRef.current) {
        const w = geo.x1 - geo.x0, h = geo.y1 - geo.y0;
        el.setAttribute('viewBox', `${geo.x0} ${geo.y0} ${w} ${h}`);
      } else {
        const sp = L.car.driving ? SMALL_DRIVE : SMALL;
        el.setAttribute('viewBox', `${(L.x - sp).toFixed(1)} ${(L.y - sp).toFixed(1)} ${sp * 2} ${sp * 2}`);
      }
      const unit = openRef.current ? (geo.x1 - geo.x0) / 300 : (L.car.driving ? SMALL_DRIVE : SMALL) / 46;
      // your parked car, a small blue block on the map
      if (carMark.current) {
        const show = L.car.here && !L.car.driving;
        carMark.current.setAttribute('visibility', show ? 'visible' : 'hidden');
        if (show) {
          carMark.current.setAttribute('transform', `translate(${L.car.x.toFixed(1)} ${L.car.y.toFixed(1)}) rotate(${((L.car.h * 180) / Math.PI).toFixed(0)}) scale(${unit.toFixed(2)})`);
        }
      }
      if (me.current) me.current.setAttribute('transform', `translate(${L.x.toFixed(1)} ${L.y.toFixed(1)}) rotate(${((L.h * 180) / Math.PI).toFixed(0)}) scale(${unit.toFixed(2)})`);
      if (route.current) {
        const pts = L.route;
        route.current.setAttribute('points', pts ? pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ') : '');
        route.current.setAttribute('stroke-width', (unit * 3.2).toFixed(2));
      }
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [geo, live]);

  const u = open ? (geo.x1 - geo.x0) / 300 : SMALL / 46;
  return (
    <div
      className={`roam-mini${open ? ' is-open' : ''}`}
      role="button"
      tabIndex={0}
      aria-label={open ? 'Close the map' : 'Open the map'}
      aria-expanded={open}
      onClick={() => {
        if (!open) onToggle();
      }}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onToggle();
        }
      }}
      style={{ touchAction: 'none' }}
    >
      <svg ref={svg} viewBox={`${AREA.x0} ${AREA.y0} 120 120`} preserveAspectRatio="xMidYMid meet" role="img" aria-hidden="true">
        <circle className="rm-lawn" cx={RING.x} cy={RING.y} r={49} />
        <path className="rm-bld" d={geo.b} />
        <circle className="rm-road" cx={RING.x} cy={RING.y} r={RING.r} strokeWidth={u * 2.6} />
        {geo.roads.map((r) => (
          <path key={r.id} className={`rm-road rm-road--${r.kind}`} d={r.d} strokeWidth={u * (r.kind === 'express' ? 3.2 : r.kind === 'main' ? 2.6 : 1.5)} />
        ))}
        <polyline ref={route} className="rm-route" points="" />
        {world.places.map((p) => (
          <g key={p.id} onClick={(e) => { if (open) { e.stopPropagation(); onPick(p.id); } }} style={{ cursor: open ? 'pointer' : 'default' }}>
            <circle className={`rm-pin${destId === p.id ? ' is-dest' : ''}${p.closed ? ' is-closed' : ''}`} cx={p.door.sx} cy={p.door.sy} r={u * (open ? 5.2 : 3.2)} strokeWidth={u * 1.4} />
            {open && (
              <text className="rm-label" x={p.door.sx} y={p.door.sy - u * 8} fontSize={u * 9.5} textAnchor="middle" strokeWidth={u * 3}>
                {p.label}
              </text>
            )}
          </g>
        ))}
        <rect ref={carMark} className="rm-car" x={-4.4} y={-2} width={8.8} height={4} rx={1.2} visibility="hidden" />
        <g ref={me}>
          <circle className="rm-me-halo" r={7} />
          <path className="rm-me" d="M7 0 L-5 5 L-2.5 0 L-5 -5Z" strokeWidth={1.4} strokeLinejoin="round" />
        </g>
      </svg>
      {open && (
        <>
          <span className="roam-mini__hint">Tap a pin to walk there</span>
          <button
            type="button"
            className="roam-btn roam-btn--round"
            style={{ position: 'absolute', right: 6, top: 6, width: 34, height: 34, minWidth: 34 }}
            aria-label="Close the map"
            onClick={(e) => {
              e.stopPropagation();
              onToggle();
            }}
          >
            ✕
          </button>
        </>
      )}
    </div>
  );
}

export const RoamMap = memo(MiniBase);
