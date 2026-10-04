// PHASE 0 STUB — P1-MAP replaces this file. Keep the export name/signature.
import type { Location } from '../../lib/types';

export interface BeninMapProps {
  locations: Location[];
  currentId?: string;
  selectedId?: string;
  onSelect: (id: string) => void;
  night: boolean;
  travel?: { from: string; to: string; progress: number } | null;
  crowd?: Record<string, number>;
}

export function BeninMap({ locations, currentId, selectedId, onSelect, night }: BeninMapProps) {
  return (
    <svg viewBox="0 0 1000 1000" width="100%" height="100%" style={{ background: night ? '#1b2238' : '#d9b48a' }}>
      <circle cx="500" cy="500" r="60" fill="none" stroke="#555" strokeWidth="14" />
      {locations.map((l) => (
        <g key={l.id} onClick={() => onSelect(l.id)} style={{ cursor: 'pointer' }}>
          <circle cx={l.x} cy={l.y} r={l.id === selectedId ? 16 : 11}
            fill={l.id === currentId ? '#1f7a3f' : '#d2342a'} stroke="#fff" strokeWidth="3" />
          <text x={l.x} y={l.y - 18} fontSize="16" textAnchor="middle" fill={night ? '#fff' : '#222'}>{l.name}</text>
        </g>
      ))}
    </svg>
  );
}
