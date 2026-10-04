// GRA duplex estate — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, PlasticChair, Car, Palm, Treeline, Haze, SIGN_FONT, rng } from './_sharedB';

const P = 'home_duplex';
const VP = 400; // vanishing x for the paving
const GY = 334; // compound floor line (house base)

function Win({ x, y, w, h, night, lit, warm = true }: { x: number; y: number; w: number; h: number; night: boolean; lit: boolean; warm?: boolean }) {
  const glass = night ? (lit ? (warm ? '#ffd58a' : '#d6ecff') : '#1a2046') : `url(#${P}-glass)`;
  return (
    <g>
      <rect x={x - 5} y={y - 5} width={w + 10} height={h + 10} fill="#fbf4e6" />
      <rect x={x - 5} y={y + h + 3} width={w + 10} height="4" fill="#d9c7a8" />
      <rect x={x} y={y} width={w} height={h} fill={glass} />
      {!night && <path d={`M${x + w * 0.1} ${y + h} L${x + w * 0.55} ${y} L${x + w * 0.75} ${y} L${x + w * 0.3} ${y + h} Z`} fill="#e9f4ff" opacity="0.35" />}
      {night && lit && <rect x={x} y={y + h * 0.55} width={w} height={h * 0.45} fill="#ff9a3c" opacity="0.25" />}
      <path d={`M${x + w / 2} ${y} v${h} M${x} ${y + h * 0.32} h${w}`} stroke="#fbf4e6" strokeWidth="2.4" />
      {/* drapes */}
      <path d={`M${x} ${y} h${w * 0.18} q-2 ${h * 0.5} 1 ${h} h${-w * 0.18} Z M${x + w} ${y} h${-w * 0.18} q2 ${h * 0.5} -1 ${h} h${w * 0.18} Z`} fill={night && lit ? '#e8a24a' : '#c9b48a'} opacity="0.85" />
      <rect x={x - 5} y={y - 5} width={w + 10} height="3" fill="#2d1b4e" opacity="0.2" />
    </g>
  );
}

function GardenLamp({ x, y, s = 1, night }: { x: number; y: number; s?: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="3" cy="0" rx="9" ry="2" fill="#2d1b4e" opacity="0.35" />
      <rect x="-2" y="-46" width="4" height="46" fill="#24232e" />
      <rect x="-5" y="-6" width="10" height="6" fill="#24232e" />
      <path d="M-7 -48 h14 l-3 -12 h-8 Z" fill={night ? '#fff1c4' : '#e9e4d6'} />
      <path d="M-8 -48 h16 M-6 -60 h12 l-6 -5 Z" stroke="#24232e" strokeWidth="2" fill="#24232e" />
    </g>
  );
}

export default function HomeDuplexScene({ night }: { night: boolean }) {
  const r = rng(404);
  // interlocking paving: rows get deeper toward the camera, joints converge on VP
  const rowsY: number[] = [];
  for (let i = 0, y = GY + 10; y < 460; i++) { rowsY.push(y); y += 5 + i * 2.6; }
  let joints = '';
  let lines = '';
  rowsY.forEach((y0, i) => {
    const y1 = rowsY[i + 1] ?? 470;
    lines += `M-10 ${y0.toFixed(1)}H810`;
    const f0 = (y0 - 230) / (GY - 230);
    const f1 = (y1 - 230) / (GY - 230);
    const n = 22;
    for (let c = 0; c <= n; c++) {
      const bx = -600 + ((c + (i % 2 ? 0.5 : 0)) * 2000) / n; // x at y=GY
      const xa = VP + (bx - VP) * f0 / 3.2;
      const xb = VP + (bx - VP) * f1 / 3.2;
      if (Math.max(xa, xb) < -10 || Math.min(xa, xb) > 810) continue;
      // interlock "dog-bone" kink halfway down the joint
      const ym = (y0 + y1) / 2;
      const xm = (xa + xb) / 2;
      const k = (y1 - y0) * 0.18 * (c % 2 ? 1 : -1);
      joints += `M${xa.toFixed(1)} ${y0.toFixed(1)}L${(xm + k).toFixed(1)} ${(ym - 1).toFixed(1)}L${(xm - k).toFixed(1)} ${(ym + 1).toFixed(1)}L${xb.toFixed(1)} ${y1.toFixed(1)}`;
    }
  });
  const flowers = Array.from({ length: 34 }, () => ({ x: 236 + r() * 330, y: GY - 2 + r() * 10, c: r() > 0.5 ? '#e0287a' : '#d2342a', s: 1.6 + r() * 1.8 }));
  const skyHole = `M0 0 H800 V240 H588 L588 158 L500 92 L300 92 L212 158 L212 240 H0 Z`;
  const wallTop = 236;

  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="GRA duplex">
      <defs>
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="1" y2="0.25">
          <stop offset="0" stopColor="#fff6e4" />
          <stop offset="0.55" stopColor="#f6e6c8" />
          <stop offset="1" stopColor="#e2cba8" />
        </linearGradient>
        <linearGradient id={`${P}-roof`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#5a6488" />
          <stop offset="0.6" stopColor="#3e4566" />
          <stop offset="1" stopColor="#2c3150" />
        </linearGradient>
        <linearGradient id={`${P}-glass`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6f93b8" />
          <stop offset="0.6" stopColor="#3f5e84" />
          <stop offset="1" stopColor="#2c4064" />
        </linearGradient>
        <linearGradient id={`${P}-pave`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c7b9ad" />
          <stop offset="0.5" stopColor="#b9a596" />
          <stop offset="1" stopColor="#a08a7c" />
        </linearGradient>
        <linearGradient id={`${P}-fence`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#efe0c4" />
          <stop offset="1" stopColor="#d8bf9a" />
        </linearGradient>
        <linearGradient id={`${P}-flood`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff4cf" stopOpacity="0.3" />
          <stop offset="1" stopColor="#ffd27a" stopOpacity="0" />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={110} sunY={64} moonX={680} moonY={62} />

      {/* leafy GRA beyond the wall */}
      <Treeline y={226} fill={night ? '#1a2644' : '#7fa88a'} seed={31} amp={20} step={44} base={300} />
      {[[60, 200, 1.1], [250, 214, 0.8], [600, 206, 0.9], [770, 196, 1.2]].map(([x, y, s], i) => (
        <g key={i} transform={`translate(${x} ${y}) scale(${s})`}>
          <ellipse cx="0" cy="0" rx="46" ry="28" fill={night ? '#18223e' : '#6a9a74'} />
          <ellipse cx="-14" cy="-10" rx="26" ry="16" fill={night ? '#1e2a4a' : '#86b28a'} />
        </g>
      ))}
      <Haze p={P} y={190} h={70} night={night} o={0.45} />

      {/* perimeter fence: wall, pillars, spikes + razor wire */}
      <rect x="-10" y={wallTop} width="820" height={GY - wallTop} fill={`url(#${P}-fence)`} />
      <rect x="-10" y={wallTop} width="820" height="7" fill="#9c8b7a" />
      <rect x="-10" y={wallTop + 7} width="820" height="3" fill="#2d1b4e" opacity="0.2" />
      <path d={Array.from({ length: 82 }, (_, i) => `M${-10 + i * 10} ${wallTop} l2 -9 l2 9`).join('')} fill="#3a3846" />
      <path d={Array.from({ length: 40 }, (_, i) => `M${-6 + i * 21} ${wallTop - 12}a8 5 0 1 0 0.1 0`).join('')} stroke={night ? '#6a6c90' : '#8a8c9a'} strokeWidth="0.9" fill="none" />
      {[-4, 96, 196, 604, 704].map((x) => (
        <g key={x}>
          <rect x={x} y={wallTop - 8} width="20" height={GY - wallTop + 8} fill="#e6d2b0" />
          <rect x={x + 12} y={wallTop - 8} width="8" height={GY - wallTop + 8} fill="#3b2a5e" opacity="0.18" />
          <rect x={x - 3} y={wallTop - 12} width="26" height="6" fill="#8e7e6e" />
          <rect x={x + 5} y={wallTop - 24} width="10" height="12" fill={night ? '#fff1c4' : '#e9e4d6'} />
          <path d={`M${x + 3} ${wallTop - 24} h14 l-3 -5 h-8 Z`} fill="#24232e" />
        </g>
      ))}

      {/* sliding gate (right) */}
      <g>
        <rect x="622" y={wallTop - 14} width="84" height={GY - wallTop + 14} fill="#1f2230" />
        <path d={Array.from({ length: 13 }, (_, i) => `M${626 + i * 6.5} ${wallTop - 10}V${GY - 4}`).join('')} stroke="#3a3e52" strokeWidth="2.4" />
        <rect x="622" y={wallTop + 10} width="84" height="5" fill="#2c3044" />
        <rect x="622" y={GY - 30} width="84" height="5" fill="#2c3044" />
        <path d={Array.from({ length: 13 }, (_, i) => `M${624 + i * 6.5} ${wallTop - 14} l2.5 -7 l2.5 7`).join('')} fill="#d9a441" />
        <circle cx="664" cy={wallTop + 42} r="10" fill="none" stroke="#d9a441" strokeWidth="2" />
        <path d="M658 278 l12 0 M664 272 v12" stroke="#d9a441" strokeWidth="1.6" />
        <rect x="622" y={wallTop - 14} width="84" height={GY - wallTop + 14} fill="#fff" opacity={night ? 0 : 0.05} />
      </g>
      {/* gateman's post */}
      <rect x="730" y="284" width="44" height="50" fill="#e6d2b0" />
      <rect x="738" y="296" width="18" height="14" fill={night ? '#ffd58a' : '#3f5e84'} />
      <path d="M724 284 L780 284 L776 276 L728 276 Z" fill="#b5552b" />
      <text x="752" y="324" fontSize="5" fontFamily={SIGN_FONT} fill="#7a3519" textAnchor="middle">SECURITY</text>

      {/* palms in the compound */}
      <Palm x={150} y={GY + 4} s={1.05} night={night} kind="coconut" lean={-12} />
      <Palm x={660} y={GY + 2} s={0.95} night={night} kind="coconut" lean={14} tone={1} />

      {/* duplex — side return (shade) */}
      <path d={`M560 160 L588 168 L588 ${GY} L560 ${GY} Z`} fill="#b7a2a6" />
      {/* main block */}
      <rect x="240" y="160" width="320" height={GY - 160} fill={`url(#${P}-wall)`} />
      <rect x="236" y="244" width="356" height="9" fill="#fffaf0" />
      <rect x="236" y="252" width="356" height="5" fill="#2d1b4e" opacity="0.2" />
      <rect x="240" y={GY - 14} width="348" height="14" fill="#8a7a6e" />
      <rect x="240" y={GY - 14} width="348" height="2.5" fill="#b9a99a" />
      {/* hip roof */}
      <path d="M212 160 L588 160 L500 94 L300 94 Z" fill={`url(#${P}-roof)`} />
      <path d={Array.from({ length: 16 }, (_, i) => `M${220 + i * 23.5} 160 L${302 + i * 13} 95`).join('')} stroke="#7a84a8" strokeWidth="1" opacity="0.4" />
      <path d="M500 94 L588 160 L560 160 Z" fill="#232742" opacity="0.6" />
      <path d="M300 94 L500 94" stroke="#8a94b8" strokeWidth="2.5" />
      <rect x="208" y="158" width="384" height="7" fill="#fbf4e6" />
      <rect x="212" y="165" width="376" height="7" fill="#2d1b4e" opacity="0.22" />
      {/* DStv dish + chimney vent */}
      <g transform="translate(520 120) rotate(-25)">
        <ellipse rx="11" ry="13" fill="#e8e6e1" />
        <ellipse cx="1.5" cy="1" rx="8" ry="10" fill="#c8c6d0" />
        <path d="M0 0 L13 3" stroke="#7d8090" strokeWidth="1.6" />
      </g>

      {/* windows */}
      <Win x={262} y={186} w={58} h={44} night={night} lit />
      <Win x={480} y={186} w={58} h={44} night={night} lit={false} />
      <Win x={262} y={268} w={58} h={46} night={night} lit warm />
      <Win x={480} y={268} w={58} h={46} night={night} lit warm={false} />
      {/* split AC units */}
      <rect x="246" y="208" width="12" height="18" fill="#ecebe6" />
      <rect x="544" y="290" width="12" height="18" fill="#ecebe6" />

      {/* central portico: pediment, columns, balcony */}
      <rect x="340" y="160" width="120" height={GY - 160} fill="#fff8ec" />
      <rect x="350" y="176" width="100" height="66" fill={night ? '#ffd58a' : `url(#${P}-glass)`} />
      <path d="M400 176 v66 M350 200 h100" stroke="#fbf4e6" strokeWidth="2.4" />
      {!night && <path d="M360 242 L392 176 L408 176 L376 242 Z" fill="#e9f4ff" opacity="0.3" />}
      <path d="M326 160 L400 118 L474 160 Z" fill="#fffaf0" />
      <path d="M338 155 L400 125 L462 155 Z" fill="#efe0c4" />
      <path d="M400 118 L474 160 L460 160 L400 126 Z" fill="#3b2a5e" opacity="0.15" />
      <circle cx="400" cy="144" r="7" fill="#d9a441" />
      <circle cx="398" cy="142" r="3" fill="#ffe6a0" opacity="0.7" />
      {/* balcony balustrade */}
      <rect x="330" y="236" width="140" height="6" fill="#fffaf0" />
      <path d={Array.from({ length: 14 }, (_, i) => `M${336 + i * 9.6} 242 v14`).join('')} stroke="#f6ead2" strokeWidth="5" strokeLinecap="round" />
      <path d={Array.from({ length: 14 }, (_, i) => `M${338 + i * 9.6} 242 v14`).join('')} stroke="#a89ab0" strokeWidth="1.2" opacity="0.6" />
      <rect x="330" y="255" width="140" height="6" fill="#fffaf0" />
      {/* front door */}
      <rect x="370" y="270" width="60" height={GY - 270} fill="#d9c7a8" />
      <rect x="376" y="276" width="48" height={GY - 276} fill="#6b3a22" />
      <path d={`M400 276 V${GY} M382 284 h12 v16 h-12 Z M406 284 h12 v16 h-12 Z M382 306 h12 v16 h-12 Z M406 306 h12 v16 h-12 Z`} stroke="#4a2414" strokeWidth="1.4" fill="none" />
      <path d="M396 300 v10 M404 300 v10" stroke="#d9a441" strokeWidth="2" />
      <rect x="400" y="276" width="24" height={GY - 276} fill="#2d1b4e" opacity="0.15" />
      {/* columns */}
      {[334, 356, 444, 466].map((x) => (
        <g key={x}>
          <rect x={x - 5} y="160" width="10" height={GY - 160} fill="#fffaf0" />
          <rect x={x + 1} y="160" width="4" height={GY - 160} fill="#3b2a5e" opacity="0.16" />
          <rect x={x - 7} y="160" width="14" height="5" fill="#efe0c4" />
          <rect x={x - 7} y={GY - 8} width="14" height="8" fill="#efe0c4" />
        </g>
      ))}
      {/* wall lamps by door */}
      <rect x="363" y="282" width="5" height="9" rx="1" fill={night ? '#fff1c4' : '#e9e4d6'} />
      <rect x="432" y="282" width="5" height="9" rx="1" fill={night ? '#fff1c4' : '#e9e4d6'} />
      {/* steps */}
      <rect x="350" y={GY} width="100" height="5" fill="#e9dfcf" />
      <rect x="342" y={GY + 5} width="116" height="5" fill="#d9cdbb" />
      {/* contact shadow + lawn bed with ixora */}
      <rect x="212" y={GY} width="376" height="4" fill="#2d1b4e" opacity="0.25" />
      <path d={`M216 ${GY + 10} Q228 ${GY - 14} 248 ${GY - 4} Q262 ${GY - 18} 282 ${GY - 4} Q300 ${GY - 16} 322 ${GY - 2} L336 ${GY + 10} Z M464 ${GY + 10} Q478 ${GY - 16} 500 ${GY - 4} Q520 ${GY - 18} 540 ${GY - 4} Q560 ${GY - 14} 584 ${GY + 10} Z`} fill={night ? '#16302e' : '#2f7a3a'} />
      <path d={`M226 ${GY - 2} Q240 ${GY - 12} 256 ${GY - 6} M480 ${GY - 4} Q500 ${GY - 14} 516 ${GY - 8}`} stroke={night ? '#24443e' : '#5aa84a'} strokeWidth="3" fill="none" />
      {flowers.filter((f) => f.x < 334 || f.x > 466).map((f, i) => (
        <circle key={i} cx={f.x.toFixed(1)} cy={(f.y - 6).toFixed(1)} r={f.s.toFixed(1)} fill={night ? '#5a2a48' : f.c} />
      ))}
      <rect x="212" y={GY + 8} width="376" height="4" fill="#9a8a7a" />

      {/* compound paving */}
      <path d={`M-10 ${GY} H212 V${GY + 12} H588 V${GY} H810 V460 H-10 Z`} fill={`url(#${P}-pave)`} />
      <path d={joints} stroke="#7a6a64" strokeWidth="0.8" fill="none" opacity="0.55" />
      <path d={lines} stroke="#7a6a64" strokeWidth="0.9" opacity="0.6" />
      {/* red-paver border bands (driveway edges) */}
      <path d={`M140 460 L330 ${GY + 12} L346 ${GY + 12} L176 460 Z M660 460 L470 ${GY + 12} L454 ${GY + 12} L624 460 Z`} fill="#b5552b" opacity="0.55" />
      {/* tree shade + sun dapple */}
      <ellipse cx="170" cy="372" rx="90" ry="14" fill="#3b2a5e" opacity="0.18" />
      <path d="M0 450 L0 400 Q200 380 400 420 L420 450 Z" fill="#3b2a5e" opacity="0.1" />
      {!night && <ellipse cx="420" cy="390" rx="200" ry="30" fill="#ffe7b8" opacity="0.18" />}

      {/* garden lamps */}
      <GardenLamp x={226} y={364} night={night} />
      <GardenLamp x={574} y={364} night={night} />

      {/* SUV in the compound */}
      <Car p={P} x={610} y={420} s={1.12} kind="suv" color="#2f3550" dark="#1c2034" night={night} flip />
      {/* plant pots */}
      {[[330, GY + 16], [470, GY + 16]].map(([x, y], i) => (
        <g key={i}>
          <path d={`M${x - 9} ${y - 14} L${x + 9} ${y - 14} L${x + 6} ${y} L${x - 6} ${y} Z`} fill="#c46a3c" />
          <path d={`M${x} ${y - 14} q-12 -14 -4 -28 q6 10 4 28 q4 -16 14 -22 q-2 12 -14 22`} fill={night ? '#1d3a34' : '#3f8a3a'} />
        </g>
      ))}

      {/* people: gateman by the gate, madam with handbag */}
      <PlasticChair x={710} y={360} s={1.2} color="#2f6fd0" shade="#1d3f7a" />
      <Person x={714} y={360} s={1.25} skin="#4a2c1e" top="#4a5a3a" bottom="#2b3350" pose="sit" facing={-1} night={night}
        extra={<path d="M-6 -52 h12 l1 -4 h-14 Z M-6 -52 h-4" stroke="#2a2a3a" strokeWidth="1.5" fill="#2a2a3a" />} />
      <Person x={300} y={392} s={1.35} skin="#5a3624" top="#7a3fa0" wrapper="#7a3fa0" headwrap="#d9a441" pose="walk" night={night}
        extra={<g><path d="M8 -26 q4 -6 8 0" stroke="#3a2214" strokeWidth="1.2" fill="none" /><rect x="7" y="-26" width="10" height="8" rx="1.5" fill="#d2342a" /></g>} />
      {/* child on a bicycle near the car */}
      <g transform="translate(470 404)">
        <ellipse cx="2" cy="0" rx="20" ry="2.5" fill="#2d1b4e" opacity="0.3" />
        <circle cx="-12" cy="-8" r="8" fill="none" stroke="#2a2a3a" strokeWidth="1.8" />
        <circle cx="12" cy="-8" r="8" fill="none" stroke="#2a2a3a" strokeWidth="1.8" />
        <path d="M-12 -8 L-2 -8 L6 -20 L-6 -20 Z M12 -8 L7 -24 L10 -26" stroke="#d2342a" strokeWidth="2" fill="none" />
      </g>
      <Person x={468} y={396} s={0.95} skin="#5a3624" top="#e0a526" bottom="#2f6fd0" pose="sit" night={night} />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[170, 240]} />
          {/* lit windows */}
          <Glow p={P} cx={291} cy={208} r={70} o={0.7} />
          <Glow p={P} cx={291} cy={291} r={70} o={0.7} />
          <Glow p={P} cx={509} cy={291} r={60} kind="gc" o={0.5} />
          <Glow p={P} cx={400} cy={209} r={80} o={0.75} />
          <rect x="262" y="186" width="58" height="44" fill="#ffd58a" opacity="0.3" />
          <rect x="262" y="268" width="58" height="46" fill="#ffd58a" opacity="0.3" />
          <rect x="350" y="176" width="100" height="66" fill="#ffd58a" opacity="0.3" />
          {/* porch + wall lamps */}
          <Glow p={P} cx={365} cy={286} r={46} o={0.9} />
          <Glow p={P} cx={435} cy={286} r={46} o={0.9} />
          <Glow p={P} cx={400} cy={GY + 20} r={110} ry={30} o={0.5} />
          {/* garden lamps */}
          <Glow p={P} cx={226} cy={310} r={50} o={0.9} />
          <Glow p={P} cx={574} cy={310} r={50} o={0.9} />
          <Glow p={P} cx={226} cy={366} r={70} ry={16} o={0.5} />
          <Glow p={P} cx={574} cy={366} r={70} ry={16} o={0.5} />
          {/* fence pillar lamps */}
          {[-4, 96, 196, 604, 704].map((x) => <Glow key={x} p={P} cx={x + 10} cy={wallTop - 18} r={34} o={0.8} />)}
          {/* security floodlight on gatehouse washing the compound */}
          <path d="M748 274 L560 450 L800 450 L800 340 Z" fill={`url(#${P}-flood)`} style={{ mixBlendMode: 'screen' }} />
          <rect x="742" y="268" width="12" height="6" fill="#fffbe6" />
          <Glow p={P} cx={748} cy={271} r={30} kind="gc" o={0.9} />
          <rect x="738" y="296" width="18" height="14" fill="#ffd58a" opacity="0.5" />
          {/* moon rim on roof + palms */}
          <path d="M500 94 L588 160" stroke="#b9c2ff" strokeWidth="2" opacity="0.35" />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
