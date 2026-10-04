// Mama Osas buka — roadside food spot — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, ZincPattern, Bulb, Treeline, Haze, SIGN_FONT, HAND_FONT } from './_sharedB';

const P = 'buka';
const CT = 300; // counter top

/** Big aluminium pot with soup; (x,y) = base centre. */
function Pot({ x, y, w = 50, soup, night, label }: { x: number; y: number; w?: number; soup: string; night: boolean; label?: string }) {
  const h = w * 0.62;
  return (
    <g>
      <ellipse cx={x + 4} cy={y} rx={w * 0.58} ry="4" fill="#2d1b4e" opacity="0.4" />
      <path d={`M${x - w / 2} ${y - h} L${x - w / 2 + 2} ${y - 3} Q${x} ${y + 2} ${x + w / 2 - 2} ${y - 3} L${x + w / 2} ${y - h} Z`} fill={`url(#${P}-alu)`} />
      <path d={`M${x + w * 0.15} ${y - h} L${x + w / 2} ${y - h} L${x + w / 2 - 2} ${y - 3} Q${x + w * 0.3} ${y} ${x + w * 0.15} ${y - 1} Z`} fill="#3b2a5e" opacity="0.22" />
      <ellipse cx={x} cy={y - h} rx={w / 2} ry={w * 0.12} fill="#8d90a6" />
      <ellipse cx={x} cy={y - h + 1} rx={w / 2 - 3} ry={w * 0.1} fill={soup} />
      <ellipse cx={x - w * 0.12} cy={y - h} rx={w * 0.14} ry={w * 0.03} fill="#fff" opacity={night ? 0.15 : 0.35} />
      <path d={`M${x - w / 2 - 6} ${y - h + 6} h6 M${x + w / 2} ${y - h + 6} h6`} stroke="#6d7084" strokeWidth="3" strokeLinecap="round" />
      <path d={`M${x - w / 2 + 3} ${y - h + 4} V${y - 6}`} stroke="#fff" strokeWidth="2" opacity="0.4" />
      {label && <text x={x} y={y - h * 0.38} fontSize="5" fontFamily={SIGN_FONT} fill="#2a2440" textAnchor="middle">{label}</text>}
    </g>
  );
}

function Steam({ x, y, s = 1, night }: { x: number; y: number; s?: number; night: boolean }) {
  return (
    <path d={`M${x} ${y} q${-8 * s} ${-12 * s} 0 ${-24 * s} q${8 * s} ${-12 * s} 0 ${-26 * s} M${x + 10 * s} ${y - 2 * s} q${-6 * s} ${-10 * s} 2 ${-20 * s} q${7 * s} ${-10 * s} -1 ${-22 * s}`}
      stroke={night ? '#b9b0d8' : '#fffaf2'} strokeWidth={4 * s} fill="none" opacity={night ? 0.35 : 0.55} strokeLinecap="round" />
  );
}

export default function BukaScene({ night }: { night: boolean }) {
  const skyHole = 'M0 0 H800 V200 H0 Z';
  const menu = [
    ['OWO SOUP + STARCH', '₦1,500'],
    ['BLACK SOUP + POUNDO', '₦2,000'],
    ['BANGA + STARCH', '₦1,800'],
    ['EGUSI + EBA', '₦1,200'],
    ['MEAT / FISH', '₦300/₦500'],
  ];
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Mama Osas buka">
      <defs>
        <linearGradient id={`${P}-alu`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#e9ebf2" />
          <stop offset="0.3" stopColor="#c6c9d6" />
          <stop offset="0.7" stopColor="#9a9db2" />
          <stop offset="1" stopColor="#6d7084" />
        </linearGradient>
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3a72b8" />
          <stop offset="1" stopColor="#2c5a94" />
        </linearGradient>
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.5" stopColor="#b0603a" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        <linearGradient id={`${P}-wood`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#a8683a" />
          <stop offset="1" stopColor="#6a3a1e" />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />
      <ZincPattern p={P} night={night} />
      <Sky p={P} night={night} sunX={700} sunY={56} moonX={90} moonY={60} />

      {/* the street behind: shops + trees */}
      <Treeline y={200} fill={night ? '#1a2644' : '#86ab92'} seed={61} amp={14} step={34} base={280} />
      {[[-10, 150, 90], [640, 140, 100], [720, 170, 90]].map(([x, y, w], i) => (
        <g key={i}>
          <rect x={x} y={y} width={w} height={260 - y} fill={night ? '#3a3a62' : i === 1 ? '#e8c89a' : '#d9b5c0'} />
          <rect x={x + 10} y={y + 16} width="16" height="18" fill={night ? '#ffcf73' : '#5a6e90'} />
          <rect x={x + 40} y={y + 16} width="16" height="18" fill={night ? '#1c2244' : '#5a6e90'} />
          <path d={`M${x - 4} ${y} h${w + 8} l-4 -8 h${-w} Z`} fill={night ? '#2c2c50' : '#9a9db0'} />
        </g>
      ))}
      <Haze p={P} y={170} h={90} night={night} o={0.45} />

      {/* ground */}
      <rect x="-10" y="250" width="820" height="210" fill={`url(#${P}-ground)`} />
      <path d="M-10 420 Q400 400 810 426" stroke="#7a3519" strokeWidth="10" opacity="0.18" fill="none" />

      {/* buka shack */}
      <g>
        <rect x="120" y="160" width="520" height="190" fill={`url(#${P}-wall)`} />
        <path d="M120 300 H640 V350 H120 Z" fill="#1d3a6a" opacity="0.5" />
        {/* back shelf with flasks, drinks, crates */}
        <rect x="140" y="214" width="480" height="5" fill="#6a3a1e" />
        {[160, 196, 232].map((x, i) => (
          <g key={x}>
            <rect x={x} y="190" width="28" height="24" rx="4" fill={['#d2342a', '#1f7a3f', '#e0a526'][i]} />
            <rect x={x} y="190" width="28" height="5" rx="2" fill="#fff" opacity="0.5" />
          </g>
        ))}
        {Array.from({ length: 10 }, (_, i) => (
          <rect key={i} x={290 + i * 9} y="196" width="6" height="18" rx="2" fill={i % 3 ? '#3a2214' : '#d2342a'} />
        ))}
        <rect x="400" y="184" width="44" height="30" fill="#e0a526" />
        <text x="422" y="203" fontSize="5" fontFamily={SIGN_FONT} fill="#7a3519" textAnchor="middle">GARRI</text>
        {/* Mama's calendar + hygiene notice */}
        <rect x="470" y="176" width="40" height="34" fill="#f6f2ea" />
        <rect x="470" y="176" width="40" height="10" fill="#d2342a" />
        <text x="490" y="202" fontSize="4.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">God dey</text>
        <rect x="530" y="180" width="70" height="26" fill="#fffaf0" transform="rotate(3 565 193)" />
        <text x="565" y="191" fontSize="5" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle" transform="rotate(3 565 193)">NO CREDIT TODAY</text>
        <text x="565" y="200" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle" transform="rotate(3 565 193)">come tomorrow o</text>
        {/* roof */}
        <path d="M96 168 L664 168 L680 128 L80 128 Z" fill={`url(#${P}-zinc)`} />
        <path d="M96 168 L664 168 L680 128 L80 128 Z" fill={`url(#${P}-rust)`} />
        <rect x="96" y="166" width="568" height="10" fill="#2d1b4e" opacity="0.35" />
        {/* sign board on roof */}
        <rect x="200" y="96" width="360" height="40" fill="#f2c81a" />
        <rect x="200" y="96" width="360" height="40" fill="none" stroke="#d2342a" strokeWidth="3" />
        <text x="380" y="122" fontSize="20" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle" letterSpacing="1">MAMA OSAS BUKA</text>
        <text x="380" y="132" fontSize="6.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Food is ready • Sweet like home</text>
        <path d="M230 136 v-0 M220 136 V168 M540 136 V168" stroke="#5a3a2a" strokeWidth="3" />
        <path d="M200 132 h360 l0 4 h-360 Z" fill="#2d1b4e" opacity="0.25" />
        {/* posts */}
        {[120, 380, 640].map((x) => <rect key={x} x={x - 5} y="168" width="10" height="182" fill="#6a4228" />)}
      </g>

      {/* Mama Osas behind the counter */}
      <Person x={410} y={332} s={1.8} skin="#4a2c1e" top="#e0a526" wrapper="#d2342a" headwrap="#1f7a3f" pose="work" facing={1} night={night}
        extra={<g><path d="M-7 -36 h14 v20 h-14 Z" fill="#f6f2ea" opacity="0.9" /><path d="M16 -30 L24 -10" stroke="#9a9db0" strokeWidth="2" /><ellipse cx="24" cy="-9" rx="4" ry="2" fill="#9a9db0" /></g>} />
      {/* helper girl */}
      <Person x={612} y={338} s={1.45} skin="#5a3624" top="#7a3fa0" bottom="#2b3350" headwrap="#f6f2ea" pose="stand" facing={-1} night={night} />

      {/* counter */}
      <rect x="150" y={CT} width="460" height="56" fill={`url(#${P}-wood)`} />
      <rect x="146" y={CT - 6} width="468" height="8" fill="#c48a5a" />
      <rect x="146" y={CT + 2} width="468" height="4" fill="#2d1b4e" opacity="0.35" />
      <path d={`M150 ${CT + 22} H610 M150 ${CT + 40} H610`} stroke="#5a2a14" strokeWidth="1.2" opacity="0.5" />
      <text x="380" y={CT + 34} fontSize="9" fontFamily={SIGN_FONT} fill="#f2c81a" textAnchor="middle" opacity="0.85">HOT HOT FOOD</text>
      {/* pots on the counter */}
      <Pot x={190} y={CT - 2} w={56} soup="#e8742a" night={night} label="OWO" />
      <Pot x={262} y={CT - 2} w={60} soup="#1f3a24" night={night} label="BLACK" />
      <Pot x={340} y={CT - 2} w={54} soup="#7a2a14" night={night} label="BANGA" />
      {/* egusi in a bowl */}
      <path d="M364 298 q14 10 28 0 Z" fill="#d9a441" />
      <ellipse cx="378" cy="298" rx="14" ry="3" fill="#e8c86a" />
      {/* starch wrapped in leaves + pounded yam mounds */}
      <ellipse cx="490" cy="296" rx="42" ry="6" fill="#9a9db0" />
      {[[466, 292], [482, 290], [498, 291], [514, 293], [474, 284], [492, 283], [508, 285]].map(([x, y], i) => (
        <g key={i}>
          <ellipse cx={x} cy={y} rx="8" ry="6" fill={i < 4 ? '#f2d26a' : '#f8f4e6'} />
          {i < 4 && <path d={`M${x - 8} ${y} q8 -10 16 0`} fill="#3f8a3a" opacity="0.9" />}
          <ellipse cx={x - 2} cy={y - 2} rx="3" ry="1.6" fill="#fff" opacity="0.5" />
        </g>
      ))}
      {/* cooler of meat */}
      <rect x="546" y="270" width="48" height="26" rx="4" fill="#d2342a" />
      <rect x="544" y="266" width="52" height="7" rx="3" fill="#f6f2ea" />
      <text x="570" y="288" fontSize="5" fontFamily={SIGN_FONT} fill="#fff" textAnchor="middle">MEAT</text>
      <Steam x={186} y={262} night={night} />
      <Steam x={258} y={258} s={1.1} night={night} />
      <Steam x={336} y={264} night={night} />
      <Steam x={488} y={278} s={0.7} night={night} />

      {/* menu chalkboard on easel */}
      <g>
        <path d="M30 412 L56 180 M132 412 L106 180 M81 180 L90 412" stroke="#6a4228" strokeWidth="4" />
        <rect x="14" y="196" width="134" height="140" rx="3" fill="#7a4a2a" />
        <rect x="20" y="202" width="122" height="128" fill="#1f2a26" />
        <text x="81" y="218" fontSize="9" fontFamily={SIGN_FONT} fill="#f2c81a" textAnchor="middle">TODAY MENU</text>
        {menu.map(([a, b], i) => (
          <g key={a}>
            <text x="25" y={236 + i * 18} fontSize="6.4" fontFamily={HAND_FONT} fill="#f6f2ea">{a}</text>
            <text x="137" y={244 + i * 18} fontSize="6.4" fontFamily={HAND_FONT} fill="#ffcf73" textAnchor="end">{b}</text>
          </g>
        ))}
        <text x="81" y="326" fontSize="5" fontFamily={HAND_FONT} fill="#7fc4ff" textAnchor="middle">Pure water ₦50 • Malt dey</text>
      </g>

      {/* firewood stove at the side */}
      <g>
        <ellipse cx="712" cy="384" rx="62" ry="8" fill="#2d1b4e" opacity="0.4" />
        <path d="M672 384 l-8 -14 h16 Z M752 384 l8 -14 h-16 Z M712 388 l-8 -14 h16 Z" fill="#6a5a5a" />
        <path d="M664 382 L700 372 M760 384 L722 372 M690 390 L712 376" stroke="#6a3a1e" strokeWidth="6" strokeLinecap="round" />
        <path d="M694 374 q6 -16 12 -4 q4 -14 10 0 q6 -12 8 2 Z" fill="#ff8a2a" />
        <path d="M700 372 q4 -8 8 0 q4 -8 6 0 Z" fill="#ffe08a" />
        <path d="M676 368 Q672 330 712 326 Q752 330 748 368 Z" fill="#2a2834" />
        <ellipse cx="712" cy="327" rx="36" ry="6" fill="#3a3846" />
        <path d="M680 352 Q712 360 744 352" stroke="#4a4858" strokeWidth="2" fill="none" />
        <Steam x={706} y={318} s={1.4} night={night} />
      </g>

      {/* benches + customers eating with their hands */}
      <g>
        <rect x="180" y="386" width="240" height="10" fill="#8a5232" />
        <rect x="180" y="386" width="240" height="3" fill="#c48a5a" />
        <path d="M190 396 V430 M410 396 V430" stroke="#5a3418" strokeWidth="6" />
        <rect x="160" y="420" width="290" height="8" fill="#7a4a2a" />
        <path d="M170 428 V448 M440 428 V448" stroke="#5a3418" strokeWidth="5" />
        {/* plates */}
        <ellipse cx="236" cy="386" rx="20" ry="5" fill="#f6f2ea" />
        <ellipse cx="236" cy="384" rx="12" ry="5" fill="#f2d26a" />
        <ellipse cx="250" cy="385" rx="8" ry="3" fill="#e8742a" />
        <ellipse cx="350" cy="386" rx="20" ry="5" fill="#f6f2ea" />
        <ellipse cx="344" cy="384" rx="11" ry="5" fill="#f8f4e6" />
        <ellipse cx="360" cy="385" rx="8" ry="3" fill="#1f3a24" />
        <rect x="290" y="372" width="10" height="16" rx="2" fill="#5a2a14" />
        <rect x="390" y="374" width="12" height="12" rx="2" fill="#7fc4ff" opacity="0.8" />
      </g>
      <Person x={226} y={430} s={1.45} skin="#4a2c1e" top="#1f7a3f" bottom="#2b3350" pose="sit" facing={1} night={night} />
      <Person x={376} y={430} s={1.45} skin="#5a3624" top="#f2f0ea" bottom="#5a4a3a" pose="sit" facing={-1} night={night}
        extra={<path d="M-5 -55 h10 v-3 h-10 Z" fill="#d2342a" />} />
      {/* hand-washing bowl */}
      <g transform="translate(520 430)">
        <ellipse cx="2" cy="0" rx="22" ry="4" fill="#2d1b4e" opacity="0.3" />
        <path d="M-18 -10 Q-16 0 0 0 Q16 0 18 -10 Z" fill="#2f6fd0" />
        <ellipse cx="0" cy="-10" rx="18" ry="4" fill="#7ec3ea" />
      </g>
      {/* okada passing */}
      <g transform="translate(640 440)">
        <ellipse cx="10" cy="0" rx="48" ry="4" fill="#2d1b4e" opacity="0.35" />
        <circle cx="-22" cy="-12" r="12" fill="none" stroke="#1f1d2a" strokeWidth="4" />
        <circle cx="34" cy="-12" r="12" fill="none" stroke="#1f1d2a" strokeWidth="4" />
        <path d="M-22 -12 L-4 -30 L22 -30 L34 -12 M-4 -30 L-10 -42 h-8" stroke="#d2342a" strokeWidth="4" fill="none" strokeLinejoin="round" />
        <rect x="-2" y="-36" width="28" height="8" rx="3" fill="#1f1d2a" />
      </g>
      <Person x={652} y={406} s={1.3} skin="#4a2c1e" top="#e0a526" bottom="#2b3350" pose="sit" facing={1} night={night} />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[120, 200]} />
          <Bulb p={P} x={260} y={190} night={night} wire={22} />
          <Bulb p={P} x={500} y={190} night={night} wire={22} />
          <Glow p={P} cx={380} cy={280} r={260} ry={110} o={0.45} />
          {/* lit sign */}
          <Glow p={P} cx={380} cy={116} r={200} ry={40} o={0.4} />
          {/* stove fire */}
          <Glow p={P} cx={712} cy={374} r={90} ry={60} kind="gf" o={1} />
          <path d="M694 374 q6 -16 12 -4 q4 -14 10 0 q6 -12 8 2 Z" fill="#ffb347" />
          {/* lantern on the bench table */}
          <rect x="296" y="370" width="8" height="12" rx="2" fill="#ffe9a8" />
          <Glow p={P} cx={300} cy={378} r={100} ry={60} o={0.8} />
          {/* okada headlight */}
          <Glow p={P} cx={690} cy={404} r={40} kind="gc" o={0.6} />
          {/* menu board candle-light */}
          <Glow p={P} cx={81} cy={260} r={80} o={0.35} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
