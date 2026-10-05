// Bronze Tech Hub — modern coworking / startup hub in Ugbowo near UNIBEN (fictional) — V1-3.
// Two-storey glass + laterite-clad block, solar roof, bronze-head logo, coworkers behind the glass,
// paved forecourt with keke, saloon car, palms, security post and inverter cabinet.
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Palm, Treeline, Haze, Car, SIGN_FONT, HAND_FONT, dim } from './_sharedB';
import { Keke } from './_sharedA';

const P = 'office';
const FL = 352; // forecourt line (building base)
const G1 = 238; // ground floor top / first floor slab bottom
const TOP = 118; // roof slab

/** Desk with a laptop and a seated coworker, seen through the glass. (x,y) = desk top centre. */
function Desk({ x, y, skin, top, night, facing = 1, screen = 'a' }: { x: number; y: number; skin: string; top: string; night: boolean; facing?: 1 | -1; screen?: 'a' | 'b' | 'c' }) {
  return (
    <g>
      <Person x={x - 14 * facing} y={y + 18} s={0.95} skin={skin} top={top} bottom="#2b3350" pose="sit" facing={facing} night={night} />
      <rect x={x - 26} y={y} width="52" height="3.5" rx="1" fill={night ? '#c9b48e' : '#e8d6b0'} />
      <path d={`M${x - 22} ${y + 3} V${y + 20} M${x + 22} ${y + 3} V${y + 20}`} stroke="#3a3846" strokeWidth="2" />
      {/* laptop, lid towards the person */}
      <path d={`M${x - 4} ${y} L${x + 14} ${y} L${x + 16} ${y - 1.5} L${x - 2} ${y - 1.5} Z`} fill="#b9bcc8" />
      <path d={`M${x - 2 + (facing > 0 ? 0 : 10)} ${y - 1.5} l2 -13 h14 l-2 13 Z`} fill="#2a2834" />
      <path d={`M${x - 0.5 + (facing > 0 ? 0 : 10)} ${y - 3} l1.6 -10 h11 l-1.6 10 Z`} fill={`url(#${P}-scr${screen})`} />
      {night && <Glow p={P} cx={x + 6} cy={y - 8} r={20} ry={14} kind="gc" o={0.6} />}
      {/* mug */}
      <rect x={x - 20} y={y - 5} width="4.5" height="5" rx="1" fill="#d2342a" />
    </g>
  );
}

/** Rooftop solar panel row. */
function Solar({ x, y, n }: { x: number; y: number; n: number }) {
  return (
    <g>
      {Array.from({ length: n }, (_, i) => (
        <g key={i} transform={`translate(${x + i * 34} ${y})`}>
          <path d="M2 14 L6 22 M28 14 L26 22" stroke="#6d7282" strokeWidth="2" />
          <path d="M0 14 L6 0 L34 0 L30 14 Z" fill={`url(#${P}-pv)`} />
          <path d="M0 14 L6 0 L34 0 L30 14 Z M3 7 H32 M10 0 L7 14 M17 0 L15 14 M24 0 L22 14" stroke="#9fb8e0" strokeWidth="0.6" fill="none" opacity="0.6" />
          <path d="M8 1 L5 8" stroke="#fff" strokeWidth="2" opacity="0.35" />
        </g>
      ))}
    </g>
  );
}

/** Potted plant (snake plant / fiddle leaf). (x,y) = pot base. */
function Planter({ x, y, s = 1, night, kind = 0 }: { x: number; y: number; s?: number; night: boolean; kind?: number }) {
  const g1 = night ? '#1d3a3a' : '#2f7a45';
  const g2 = night ? '#25484a' : '#5aa64e';
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="2" cy="0" rx="14" ry="2.6" fill="#2d1b4e" opacity="0.3" />
      {kind === 0 ? (
        <>
          <path d="M-6 -16 Q-10 -36 -8 -46 Q-3 -34 -2 -16 Z M0 -16 Q-1 -42 3 -54 Q6 -38 4 -16 Z M5 -16 Q9 -34 12 -40 Q11 -28 9 -16 Z" fill={g1} />
          <path d="M0 -16 Q-1 -42 3 -54 Q2 -36 2 -16 Z" fill={g2} />
        </>
      ) : (
        <>
          <path d="M1 -16 V-46" stroke="#5a3a26" strokeWidth="2" />
          {[[-8, -44], [8, -40], [-9, -32], [9, -28], [0, -52], [-6, -22], [7, -20]].map(([lx, ly], i) => (
            <ellipse key={i} cx={lx} cy={ly} rx="7" ry="4.5" transform={`rotate(${lx > 0 ? -30 : 30} ${lx} ${ly})`} fill={i % 2 ? g2 : g1} />
          ))}
        </>
      )}
      <path d="M-10 -16 H12 L9 0 H-7 Z" fill={night ? '#3a3046' : '#efe6d6'} />
      <path d="M3 -16 H12 L9 0 H2 Z" fill="#2d1b4e" opacity="0.25" />
    </g>
  );
}

export default function OfficeScene({ night }: { night: boolean }) {
  // interiors stay lit at night: keep NightShade off the glass
  const lit = `M140 136 H512 V230 H140 Z M150 254 H512 V${FL - 2} H150 Z`;
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Bronze Tech Hub coworking space in Ugbowo">
      <defs>
        <linearGradient id={`${P}-glass`} x1="0" y1="0" x2="0.35" y2="1">
          <stop offset="0" stopColor={night ? '#2a3d6e' : '#cfe6f4'} />
          <stop offset="0.45" stopColor={night ? '#20325c' : '#9cc6e6'} />
          <stop offset="1" stopColor={night ? '#18264a' : '#6f9fc8'} />
        </linearGradient>
        <linearGradient id={`${P}-room`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#fff1d6' : '#eef2f2'} />
          <stop offset="0.6" stopColor={night ? '#f2dcb8' : '#dfe6e6'} />
          <stop offset="1" stopColor={night ? '#d8bd94' : '#c6cfd2'} />
        </linearGradient>
        <linearGradient id={`${P}-clad`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c86a3e" />
          <stop offset="0.5" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8e3f1f" />
        </linearGradient>
        <linearGradient id={`${P}-slab`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#f4f1ea" />
          <stop offset="0.6" stopColor="#ddd8cc" />
          <stop offset="1" stopColor="#b9b2a4" />
        </linearGradient>
        <linearGradient id={`${P}-fascia`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2a2d3e" />
          <stop offset="1" stopColor="#16182a" />
        </linearGradient>
        <linearGradient id={`${P}-gold`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffe6a0" />
          <stop offset="0.45" stopColor="#d9a441" />
          <stop offset="1" stopColor="#9a6a26" />
        </linearGradient>
        <radialGradient id={`${P}-bronze`} cx="0.35" cy="0.3" r="0.8">
          <stop offset="0" stopColor="#f3d28a" />
          <stop offset="0.45" stopColor="#b0793a" />
          <stop offset="1" stopColor="#5e3a16" />
        </radialGradient>
        <linearGradient id={`${P}-pv`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={night ? '#1d2a5a' : '#3b5fa8'} />
          <stop offset="0.5" stopColor={night ? '#141e44' : '#24407e'} />
          <stop offset="1" stopColor={night ? '#0e1636' : '#172c5c'} />
        </linearGradient>
        <linearGradient id={`${P}-scra`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#2b3a66" /><stop offset="1" stopColor="#5ad1a4" />
        </linearGradient>
        <linearGradient id={`${P}-scrb`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#3b2a5e" /><stop offset="1" stopColor="#f0a35a" />
        </linearGradient>
        <linearGradient id={`${P}-scrc`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#1f3a5a" /><stop offset="1" stopColor="#7fc8ff" />
        </linearGradient>
        <pattern id={`${P}-tiles`} patternUnits="userSpaceOnUse" width="28" height="14">
          <rect width="28" height="14" fill={night ? '#6a6276' : '#b8aea2'} />
          <path d="M0 0 H28 M0 7 H28 M7 0 V7 M21 7 V14" stroke={night ? '#4e475a' : '#8f857a'} strokeWidth="1" />
          <rect x="8" y="1" width="12" height="5" fill={night ? '#7a5a5a' : '#c4886a'} opacity="0.55" />
        </pattern>
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.5" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        <linearGradient id={`${P}-spill`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffd8a0" stopOpacity="0.2" />
          <stop offset="1" stopColor="#ffd8a0" stopOpacity="0" />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />

      <Sky p={P} night={night} sunX={110} sunY={64} moonX={700} moonY={60} />
      {/* distant Ugbowo: UNIBEN water tower, low roofs, mast */}
      <g opacity="0.9">
        <Treeline y={262} fill={dim('#5d8f5a', night, 0.7)} seed={41} amp={14} step={22} />
        <rect x="40" y="196" width="6" height="70" fill={dim('#8a8f9a', night)} />
        <ellipse cx="43" cy="192" rx="18" ry="10" fill={dim('#b8bcc4', night)} />
        <path d="M708 150 L716 268 M724 150 L716 268 M710 180 H722 M712 210 H720 M713 240 H719" stroke={dim('#a33a2e', night)} strokeWidth="2" />
        <circle cx="716" cy="148" r="2.5" fill={night ? '#ff4a3a' : '#d2342a'} />
        {night && <Glow p={P} cx={716} cy={148} r={10} kind="gf" o={0.9} />}
      </g>
      <Haze p={P} y={230} h={50} night={night} o={0.4} />
      <Treeline y={292} fill={dim('#3f7a3a', night, 0.7)} seed={77} amp={18} step={30} />

      {/* ---------- building ---------- */}
      <ellipse cx="410" cy={FL + 2} rx="320" ry="8" fill="#2d1b4e" opacity="0.3" />
      {/* roof slab + parapet + solar */}
      <Solar x={160} y={TOP - 22} n={9} />
      <rect x="120" y={TOP} width="560" height="14" fill={`url(#${P}-slab)`} />
      <rect x="120" y={TOP + 12} width="560" height="4" fill="#2d1b4e" opacity="0.25" />

      {/* first floor: glass curtain wall (left) */}
      <rect x="130" y={TOP + 16} width="392" height={G1 - TOP - 16} fill={`url(#${P}-room)`} />
      {/* interior upstairs: back wall, whiteboard, pendant lamps, desks */}
      <rect x="130" y={TOP + 16} width="392" height="22" fill={night ? '#e8d2ac' : '#d9e0e0'} />
      <rect x="160" y="150" width="70" height="40" fill="#fbfbf6" stroke="#9aa0aa" strokeWidth="1.5" />
      {[[166, 156, '#ffd84a'], [180, 156, '#7fd0ff'], [194, 156, '#ff9ab4'], [166, 170, '#9be38a'], [180, 170, '#ffd84a'], [208, 162, '#ff9ab4']].map(([sx, sy, c], i) => (
        <rect key={i} x={sx as number} y={sy as number} width="10" height="10" fill={c as string} transform={`rotate(${i % 2 ? 4 : -3} ${sx} ${sy})`} />
      ))}
      <path d="M200 182 q8 -10 18 -4" stroke="#2f6fd0" strokeWidth="1.5" fill="none" />
      <text x="295" y="158" fontSize="8" fontFamily={HAND_FONT} fill={night ? '#7a4d1f' : '#5a6270'} textAnchor="middle">ship it, then sleep</text>
      {[250, 340, 430].map((x) => (
        <g key={x}>
          <path d={`M${x} ${TOP + 16} V${TOP + 34}`} stroke="#3a3846" strokeWidth="1" />
          <path d={`M${x - 9} ${TOP + 40} Q${x} ${TOP + 30} ${x + 9} ${TOP + 40} Z`} fill="#2a2d3e" />
          {night && <Glow p={P} cx={x} cy={TOP + 46} r={38} ry={22} o={0.8} />}
        </g>
      ))}
      <Desk x={262} y={202} skin="#5a3624" top="#1f7a3f" night={night} screen="a" />
      <Desk x={352} y={202} skin="#3e2416" top="#f2c230" night={night} facing={-1} screen="b" />
      <Desk x={450} y={202} skin="#6b4128" top="#6b63e0" night={night} screen="c" />
      <Person x={196} y={230} s={1.05} skin="#4a2c1e" top="#fffaf0" bottom="#3a4468" pose="stand" facing={1} night={night}
        extra={<rect x="9" y="-35" width="4" height="7" rx="1" fill="#1a1a26" />} />
      <Planter x={500} y={230} s={0.8} night={night} kind={1} />
      {/* glass + mullions + reflections */}
      <rect x="130" y={TOP + 16} width="392" height={G1 - TOP - 16} fill={`url(#${P}-glass)`} opacity={night ? 0.22 : 0.45} />
      {[130, 186, 242, 298, 354, 410, 466, 522].map((x) => <rect key={x} x={x - 2} y={TOP + 16} width="4" height={G1 - TOP - 16} fill="#3a3e4e" />)}
      <rect x="128" y="186" width="396" height="3" fill="#3a3e4e" />
      {!night && (
        <g opacity="0.5">
          <path d={`M150 ${TOP + 16} L190 ${TOP + 16} L140 ${G1} L130 ${G1} L130 ${TOP + 40} Z`} fill="#fff" opacity="0.5" />
          <path d={`M300 ${TOP + 16} L318 ${TOP + 16} L276 ${G1} L258 ${G1} Z`} fill="#fff" opacity="0.4" />
          <path d={`M420 ${TOP + 16} L470 ${TOP + 16} L430 ${G1} L380 ${G1} Z`} fill="#fff" opacity="0.25" />
        </g>
      )}

      {/* laterite-clad block (right) with timber fins */}
      <rect x="522" y={TOP + 16} width="158" height={FL - TOP - 16} fill={`url(#${P}-clad)`} />
      {Array.from({ length: 12 }, (_, i) => (
        <g key={i}>
          <rect x={530 + i * 12.5} y={TOP + 22} width="5" height={G1 - TOP - 30} fill={night ? '#5a3a2a' : '#8a5a34'} />
          <rect x={533 + i * 12.5} y={TOP + 22} width="2" height={G1 - TOP - 30} fill="#2d1b4e" opacity="0.3" />
        </g>
      ))}
      {/* bronze-head logo medallion (stylised, respectful) */}
      <g transform={`translate(601 ${TOP + 62})`}>
        <circle r="34" fill="#16182a" />
        <circle r="30" fill="none" stroke={`url(#${P}-gold)`} strokeWidth="2.5" />
        <path d="M-12 22 Q-15 4 -12 -6 Q-12 -22 0 -24 Q12 -22 12 -6 Q15 4 12 22 Z" fill={`url(#${P}-bronze)`} />
        <path d="M-13 -8 Q0 -30 13 -8 L11 -14 Q0 -26 -11 -14 Z" fill="#7a4d1f" />
        {[-10, -4, 2, 8].map((y) => <path key={y} d={`M-12 ${y + 8} Q0 ${y + 11} 12 ${y + 8}`} stroke="#e7b864" strokeWidth="1.4" fill="none" opacity="0.8" />)}
        <path d="M-6 -4 h4 M2 -4 h4 M-2 2 v5 M-4 11 h8" stroke="#4a2a10" strokeWidth="1.4" strokeLinecap="round" />
        {night && <Glow p={P} cx={0} cy={0} r={52} kind="gw" o={0.5} />}
      </g>

      {/* fascia band with the name */}
      <rect x="120" y={G1} width="560" height="18" fill={`url(#${P}-fascia)`} />
      <text x="326" y={G1 + 13.5} fontSize="13" fontFamily={SIGN_FONT} fill={`url(#${P}-gold)`} textAnchor="middle" letterSpacing="3">BRONZE TECH HUB</text>
      <text x="601" y={G1 + 12.5} fontSize="6.4" fontFamily={SIGN_FONT} fill="#e8e2d0" textAnchor="middle" letterSpacing="1.2">UGBOWO • EST. 2026</text>

      {/* ground floor */}
      <rect x="130" y={G1 + 18} width="392" height={FL - G1 - 18} fill={`url(#${P}-room)`} />
      <rect x="130" y={G1 + 18} width="392" height="30" fill={night ? '#ead6b0' : '#e2e8e6'} />
      {/* feature wall: "Hello, Benin" neon + adire-ish pattern */}
      <rect x="150" y={G1 + 24} width="110" height="40" fill={night ? '#26304e' : '#2f3a5e'} />
      <text x="205" y={G1 + 49} fontSize="12" fontFamily={HAND_FONT} fill={night ? '#ffe9a8' : '#f3d28a'} textAnchor="middle">Hello, Benin</text>
      {night && <Glow p={P} cx={205} cy={G1 + 45} r={60} ry={24} kind="gw" o={0.55} />}
      {/* reception + big screen */}
      <rect x="420" y={G1 + 24} width="76" height="42" rx="2" fill="#1e1d2a" />
      <rect x="423" y={G1 + 27} width="70" height="36" fill={`url(#${P}-scrc)`} />
      <text x="458" y={G1 + 41} fontSize="6.5" fontFamily={SIGN_FONT} fill="#fffaf0" textAnchor="middle">HACKATHON</text>
      <text x="458" y={G1 + 51} fontSize="5.4" fontFamily={SIGN_FONT} fill="#ffe36a" textAnchor="middle">SAT · 10AM · FREE</text>
      {night && <Glow p={P} cx={458} cy={G1 + 45} r={50} ry={30} kind="gc" o={0.6} />}
      {/* long co-working table */}
      <Desk x={220} y={FL - 30} skin="#6b4128" top="#d2342a" night={night} screen="b" />
      <Desk x={290} y={FL - 30} skin="#4a2c1e" top="#2f7fd6" night={night} facing={-1} screen="a" />
      {/* entrance doors */}
      <rect x="338" y={G1 + 30} width="64" height={FL - G1 - 30} fill={night ? '#3a3046' : '#55606e'} />
      <rect x="342" y={G1 + 34} width="27" height={FL - G1 - 34} fill={`url(#${P}-glass)`} opacity={night ? 0.6 : 0.85} />
      <rect x="371" y={G1 + 34} width="27" height={FL - G1 - 34} fill={`url(#${P}-glass)`} opacity={night ? 0.6 : 0.85} />
      <path d={`M365 ${G1 + 70} V${G1 + 84} M375 ${G1 + 70} V${G1 + 84}`} stroke="#d9a441" strokeWidth="2.5" strokeLinecap="round" />
      <Person x={502} y={FL - 2} s={1.15} skin="#5a3624" top="#b0793a" bottom="#2b3350" pose="stand" facing={-1} night={night}
        extra={<path d="M-12 -30 h9 v7 h-9 Z" fill="#c9ccd6" />} />
      {/* ground-floor glass */}
      <rect x="130" y={G1 + 18} width="392" height={FL - G1 - 18} fill={`url(#${P}-glass)`} opacity={night ? 0.18 : 0.4} />
      {[130, 186, 242, 298, 338, 402, 466, 522].map((x) => <rect key={x} x={x - 2} y={G1 + 18} width="4" height={FL - G1 - 18} fill="#3a3e4e" />)}
      {!night && <path d={`M196 ${G1 + 18} L226 ${G1 + 18} L186 ${FL} L156 ${FL} Z`} fill="#fff" opacity="0.22" />}
      {/* clad block ground floor: inverter room door + vents */}
      <rect x="560" y={G1 + 40} width="40" height={FL - G1 - 40} fill="#5a3a26" />
      <rect x="563" y={G1 + 43} width="34" height={FL - G1 - 46} fill="#6d4630" />
      <circle cx="592" cy={G1 + 74} r="1.8" fill="#d9a441" />
      <g transform={`translate(612 ${G1 + 34})`}>
        <rect width="54" height="22" rx="2" fill="#fffaf0" />
        <text x="27" y="9" fontSize="5.2" fontFamily={SIGN_FONT} fill="#1f7a3f" textAnchor="middle">SOLAR + INVERTER</text>
        <text x="27" y="17" fontSize="5.2" fontFamily={SIGN_FONT} fill="#2a2440" textAnchor="middle">24/7 LIGHT</text>
      </g>
      {[620, 636, 652].map((x) => <rect key={x} x={x} y={G1 + 66} width="10" height="16" fill="#3a2a22" opacity="0.6" />)}
      {/* plinth */}
      <rect x="118" y={FL - 4} width="564" height="6" fill="#d9d2c4" />

      {/* ---------- forecourt ---------- */}
      <rect x="-10" y={FL + 2} width="820" height="44" fill={`url(#${P}-tiles)`} />
      <rect x="-10" y={FL + 2} width="820" height="4" fill="#2d1b4e" opacity="0.2" />
      <rect x="-10" y={FL + 46} width="820" height={460 - FL - 46} fill={`url(#${P}-ground)`} />
      <rect x="-10" y={FL + 44} width="820" height="5" fill="#d9d2c4" />
      <path d="M-10 428 Q400 414 810 432" stroke="#7a3519" strokeWidth="8" opacity="0.2" fill="none" />
      <path d="M140 420 l6 -2 M300 436 l5 1 M520 426 l6 -1 M640 444 l4 -2" stroke="#8a3a1e" strokeWidth="2" opacity="0.5" strokeLinecap="round" />

      {/* palms framing the hub */}
      <Palm x={70} y={FL + 6} s={1.25} night={night} lean={10} />
      <Palm x={748} y={FL + 8} s={1.1} night={night} lean={-12} kind="coconut" tone={1} />
      {/* planters along the glass */}
      <Planter x={146} y={FL + 6} s={1.1} night={night} />
      <Planter x={322} y={FL + 6} s={1} night={night} kind={1} />
      <Planter x={418} y={FL + 6} s={1} night={night} kind={1} />

      {/* security post with guard */}
      <g>
        <rect x="690" y={FL - 50} width="44" height="52" fill="#efe6d6" />
        <rect x="690" y={FL - 56} width="50" height="8" fill="#1f7a3f" />
        <rect x="698" y={FL - 40} width="28" height="16" fill={`url(#${P}-glass)`} />
        <text x="712" y={FL - 6} fontSize="5" fontFamily={SIGN_FONT} fill="#2a2440" textAnchor="middle">SECURITY</text>
      </g>
      <Person x={672} y={FL + 30} s={1.35} skin="#3e2416" top="#2b3350" bottom="#1d2238" pose="stand" facing={-1} night={night}
        extra={<path d="M-6 -60 Q0 -66 6 -60 L7 -57 H-7 Z" fill="#1d2238" />} />

      {/* saloon car + keke (ride-hail drop-off) */}
      <Car p={P} x={560} y={FL + 40} s={1.15} color="#e8e8ec" dark="#8a8fa0" night={night} />
      <Keke x={196} y={FL + 42} s={1.05} flip />

      {/* walking dev with laptop bag + phone; student with backpack */}
      <Person x={380} y={FL + 52} s={1.7} skin="#5a3624" top="#141634" bottom="#3a4468" pose="walk" facing={1} night={night}
        extra={<g><rect x="-15" y="-34" width="12" height="10" rx="2" fill="#2a2834" /><path d="M-9 -34 L3 -46" stroke="#2a2834" strokeWidth="1.5" /><rect x="9" y="-37" width="4" height="7" rx="1" fill="#1a1a26" /></g>} />
      <Person x={262} y={FL + 60} s={1.75} skin="#6b4128" top="#d9a441" bottom="#2b3350" pose="walk" facing={-1} night={night}
        headwrap="#1f7a3f"
        extra={<g><rect x="-14" y="-41" width="8" height="18" rx="3" fill="#2f7fd6" /><rect x="-14" y="-41" width="3" height="18" rx="1.5" fill="#2d1b4e" opacity="0.3" /></g>} />

      {/* solar street light */}
      <g>
        <rect x="104" y={FL - 104} width="4" height="152" fill={night ? '#3a3046' : '#6d7282'} />
        <path d={`M84 ${FL - 112} L122 ${FL - 120} L126 ${FL - 112} L88 ${FL - 104} Z`} fill={`url(#${P}-pv)`} />
        <rect x="108" y={FL - 100} width="18" height="5" rx="2" fill="#d8dce4" />
      </g>

      {/* chalkboard A-frame */}
      <g transform={`translate(612 ${FL + 40})`}>
        <path d="M-16 0 L-10 -40 L10 -40 L16 0" stroke="#6b4a33" strokeWidth="3" fill="none" />
        <rect x="-12" y="-38" width="24" height="30" fill="#24302a" />
        <text x="0" y="-28" fontSize="4.6" fontFamily={HAND_FONT} fill="#fffaf0" textAnchor="middle">Code camp</text>
        <text x="0" y="-21" fontSize="4.6" fontFamily={HAND_FONT} fill="#ffe36a" textAnchor="middle">Interns wanted</text>
        <text x="0" y="-14" fontSize="4.6" fontFamily={HAND_FONT} fill="#9be38a" textAnchor="middle">Free Wi-Fi</text>
      </g>

      {night && (
        <g>
          <NightShade p={P} exclude={lit} bottom={0.7} />
          {/* warm interior cast */}
          <rect x="130" y={TOP + 16} width="392" height={G1 - TOP - 16} fill="#ffcf8a" opacity="0.12" style={{ mixBlendMode: 'screen' }} />
          <rect x="130" y={G1 + 18} width="392" height={FL - G1 - 18} fill="#ffcf8a" opacity="0.12" style={{ mixBlendMode: 'screen' }} />
          <path d={`M130 ${FL} L522 ${FL} L560 450 L100 450 Z`} fill={`url(#${P}-spill)`} style={{ mixBlendMode: 'screen' }} />
          {/* backlit name */}
          <Glow p={P} cx={326} cy={G1 + 9} r={150} ry={22} kind="gw" o={0.45} />
          <text x="326" y={G1 + 13.5} fontSize="13" fontFamily={SIGN_FONT} fill="#ffe9a8" textAnchor="middle" letterSpacing="3">BRONZE TECH HUB</text>
          {/* uplights on the cladding */}
          {[540, 600, 660].map((x) => <Glow key={x} p={P} cx={x} cy={FL - 30} r={26} ry={70} kind="gw" o={0.35} />)}
          {/* car + keke headlights, guard post lamp */}
          <Glow p={P} cx={640} cy={FL + 26} r={30} ry={12} kind="gw" o={0.6} />
          <Glow p={P} cx={262} cy={FL + 24} r={22} ry={10} kind="gw" o={0.6} />
          <Glow p={P} cx={712} cy={FL - 32} r={30} ry={20} kind="gw" o={0.6} />
          {/* solar street light */}
          <ellipse cx={117} cy={FL - 97} rx={9} ry={3} fill="#fff6d8" />
          <Glow p={P} cx={117} cy={FL - 90} r={60} ry={40} kind="gw" o={0.8} />
          <Glow p={P} cx={117} cy={FL + 30} r={70} ry={18} kind="gw" o={0.45} />
          {/* phone glow */}
          <Glow p={P} cx={398} cy={FL - 8} r={12} kind="gc" o={0.6} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
