import { CommonDefs, Finish, Glow, Haze, Person, Sky, Palm, Car, LampPost, Txt, PAL, rng } from './_sharedA';

const P = 'hospital';

function Ambulance({ x, y, s = 1, night }: { x: number; y: number; s?: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="68" cy="1" rx="74" ry="5" fill={PAL.shadow} opacity="0.4" />
      <path d="M4 -10 Q2 -30 10 -38 L28 -40 L32 -60 Q33 -64 40 -64 L132 -64 Q138 -64 138 -58 L138 -8 Q138 -5 134 -5 L8 -5 Q4 -5 4 -10Z" fill="#f4f6fa" />
      <path d="M90 -64 L132 -64 Q138 -64 138 -58 L138 -5 L100 -5Z" fill="#9aa4c8" opacity="0.35" />
      <path d="M10 -36 L28 -38 L33 -56 L46 -56 L46 -36Z" fill="#33405a" />
      <path d="M14 -36 L22 -37 L30 -54 L34 -54Z" fill="#d9ecff" opacity="0.4" />
      <rect x="4" y="-27" width="134" height="7" fill="#d2342a" />
      <rect x="4" y="-20" width="134" height="3" fill="#2a5aa8" />
      <rect x="56" y="-56" width="26" height="18" rx="1.5" fill="#33405a" />
      <g transform="translate(108 -46)">
        <rect x="-3" y="-9" width="6" height="18" fill="#d2342a" />
        <rect x="-9" y="-3" width="18" height="6" fill="#d2342a" />
      </g>
      <Txt x={70} y={-30} size={8} fill="#2a5aa8" family="Arial, sans-serif" weight={900}>AMBULANCE</Txt>
      <rect x="36" y="-70" width="10" height="6" rx="1.5" fill={night ? '#ff5a5a' : '#c4262a'} />
      <rect x="46" y="-70" width="10" height="6" rx="1.5" fill={night ? '#6aa0ff' : '#2a5aa8'} />
      <path d="M40 -64 L132 -64" stroke="#fff" strokeWidth="1.2" />
      <rect x="3" y="-16" width="5" height="4" rx="1" fill="#fff4cf" />
      {[24, 116].map((cx) => (
        <g key={cx}>
          <circle cx={cx} cy={-6} r="8" fill="#1e1a26" />
          <circle cx={cx} cy={-6} r="3.6" fill="#a2a2ae" />
        </g>
      ))}
    </g>
  );
}

export default function HospitalScene({ night }: { night: boolean }) {
  const r = rng(77);
  const cols = 14;
  const floors = 6;
  const main: { x: number; y: number; lit: number }[] = [];
  for (let f = 0; f < floors; f++) {
    for (let c = 0; c < cols; c++) {
      main.push({ x: 162 + c * 28.5, y: 112 + f * 30, lit: r() });
    }
  }
  const wing: { x: number; y: number; w: number; h: number; lit: number }[] = [];
  for (let f = 0; f < 5; f++) {
    for (let c = 0; c < 7; c++) {
      const t = c / 7;
      const x = 572 + c * 27 - c * c * 0.6;
      const top = 138 + t * 26;
      const fh = (282 - top) / 5;
      wing.push({ x, y: top + f * fh + 4, w: 20 - c * 1.2, h: fh - 10, lit: r() });
    }
  }
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Teaching hospital">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ffffff" />
          <stop offset="0.45" stopColor="#eef1f5" />
          <stop offset="1" stopColor="#c9cfdc" />
        </linearGradient>
        <linearGradient id={`${P}-side`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c3c8d8" />
          <stop offset="1" stopColor="#9da3bd" />
        </linearGradient>
        <linearGradient id={`${P}-glass`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#9cc6ec" />
          <stop offset="0.5" stopColor="#4f86c6" />
          <stop offset="1" stopColor="#2c5a98" />
        </linearGradient>
        <linearGradient id={`${P}-tar`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7d7c8a" />
          <stop offset="0.5" stopColor="#5c5a6c" />
          <stop offset="1" stopColor="#3e3a52" />
        </linearGradient>
        <linearGradient id={`${P}-lawn`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6aa84a" />
          <stop offset="1" stopColor="#2f6f3a" />
        </linearGradient>
      </defs>

      <Sky p={P} night={night} sun={[90, 70]} moon={[90, 64]} clouds={[[700, 60, 0.8], [360, 46, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far trees */}
        <g fill="#6f9a7a" opacity="0.7">
          {[0, 50, 95, 690, 740, 785].map((x, i) => (
            <ellipse key={x} cx={x} cy={262 - (i % 2) * 8} rx="40" ry="34" />
          ))}
        </g>
        <Haze p={P} y={180} h={110} />

        {/* left low wing */}
        <rect x="20" y="196" width="140" height="106" fill="url(#hospital-wall)" />
        <rect x="20" y="190" width="140" height="8" fill="#2a5aa8" />
        {[0, 1, 2].map((f) => (
          <rect key={f} x="30" y={208 + f * 30} width="120" height="16" fill="url(#hospital-glass)" />
        ))}
        {[0, 1, 2, 3, 4, 5].map((c) => (
          <rect key={c} x={30 + c * 24} y="206" width="2" height="90" fill="#e8ecf2" />
        ))}

        {/* main block */}
        <rect x="150" y="86" width="425" height="216" fill="url(#hospital-wall)" />
        <rect x="150" y="78" width="425" height="10" fill="#2a5aa8" />
        <rect x="150" y="88" width="425" height="3" fill="#1a3a74" opacity="0.5" />
        {main.map((w, i) => (
          <rect key={i} x={w.x} y={w.y} width="21" height="19" fill="url(#hospital-glass)" />
        ))}
        {main.filter((_, i) => i % 3 === 0).map((w, i) => (
          <rect key={`h${i}`} x={w.x + 2} y={w.y + 2} width="5" height="15" fill="#e8f4ff" opacity="0.35" />
        ))}
        {[0, 1, 2, 3, 4, 5].map((f) => (
          <rect key={f} x="150" y={133 + f * 30} width="425" height="2" fill="#b8c0d4" />
        ))}
        {/* blue stair tower with cross */}
        <rect x="335" y="56" width="58" height="246" fill="#2f63b4" />
        <rect x="335" y="56" width="16" height="246" fill="#5b8fdc" />
        <rect x="381" y="56" width="12" height="246" fill="#1b3d7a" />
        <circle cx="364" cy="84" r="17" fill="#fff" />
        <rect x="360" y="72" width="8" height="24" fill="#d2342a" />
        <rect x="352" y="80" width="24" height="8" fill="#d2342a" />
        {[0, 1, 2, 3, 4, 5].map((f) => (
          <rect key={f} x="345" y={116 + f * 30} width="38" height="14" fill="#9cc6ec" opacity="0.75" />
        ))}
        <rect x="190" y="60" width="130" height="20" fill="#fff" />
        <Txt x={255} y={75} size={11} fill="#2a5aa8" spacing={1}>TEACHING</Txt>
        <rect x="408" y="60" width="130" height="20" fill="#fff" />
        <Txt x={473} y={75} size={11} fill="#2a5aa8" spacing={1}>HOSPITAL</Txt>
        <path d="M393 91 L425 91 L425 302 L393 302Z" fill="#2d1b4e" opacity="0.13" />
        <rect x="150" y="262" width="425" height="40" fill="#2d1b4e" opacity="0.08" />
        <rect x="150" y="91" width="425" height="10" fill="#2d1b4e" opacity="0.08" />
        {/* rooftop water tanks */}
        {[[156, 78], [546, 78], [690, 112]].map(([tx, ty]) => (
          <g key={tx}>
            <rect x={tx} y={ty - 8} width="4" height="10" fill="#4a4a5a" />
            <rect x={tx + 14} y={ty - 8} width="4" height="10" fill="#4a4a5a" />
            <path d={`M${tx - 3} ${ty - 8} L${tx - 3} ${ty - 24} Q${tx + 11} ${ty - 30} ${tx + 25} ${ty - 24} L${tx + 25} ${ty - 8}Z`} fill="#2a4d9b" />
            <path d={`M${tx + 14} ${ty - 26} Q${tx + 22} ${ty - 26} ${tx + 25} ${ty - 24} L${tx + 25} ${ty - 8} L${tx + 14} ${ty - 8}Z`} fill="#1a1a4e" opacity="0.4" />
            <path d={`M${tx - 3} ${ty - 16} L${tx + 25} ${ty - 16}`} stroke="#1d3a6b" strokeWidth="1" />
          </g>
        ))}
        {/* right receding wing (perspective) */}
        <path d="M575 88 L765 128 L765 298 L575 302Z" fill="url(#hospital-side)" />
        <path d="M575 80 L765 122 L765 130 L575 90Z" fill="#1d3f7c" />
        {wing.map((w, i) => (
          <rect key={i} x={w.x} y={w.y} width={w.w} height={w.h} fill="#3d6aa8" opacity="0.9" />
        ))}
        <rect x="560" y="86" width="15" height="216" fill="#2d1b4e" opacity="0.12" />

        {/* emergency canopy */}
        <path d="M168 258 L330 258 L338 270 L160 270Z" fill="#e9edf3" />
        <rect x="160" y="270" width="178" height="5" fill="#9aa4c0" />
        <rect x="178" y="240" width="142" height="20" fill="#fff" stroke="#d2342a" strokeWidth="2" />
        <Txt x={249} y={256} size={14} fill="#d2342a" spacing={2}>EMERGENCY</Txt>
        <rect x="170" y="275" width="4" height="28" fill="#9aa4c0" />
        <rect x="324" y="275" width="4" height="28" fill="#9aa4c0" />
        <rect x="200" y="278" width="100" height="24" fill="#2b3f66" />
        <rect x="248" y="278" width="2" height="24" fill="#c7d3e6" />
        <rect x="204" y="280" width="14" height="20" fill="#cfe6ff" opacity="0.4" />
        {/* main entrance */}
        <rect x="420" y="272" width="120" height="30" fill="#2b3f66" />
        <rect x="412" y="266" width="136" height="7" fill="#2a5aa8" />
        {[440, 470, 500].map((x) => <rect key={x} x={x} y="272" width="2" height="30" fill="#c7d3e6" />)}

        {/* ground */}
        <rect x="0" y="300" width="800" height="150" fill="url(#hospital-tar)" />
        <rect x="0" y="300" width="800" height="12" fill="#c9cbd2" />
        <rect x="0" y="300" width="800" height="3" fill="#e9eaee" />
        <path d="M0 312 L800 312 L800 330 L0 336Z" fill="url(#hospital-lawn)" />
        {[60, 140, 620, 700, 760].map((x) => (
          <g key={x}>
            <ellipse cx={x} cy="316" rx="26" ry="9" fill="#2f7a35" />
            <circle cx={x - 8} cy="313" r="2.4" fill="#e8331c" />
            <circle cx={x + 6} cy="315" r="2.4" fill="#f2c230" />
            <circle cx={x + 14} cy="312" r="2" fill="#ff7db0" />
          </g>
        ))}
        {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => (
          <path key={i} d={`M${60 + i * 100} 360 L${30 + i * 104} 450`} stroke="#e9e6dc" strokeWidth="3" opacity="0.6" />
        ))}
        <path d="M0 352 L800 345" stroke="#f2c230" strokeWidth="3" strokeDasharray="22 16" opacity="0.8" />
        <ellipse cx="420" cy="420" rx="420" ry="40" fill={PAL.shadow} opacity="0.15" />

      </g>
      {night && (
        <g>
          {main.filter((w) => w.lit > 0.62).map((w, i) => (
            <rect key={i} x={w.x} y={w.y} width="21" height="19" fill={w.lit > 0.86 ? '#ffcf86' : '#bfe0ff'} opacity="0.62" />
          ))}
          {wing.filter((w) => w.lit > 0.68).map((w, i) => (
            <rect key={`w${i}`} x={w.x} y={w.y} width={w.w} height={w.h} fill="#bfe0ff" opacity="0.5" />
          ))}
          {[0, 2, 3, 5].map((f) => (
            <rect key={`s${f}`} x="345" y={116 + f * 30} width="38" height="14" fill="#cfe6ff" opacity="0.6" />
          ))}
          <Glow p={P} kind="cool" cx={364} cy={84} rx={36} o={0.9} />
          <circle cx="364" cy="84" r="17" fill="#fff" opacity="0.9" />
          <rect x="360" y="72" width="8" height="24" fill="#ff4a3a" />
          <rect x="352" y="80" width="24" height="8" fill="#ff4a3a" />
          <Glow p={P} kind="red" cx={249} cy={250} rx={110} ry={34} o={0.7} />
          <rect x="178" y="240" width="142" height="20" fill="#fff" stroke="#ff4a3a" strokeWidth="2" />
          <Txt x={249} y={256} size={14} fill="#e62a1e" spacing={2}>EMERGENCY</Txt>
          <rect x="200" y="278" width="100" height="24" fill="#cfe6ff" opacity="0.75" />
          <rect x="420" y="272" width="120" height="30" fill="#ffe2a8" opacity="0.7" />
          <Glow p={P} kind="cool" cx={250} cy={310} rx={120} ry={30} o={0.6} />
          <Glow p={P} kind="warm" cx={480} cy={312} rx={110} ry={28} o={0.55} />
          {[[255, 75, 'TEACHING'], [473, 75, 'HOSPITAL']].map(([x, y, t]) => (
            <Txt key={t as string} x={x as number} y={y as number} size={11} fill="#cfe6ff" spacing={1}>{t}</Txt>
          ))}
        </g>
      )}
      <g filter={night ? `url(#${P}-night)` : undefined}>
        <Palm x={110} y={320} s={1.05} lean={-1} />
        <Palm x={612} y={322} s={1.15} lean={1} />
        <Palm x={735} y={330} s={0.9} lean={-0.6} />

        <Ambulance x={190} y={350} s={1.05} night={night} />
        <Car x={520} y={392} s={1.05} body="#3a6fb5" dark="#22436f" />
        <Car x={640} y={440} s={1.15} flip body="#d9dbe2" />

        {/* people */}
        <Person x={385} y={338} s={1.05} top="#ffffff" bottom="#ffffff" head="beret" headColor="#ffffff" skin="#5a301c" arm="hold" hold="#7fb2e6" />
        <Person x={410} y={340} s={1.05} top="#7fc4d8" bottom="#2c5a98" head="hair" skin="#6e3b22" />
        <Person x={470} y={345} s={1} top="#f08a1a" wrapper bottom="#2a4d9b" head="gele" headColor="#f08a1a" skin="#4e2a18" />
        <Person x={160} y={432} s={1.4} top="#d2342a" bottom="#2c2f5c" head="hair" skin="#6e3b22" arm="phone" />
        <LampPost x={575} y={350} h={110} night={night} />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="red" cx={238} cy={276} rx={50} ry={34} o={0.95} />
          <Glow p={P} kind="blue" cx={252} cy={276} rx={50} ry={34} o={0.9} />
          <Glow p={P} kind="warm" cx={598} cy={235} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={598} cy={352} rx={110} ry={34} o={0.6} />
          <Glow p={P} kind="warm" cx={192} cy={334} rx={26} ry={10} o={0.9} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
