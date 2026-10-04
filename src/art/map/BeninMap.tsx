// P1-MAP — the main game screen: illustrated, pannable, zoomable map of Benin City.
// Layers: static art (memo, rendered once) → light grade (day/night) → labels → pins → travel.
import { memo, useMemo, type CSSProperties, type ReactNode } from 'react';
import type { Location } from '../../lib/types';
import { MapArt, MapLabels, MapLight } from './MapArt';
import { MAP_CSS, MapPins, PinDefs, TravelLayer } from './MapPins';
import { getMapModel } from './mapModel';
import { useMapViewport } from './useMapViewport';

// The procedural city (~1.2k buildings, ~1.4k trees/bushes) is generated once per session.
// Kick it off in idle time as soon as this module loads, so it normally finishes while the
// game state is still being fetched and the first map paint doesn't pay for it.
if (typeof window !== 'undefined') {
  const warm = () => void getMapModel();
  if ('requestIdleCallback' in window) window.requestIdleCallback(warm, { timeout: 1200 });
  else setTimeout(warm, 30);
}

export interface BeninMapProps {
  locations: Location[];
  currentId?: string;
  selectedId?: string;
  onSelect: (id: string) => void;
  night: boolean;
  travel?: { from: string; to: string; progress: number } | null;
  crowd?: Record<string, number>;
}

interface SvgProps extends BeninMapProps {
  /** committed zoom level (CSS px per map unit) — drives pin size + label culling */
  zoom: number;
  width?: number | string;
  height?: number | string;
}

const StaticLayers = memo(function StaticLayers({ night }: { night: boolean }) {
  return (
    <>
      <style>{MAP_CSS}</style>
      <MapArt />
      <MapLight night={night} />
      <MapLabels night={night} />
      <PinDefs />
    </>
  );
});

/** Pure SVG of the map (no gestures). Exported for previews / static rendering. */
export function BeninMapSvg({ locations, currentId, selectedId, onSelect, night, travel, crowd, zoom, width = 1000, height = 1000 }: SvgProps) {
  const byId = useMemo(() => new Map(locations.map((l) => [l.id, l])), [locations]);
  const from = travel ? byId.get(travel.from) : undefined;
  const to = travel ? byId.get(travel.to) : undefined;
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1000 1000"
      width={width}
      height={height}
      role="img"
      aria-label="Map of Benin City"
      style={{ display: 'block', overflow: 'hidden', userSelect: 'none', WebkitUserSelect: 'none' }}
    >
      <StaticLayers night={night} />
      {from && to && travel && <TravelLayer from={from} to={to} progress={travel.progress} zoom={zoom} />}
      <MapPins locations={locations} currentId={currentId} selectedId={selectedId} night={night} crowd={crowd} zoom={zoom} onSelect={onSelect} />
    </svg>
  );
}

const btn: CSSProperties = {
  width: 44,
  height: 44,
  borderRadius: 14,
  border: '1px solid rgba(251,240,220,0.18)',
  background: 'var(--glass, rgba(18,16,40,0.74))',
  color: 'var(--glass-text, #fbf0dc)',
  fontSize: 22,
  fontWeight: 800,
  lineHeight: 1,
  display: 'grid',
  placeItems: 'center',
  cursor: 'pointer',
  boxShadow: '0 2px 4px rgba(20,10,30,0.25), 0 8px 18px rgba(20,10,30,0.25)',
  backdropFilter: 'blur(8px)',
  WebkitBackdropFilter: 'blur(8px)',
  WebkitTapHighlightColor: 'transparent',
  touchAction: 'manipulation',
  padding: 0,
};

function CtrlButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" aria-label={label} title={label} style={btn} onClick={onClick}>
      {children}
    </button>
  );
}

export function BeninMap(props: BeninMapProps) {
  const { locations, currentId, night } = props;
  const current = useMemo(() => locations.find((l) => l.id === currentId), [locations, currentId]);
  const vp = useMapViewport({ focus: current ? { x: current.x, y: current.y } : null, onTapPin: props.onSelect });

  return (
    <div
      className="benin-map"
      style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden', background: night ? '#0b0d26' : '#b57447' }}
    >
      <div
        ref={vp.surfaceRef}
        {...vp.handlers}
        tabIndex={-1}
        style={{
          position: 'absolute',
          inset: 0,
          touchAction: 'none',
          cursor: 'grab',
          outline: 'none',
          WebkitTapHighlightColor: 'transparent',
          WebkitUserSelect: 'none',
          userSelect: 'none',
        }}
      >
        <div
          ref={vp.contentRef}
          style={{ position: 'absolute', left: 0, top: 0, width: 1000, height: 1000, transformOrigin: '0 0', opacity: vp.ready ? 1 : 0 }}
        >
          <BeninMapSvg {...props} zoom={vp.zoom} />
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          right: 'calc(12px + var(--sar, 0px))',
          top: '50%',
          transform: 'translateY(-50%)',
          display: 'flex',
          flexDirection: 'column',
          gap: 8,
          zIndex: 2,
        }}
      >
        <CtrlButton label="Zoom in" onClick={() => vp.zoomBy(1.6)}>
          +
        </CtrlButton>
        <CtrlButton label="Zoom out" onClick={() => vp.zoomBy(1 / 1.6)}>
          −
        </CtrlButton>
        {current && (
          <CtrlButton label="Find me" onClick={() => vp.centerOn(current.x, current.y)}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
              <circle cx="12" cy="12" r="6.5" />
              <circle cx="12" cy="12" r="2" fill="currentColor" />
              <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
            </svg>
          </CtrlButton>
        )}
      </div>
    </div>
  );
}
