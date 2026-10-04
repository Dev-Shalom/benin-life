import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Palm, Car, LampPost, Txt, PAL, rng } from './_sharedA';

const P = 'bank';

/** Bronze Bank mark: bronze disc with a stylised coral-bead "B". */
function Logo({ x, y, r }: { x: number; y: number; r: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <circle r={r} fill="url(#bank-bronze)" />
      <circle r={r * 0.82} fill="none" stroke="#fff3d6" strokeWidth={r * 0.06} opacity="0.7" />
      <path
        d={`M${-r * 0.32} ${-r * 0.5} L${-r * 0.32} ${r * 0.5} L${r * 0.1} ${r * 0.5} Q${r * 0.46} ${r * 0.5} ${r * 0.46} ${r * 0.24} Q${r * 0.46} ${r * 0.02} ${r * 0.18} ${-r * 0.02} Q${r * 0.4} ${-r * 0.08} ${r * 0.4} ${-r * 0.28} Q${r * 0.4} ${-r * 0.5} ${r * 0.06} ${-r * 0.5}Z`}
        fill="#6e2a12"
      />
      {[-0.36, -0.12, 0.12, 0.36].map((t) => (
        <circle key={t} cx={-r * 0.32} cy={r * t} r={r * 0.07} fill={PAL.coral} />
      ))}
    </g>
  );
}

function Atm({ x, y, night }: { x: number; y: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x="0" y="-62" width="30" height="62" rx="2" fill="#d9dbe4" />
      <rect x="0" y="-62" width="30" height="10" rx="2" fill="#b0793a" />
      <rect x="5" y="-48" width="20" height="14" fill={night ? '#7ff0ff' : '#2d6f8c'} />
      <rect x="7" y="-46" width="8" height="2" fill="#e8fbff" opacity="0.7" />
      <rect x="6" y="-30" width="18" height="10" fill="#9fa2b0" />
      {[0, 1, 2].map((i) => <rect key={i} x={8 + i * 5} y="-28" width="3" height="2" fill="#5a5d6a" />)}
      <rect x="9" y="-16" width="12" height="2" fill="#2a2433" />
      <rect x="22" y="-62" width="8" height="62" fill="#2d1b4e" opacity="0.18" />
    </g>
  );
}

export default function BankScene({ night }: { night: boolean }) {
  const r = rng(53);
  const panes: { x: number; y: number; lit: number }[] = [];
  for (let f = 0; f < 3; f++) for (let c = 0; c < 8; c++) panes.push({ x: 300 + c * 40, y: 104 + f * 50, lit: r() });
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Bronze Bank branch in GRA">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-bronze`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#f6d898" />
          <stop offset="0.35" stopColor="#d9a441" />
          <stop offset="0.7" stopColor="#b0793a" />
          <stop offset="1" stopColor="#5e3a16" />
        </linearGradient>
        <linearGradient id={`${P}-curtain`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#bfe0ee" />
          <stop offset="0.3" stopColor="#5f9cb8" />
          <stop offset="0.5" stopColor="#8cc4d8" />
          <stop offset="0.75" stopColor="#3d6f8f" />
          <stop offset="1" stopColor="#264a6a" />
        </linearGradient>
        <linearGradient id={`${P}-stone`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#f4ede2" />
          <stop offset="0.6" stopColor="#e2d6c4" />
          <stop offset="1" stopColor="#bfb0a0" />
        </linearGradient>
        <linearGradient id={`${P}-pave`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d4c7b4" />
          <stop offset="0.5" stopColor="#b2a392" />
          <stop offset="1" stopColor="#8a7a74" />
        </linearGradient>
        <pattern id={`${P}-tiles`} patternUnits="userSpaceOnUse" width="30" height="14">
          <path d="M0 0 H30 M0 7 H30 M15 0 V7 M0 7 V14" stroke="#6e5a5a" strokeOpacity="0.18" strokeWidth="1" />
        </pattern>
      </defs>

      <Sky p={P} night={night} sun={[700, 64]} moon={[700, 60]} clouds={[[180, 64, 0.8], [470, 36, 0.55]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* leafy GRA backdrop */}
        <g opacity="0.85">
          <Tree x={70} y={300} s={1.3} dark="#3d6e4e" mid="#4f8a5a" light="#7fb06a" />
          <Tree x={740} y={300} s={1.35} dark="#3d6e4e" mid="#4f8a5a" light="#7fb06a" />
          <Tree x={170} y={300} s={1} dark="#4a7a5a" mid="#5f9a66" light="#8fc07a" />
        </g>
        <Haze p={P} y={150} h={140} o={0.8} />

        {/* building: stone block + curtain wall */}
        <ellipse cx="420" cy="312" rx="290" ry="12" fill={PAL.shadow} opacity="0.3" />
        <rect x="290" y="96" width="340" height="214" fill="url(#bank-curtain)" />
        {panes.map((p, i) => (
          <rect key={i} x={p.x} y={p.y} width="38" height="48" fill="#dff2fa" opacity={0.06 + (i % 5) * 0.03} />
        ))}
        {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((c) => (
          <rect key={c} x={298 + c * 40} y="96" width="3" height="214" fill="#e6edf2" />
        ))}
        {[0, 1, 2, 3].map((f) => (
          <rect key={f} x="290" y={100 + f * 50} width="340" height="4" fill="#e6edf2" />
        ))}
        {/* sky + tree reflections in glass */}
        <path d="M300 104 L380 104 L300 190Z" fill="#ffffff" opacity="0.22" />
        <path d="M470 104 L520 104 L420 250 L380 250Z" fill="#ffffff" opacity="0.1" />
        <ellipse cx="610" cy="250" rx="40" ry="34" fill="#2f5a4a" opacity="0.35" />
        <rect x="290" y="88" width="350" height="10" fill="#eef0f4" />
        <rect x="610" y="96" width="20" height="214" fill="#2d1b4e" opacity="0.18" />

        {/* stone block with bronze fins */}
        <rect x="150" y="72" width="150" height="238" fill="url(#bank-stone)" />
        <rect x="146" y="66" width="158" height="10" fill="#f8f4ec" />
        {[164, 184, 204].map((x) => (
          <rect key={x} x={x} y="196" width="8" height="114" fill="url(#bank-bronze)" />
        ))}
        <Logo x={225} y={128} r={34} />
        <rect x="282" y="72" width="18" height="238" fill="#2d1b4e" opacity="0.12" />

        {/* fascia sign */}
        <rect x="300" y="60" width="300" height="30" fill="#2a1f2e" />
        <rect x="300" y="88" width="300" height="3" fill={PAL.gold} />
        <Txt x={450} y={83} size={22} fill="#e9b85a" spacing={6}>BRONZE BANK</Txt>

        {/* entrance canopy + doors */}
        <path d="M330 232 L520 232 L530 244 L320 244Z" fill="#f2efe8" />
        <rect x="320" y="244" width="210" height="4" fill="#b0793a" />
        <rect x="360" y="248" width="130" height="62" fill="#2a3e58" />
        {[392, 424, 456].map((x) => <rect key={x} x={x} y="248" width="2" height="62" fill="#c7d3e6" />)}
        <rect x="364" y="252" width="22" height="56" fill="#cfe6ff" opacity="0.25" />
        {/* ATM gallery */}
        <rect x="532" y="236" width="98" height="74" fill="#3a3b48" />
        <rect x="528" y="226" width="106" height="12" fill={PAL.gold} />
        <Txt x={581} y={235} size={8} fill="#2a1f2e" spacing={2}>24HR ATM</Txt>
        <Atm x={540} y={310} night={night} />
        <Atm x={576} y={310} night={night} />
        <Atm x={612} y={310} night={night} />

        {/* ground: forecourt + kerb + hedge */}
        <rect x="0" y="306" width="800" height="144" fill="url(#bank-pave)" />
        <rect x="0" y="306" width="800" height="144" fill="url(#bank-tiles)" />
        <rect x="0" y="306" width="800" height="5" fill="#efe8dc" />
        <rect x="0" y="300" width="150" height="10" fill="#3f7a3f" />
        {[0, 20, 40, 60, 80, 100, 120].map((x) => <ellipse key={x} cx={x + 10} cy="300" rx="12" ry="7" fill="#4f8f45" />)}
        <path d="M0 396 L800 382 L800 450 L0 450Z" fill="#5f5a6c" />
        <path d="M0 396 L800 382" stroke="#e9e6dc" strokeWidth="4" />
        <path d="M0 424 L800 414" stroke="#f2e3a0" strokeWidth="2" strokeDasharray="24 18" opacity="0.7" />
        {/* parking bay lines */}
        {[90, 170, 250].map((x) => (
          <path key={x} d={`M${x} 330 L${x - 14} 384`} stroke="#f4f1ea" strokeWidth="2" opacity="0.7" />
        ))}
        <Palm x={120} y={310} s={0.85} lean={-0.6} />
      </g>

      {night && (
        <g>
          {panes.filter((p) => p.lit > 0.4 && p.y < 200).map((p, i) => (
            <rect key={i} x={p.x + 3} y={p.y + 4} width="34" height="42" fill={p.lit > 0.85 ? "#ffe2a8" : "#d7ecff"} opacity="0.5" />
          ))}
          <rect x="360" y="248" width="130" height="62" fill="#e6f2ff" opacity="0.7" />
          <rect x="532" y="238" width="98" height="72" fill="#bfe8ff" opacity="0.22" />
          <Glow p={P} kind="cool" cx={425} cy={300} rx={130} ry={40} o={0.7} />
          <Glow p={P} kind="teal" cx={580} cy={276} rx={70} ry={40} o={0.55} />
          <Glow p={P} kind="warm" cx={450} cy={75} rx={190} ry={36} o={0.55} />
          <Txt x={450} y={83} size={22} fill="#ffd27a" spacing={6}>BRONZE BANK</Txt>
          <Glow p={P} kind="warm" cx={225} cy={128} rx={60} o={0.6} />
          <Glow p={P} kind="warm" cx={581} cy={232} rx={70} ry={14} o={0.45} />
          <Txt x={581} y={235} size={8} fill="#3a2410" spacing={2}>24HR ATM</Txt>
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        <LampPost x={766} y={384} h={150} night={night} flip />
        {/* cars in bays */}
        <Car x={20} y={382} s={0.95} body="#f2f2f6" />
        <Car x={120} y={384} s={0.95} body="#2a2f40" dark="#14161e" />
        {/* ATM queue */}
        {[
          { x: 560, top: '#2a5aa8', bot: '#2c2f5c', h: 'hair' as const, w: false, arm: 'phone' as const },
          { x: 588, top: PAL.coral, bot: '#f2c230', h: 'gele' as const, w: true, arm: 'down' as const },
          { x: 616, top: '#f4f4f4', bot: '#3a3340', h: 'cap' as const, w: false, arm: 'down' as const },
          { x: 646, top: PAL.ects, bot: '#d9cdb8', h: 'hair' as const, w: false, arm: 'phone' as const },
          { x: 676, top: '#8a3aa8', bot: '#8a3aa8', h: 'gele' as const, w: true, arm: 'down' as const },
        ].map((q, i) => (
          <Person key={i} x={q.x + i * 8} y={348 + i * 6} s={1.1 + i * 0.05} flip top={q.top} bottom={q.bot} head={q.h} headColor={q.w ? q.top : '#1b1424'} wrapper={q.w} arm={q.arm} skin={i % 2 ? '#5a301c' : '#6e3b22'} />
        ))}
        {/* security guard */}
        <Person x={340} y={344} s={1.2} top="#3a3f6e" bottom="#1f2240" head="beret" headColor="#1f2240" skin="#4e2a18" arm="hold" hold="#1f2240" />
        <rect x="333" y="296" width="6" height="2" fill={PAL.gold} />
        {/* customer leaving */}
        <Person x={430} y={356} s={1.15} top="#e9d8b8" bottom="#e9d8b8" head="cap" headColor="#3a3340" skin="#6e3b22" arm="hold" hold="#f2f2f6" />
        <Car x={470} y={440} s={1.25} flip body="#9a1f2a" dark="#5a1018" />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="warm" cx={746} cy={222} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={740} cy={386} rx={120} ry={30} o={0.55} />
          {[555, 591, 627].map((x) => <Glow key={x} p={P} kind="teal" cx={x} cy={269} rx={18} ry={12} o={0.9} />)}
          <Glow p={P} kind="warm" cx={360} cy={420} rx={34} ry={10} o={0.8} />
          <Glow p={P} kind="red" cx={466} cy={419} rx={12} ry={6} o={0.9} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
