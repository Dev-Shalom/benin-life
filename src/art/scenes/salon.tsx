// Fresh Cut barbing & hair salon (Uselu) — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Generator, PlasticChair, Treeline, Haze, SIGN_FONT, HAND_FONT } from './_sharedB';

const P = 'salon';
const FL = 344; // shop floor / pavement line

/** Hairstyle chart head. */
function StyleHead({ x, y, kind, label }: { x: number; y: number; kind: number; label: string }) {
  const hair = '#1a1420';
  const hairs = [
    <path key="0" d={`M${x - 8} ${y - 3} Q${x} ${y - 13} ${x + 8} ${y - 3}`} stroke={hair} strokeWidth="2.4" fill="none" />,
    <path key="1" d={`M${x - 3} ${y - 9} L${x} ${y - 20} L${x + 3} ${y - 9} Z`} fill={hair} />,
    <ellipse key="2" cx={x} cy={y - 8} rx="13" ry="10" fill={hair} />,
    <path key="3" d={`M${x - 9} ${y - 4} Q${x} ${y - 16} ${x + 9} ${y - 4} M${x - 9} ${y - 4} v12 M${x - 5} ${y - 9} v16 M${x + 5} ${y - 9} v16 M${x + 9} ${y - 4} v12`} stroke={hair} strokeWidth="2.4" fill="none" strokeLinecap="round" />,
    <g key="4"><path d={`M${x - 8} ${y - 4} Q${x} ${y - 14} ${x + 8} ${y - 4}`} fill={hair} /><path d={`M${x - 6} ${y - 6} L${x - 2} ${y - 12} M${x} ${y - 7} L${x} ${y - 13} M${x + 6} ${y - 6} L${x + 2} ${y - 12}`} stroke="#c9a070" strokeWidth="0.8" /></g>,
    <g key="5"><path d={`M${x - 8} ${y - 4} Q${x} ${y - 13} ${x + 8} ${y - 4}`} fill={hair} /><ellipse cx={x} cy={y - 16} rx="5" ry="4" fill={hair} /></g>,
  ];
  return (
    <g>
      <rect x={x - 17} y={y - 22} width="34" height="40" fill="#fffaf0" />
      <circle cx={x} cy={y} r="7.5" fill="#6b4128" />
      <path d={`M${x - 3} ${y + 7} v4 h6 v-4`} fill="#6b4128" />
      {hairs[kind]}
      <text x={x} y={y + 16} fontSize="4.2" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">{label}</text>
    </g>
  );
}

export default function SalonScene({ night }: { night: boolean }) {
  const skyHole = `M0 0 H800 V60 H0 Z M66 140 H386 V${FL} H66 Z M426 140 H736 V${FL} H426 Z`;
  const tube = night ? '#eaf8ff' : '#f6f2ea';
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Fresh Cut barbing and salon">
      <defs>
        <linearGradient id={`${P}-tiles`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#a8e0d0' : '#cfe8dc'} />
          <stop offset="1" stopColor={night ? '#7ab8b0' : '#a8d0c4'} />
        </linearGradient>
        <linearGradient id={`${P}-pink`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#e8b0d8' : '#f2c4d8'} />
          <stop offset="1" stopColor={night ? '#c088b8' : '#e0a0bc'} />
        </linearGradient>
        <linearGradient id={`${P}-mirror`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#dff0f8" />
          <stop offset="0.5" stopColor="#9cc0d4" />
          <stop offset="1" stopColor="#7a9ab8" />
        </linearGradient>
        <linearGradient id={`${P}-front`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#f2e2c4" />
          <stop offset="1" stopColor="#d8c0a0" />
        </linearGradient>
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        <linearGradient id={`${P}-spill`} gradientUnits="userSpaceOnUse" x1="0" y1={FL} x2="0" y2="450">
          <stop offset="0" stopColor="#cfefff" stopOpacity="0.2" />
          <stop offset="1" stopColor="#cfefff" stopOpacity="0" />
        </linearGradient>
        <pattern id={`${P}-tilegrid`} patternUnits="userSpaceOnUse" width="16" height="16">
          <path d="M0 0 H16 M0 0 V16" stroke="#fff" strokeWidth="1" opacity="0.5" />
        </pattern>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={720} sunY={40} moonX={110} moonY={34} clouds={false} />
      <Treeline y={70} fill={night ? '#1a2644' : '#7fa88a'} seed={71} amp={14} step={40} base={130} />
      <Haze p={P} y={30} h={60} night={night} o={0.4} />

      {/* building front */}
      <rect x="40" y="60" width="720" height={FL - 60} fill={`url(#${P}-front)`} />
      {night && <rect x="40" y="60" width="720" height={FL - 60} fill="#4a3a6a" opacity="0.45" />}
      <rect x="40" y="60" width="720" height="8" fill="#b9a088" />

      {/* signboard */}
      <g>
        <rect x="90" y="72" width="620" height="54" fill="#1f3f8a" />
        <rect x="90" y="72" width="620" height="54" fill="none" stroke="#f6f2ea" strokeWidth="3" />
        {/* barber stripes ends */}
        {[96, 664].map((x) => (
          <g key={x}>
            <rect x={x} y="78" width="40" height="42" fill="#f6f2ea" />
            <path d={`M${x} 86 l40 -8 M${x} 100 l40 -8 M${x} 114 l40 -8 M${x} 128 l40 -8`} stroke="#d2342a" strokeWidth="6" />
          </g>
        ))}
        <text x="400" y="106" fontSize="30" fontFamily={SIGN_FONT} fill="#f2c81a" textAnchor="middle" letterSpacing="3">FRESH CUT</text>
        <text x="400" y="120" fontSize="8" fontFamily={SIGN_FONT} fill="#f6f2ea" textAnchor="middle" letterSpacing="2">BARBING • HAIR SALON • UNISEX</text>
        <rect x="90" y="126" width="620" height="5" fill="#2d1b4e" opacity="0.35" />
      </g>

      {/* ===== barbing side (left) ===== */}
      <rect x="66" y="140" width="320" height={FL - 140} fill={`url(#${P}-tiles)`} />
      <rect x="66" y="140" width="320" height={FL - 140} fill={`url(#${P}-tilegrid)`} />
      {/* hairstyle chart */}
      <g>
        <rect x="76" y="148" width="226" height="48" fill="#d2342a" />
        <StyleHead x={96} y={170} kind={0} label="LOW CUT" />
        <StyleHead x={133} y={170} kind={1} label="PUNK" />
        <StyleHead x={170} y={170} kind={2} label="AFRO" />
        <StyleHead x={207} y={170} kind={3} label="DADA" />
        <StyleHead x={244} y={170} kind={4} label="GALLAS" />
        <StyleHead x={281} y={170} kind={5} label="SHUKU" />
      </g>
      {/* mirror + shelf */}
      <rect x="120" y="202" width="200" height="72" fill="#c9ccd8" />
      <rect x="124" y="206" width="192" height="64" fill={`url(#${P}-mirror)`} />
      <path d="M150 270 L190 206 L208 206 L168 270 Z M220 270 L250 206 L258 206 L228 270 Z" fill="#fff" opacity="0.35" />
      {/* reflection of customer's head */}
      <circle cx="226" cy="246" r="9" fill="#5a3624" opacity="0.7" />
      <rect x="120" y="276" width="200" height="6" fill="#8a8ca0" />
      {[134, 146, 160, 176, 290, 302].map((x, i) => (
        <rect key={x} x={x} y={262 + (i % 2) * 2} width="7" height={14 - (i % 2) * 2} rx="2" fill={['#2f6fd0', '#d2342a', '#f6f2ea', '#1f7a3f', '#e0a526', '#7a3fa0'][i]} />
      ))}
      {/* wall fan */}
      <g transform="translate(350 170)">
        <circle r="14" fill="none" stroke="#7d8090" strokeWidth="1.5" />
        <path d="M0 0 l-10 -6 l2 -4 Z M0 0 l10 -6 l-2 -4 Z M0 0 l0 12 l4 -2 Z" fill="#9a9db0" />
        <circle r="3" fill="#5a5a6a" />
      </g>
      {/* barber chair */}
      <g>
        <ellipse cx="226" cy={FL - 2} rx="34" ry="5" fill="#2d1b4e" opacity="0.35" />
        <path d={`M210 ${FL - 2} h32 l-4 -8 h-24 Z`} fill="#3a3846" />
        <rect x="222" y={FL - 34} width="8" height="26" fill="#9a9db0" />
        <rect x="200" y={FL - 50} width="52" height="16" rx="5" fill="#d2342a" />
        <rect x="238" y={FL - 92} width="16" height="48" rx="5" fill="#b8241e" />
        <rect x="196" y={FL - 62} width="12" height="5" rx="2" fill="#3a3846" />
      </g>
      {/* customer under white cape */}
      <Person x={232} y={FL - 30} s={1.25} skin="#5a3624" top="#f6f2ea" bottom="#f6f2ea" pose="sit" facing={-1} night={night} />
      <path d={`M210 ${FL - 74} Q232 ${FL - 82} 248 ${FL - 74} L254 ${FL - 34} L204 ${FL - 34} Z`} fill="#f6f2ea" />
      {/* barber with clippers */}
      <Person x={180} y={FL} s={1.6} skin="#4a2c1e" top="#1a1420" bottom="#3a4468" pose="work" facing={1} night={night}
        extra={<g><rect x="14" y="-36" width="8" height="5" rx="1.5" fill="#2a2a3a" transform="rotate(-30 18 -33)" /><path d="M10 -56 q2 -8 8 -4" stroke="#e0a526" strokeWidth="1" fill="none" /></g>} />
      {/* cord from clipper to socket */}
      <path d={`M216 ${FL - 52} Q300 ${FL - 20} 360 ${FL - 70}`} stroke="#1a1824" strokeWidth="1.2" fill="none" />
      <rect x="356" y={FL - 78} width="10" height="12" fill="#f6f2ea" />
      {/* hair on the floor */}
      <path d={`M200 ${FL - 4} l4 -2 M210 ${FL - 3} l3 -3 M240 ${FL - 4} l-3 -2 M252 ${FL - 3} l3 -1`} stroke="#1a1420" strokeWidth="1" />

      {/* pillar between shops */}
      <rect x="386" y="134" width="40" height={FL - 134} fill="#e6d2b0" />
      <rect x="410" y="134" width="16" height={FL - 134} fill="#3b2a5e" opacity="0.15" />
      <g transform="translate(392 170) rotate(-4)">
        <rect width="30" height="44" fill="#fffaf0" />
        <text x="15" y="12" fontSize="4.6" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle">LIGHT NO</text>
        <text x="15" y="19" fontSize="4.6" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle">DEY?</text>
        <text x="15" y="28" fontSize="4.6" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">WE GET</text>
        <text x="15" y="35" fontSize="4.6" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">GEN!!</text>
      </g>

      {/* ===== hair salon side (right) ===== */}
      <rect x="426" y="140" width="310" height={FL - 140} fill={`url(#${P}-pink)`} />
      {/* wig heads on a shelf */}
      <rect x="446" y="196" width="140" height="5" fill="#8a5232" />
      {[466, 506, 546].map((x, i) => (
        <g key={x}>
          <ellipse cx={x} cy="184" rx="9" ry="11" fill="#e8d8c8" />
          <path d={i === 0 ? `M${x - 12} 196 Q${x - 14} 168 ${x} 168 Q${x + 14} 168 ${x + 12} 196 L${x + 8} 182 Q${x} 176 ${x - 8} 182 Z` : i === 1 ? `M${x - 10} 186 Q${x - 12} 166 ${x} 168 Q${x + 12} 166 ${x + 10} 186 L${x + 7} 178 Q${x} 174 ${x - 7} 178 Z` : `M${x - 11} 198 L${x - 11} 178 Q${x} 160 ${x + 11} 178 L${x + 11} 198 L${x + 8} 180 Q${x} 174 ${x - 8} 180 Z`}
            fill={['#1a1420', '#7a3a2a', '#d9a441'][i]} />
        </g>
      ))}
      {/* posters of braids */}
      <rect x="610" y="150" width="56" height="70" fill="#fffaf0" />
      <circle cx="638" cy="182" r="12" fill="#6b4128" />
      <path d="M624 178 Q638 160 652 178 M626 180 v28 M632 176 v34 M638 174 v36 M644 176 v34 M650 180 v28" stroke="#1a1420" strokeWidth="2" fill="none" />
      <text x="638" y="216" fontSize="5" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">KNOTLESS</text>
      <rect x="674" y="150" width="50" height="60" fill="#fffaf0" />
      <circle cx="699" cy="178" r="11" fill="#5a3624" />
      <path d="M686 176 Q699 158 712 176 L714 196 M686 176 L684 196" stroke="#7a3a2a" strokeWidth="3" fill="none" />
      <text x="699" y="204" fontSize="5" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">FRONTAL</text>
      {/* hood dryer + lady reading */}
      <g>
        <rect x="474" y={FL - 40} width="56" height="14" rx="4" fill="#2f6fd0" />
        <path d={`M488 ${FL - 26} V${FL} M516 ${FL - 26} V${FL}`} stroke="#3a3846" strokeWidth="3" />
        <path d={`M522 ${FL - 120} V${FL - 40}`} stroke="#9a9db0" strokeWidth="4" />
      </g>
      <Person x={500} y={FL - 30} s={1.3} skin="#5a3624" top="#e86a9a" bottom="#2b3350" pose="sit" facing={1} night={night}
        extra={<g transform="translate(14 -36) rotate(-10)"><rect width="10" height="8" fill="#f6f2ea" /></g>} />
      <path d={`M484 ${FL - 108} Q500 ${FL - 130} 528 ${FL - 116} L530 ${FL - 96} Q506 ${FL - 88} 484 ${FL - 96} Z`} fill="#e8e6e1" />
      <path d={`M516 ${FL - 120} Q528 ${FL - 116} 530 ${FL - 96} L522 ${FL - 94} Z`} fill="#3b2a5e" opacity="0.2" />
      {/* braiding in progress */}
      <PlasticChair x={640} y={FL} s={1.3} color="#f6f2ea" shade="#9b97b0" />
      <Person x={644} y={FL} s={1.3} skin="#4a2c1e" top="#2f6fd0" bottom="#2b3350" pose="sit" facing={-1} night={night}
        extra={<path d="M-4 -60 v16 M-1 -60 v18 M2 -60 v17 M5 -59 v15" stroke="#1a1420" strokeWidth="1.2" />} />
      <Person x={684} y={FL} s={1.55} skin="#5a3624" top="#7a3fa0" wrapper="#e0a526" headwrap="#d2342a" pose="work" facing={-1} night={night} />

      {/* fluorescent tubes */}
      <rect x="150" y="142" width="80" height="4" rx="2" fill={tube} />
      <rect x="520" y="142" width="80" height="4" rx="2" fill={tube} />

      {/* pavement + road */}
      <rect x="40" y={FL} width="720" height="12" fill="#b9a99a" />
      <rect x="40" y={FL + 10} width="720" height="4" fill="#2d1b4e" opacity="0.3" />
      <rect x="-10" y={FL + 14} width="820" height={460 - FL} fill={`url(#${P}-ground)`} />
      <rect x="-10" y="60" width="50" height="300" fill={night ? '#3a3a62' : '#e0c8a8'} />
      <rect x="760" y="60" width="50" height="300" fill={night ? '#3a3a62' : '#d8b8c0'} />
      <path d="M-10 410 Q400 396 810 414" stroke="#7a3519" strokeWidth="8" opacity="0.2" fill="none" />

      {/* barber pole */}
      <g>
        <rect x="46" y="200" width="14" height="70" rx="6" fill="#f6f2ea" />
        <path d="M46 210 l14 -8 M46 226 l14 -8 M46 242 l14 -8 M46 258 l14 -8 M46 272 l14 -8" stroke="#d2342a" strokeWidth="4" />
        <path d="M46 218 l14 -8 M46 234 l14 -8 M46 250 l14 -8 M46 266 l14 -8" stroke="#2f6fd0" strokeWidth="3" />
        <rect x="44" y="196" width="18" height="6" rx="2" fill="#9a9db0" />
        <rect x="44" y="268" width="18" height="6" rx="2" fill="#9a9db0" />
      </g>

      {/* waiting bench with customer on phone */}
      <g>
        <rect x="70" y="398" width="130" height="8" fill="#8a5232" />
        <path d="M80 406 V428 M190 406 V428" stroke="#5a3418" strokeWidth="5" />
      </g>
      <Person x={130} y={428} s={1.4} skin="#5a3624" top="#d2342a" bottom="#2b3350" pose="sit" facing={1} night={night}
        extra={<rect x="13" y="-34" width="4" height="7" rx="1" fill="#1a1a26" />} />

      {/* generator outside with extension lead */}
      <Generator p={P} x={706} y={428} s={1.6} night={night} color="#d2342a" />
      <path d={`M670 412 Q600 420 560 400 Q520 380 480 ${FL + 4}`} stroke="#1a1824" strokeWidth="2" fill="none" />
      <rect x="586" y="400" width="44" height="22" fill="#fffaf0" transform="rotate(-4 608 411)" />
      <text x="608" y="410" fontSize="5" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle" transform="rotate(-4 608 411)">FUEL MONEY</text>
      <text x="608" y="418" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle" transform="rotate(-4 608 411)">extra ₦200</text>

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} />
          {/* fluorescent interiors */}
          {/* interiors stay lit (excluded from shade) — just a cool fluorescent cast */}
          <rect x="66" y="140" width="320" height={FL - 140} fill="#b8d8f0" opacity="0.25" style={{ mixBlendMode: 'multiply' }} />
          <rect x="426" y="140" width="310" height={FL - 140} fill="#d8c8f0" opacity="0.25" style={{ mixBlendMode: 'multiply' }} />
          <Glow p={P} cx={190} cy={146} r={120} ry={30} kind="gc" o={0.5} />
          <Glow p={P} cx={560} cy={146} r={120} ry={30} kind="gc" o={0.5} />
          <rect x="150" y="142" width="80" height="4" rx="2" fill="#fff" />
          <rect x="520" y="142" width="80" height="4" rx="2" fill="#fff" />
          {/* light spill onto pavement */}
          <path d={`M66 ${FL} L386 ${FL} L460 450 L0 450 Z M426 ${FL} L736 ${FL} L800 440 L400 450 Z`} fill={`url(#${P}-spill)`} style={{ mixBlendMode: 'screen' }} />
          {/* backlit sign */}
          <Glow p={P} cx={400} cy={98} r={330} ry={50} kind="gc" o={0.3} />
          <text x="400" y="106" fontSize="30" fontFamily={SIGN_FONT} fill="#ffe36a" textAnchor="middle" letterSpacing="3">FRESH CUT</text>
          {/* neon OPEN */}
          <rect x="300" y="290" width="54" height="22" rx="4" fill="#1a1028" />
          <text x="327" y="306" fontSize="12" fontFamily={SIGN_FONT} fill="#ff4fa8" textAnchor="middle">OPEN</text>
          <Glow p={P} cx={327} cy={301} r={44} ry={24} kind="gf" o={0.6} />
          {/* phone glow */}
          <Glow p={P} cx={150} cy={392} r={16} kind="gc" o={0.7} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
