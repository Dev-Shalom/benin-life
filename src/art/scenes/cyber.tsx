// Ugbowo Wi-Fi Joint — cyber café by UNIBEN — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Generator, PlasticChair, Treeline, Haze, SIGN_FONT, HAND_FONT } from './_sharedB';

const P = 'cyber';
const FL = 344; // shop floor / pavement line
const TT = 304; // browsing table top

/** Desktop on the table, screen facing the viewer. (x,y) = foot centre on the table top. */
function Monitor({ x, y, crt, screen, night }: { x: number; y: number; crt: boolean; screen: string; night: boolean }) {
  const w = crt ? 46 : 52;
  const h = crt ? 38 : 32;
  const top = y - h - 8;
  const lit = night ? '#eaf6ff' : '#f6f2ea';
  return (
    <g>
      <ellipse cx={x + 3} cy={y} rx={w * 0.55} ry="2.4" fill="#2d1b4e" opacity="0.35" />
      {crt ? (
        <>
          <path d={`M${x - w / 2 + 6} ${top + 4} L${x + w / 2 + 8} ${top + 8} L${x + w / 2 + 6} ${y - 4} L${x - w / 2 + 8} ${y - 4} Z`} fill="#a89c84" />
          <rect x={x - w / 2} y={top} width={w} height={h + 4} rx="3" fill={`url(#${P}-beige)`} />
          <rect x={x - 8} y={y - 5} width="16" height="5" fill="#b8ac92" />
        </>
      ) : (
        <>
          <rect x={x - 2} y={top + h} width="4" height={y - top - h - 2} fill="#2a2834" />
          <path d={`M${x - 10} ${y} h20 l-3 -3 h-14 Z`} fill="#2a2834" />
          <rect x={x - w / 2} y={top} width={w} height={h + 2} rx="2" fill="#1e1d2a" />
        </>
      )}
      <rect x={x - w / 2 + 4} y={top + 3} width={w - 8} height={h - 4} rx={crt ? 4 : 1} fill={`url(#${P}-${screen})`} />
      {/* browser chrome: tab bar + address bar + text lines */}
      <rect x={x - w / 2 + 4} y={top + 3} width={w - 8} height="4" fill={lit} opacity="0.85" />
      <rect x={x - w / 2 + 7} y={top + 4} width={w * 0.45} height="2" rx="1" fill="#9aa6c0" />
      <path d={`M${x - w / 2 + 8} ${top + 13} h${w * 0.5} M${x - w / 2 + 8} ${top + 18} h${w * 0.35} M${x - w / 2 + 8} ${top + 23} h${w * 0.45}`} stroke={lit} strokeWidth="1.6" opacity="0.7" />
      <path d={`M${x - w / 2 + 6} ${top + 5} L${x - w / 2 + 16} ${top + h - 4}`} stroke="#fff" strokeWidth="4" opacity={night ? 0.08 : 0.18} />
      {crt && <circle cx={x + w / 2 - 6} cy={top + h + 1.5} r="1.2" fill="#3bd36a" />}
      {/* keyboard */}
      <path d={`M${x - 20} ${y + 6} L${x + 18} ${y + 6} L${x + 14} ${y + 1} L${x - 16} ${y + 1} Z`} fill="#3a3846" />
      <path d={`M${x - 15} ${y + 3.5} h28`} stroke="#8d8fa6" strokeWidth="1.2" strokeDasharray="2 1" />
      {night && <Glow p={P} cx={x} cy={top + h / 2} r={w * 1.3} ry={h * 1.4} kind="gc" o={0.55} />}
    </g>
  );
}

export default function CyberScene({ night }: { night: boolean }) {
  const skyHole = `M0 0 H800 V60 H0 Z M70 140 H610 V${FL} H70 Z M640 140 H736 V${FL} H640 Z`;
  const tube = night ? '#ffffff' : '#f6f2ea';
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Ugbowo Wi-Fi Joint cyber cafe">
      <defs>
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#c8e4ea' : '#d8eee6'} />
          <stop offset="0.55" stopColor={night ? '#a8ccd8' : '#bfe0d6'} />
          <stop offset="1" stopColor={night ? '#88aac0' : '#9cc6bc'} />
        </linearGradient>
        <linearGradient id={`${P}-front`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#f4e6c8" />
          <stop offset="0.6" stopColor="#e6d0aa" />
          <stop offset="1" stopColor="#d2b48e" />
        </linearGradient>
        <linearGradient id={`${P}-sign`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2a9a52" />
          <stop offset="0.5" stopColor="#1f7a3f" />
          <stop offset="1" stopColor="#155a2e" />
        </linearGradient>
        <linearGradient id={`${P}-beige`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#f2ead6" />
          <stop offset="0.5" stopColor="#ddd2b8" />
          <stop offset="1" stopColor="#b8ac92" />
        </linearGradient>
        <linearGradient id={`${P}-wood`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c08a52" />
          <stop offset="0.2" stopColor="#a8703e" />
          <stop offset="1" stopColor="#6a3a1e" />
        </linearGradient>
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.5" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        {[['s1', '#3a6fd8', '#8fc0ff'], ['s2', '#1f7a3f', '#9be0a8'], ['s3', '#d9a441', '#fff0b8'], ['s4', '#5a4ac8', '#c0b8ff']].map(([id, a, b]) => (
          <linearGradient key={id} id={`${P}-${id}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={b} />
            <stop offset="0.45" stopColor={a} />
            <stop offset="1" stopColor="#1a2450" />
          </linearGradient>
        ))}
        <linearGradient id={`${P}-spill`} gradientUnits="userSpaceOnUse" x1="0" y1={FL} x2="0" y2="450">
          <stop offset="0" stopColor="#9fd0ff" stopOpacity="0.28" />
          <stop offset="0.5" stopColor="#7fb0ff" stopOpacity="0.1" />
          <stop offset="1" stopColor="#7fb0ff" stopOpacity="0" />
        </linearGradient>
        <pattern id={`${P}-tiles`} patternUnits="userSpaceOnUse" width="24" height="10">
          <path d="M0 0 H24 M0 0 V10" stroke="#fff" strokeWidth="0.8" opacity="0.35" />
        </pattern>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={700} sunY={38} moonX={700} moonY={34} clouds={false} />
      <Treeline y={64} fill={night ? '#1a2644' : '#6f9e7c'} seed={83} amp={16} step={38} base={130} />
      <Haze p={P} y={28} h={60} night={night} o={0.4} />

      {/* building front */}
      <rect x="40" y="60" width="720" height={FL - 60} fill={`url(#${P}-front)`} />
      {night && <rect x="40" y="60" width="720" height={FL - 60} fill="#4a3a6a" opacity="0.45" />}
      <rect x="40" y="60" width="720" height="8" fill="#b9a088" />
      <rect x="40" y="128" width="720" height="10" fill="#c9b08e" />

      {/* signboard */}
      <g>
        <rect x="80" y="70" width="640" height="56" fill={`url(#${P}-sign)`} />
        <rect x="84" y="74" width="632" height="48" fill="none" stroke="#d9a441" strokeWidth="2.5" />
        {/* wifi badge */}
        <g transform="translate(124 104)">
          <circle r="20" fill="#f6f2ea" />
          <path d="M-12 -2 Q0 -14 12 -2 M-8 3 Q0 -6 8 3 M-4 8 Q0 4 4 8" stroke="#d2342a" strokeWidth="3" fill="none" strokeLinecap="round" />
          <circle cy="12" r="2.4" fill="#d2342a" />
        </g>
        <text x="410" y="102" fontSize="27" fontFamily={SIGN_FONT} fill="#f6f2ea" textAnchor="middle" letterSpacing="2">UGBOWO WI-FI JOINT</text>
        <text x="410" y="116" fontSize="8" fontFamily={SIGN_FONT} fill="#f2c81a" textAnchor="middle" letterSpacing="1.5">BROWSING • PRINTING • TYPING • JAMB/WAEC CHECK</text>
        <g transform="translate(680 98) rotate(8)">
          <rect x="-32" y="-16" width="64" height="32" rx="4" fill="#d2342a" />
          <rect x="-29" y="-13" width="58" height="26" rx="3" fill="none" stroke="#fffaf0" strokeWidth="0.8" opacity="0.6" />
          <text y="-3" fontSize="7.4" fontFamily={HAND_FONT} fill="#fffaf0" textAnchor="middle">Network sweet</text>
          <text y="8" fontSize="7.4" fontFamily={HAND_FONT} fill="#fffaf0" textAnchor="middle">like agege bread!</text>
        </g>
        <rect x="80" y="126" width="640" height="4" fill="#2d1b4e" opacity="0.35" />
      </g>

      {/* ===== browsing hall ===== */}
      <rect x="70" y="140" width="540" height={FL - 140} fill={`url(#${P}-wall)`} />
      <rect x="70" y={TT - 30} width="540" height={FL - TT + 30} fill="#8fb8b0" opacity="0.55" />
      <rect x="70" y={FL - 22} width="540" height="22" fill="#c8bca8" />
      <rect x="70" y={FL - 22} width="540" height="22" fill={`url(#${P}-tiles)`} />
      <rect x="70" y="140" width="540" height="10" fill="#3b2a5e" opacity="0.18" />
      {/* notices on the back wall */}
      <g transform="translate(92 158) rotate(-2)">
        <rect width="82" height="40" fill="#fffaf0" />
        <rect width="82" height="9" fill="#d2342a" />
        <text x="41" y="7" fontSize="5.6" fontFamily={SIGN_FONT} fill="#fffaf0" textAnchor="middle">PRICE LIST</text>
        <text x="6" y="18" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440">Browsing 1hr ....₦300</text>
        <text x="6" y="26" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440">Print (B/W) .......₦50</text>
        <text x="6" y="34" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440">Typing per page ₦150</text>
      </g>
      <g transform="translate(196 156)">
        <rect width="96" height="34" fill="#f2c81a" />
        <text x="48" y="14" fontSize="8.4" fontFamily={SIGN_FONT} fill="#1a1420" textAnchor="middle">PAY BEFORE</text>
        <text x="48" y="27" fontSize="8.4" fontFamily={SIGN_FONT} fill="#1a1420" textAnchor="middle">YOU BROWSE</text>
      </g>
      <g transform="translate(316 160) rotate(2)">
        <rect width="74" height="36" fill="#fffaf0" />
        <text x="37" y="11" fontSize="5.6" fontFamily={SIGN_FONT} fill="#1f7a3f" textAnchor="middle">JAMB • WAEC • NECO</text>
        <text x="37" y="21" fontSize="5.4" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">RESULT CHECKING</text>
        <text x="37" y="30" fontSize="5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">bring your scratch card</text>
      </g>
      {/* wall clock */}
      <g transform="translate(420 176)">
        <circle r="11" fill="#fffaf0" stroke="#3a3846" strokeWidth="2" />
        <path d="M0 0 V-7 M0 0 L5 3" stroke="#2a2440" strokeWidth="1.4" strokeLinecap="round" />
      </g>
      {/* Wi-Fi router with blinking lights */}
      <g transform="translate(466 192)">
        <path d="M-12 -6 L-15 -26 M12 -6 L15 -26" stroke="#2a2834" strokeWidth="2" strokeLinecap="round" />
        <rect x="-18" y="-7" width="36" height="12" rx="3" fill="#f2f0ea" />
        <rect x="-18" y="0" width="36" height="5" rx="2" fill="#9b97b0" opacity="0.5" />
        {[-11, -5, 1, 7].map((cx, i) => (
          <circle key={cx} cx={cx} cy="-1" r="1.4" fill={i === 3 ? '#ffb347' : '#3bd36a'} />
        ))}
        <path d="M-4 5 V14 Q30 24 66 94" stroke="#2a2834" strokeWidth="1" fill="none" />
        {night && <Glow p={P} cx={-2} cy={-1} r={16} ry={8} kind="gg" o={0.9} />}
      </g>
      {/* ceiling fan */}
      <g transform="translate(300 140)">
        <path d="M0 0 V14" stroke="#5a5a6a" strokeWidth="2" />
        <ellipse cx="0" cy="16" rx="6" ry="3" fill="#7d8090" />
        <ellipse cx="-22" cy="17" rx="20" ry="2.6" fill="#a8abbc" />
        <ellipse cx="22" cy="16" rx="20" ry="2.2" fill="#9a9db0" />
        <ellipse cx="0" cy="18" rx="5" ry="2" fill="#5a5a6a" />
      </g>
      {/* fluorescent tubes */}
      <rect x="140" y="142" width="80" height="4" rx="2" fill={tube} />
      <rect x="400" y="142" width="80" height="4" rx="2" fill={tube} />

      {/* long browsing table */}
      <rect x="84" y={TT} width="420" height="6" fill={`url(#${P}-wood)`} />
      <rect x="84" y={TT} width="420" height="1.5" fill="#e0b080" />
      <rect x="84" y={TT + 6} width="420" height="10" fill="#6a3a1e" opacity="0.6" />
      <path d={`M92 ${TT + 6} V${FL} M496 ${TT + 6} V${FL} M290 ${TT + 6} V${FL}`} stroke="#5a3418" strokeWidth="4" />
      {/* CPU towers under the table */}
      {[176, 276, 376, 476].map((x) => (
        <g key={x}>
          <rect x={x - 8} y={FL - 30} width="15" height="28" rx="1.5" fill="#d8d0bc" />
          <rect x={x - 1} y={FL - 30} width="8" height="28" fill="#3b2a5e" opacity="0.2" />
          <circle cx={x - 3} cy={FL - 24} r="1.2" fill="#3bd36a" />
        </g>
      ))}
      {/* monitors: CRT/flat mix */}
      <Monitor x={164} y={TT} crt screen="s1" night={night} />
      <Monitor x={264} y={TT} crt={false} screen="s2" night={night} />
      <Monitor x={364} y={TT} crt screen="s3" night={night} />
      <Monitor x={464} y={TT} crt={false} screen="s4" night={night} />
      {/* chairs + students */}
      <PlasticChair x={124} y={FL} s={1.3} color="#f6f2ea" shade="#9b97b0" />
      <Person x={128} y={FL} s={1.5} skin="#5a3624" top="#2f6fd0" bottom="#2b3350" pose="sit" facing={1} night={night} />
      <PlasticChair x={224} y={FL} s={1.3} color="#d2342a" shade="#8a2a24" />
      <Person x={228} y={FL} s={1.5} skin="#4a2c1e" top="#e0a526" bottom="#3a4468" pose="sit" facing={1} night={night} />
      <PlasticChair x={324} y={FL} s={1.3} color="#f6f2ea" shade="#9b97b0" />
      <Person x={328} y={FL} s={1.5} skin="#6b4128" top="#f6f2ea" bottom="#2b3350" pose="sit" facing={1} night={night}
        extra={<g><path d="M-6 -45 Q-6 -55 0 -55 Q6 -55 6 -45" stroke="#2a2834" strokeWidth="1.6" fill="none" /><rect x="-7.5" y="-47" width="4" height="6" rx="1.5" fill="#d2342a" /></g>} />
      <PlasticChair x={430} y={FL} s={1.3} color="#2f6fd0" shade="#1d4f8a" />

      {/* attendant counter */}
      <Person x={560} y={FL - 8} s={1.6} skin="#4a2c1e" top="#d2342a" bottom="#2b3350" pose="stand" facing={-1} night={night} />
      <g>
        <rect x="514" y={FL - 52} width="90" height="52" fill={`url(#${P}-wood)`} />
        <rect x="510" y={FL - 56} width="98" height="6" fill="#c08a52" />
        <rect x="574" y={FL - 50} width="30" height="50" fill="#3b2a5e" opacity="0.22" />
        <rect x="522" y={FL - 44} width="44" height="20" fill="#fffaf0" />
        <text x="544" y={FL - 36} fontSize="5" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">NO LIGHT,</text>
        <text x="544" y={FL - 28} fontSize="5" fontFamily={SIGN_FONT} fill="#2a2440" textAnchor="middle">NO BROWSING</text>
        <rect x="530" y={FL - 63} width="22" height="7" fill="#1f7a3f" />
        <rect x="532" y={FL - 63} width="18" height="2" fill="#fffaf0" />
        <rect x="584" y={FL - 62} width="12" height="6" rx="1" fill="#2a2834" />
      </g>

      {/* pillar */}
      <rect x="610" y="134" width="30" height={FL - 134} fill="#e6d2b0" />
      <rect x="628" y="134" width="12" height={FL - 134} fill="#3b2a5e" opacity="0.15" />

      {/* ===== printing / photocopy bay ===== */}
      <rect x="640" y="140" width="96" height={FL - 140} fill={night ? '#e8dcc0' : '#efe2c4'} />
      <rect x="640" y="140" width="96" height="10" fill="#3b2a5e" opacity="0.18" />
      <g transform="translate(648 154)">
        <rect width="80" height="18" fill="#2f6fd0" />
        <text x="40" y="8" fontSize="5.4" fontFamily={SIGN_FONT} fill="#fffaf0" textAnchor="middle">PRINTING • SCANNING</text>
        <text x="40" y="15" fontSize="5.4" fontFamily={SIGN_FONT} fill="#f2c81a" textAnchor="middle">LAMINATION</text>
      </g>
      {/* paper shelf */}
      <rect x="648" y="196" width="80" height="4" fill="#8a5232" />
      {[652, 668, 684, 700].map((x, i) => (
        <g key={x}>
          <rect x={x} y={180 + (i % 2) * 4} width="14" height={16 - (i % 2) * 4} fill="#fffaf0" />
          <path d={`M${x} ${186 + (i % 2) * 4} h14 M${x} ${191 + (i % 2) * 2} h14`} stroke="#c9c3b4" strokeWidth="0.8" />
        </g>
      ))}
      {/* photocopier */}
      <g>
        <ellipse cx="692" cy={FL} rx="40" ry="4" fill="#2d1b4e" opacity="0.35" />
        <rect x="656" y={FL - 64} width="72" height="62" rx="3" fill={`url(#${P}-beige)`} />
        <rect x="704" y={FL - 64} width="24" height="62" fill="#3b2a5e" opacity="0.2" />
        <rect x="652" y={FL - 72} width="80" height="10" rx="2" fill="#5a5a6a" />
        <rect x="660" y={FL - 76} width="40" height="4" fill="#fffaf0" />
        <rect x="662" y={FL - 50} width="34" height="6" fill="#2a2834" />
        <rect x="708" y={FL - 56} width="14" height="6" rx="1" fill="#3bd36a" />
        <path d={`M664 ${FL - 34} h56 M664 ${FL - 20} h56`} stroke="#8d8fa6" strokeWidth="1.5" />
        <path d={`M640 ${FL - 48} L656 ${FL - 52} L656 ${FL - 44} L642 ${FL - 41} Z`} fill="#fffaf0" />
      </g>

      {/* pavement + ground */}
      <rect x="40" y={FL} width="720" height="12" fill="#b9a99a" />
      <rect x="40" y={FL + 10} width="720" height="4" fill="#2d1b4e" opacity="0.3" />
      <rect x="-10" y={FL + 14} width="820" height={460 - FL} fill={`url(#${P}-ground)`} />
      <rect x="-10" y="60" width="50" height="300" fill={night ? '#3a3a62' : '#d8b8a0'} />
      <rect x="760" y="60" width="50" height="300" fill={night ? '#3a3a62' : '#c8c0d8'} />
      <path d="M-10 412 Q400 398 810 416" stroke="#7a3519" strokeWidth="8" opacity="0.2" fill="none" />
      <path d="M120 396 l6 -2 M260 430 l5 1 M480 420 l6 -1 M560 440 l4 -2" stroke="#8a3a1e" strokeWidth="2" opacity="0.5" strokeLinecap="round" />

      {/* weeds along the pavement kerb + bush by the wall */}
      {[64, 230, 372, 604, 748].map((x, i) => (
        <path key={x} d={`M${x} ${FL + 15} q-3 -8 -7 -10 M${x} ${FL + 15} q0 -10 2 -13 M${x} ${FL + 15} q4 -7 9 -8`} stroke={i % 2 ? '#2f6b34' : '#4f9a3f'} strokeWidth="2" fill="none" strokeLinecap="round" />
      ))}
      <g>
        <ellipse cx="770" cy="358" rx="34" ry="5" fill="#2d1b4e" opacity="0.3" />
        <path d="M740 358 Q736 320 756 312 Q760 290 780 296 Q800 290 806 312 L806 358 Z" fill={night ? '#1d2f45' : '#2f6b34'} />
        <path d="M750 340 Q752 318 766 314 Q770 300 782 304" stroke={night ? '#26364a' : '#5d9a45'} strokeWidth="5" fill="none" strokeLinecap="round" />
      </g>

      {/* power pole with tangled wires */}
      <g>
        <rect x="18" y="10" width="9" height="430" fill={night ? '#3a3046' : '#6b4a33'} />
        <rect x="24" y="10" width="3" height="430" fill="#2d1b4e" opacity="0.3" />
        <rect x="2" y="30" width="42" height="5" fill={night ? '#3a3046' : '#5a3a26'} />
        {[6, 22, 38].map((x) => <circle key={x} cx={x} cy="28" r="2.4" fill="#d8d4c8" />)}
        <path d="M6 28 Q300 70 810 36 M22 28 Q250 58 810 52 M38 28 Q200 90 400 64 Q520 54 810 70 M24 40 Q60 80 52 120 Q48 140 40 142" stroke="#1a1824" strokeWidth="1.2" fill="none" />
        <path d="M30 44 q14 6 8 16 q-10 4 -6 -6 q8 -8 12 4" stroke="#1a1824" strokeWidth="1" fill="none" />
      </g>

      {/* bench with student waiting + student with backpack */}
      <g>
        <rect x="80" y="398" width="130" height="8" fill="#8a5232" />
        <rect x="80" y="398" width="130" height="2" fill="#c08a52" />
        <path d="M90 406 V428 M200 406 V428" stroke="#5a3418" strokeWidth="5" />
      </g>
      <Person x={150} y={428} s={1.4} skin="#5a3624" top="#7a3fa0" bottom="#2b3350" pose="sit" facing={1} night={night}
        extra={<rect x="13" y="-34" width="4" height="7" rx="1" fill="#1a1a26" />} />
      <Person x={300} y={440} s={1.75} skin="#4a2c1e" top="#1f7a3f" bottom="#3a4468" pose="walk" facing={1} night={night}
        extra={<g><rect x="-14" y="-41" width="8" height="18" rx="3" fill="#d2342a" /><rect x="-14" y="-41" width="3" height="18" rx="1.5" fill="#2d1b4e" opacity="0.3" /><path d="M-7 -41 L-5 -40 M-7 -26 L-5 -27" stroke="#8a2a24" strokeWidth="1.5" /><rect x="8" y="-30" width="7" height="9" fill="#fffaf0" transform="rotate(10 11 -25)" /></g>} />

      {/* generator with cable into the shop */}
      <Generator p={P} x={690} y={426} s={1.6} night={night} color="#d9a441" />
      <path d={`M654 410 Q590 420 560 396 Q530 374 520 ${FL + 2}`} stroke="#1a1824" strokeWidth="2" fill="none" />
      <g transform="rotate(-5 470 405)">
        <rect x="430" y="388" width="80" height="32" fill="#fffaf0" />
        <rect x="430" y="388" width="80" height="32" fill="none" stroke="#d2342a" strokeWidth="1.5" />
        <text x="470" y="400" fontSize="6" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle">NEPA don take light?</text>
        <text x="470" y="412" fontSize="6" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Our gen dey ginger!</text>
      </g>
      <path d="M470 420 V440" stroke="#5a3418" strokeWidth="3" />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} bottom={0.68} />
          {/* interiors stay lit — cool fluorescent + screen cast */}
          <rect x="70" y="140" width="540" height={FL - 140} fill="#8fb0e8" opacity="0.4" style={{ mixBlendMode: 'multiply' }} />
          <rect x="640" y="140" width="96" height={FL - 140} fill="#d8c8f0" opacity="0.25" style={{ mixBlendMode: 'multiply' }} />
          <Glow p={P} cx={180} cy={146} r={110} ry={28} kind="gc" o={0.5} />
          <Glow p={P} cx={440} cy={146} r={110} ry={28} kind="gc" o={0.5} />
          <rect x="140" y="142" width="80" height="4" rx="2" fill="#fff" />
          <rect x="400" y="142" width="80" height="4" rx="2" fill="#fff" />
          <Glow p={P} cx={300} cy={280} r={240} ry={70} kind="gc" o={0.3} />
          {[164, 264, 364, 464].map((x) => <Glow key={x} p={P} cx={x} cy={276} r={44} ry={30} kind="gc" o={0.55} />)}
          {/* lit wifi badge + tagline sticker */}
          <circle cx="124" cy="104" r="20" fill="#fffaf0" />
          <path d="M112 102 Q124 90 136 102 M116 107 Q124 98 132 107 M120 112 Q124 108 128 112" stroke="#ff4a3a" strokeWidth="3" fill="none" strokeLinecap="round" />
          <circle cx="124" cy="116" r="2.4" fill="#ff4a3a" />
          <Glow p={P} cx={124} cy={104} r={34} kind="gw" o={0.5} />
          <g transform="translate(680 98) rotate(8)">
            <rect x="-32" y="-16" width="64" height="32" rx="4" fill="#e8402e" />
            <text y="-3" fontSize="7.4" fontFamily={HAND_FONT} fill="#fffaf0" textAnchor="middle">Network sweet</text>
            <text y="8" fontSize="7.4" fontFamily={HAND_FONT} fill="#fffaf0" textAnchor="middle">like agege bread!</text>
          </g>
          {/* screen light spill onto pavement */}
          <path d={`M70 ${FL} L610 ${FL} L700 450 L-20 450 Z`} fill={`url(#${P}-spill)`} style={{ mixBlendMode: 'screen' }} />
          {/* backlit sign */}
          <Glow p={P} cx={410} cy={98} r={340} ry={52} kind="gg" o={0.28} />
          <text x="410" y="102" fontSize="27" fontFamily={SIGN_FONT} fill="#ffffff" textAnchor="middle" letterSpacing="2">UGBOWO WI-FI JOINT</text>
          <text x="410" y="116" fontSize="8" fontFamily={SIGN_FONT} fill="#ffe36a" textAnchor="middle" letterSpacing="1.5">BROWSING • PRINTING • TYPING • JAMB/WAEC CHECK</text>
          {/* router blink */}
          <Glow p={P} cx={466} cy={191} r={22} ry={10} kind="gg" o={0.8} />
          {/* neon OPEN */}
          <rect x="92" y="212" width="54" height="22" rx="4" fill="#1a1028" />
          <text x="119" y="228" fontSize="12" fontFamily={SIGN_FONT} fill="#4fe8ff" textAnchor="middle">OPEN</text>
          <Glow p={P} cx={119} cy={223} r={44} ry={24} kind="gc" o={0.7} />
          {/* phone glow + generator work light */}
          <Glow p={P} cx={170} cy={392} r={16} kind="gc" o={0.7} />
          <Glow p={P} cx={690} cy={410} r={60} ry={24} kind="gw" o={0.35} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
