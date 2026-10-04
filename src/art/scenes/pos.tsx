import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Keke, Car, Txt, PAL } from './_sharedA';

const P = 'pos';

/** Big striped market umbrella; (x,y) = pole foot, canopy centred at y - h. */
function Umbrella({ x, y, h = 130, rx = 90, c1, c2, label }: { x: number; y: number; h?: number; rx?: number; c1: string; c2: string; label?: string }) {
  const top = y - h;
  const n = 8;
  const pts = Array.from({ length: n + 1 }, (_, i) => {
    const t = i / n;
    return [x - rx + t * rx * 2, top + 20 + Math.sin(t * Math.PI) * 10] as const;
  });
  return (
    <g>
      <rect x={x - 2} y={top - 10} width="4" height={h + 10} fill="#5a5a6a" />
      {pts.slice(0, -1).map(([px, py], i) => {
        const [nx, ny] = pts[i + 1];
        return (
          <path key={i} d={`M${x} ${top - 12} L${px.toFixed(1)} ${py.toFixed(1)} Q${((px + nx) / 2).toFixed(1)} ${(Math.max(py, ny) + 8).toFixed(1)} ${nx.toFixed(1)} ${ny.toFixed(1)}Z`} fill={i % 2 ? c1 : c2} />
        );
      })}
      <path d={`M${x} ${top - 12} L${x + rx} ${top + 20} L${x + rx * 0.3} ${top + 28}Z`} fill={PAL.shadow} opacity="0.18" />
      <path d={`M${x} ${top - 12} L${x - rx} ${top + 20} L${x - rx * 0.55} ${top + 26}Z`} fill="#fff" opacity="0.12" />
      <circle cx={x} cy={top - 13} r="3" fill="#3a3340" />
      {label && <Txt x={x - rx * 0.32} y={top + 20} size={9} fill="#ffffff">{label}</Txt>}
    </g>
  );
}

function Terminal({ x, y, night, s = 1.4 }: { x: number; y: number; night: boolean; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="0" y="-12" width="10" height="13" rx="1.5" fill="#2a2433" />
      <rect x="1.5" y="-10.5" width="7" height="5" fill={night ? '#8ff0ff' : '#5ab0c8'} />
      <rect x="2" y="-4" width="6" height="3" fill="#6a6478" />
      <rect x="1" y="-15" width="8" height="3" fill="#f6efe0" />
    </g>
  );
}

function Generator({ x, y, night }: { x: number; y: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <ellipse cx="22" cy="1" rx="28" ry="4" fill={PAL.shadow} opacity="0.45" />
      <path d="M8 -46 Q0 -64 12 -76 Q22 -88 10 -102" stroke="#cfcad8" strokeWidth="7" strokeLinecap="round" fill="none" opacity={night ? 0.15 : 0.35} />
      <rect x="0" y="-34" width="44" height="32" rx="3" fill="#f2c230" />
      <rect x="0" y="-34" width="44" height="6" rx="3" fill="#d2342a" />
      <rect x="6" y="-24" width="20" height="16" fill="#3a3340" />
      {[0, 1, 2, 3].map((i) => <rect key={i} x="8" y={-22 + i * 4} width="16" height="1.5" fill="#6a6478" />)}
      <circle cx="35" cy="-16" r="4" fill="#3a3340" />
      <rect x="-2" y="-38" width="48" height="4" rx="2" fill="#3a3340" />
      <rect x="4" y="-30" width="4" height="4" fill="#9a9aa8" />
      <rect x="32" y="-34" width="12" height="32" fill={PAL.shadow} opacity="0.2" />
      <rect x="2" y="-2" width="6" height="3" fill="#2a2433" />
      <rect x="36" y="-2" width="6" height="3" fill="#2a2433" />
    </g>
  );
}

export default function PosScene({ night }: { night: boolean }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Roadside PoS stand">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-tar`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#77737f" />
          <stop offset="1" stopColor="#4a4560" />
        </linearGradient>
        <linearGradient id={`${P}-walk`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d8a074" />
          <stop offset="0.5" stopColor="#c27c4c" />
          <stop offset="1" stopColor="#934826" />
        </linearGradient>
        <linearGradient id={`${P}-table`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#f4f4f6" />
          <stop offset="1" stopColor="#c8c8d2" />
        </linearGradient>
      </defs>

      <Sky p={P} night={night} sun={[90, 66]} moon={[90, 60]} clouds={[[330, 50, 0.7], [640, 80, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* shop row */}
        <g>
          <rect x="0" y="120" width="250" height="134" fill="#e7cfa4" />
          <rect x="0" y="112" width="256" height="10" fill="#8e5a3a" />
          <rect x="250" y="96" width="250" height="158" fill="#cfd8e8" />
          <rect x="250" y="88" width="256" height="10" fill="#4a5a7a" />
          <rect x="500" y="130" width="300" height="124" fill="#e9b8a0" />
          <rect x="500" y="122" width="300" height="10" fill="#7e3418" />
          {/* upper windows */}
          {[20, 90, 160, 270, 340, 410, 530, 600, 670, 740].map((x) => (
            <g key={x}>
              <rect x={x} y={x < 250 ? 134 : x < 500 ? 112 : 144} width="40" height="28" fill="#4d5c7a" />
              <rect x={x} y={x < 250 ? 134 : x < 500 ? 112 : 144} width="12" height="28" fill="#dfeaff" opacity="0.15" />
            </g>
          ))}
          {[270, 340, 410].map((x) => <rect key={x} x={x} y="150" width="40" height="22" fill="#4d5c7a" />)}
          {/* signboards */}
          <rect x="16" y="172" width="210" height="22" fill="#1f7a3f" />
          <Txt x={121} y={188} size={11} fill="#ffffff" spacing={1}>PHONE VILLAGE</Txt>
          <rect x="266" y="180" width="216" height="22" fill="#d2342a" />
          <Txt x={374} y={196} size={11} fill="#ffffff" spacing={1}>MAMA T PROVISIONS</Txt>
          <rect x="520" y="172" width="260" height="22" fill="#2a5aa8" />
          <Txt x={650} y={188} size={11} fill="#ffffff" spacing={1}>+ GOODLIFE PHARMACY</Txt>
          {/* shopfronts */}
          {[[16, 196, 210], [266, 204, 216], [520, 196, 260]].map(([x, y, w]) => (
            <g key={x}>
              <rect x={x} y={y} width={w} height={254 - y} fill="#2e2a3e" />
              <rect x={x} y={y} width={w} height="6" fill={PAL.shadow} opacity="0.4" />
              {Array.from({ length: Math.floor(w / 14) }, (_, i) => <rect key={i} x={x + 4 + i * 14} y={y + 10} width="10" height="12" fill={['#f2c230', '#59c06a', PAL.coral, '#8ad0ff', '#ffffff'][(i + x) % 5]} opacity="0.75" />)}
            </g>
          ))}
          <rect x="230" y="96" width="20" height="158" fill={PAL.shadow} opacity="0.12" />
          <rect x="480" y="96" width="20" height="158" fill={PAL.shadow} opacity="0.15" />
        </g>
        <Tree x={790} y={250} s={0.8} />
        <Haze p={P} y={140} h={120} o={0.6} />

        {/* road behind + walkway */}
        <rect x="0" y="252" width="800" height="40" fill="url(#pos-tar)" />
        <path d="M0 272 L800 272" stroke="#f2e3a0" strokeWidth="2" strokeDasharray="20 16" opacity="0.6" />
        <Keke x={540} y={286} s={0.75} flip />
        <Car x={80} y={290} s={0.75} body="#e9e9ee" />
        <rect x="0" y="290" width="800" height="160" fill="url(#pos-walk)" />
        <rect x="0" y="290" width="800" height="5" fill="#e8c8a8" />
        {Array.from({ length: 40 }, (_, i) => (
          <circle key={i} cx={(i * 113) % 800} cy={300 + ((i * 61) % 150)} r={1 + (i % 3) * 0.6} fill="#7e3418" opacity="0.35" />
        ))}

        {/* second PoS stand further down the line */}
        <g>
          <Umbrella x={738} y={322} h={104} rx={58} c1="#1f7a3f" c2="#f4f4f6" />
          <rect x="702" y="292" width="72" height="5" fill="#d9dbe4" />
          <rect x="706" y="297" width="4" height="22" fill="#9a9aa8" />
          <rect x="766" y="297" width="4" height="22" fill="#9a9aa8" />
          <rect x="708" y="298" width="60" height="16" fill="#f2c230" />
          <Txt x={738} y={310} size={8} fill="#1f1a26">POS</Txt>
        </g>

        {/* main stand */}
        <Umbrella x={300} y={404} h={250} rx={190} c1={PAL.coral} c2="#f2c230" />
        {/* agents behind the table */}
        <Person x={238} y={384} s={1.5} top="#f4f4f4" bottom="#2c2f5c" head="cap" headColor="#1f7a3f" skin="#4e2a18" arm="hold" hold="#2a2433" />
        <Person x={352} y={382} s={1.45} top="#8a3aa8" wrapper bottom="#8a3aa8" head="gele" headColor="#f2c230" skin="#6e3b22" arm="hold" hold="#c9e6b0" />
        {/* table */}
        <rect x="140" y="330" width="320" height="10" fill="url(#pos-table)" />
        <Terminal x={170} y={331} night={night} />
        <Terminal x={200} y={331} night={night} />
        <Terminal x={410} y={331} night={night} />
        <rect x="270" y="320" width="54" height="10" fill="#3a6a3a" />
        <rect x="273" y="317" width="48" height="4" fill="#7ab070" />
        <rect x="330" y="322" width="22" height="8" fill="#c9e6b0" />
        <rect x="330" y="320" width="22" height="3" fill="#a8d090" />
        {/* banner across the table front */}
        <rect x="132" y="340" width="336" height="54" fill="#f6efe0" stroke="#7e3418" strokeWidth="1.5" />
        <rect x="132" y="340" width="336" height="7" fill={PAL.coral} />
        <Txt x={300} y={370} size={16} fill="#1f1a26" spacing={0.5}>POS • WITHDRAWAL • TRANSFER</Txt>
        <Txt x={300} y={386} size={9} fill="#1f7a3f" family="Arial, sans-serif" weight={900} spacing={1.5}>AIRTIME • DATA • BILLS • DEPOSIT</Txt>
        <rect x="132" y="394" width="336" height="10" fill={PAL.shadow} opacity="0.25" />
        <rect x="138" y="394" width="6" height="12" fill="#9a9aa8" />
        <rect x="456" y="394" width="6" height="12" fill="#9a9aa8" />
        {/* cable to generator */}
        <path d="M140 352 Q110 410 84 404" stroke="#1f1a26" strokeWidth="1.8" fill="none" />
        <Generator x={30} y={420} night={night} />
      </g>

      {night && (
        <g>
          {/* rechargeable bulb hanging under umbrella */}
          <path d="M300 160 L300 196" stroke="#2a2433" strokeWidth="1" />
          <circle cx="300" cy="200" r="6" fill="#fff6dc" />
          <Glow p={P} kind="warm" cx={300} cy={200} rx={40} o={1} />
          <Glow p={P} kind="warm" cx={300} cy={330} rx={240} ry={90} o={0.6} />
          <Glow p={P} kind="cool" cx={195} cy={320} rx={40} ry={14} o={0.9} />
          <Glow p={P} kind="cool" cx={417} cy={320} rx={20} ry={10} o={0.9} />
          <Glow p={P} kind="warm" cx={738} cy={250} rx={60} ry={50} o={0.6} />
          <Glow p={P} kind="amber" cx={52} cy={400} rx={40} ry={20} o={0.5} />
          <Txt x={300} y={370} size={16} fill="#3a2410" spacing={0.5}>POS • WITHDRAWAL • TRANSFER</Txt>
          {[[16, 196, 210], [520, 196, 260]].map(([x, y, w]) => (
            <rect key={x} x={x} y={y + 8} width={w} height="20" fill="#ffd8a0" opacity="0.3" />
          ))}
          <Glow p={P} kind="warm" cx={540} cy={276} rx={22} ry={8} o={0.8} />
          <Glow p={P} kind="warm" cx={82} cy={278} rx={22} ry={8} o={0.8} />
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* queue */}
        {[
          { x: 686, y: 372, top: PAL.coral, bot: '#f2c230', h: 'gele' as const, w: true, arm: 'phone' as const, skin: '#6e3b22' },
          { x: 642, y: 380, top: '#f4f4f4', bot: '#3a3340', h: 'cap' as const, w: false, arm: 'down' as const, skin: '#4e2a18' },
          { x: 596, y: 388, top: '#1f7a3f', bot: '#d9cdb8', h: 'hair' as const, w: false, arm: 'phone' as const, skin: '#5a301c' },
          { x: 548, y: 396, top: '#2a6ab8', bot: '#2a6ab8', h: 'gele' as const, w: true, arm: 'down' as const, skin: '#6e3b22' },
        ].map((q, i) => (
          <Person key={i} x={q.x} y={q.y} s={1.05 + i * 0.08} flip top={q.top} bottom={q.bot} wrapper={q.w} head={q.h} headColor={q.w ? q.top : '#1b1424'} arm={q.arm} skin={q.skin} />
        ))}
        {/* customer at the table */}
        <Person x={496} y={412} s={1.5} flip top="#d9a441" bottom="#2c2f5c" head="hair" skin="#4e2a18" arm="out" />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="cool" cx={690} cy={320} rx={9} o={0.8} />
          <Glow p={P} kind="cool" cx={601} cy={331} rx={10} o={0.8} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
