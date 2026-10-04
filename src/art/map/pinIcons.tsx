// P1-MAP — badge colours + glyphs for every scene type. Glyphs live in a ~18×18 box centred on (0,0).
import type { JSX } from 'react';
import type { SceneType } from '../../lib/types';

export interface PinStyle {
  c1: string; // gradient top (lit)
  c2: string; // gradient bottom (shade)
  ink: string; // glyph colour
  accent?: string;
}

export const PIN_STYLE: Record<SceneType, PinStyle> = {
  market: { c1: '#f6b04a', c2: '#c0620f', ink: '#fffaf0', accent: '#d2342a' },
  hospital: { c1: '#f26464', c2: '#b0202d', ink: '#fffaf0' },
  campus: { c1: '#5a91e0', c2: '#224c92', ink: '#fffaf0', accent: '#f3d28a' },
  palace: { c1: '#e9bd5a', c2: '#8f5a12', ink: '#fff6dc', accent: '#d2342a' },
  museum: { c1: '#cf9858', c2: '#74461c', ink: '#fff6dc' },
  club: { c1: '#a868dc', c2: '#55248a', ink: '#fffaf0', accent: '#f3d28a' },
  bank: { c1: '#38b062', c2: '#13512a', ink: '#fffaf0' },
  police: { c1: '#4c68b8', c2: '#1a285c', ink: '#fffaf0', accent: '#d9a441' },
  motorpark: { c1: '#f7cf47', c2: '#b9820a', ink: '#2a1a0c', accent: '#1f7a3f' },
  street: { c1: '#9a8a80', c2: '#4b3f3a', ink: '#fffaf0', accent: '#f3cf5e' },
  pos: { c1: '#22b5a6', c2: '#0b625a', ink: '#fffaf0' },
  home_face_me: { c1: '#d6845a', c2: '#7a3a22', ink: '#fffaf0' },
  home_flat: { c1: '#e49a68', c2: '#9a4a26', ink: '#fffaf0' },
  home_duplex: { c1: '#62b68e', c2: '#2a6a50', ink: '#fffaf0', accent: '#d2342a' },
  farm: { c1: '#7dbb45', c2: '#3a7420', ink: '#fffaf0', accent: '#8a5a2a' },
  airport: { c1: '#5ec0ea', c2: '#1c6a9a', ink: '#fffaf0' },
  shrine: { c1: '#a23a48', c2: '#4a0f1c', ink: '#f3d28a', accent: '#fffaf0' },
  workshop: { c1: '#c99350', c2: '#6a4116', ink: '#fff6dc' },
  buka: { c1: '#f37a45', c2: '#a8361a', ink: '#fffaf0' },
  salon: { c1: '#ec7bb0', c2: '#a02c68', ink: '#fffaf0' },
  cyber: { c1: '#5c62dc', c2: '#252886', ink: '#fffaf0', accent: '#7ee0c5' },
  office: { c1: '#3fb8c9', c2: '#155a78', ink: '#f2fbff', accent: '#d9a441' },
};

export const SCENES = Object.keys(PIN_STYLE) as SceneType[];

const sw = { fill: 'none', strokeLinecap: 'round', strokeLinejoin: 'round' } as const;

export function PinGlyph({ scene }: { scene: SceneType }): JSX.Element {
  const st = PIN_STYLE[scene] ?? PIN_STYLE.street;
  const ink = st.ink;
  const acc = st.accent ?? ink;
  switch (scene) {
    case 'market':
      return (
        <g>
          <path d="M-8,-2.5L-6.2,-7.5H6.2L8,-2.5Z" fill={ink} />
          <path d="M-3.4,-7.5L-4,-2.5M0,-7.5V-2.5M3.4,-7.5L4,-2.5" stroke={acc} strokeWidth={1.3} />
          <path d="M-8,-2.5a2,1.8 0 0 0 4,0a2,1.8 0 0 0 4,0a2,1.8 0 0 0 4,0a2,1.8 0 0 0 4,0Z" fill={ink} />
          <path d="M-6.4,0.5V7H6.4V0.5" {...sw} stroke={ink} strokeWidth={1.6} />
          <circle cx={-2.6} cy={4.2} r={1.6} fill={acc} />
          <circle cx={0.9} cy={4.4} r={1.5} fill="#f3cf5e" />
          <circle cx={3.6} cy={4.1} r={1.3} fill="#7dbb45" />
        </g>
      );
    case 'hospital':
      return (
        <g>
          <circle r={8.2} fill={ink} />
          <path d="M-2.1,-6H2.1V-2.1H6V2.1H2.1V6H-2.1V2.1H-6V-2.1H-2.1Z" fill="#c8262f" />
        </g>
      );
    case 'campus':
      return (
        <g>
          <path d="M0,-6.5L9,-2.5L0,1.5L-9,-2.5Z" fill={ink} />
          <path d="M-5.2,-0.5V3.6C-5.2,6.4 5.2,6.4 5.2,3.6V-0.5L0,1.8Z" fill={ink} opacity={0.92} />
          <path d="M7.6,-2V4" {...sw} stroke={acc} strokeWidth={1.2} />
          <circle cx={7.6} cy={4.6} r={1.2} fill={acc} />
        </g>
      );
    case 'palace':
      return (
        <g>
          <path d="M-7.5,5H7.5L8.4,-3.8L4,-0.6L0,-6.8L-4,-0.6L-8.4,-3.8Z" fill={ink} stroke="#8f5a12" strokeWidth={0.5} strokeLinejoin="round" />
          <path d="M-7.5,5H7.5V7.4H-7.5Z" fill={acc} />
          {[-5, -2.5, 0, 2.5, 5].map((x) => (
            <circle key={x} cx={x} cy={6.2} r={0.9} fill="#ffb199" />
          ))}
          <circle cx={0} cy={-6.8} r={1.4} fill={acc} />
          <circle cx={-8.4} cy={-3.8} r={1.1} fill={acc} />
          <circle cx={8.4} cy={-3.8} r={1.1} fill={acc} />
        </g>
      );
    case 'museum':
      return (
        <g>
          <path d="M-8.5,-3L0,-8.2L8.5,-3Z" fill={ink} />
          <path d="M-5.8,-1.2V5M-1.95,-1.2V5M1.95,-1.2V5M5.8,-1.2V5" {...sw} stroke={ink} strokeWidth={1.9} />
          <path d="M-8.5,7H8.5" {...sw} stroke={ink} strokeWidth={2} />
        </g>
      );
    case 'club':
      return (
        <g>
          <path d="M-6.5,-6.5H6.5L0,1Z" fill={ink} />
          <path d="M0,1V6.5M-3.6,6.8H3.6" {...sw} stroke={ink} strokeWidth={1.7} />
          <circle cx={2.2} cy={-3.6} r={1.3} fill={acc} />
          <path d="M5.5,-8.5L2.2,-3.6" {...sw} stroke={acc} strokeWidth={0.9} />
        </g>
      );
    case 'bank':
      return (
        <g>
          <path d="M-4.2,6.5V-6.5L4.2,6.5V-6.5" {...sw} stroke={ink} strokeWidth={2} />
          <path d="M-7,-1.4H7M-7,1.8H7" {...sw} stroke={ink} strokeWidth={1.3} />
        </g>
      );
    case 'police':
      return (
        <g>
          <path d="M0,-8L7,-5.4V0C7,4.6 3.6,7.2 0,8.4C-3.6,7.2 -7,4.6 -7,0V-5.4Z" fill={ink} />
          <path d="M0,-3.6L1.15,-1.1L3.8,-0.9L1.8,0.9L2.4,3.5L0,2.1L-2.4,3.5L-1.8,0.9L-3.8,-0.9L-1.15,-1.1Z" fill={acc} />
        </g>
      );
    case 'motorpark':
      return (
        <g>
          <rect x={-6.8} y={-7.4} width={13.6} height={12.6} rx={2.4} fill={ink} />
          <rect x={-5.2} y={-5.8} width={10.4} height={4.6} rx={0.8} fill="#f7e7a8" />
          <circle cx={-3.8} cy={2} r={1.2} fill="#f7e7a8" />
          <circle cx={3.8} cy={2} r={1.2} fill="#f7e7a8" />
          <path d="M-4.6,5.2V7.6M4.6,5.2V7.6" {...sw} stroke={ink} strokeWidth={2.2} />
        </g>
      );
    case 'street':
      return (
        <g>
          <path d="M-1.5,8V-5.5" {...sw} stroke={ink} strokeWidth={1.8} />
          <path d="M-1.5,-5.5Q-1.5,-8 2,-8H5" {...sw} stroke={ink} strokeWidth={1.6} />
          <path d="M3,-8H7.6L6.8,-5.8H3.8Z" fill={acc} />
          <path d="M-5,8H2" {...sw} stroke={ink} strokeWidth={1.8} />
          <path d="M5.3,-4.5L6.5,-1.5M3.8,-4.5L3,-1.6" {...sw} stroke={acc} strokeWidth={0.8} opacity={0.8} />
        </g>
      );
    case 'pos':
      return (
        <g>
          <rect x={-5} y={-8} width={10} height={16} rx={1.8} fill={ink} />
          <rect x={-3.6} y={-6.6} width={7.2} height={4.4} rx={0.6} fill="#0b625a" />
          <path d="M-2.4,-4.4H1.2" {...sw} stroke="#7ee0c5" strokeWidth={0.9} />
          {[-2.4, 0, 2.4].flatMap((x) => [0.2, 2.6, 5].map((y) => <circle key={`${x}${y}`} cx={x} cy={y} r={0.85} fill="#0b625a" />))}
        </g>
      );
    case 'home_face_me':
      return (
        <g>
          <path d="M-9,-0.5L0,-7L9,-0.5" {...sw} stroke={ink} strokeWidth={1.9} />
          <rect x={-7} y={-0.5} width={14} height={7.5} fill={ink} />
          <path d="M-4.5,7V3M-1.5,7V3M1.5,7V3M4.5,7V3" {...sw} stroke="#7a3a22" strokeWidth={1.4} />
        </g>
      );
    case 'home_flat':
      return (
        <g>
          <rect x={-6} y={-8} width={12} height={16} rx={0.8} fill={ink} />
          {[-5.6, -1.6, 2.4].flatMap((y) => [-3.4, 0.6].map((x) => <rect key={`${x}${y}`} x={x} y={y} width={2.8} height={2.4} fill="#9a4a26" />))}
          <rect x={-1.3} y={5} width={2.6} height={3} fill="#9a4a26" />
        </g>
      );
    case 'home_duplex':
      return (
        <g>
          <path d="M-9,-1L-2,-8L5,-1" fill={acc} />
          <rect x={-7.4} y={-1.4} width={11} height={9.4} fill={ink} />
          <path d="M3.6,2H9V8H3.6" fill={ink} opacity={0.85} />
          <rect x={-5.6} y={0.3} width={2.6} height={2.3} fill="#2a6a50" />
          <rect x={-1.2} y={0.3} width={2.6} height={2.3} fill="#2a6a50" />
          <rect x={-3.4} y={4.4} width={2.6} height={3.6} fill="#2a6a50" />
        </g>
      );
    case 'farm':
      return (
        <g>
          <path d="M-8,7.5Q0,2.5 8,7.5" fill={acc} stroke={ink} strokeWidth={1} />
          <path d="M0,5.5V-1" {...sw} stroke={ink} strokeWidth={1.8} />
          <path d="M0,-0.5C-0.8,-5.6 -6.8,-7 -7.6,-6.6C-7.4,-2.6 -4,-0.6 0,-0.5Z" fill={ink} />
          <path d="M0,1.5C0.6,-3.2 5.6,-4.6 7.4,-4.2C7,-0.8 4,1.4 0,1.5Z" fill={ink} opacity={0.92} />
        </g>
      );
    case 'airport':
      return (
        <g transform="rotate(-40)">
          <path d="M0,-9C1.3,-9 1.6,-7.6 1.6,-6V-2L8.5,2.2V4.2L1.6,2.2V5.8L3.8,7.6V9L0,8L-3.8,9V7.6L-1.6,5.8V2.2L-8.5,4.2V2.2L-1.6,-2V-6C-1.6,-7.6 -1.3,-9 0,-9Z" fill={ink} />
        </g>
      );
    case 'shrine':
      return (
        <g>
          <path d="M0,-7.6C-2,-7.6 -2.2,-5 -2.1,-3.4C-6,-2.4 -7.4,0.6 -7.4,3C-7.4,6.4 -4,8.4 0,8.4C4,8.4 7.4,6.4 7.4,3C7.4,0.6 6,-2.4 2.1,-3.4C2.2,-5 2,-7.6 0,-7.6Z" fill={ink} />
          <path d="M-6.4,2.4Q0,4.6 6.4,2.4" {...sw} stroke="#7a1a2a" strokeWidth={1.2} />
          {[-3.6, 0, 3.6].map((x) => (
            <ellipse key={x} cx={x} cy={5.6} rx={1.1} ry={0.75} fill={acc} />
          ))}
        </g>
      );
    case 'workshop':
      return (
        <g>
          <path d="M-8,0.5H5.5C5.5,2.8 3.6,3.8 1.4,3.8V5.6H4.4V7.8H-4.6V5.6H-1.6V3.8C-5,3.8 -8,2.8 -8,0.5Z" fill={ink} />
          <path d="M-1.4,-1.6L5.6,-7.6" {...sw} stroke={ink} strokeWidth={1.6} />
          <rect x={3.4} y={-9.6} width={6} height={3.4} rx={0.6} transform="rotate(-40 6.4 -7.9)" fill={ink} />
          <circle cx={-5.4} cy={-4.5} r={0.9} fill="#ffcf73" />
          <circle cx={-3.2} cy={-6.8} r={0.7} fill="#ffcf73" />
        </g>
      );
    case 'buka':
      return (
        <g>
          <path d="M-8.4,0H8.4C8.4,5 4.6,7.6 0,7.6C-4.6,7.6 -8.4,5 -8.4,0Z" fill={ink} />
          <path d="M-9.4,0H9.4" {...sw} stroke={ink} strokeWidth={1.6} />
          <path d="M-3.4,-2.4C-5,-4 -1.8,-5 -3.4,-7.4M0.4,-2.4C-1.2,-4 2,-5 0.4,-7.4M4.2,-2.4C2.6,-4 5.8,-5 4.2,-7.4" {...sw} stroke={ink} strokeWidth={1.3} />
        </g>
      );
    case 'salon':
      return (
        <g>
          <circle cx={-4.2} cy={4.4} r={2.8} {...sw} stroke={ink} strokeWidth={1.7} />
          <circle cx={4.2} cy={4.4} r={2.8} {...sw} stroke={ink} strokeWidth={1.7} />
          <path d="M-2.4,2.3L5.4,-8M2.4,2.3L-5.4,-8" {...sw} stroke={ink} strokeWidth={1.8} />
          <circle cx={0} cy={-1.8} r={0.9} fill="#a02c68" />
        </g>
      );
    case 'cyber':
      return (
        <g>
          <path d="M-8.4,-2.6A12,12 0 0 1 8.4,-2.6M-5.6,0.6A8,8 0 0 1 5.6,0.6M-2.8,3.6A4,4 0 0 1 2.8,3.6" {...sw} stroke={ink} strokeWidth={1.8} />
          <circle cx={0} cy={6.4} r={1.7} fill={acc} />
        </g>
      );
    case 'office':
      // modern glass tower with a gold crown + a lit floor band (tech hub)
      return (
        <g>
          <path d="M-5.6,8V-5.4L1.6,-8.6V8Z" fill={ink} />
          <path d="M1.6,8V-8.6L6.4,-6.2V8Z" fill={ink} opacity={0.72} />
          <path d="M-5.6,-5.4L1.6,-8.6L6.4,-6.2" {...sw} stroke={acc} strokeWidth={1.4} />
          <path d="M-3.8,-3.2H-0.2M-3.8,-0.4H-0.2M-3.8,2.4H-0.2M3,-3.4V5.6" {...sw} stroke="#155a78" strokeWidth={1.1} />
          <path d="M-8,8H8.4" {...sw} stroke={acc} strokeWidth={1.6} />
        </g>
      );
    default:
      return <circle r={4} fill={ink} />;
  }
}
