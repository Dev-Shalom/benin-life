import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Palm, LampPost, Txt, PAL, rng } from './_sharedA';

const P = 'police';
const NAVY = '#1f2a5a';

/** Patrol pickup facing left, navy with white POLICE lettering and a light bar. */
function PatrolVan({ x, y, s = 1, night }: { x: number; y: number; s?: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="66" cy="1" rx="72" ry="5" fill={PAL.shadow} opacity="0.45" />
      {/* bed with cage */}
      <path d="M70 -34 L134 -34 L134 -8 L70 -8Z" fill="#1a2350" />
      {[78, 92, 106, 120].map((bx) => <rect key={bx} x={bx} y="-52" width="2" height="18" fill="#4a5070" />)}
      <rect x="74" y="-54" width="58" height="3" fill="#4a5070" />
      {/* cab */}
      <path d="M4 -12 Q2 -26 12 -30 L24 -32 L34 -52 Q36 -56 42 -56 L68 -56 Q72 -56 72 -52 L72 -8 L8 -8 Q4 -8 4 -12Z" fill={NAVY} />
      <path d="M36 -50 L50 -50 L50 -33 L27 -33Z" fill="#33405a" />
      <path d="M53 -50 L68 -50 L68 -33 L53 -33Z" fill="#33405a" />
      <path d="M38 -49 L44 -49 L34 -35 L30 -35Z" fill="#d9ecff" opacity="0.35" />
      <rect x="4" y="-22" width="130" height="5" fill="#f4f4f6" />
      <Txt x={96} y={-23} size={10} fill="#f4f4f6" family="Arial Black, Arial, sans-serif">POLICE</Txt>
      <path d="M4 -12 L134 -12 L134 -8 L8 -8 Q4 -8 4 -12Z" fill="#0f1430" opacity="0.6" />
      <path d="M12 -30 L68 -30" stroke="#8a96c8" strokeWidth="1" opacity="0.6" />
      {/* light bar */}
      <rect x="38" y="-61" width="13" height="5" rx="1.5" fill={night ? '#ff5a5a' : '#c4262a'} />
      <rect x="51" y="-61" width="13" height="5" rx="1.5" fill={night ? '#6aa0ff' : '#2a5aa8'} />
      <rect x="2" y="-20" width="5" height="4" rx="1" fill="#fff4cf" />
      <rect x="131" y="-20" width="4" height="5" fill="#e2453b" />
      {[24, 112].map((cx) => (
        <g key={cx}>
          <circle cx={cx} cy={-8} r="9" fill="#1e1a26" />
          <circle cx={cx} cy={-8} r="4" fill="#a2a2ae" />
        </g>
      ))}
    </g>
  );
}

function Badge({ x, y, r }: { x: number; y: number; r: number }) {
  const pts = Array.from({ length: 10 }, (_, i) => {
    const a = (i * Math.PI) / 5 - Math.PI / 2;
    const rr = i % 2 ? r * 0.45 : r;
    return `${(x + Math.cos(a) * rr).toFixed(1)},${(y + Math.sin(a) * rr).toFixed(1)}`;
  }).join(' ');
  return (
    <g>
      <circle cx={x} cy={y} r={r * 1.25} fill="#1f7a3f" />
      <circle cx={x} cy={y} r={r * 1.1} fill="#f4f4f6" />
      <polygon points={pts} fill={PAL.gold} stroke="#8a5a1a" strokeWidth="0.6" />
    </g>
  );
}

export default function PoliceScene({ night }: { night: boolean }) {
  const r = rng(91);
  const wins = Array.from({ length: 2 }, (_, f) => Array.from({ length: 9 }, (_, c) => ({ x: 236 + c * 40, y: 132 + f * 62, lit: r() }))).flat();
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Police Command headquarters">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ffffff" />
          <stop offset="0.5" stopColor="#eef0f6" />
          <stop offset="1" stopColor="#c6cbe0" />
        </linearGradient>
        <linearGradient id={`${P}-roof`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#4a6ab8" />
          <stop offset="1" stopColor="#24387a" />
        </linearGradient>
        <linearGradient id={`${P}-tar`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#77737f" />
          <stop offset="0.5" stopColor="#5c5868" />
          <stop offset="1" stopColor="#3e3a52" />
        </linearGradient>
        <linearGradient id={`${P}-earth`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d48a5a" />
          <stop offset="1" stopColor="#a3502a" />
        </linearGradient>
      </defs>

      <Sky p={P} night={night} sun={[110, 70]} moon={[110, 64]} clouds={[[420, 50, 0.8], [700, 90, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        <g opacity="0.85">
          <Tree x={60} y={262} s={1.1} dark="#3d6e4e" mid="#4f8a5a" light="#7fb06a" />
          <Tree x={720} y={262} s={1.2} dark="#3d6e4e" mid="#4f8a5a" light="#7fb06a" />
        </g>
        <Haze p={P} y={150} h={120} o={0.8} />

        {/* HQ block */}
        <ellipse cx="410" cy="262" rx="230" ry="8" fill={PAL.shadow} opacity="0.3" />
        <rect x="216" y="112" width="384" height="150" fill="url(#police-wall)" />
        <path d="M200 114 L410 84 L616 114Z" fill="url(#police-roof)" />
        <rect x="200" y="112" width="416" height="6" fill="#1a2a60" />
        <rect x="216" y="172" width="384" height="8" fill="#2a5aa8" />
        {wins.map((w, i) => (
          <g key={i}>
            <rect x={w.x} y={w.y} width="26" height="30" fill="#3a4a72" />
            {[0, 1, 2, 3, 4].map((l) => <rect key={l} x={w.x} y={w.y + 3 + l * 6} width="26" height="2" fill="#9aa6c8" />)}
            <rect x={w.x - 2} y={w.y + 30} width="30" height="3" fill="#2a5aa8" />
          </g>
        ))}
        {/* portico */}
        <rect x="350" y="150" width="120" height="112" fill="#e4e8f2" />
        <path d="M340 152 L410 126 L480 152Z" fill="#2a5aa8" />
        <path d="M352 150 L410 132 L468 150Z" fill="#f4f4f8" />
        <Badge x={410} y={144} r={6} />
        {[358, 386, 426, 454].map((x) => (
          <g key={x}>
            <rect x={x} y="156" width="10" height="106" fill="#ffffff" />
            <rect x={x + 6} y="156" width="4" height="106" fill="#2d1b4e" opacity="0.15" />
          </g>
        ))}
        <rect x="388" y="214" width="44" height="48" fill="#2a3e66" />
        <rect x="380" y="198" width="60" height="12" fill={NAVY} />
        <Txt x={410} y={207} size={7} fill="#fff" spacing={1}>ENQUIRIES</Txt>
        <rect x="216" y="112" width="384" height="150" fill="#2d1b4e" opacity="0.05" />
        <rect x="580" y="112" width="20" height="150" fill="#2d1b4e" opacity="0.15" />

        <Palm x={604} y={262} s={0.85} lean={0.4} />
        <Palm x={186} y={256} s={0.7} lean={-0.5} />
        {/* compound wall: blue + white bands */}
        <rect x="0" y="250" width="800" height="44" fill="#f2f3f8" />
        {Array.from({ length: 20 }, (_, i) => (
          <rect key={i} x={i * 40} y="250" width="20" height="44" fill="#2a5aa8" />
        ))}
        <rect x="0" y="246" width="800" height="5" fill="#d9dce8" />
        <path d="M0 246 L800 246" stroke="#5a5a6a" strokeWidth="1" strokeDasharray="2 3" />
        {/* gate opening */}
        <rect x="300" y="246" width="220" height="48" fill="#6a6878" />
        <rect x="292" y="232" width="16" height="64" fill="#e4e8f2" />
        <rect x="512" y="232" width="16" height="64" fill="#e4e8f2" />
        <rect x="292" y="228" width="16" height="6" fill="#2a5aa8" />
        <rect x="512" y="228" width="16" height="6" fill="#2a5aa8" />

        {/* flagpole */}
        <rect x="644" y="96" width="4" height="200" fill="#c9cbd6" />
        <circle cx="646" cy="95" r="3.5" fill={PAL.gold} />
        <path d="M648 100 Q668 96 688 102 L688 132 Q668 126 648 130Z" fill="#f4f4f6" />
        <path d="M648 100 Q654 99 661 99 L661 130 Q654 129 648 130Z" fill="#1f8a45" />
        <path d="M675 100 Q682 101 688 102 L688 132 Q682 130 675 128Z" fill="#1f8a45" />
        <rect x="636" y="292" width="20" height="6" fill="#d9dce8" />

        {/* signboard */}
        <rect x="80" y="196" width="4" height="70" fill="#5a5a6a" />
        <rect x="176" y="196" width="4" height="70" fill="#5a5a6a" />
        <rect x="60" y="176" width="140" height="58" fill={NAVY} />
        <rect x="64" y="180" width="132" height="50" fill="none" stroke="#f4f4f6" strokeWidth="1.5" />
        <Badge x={84} y={205} r={9} />
        <Txt x={142} y={198} size={9} fill="#ffffff">POLICE</Txt>
        <Txt x={142} y={211} size={9} fill="#ffffff">COMMAND HQ</Txt>
        <Txt x={142} y={224} size={5.5} fill="#f2c230" family="Arial, sans-serif" weight={700} spacing={0.5}>POLICE IS YOUR FRIEND</Txt>

        {/* ground */}
        <rect x="0" y="294" width="800" height="156" fill="url(#police-earth)" />
        <path d="M300 294 L520 294 L640 450 L180 450Z" fill="url(#police-tar)" />
        <path d="M410 300 L410 320 M410 336 L410 360 M410 380 L410 412" stroke="#f4f1ea" strokeWidth="3" opacity="0.6" />
        {Array.from({ length: 40 }, (_, i) => (
          <circle key={i} cx={(i * 97) % 800} cy={300 + ((i * 53) % 150)} r={1 + (i % 3) * 0.6} fill="#7e3418" opacity="0.35" />
        ))}
        {/* boom barrier */}
        <rect x="530" y="290" width="12" height="30" fill="#3a3a48" />
        <g>
          {Array.from({ length: 10 }, (_, i) => (
            <rect key={i} x={340 + i * 19} y="298" width="19" height="6" fill={i % 2 ? '#f4f4f6' : '#d2342a'} />
          ))}
        </g>
        {/* sandbags */}
        {[0, 1, 2, 3, 4].map((i) => (
          <ellipse key={i} cx={560 + i * 18} cy={322} rx="11" ry="6" fill="#c9b48a" stroke="#8a7a5a" strokeWidth="0.8" />
        ))}
        {[0, 1, 2, 3].map((i) => (
          <ellipse key={i} cx={569 + i * 18} cy={313} rx="11" ry="6" fill="#d8c49a" stroke="#8a7a5a" strokeWidth="0.8" />
        ))}
      </g>

      {night && (
        <g>
          {wins.filter((w) => w.lit > 0.5 && (w.x < 340 || w.x > 470)).map((w, i) => (
            <rect key={i} x={w.x} y={w.y} width="26" height="30" fill={w.lit > 0.85 ? '#ffd8a0' : '#d8ecff'} opacity="0.55" />
          ))}
          <rect x="388" y="214" width="44" height="48" fill="#ffe2a8" opacity="0.7" />
          <Glow p={P} kind="warm" cx={410} cy={210} rx={90} ry={50} o={0.6} />
          <Glow p={P} kind="cool" cx={130} cy={206} rx={100} ry={40} o={0.45} />
          <Txt x={142} y={198} size={9} fill="#ffffff">POLICE</Txt>
          <Txt x={142} y={211} size={9} fill="#ffffff">COMMAND HQ</Txt>
          {/* gate floodlights */}
          <Glow p={P} kind="cool" cx={300} cy={226} rx={18} o={1} />
          <Glow p={P} kind="cool" cx={520} cy={226} rx={18} o={1} />
          <Glow p={P} kind="cool" cx={410} cy={320} rx={170} ry={40} o={0.55} />
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        <LampPost x={720} y={392} h={150} night={night} flip />
        <PatrolVan x={170} y={390} s={1.25} night={night} />
        <Person x={500} y={340} s={1.15} top="#16182e" bottom="#16182e" head="beret" headColor="#16182e" skin="#4e2a18" arm="hold" hold="#16182e" />
        <Person x={470} y={344} s={1.15} top="#16182e" bottom="#16182e" head="beret" headColor="#16182e" skin="#5a301c" flip />
        <Person x={600} y={420} s={1.35} top={PAL.coral} wrapper bottom="#2a4d9b" head="gele" headColor={PAL.coral} skin="#6e3b22" arm="hold" hold="#f2ecdc" />
        <Person x={640} y={424} s={1.35} top="#f4f4f4" bottom="#3a3340" head="hair" skin="#4e2a18" />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="red" cx={226} cy={311} rx={70} ry={44} o={0.95} />
          <Glow p={P} kind="blue" cx={246} cy={311} rx={70} ry={44} o={0.9} />
          <Glow p={P} kind="warm" cx={174} cy={370} rx={34} ry={12} o={0.9} />
          <Glow p={P} kind="warm" cx={700} cy={224} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={690} cy={394} rx={120} ry={30} o={0.55} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
