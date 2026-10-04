import { CommonDefs, Finish, Glow, Haze, Person, Sky, Palm, Car, Bus, Keke, LampPost, Txt, PAL } from './_sharedA';

const P = 'museum';

function IdiaBust({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="-14" y="-30" width="28" height="30" fill="#e9e1d2" />
      <rect x="4" y="-30" width="10" height="30" fill="#2d1b4e" opacity="0.2" />
      <rect x="-17" y="-34" width="34" height="5" fill="#f6f0e4" />
      {/* collar of coral rings */}
      {[0, 1, 2, 3, 4].map((i) => (
        <rect key={i} x={-9 + i * 0.4} y={-42 - i * 4} width={18 - i * 0.8} height="4" rx="2" fill="url(#museum-bronze)" />
      ))}
      <path d="M-7 -60 Q-8 -72 0 -74 Q8 -72 7 -60 Q4 -55 0 -55 Q-4 -55 -7 -60Z" fill="url(#museum-bronze)" />
      {/* tall beaded crown sweeping back */}
      <path d="M-8 -68 Q-10 -84 -2 -98 L8 -96 Q10 -82 8 -68Z" fill="url(#museum-bronze)" />
      <path d="M-6 -72 L6 -72 M-6 -78 L7 -78 M-5 -84 L7 -84 M-3 -90 L7 -90" stroke="#6e4418" strokeWidth="1" strokeDasharray="1.5 1" />
      <circle cx="-3" cy="-64" r="0.9" fill="#3a1c10" />
      <path d="M2 -60 L5 -61" stroke="#3a1c10" strokeWidth="0.8" />
    </g>
  );
}

function Warrior({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="-15" y="-26" width="30" height="26" fill="#e9e1d2" />
      <rect x="4" y="-26" width="11" height="26" fill="#2d1b4e" opacity="0.2" />
      <rect x="-18" y="-30" width="36" height="5" fill="#f6f0e4" />
      <g fill="url(#museum-bronze)">
        <path d="M-6 -30 L-5 -52 L5 -52 L6 -30 L2 -30 L0 -42 L-2 -30Z" />
        <path d="M-7 -52 Q-8 -66 0 -68 Q8 -66 7 -52Z" />
        <circle cx="0" cy="-74" r="6" />
        <path d="M-7 -78 L0 -86 L7 -78Z" />
        <ellipse cx="-11" cy="-58" rx="6" ry="9" />
        <path d="M8 -64 L12 -64 L12 -40 L10 -40Z" />
      </g>
      <line x1="12" y1="-96" x2="12" y2="-32" stroke="#8a5a26" strokeWidth="1.8" />
      <path d="M12 -102 l-3 6 h6Z" fill={PAL.gold} />
    </g>
  );
}

export default function MuseumScene({ night }: { night: boolean }) {
  const fins = Array.from({ length: 17 }, (_, i) => -80 + i * 10);
  const cx = 400;
  const R = 122;
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="National Museum at King's Square, Ring Road">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-bronze`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#f3d08a" />
          <stop offset="0.3" stopColor="#d9a441" />
          <stop offset="0.65" stopColor="#b0793a" />
          <stop offset="1" stopColor="#5e3a16" />
        </linearGradient>
        <linearGradient id={`${P}-drum`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c9c0c8" />
          <stop offset="0.18" stopColor="#fbf6ec" />
          <stop offset="0.45" stopColor="#efe5d4" />
          <stop offset="0.8" stopColor="#b8acb8" />
          <stop offset="1" stopColor="#8c84a0" />
        </linearGradient>
        <linearGradient id={`${P}-glass`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#4a5f80" />
          <stop offset="0.25" stopColor="#7b9cc4" />
          <stop offset="0.6" stopColor="#4a6590" />
          <stop offset="1" stopColor="#2c3558" />
        </linearGradient>
        <linearGradient id={`${P}-road`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7a7686" />
          <stop offset="0.6" stopColor="#5a5468" />
          <stop offset="1" stopColor="#3f3852" />
        </linearGradient>
        <radialGradient id={`${P}-lawn`} cx="50%" cy="40%" r="60%">
          <stop offset="0" stopColor="#86c060" />
          <stop offset="0.7" stopColor="#4f8f3e" />
          <stop offset="1" stopColor="#2f6a35" />
        </radialGradient>
      </defs>

      <Sky p={P} night={night} sun={[120, 70]} moon={[660, 60]} clouds={[[300, 58, 0.75], [640, 110, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* city skyline beyond the ring */}
        <g fill="#b7a8bd">
          <rect x="0" y="140" width="60" height="70" />
          <rect x="55" y="160" width="90" height="50" />
          <rect x="140" y="128" width="40" height="82" />
          <rect x="176" y="168" width="70" height="42" />
          <rect x="560" y="158" width="70" height="52" />
          <rect x="626" y="124" width="46" height="86" />
          <rect x="668" y="150" width="80" height="60" />
          <rect x="744" y="166" width="60" height="44" />
        </g>
        <g fill="#9488ad" opacity="0.8">
          {[[12, 150], [30, 150], [70, 172], [100, 172], [150, 140], [150, 160], [580, 170], [636, 138], [636, 158], [690, 162], [720, 162]].map(([x, y]) => (
            <rect key={`${x}-${y}`} x={x} y={y} width="10" height="8" />
          ))}
        </g>
        <rect x="190" y="112" width="44" height="26" fill="#d2342a" />
        <rect x="210" y="138" width="4" height="34" fill="#6a6a80" />
        <Txt x={212} y={128} size={6} fill="#fff" family="Arial, sans-serif">BENIN 2026</Txt>
        {/* far tree line + shopfront strip on the outer ring */}
        <g fill="#5f8f5a">
          {[20, 90, 160, 250, 540, 620, 700, 780].map((x, i) => (
            <ellipse key={x} cx={x} cy={196 - (i % 3) * 4} rx={34} ry={20} />
          ))}
        </g>
        <rect x="0" y="198" width="800" height="14" fill="#c98a5e" />
        {[[30, '#d2342a'], [120, '#1f7a3f'], [210, '#f2c230'], [560, '#2a5aa8'], [650, '#d2342a'], [740, '#f2c230']].map(([x, c]) => (
          <rect key={x as number} x={x as number} y="200" width="46" height="5" fill={c as string} opacity="0.85" />
        ))}
        <Haze p={P} y={110} h={120} />

        {/* ring road */}
        <rect x="0" y="210" width="800" height="240" fill="url(#museum-road)" />
        <ellipse cx="400" cy="306" rx="600" ry="100" fill="none" stroke="#f2e3a0" strokeWidth="2" strokeDasharray="18 14" opacity="0.55" />
        <ellipse cx="400" cy="300" rx="440" ry="96" fill="none" stroke="#f2e3a0" strokeWidth="2" strokeDasharray="18 14" opacity="0.65" />
        <ellipse cx="400" cy="296" rx="300" ry="58" fill="#e9e3d6" />
        <ellipse cx="400" cy="296" rx="300" ry="58" fill="none" stroke="#2a2433" strokeWidth="5" strokeDasharray="10 10" />
        <ellipse cx="400" cy="292" rx="294" ry="54" fill="url(#museum-lawn)" />
        {/* far-side traffic */}
        <Car x={70} y={214} s={0.45} body="#e9e9ee" />
        <Car x={640} y={218} s={0.45} flip body="#d2342a" />
        <Bus x={700} y={222} s={0.42} flip body={PAL.ects} stripe="#f4f4f4" />
        <Keke x={250} y={232} s={0.5} flip />

        {/* museum drum */}
        <g>
          <ellipse cx={cx + 10} cy="292" rx={R + 30} ry="20" fill={PAL.shadow} opacity="0.35" />
          <path d={`M${cx - R} 180 L${cx - R} 286 A${R} 22 0 0 0 ${cx + R} 286 L${cx + R} 180Z`} fill="url(#museum-drum)" />
          <path d={`M${cx - R + 8} 196 L${cx - R + 8} 270 A${R - 8} 18 0 0 0 ${cx + R - 8} 270 L${cx + R - 8} 196Z`} fill="url(#museum-glass)" />
          {fins.map((a) => {
            const rad = (a * Math.PI) / 180;
            const fx = cx + R * Math.sin(rad);
            const fw = 7 * Math.cos(rad) + 1;
            const lit = a < 10;
            return (
              <g key={a}>
                <rect x={fx - fw / 2} y="186" width={fw} height={98 + Math.cos(rad) * 20 - 18} fill={lit ? '#fbf6ec' : '#c9bfcf'} />
                <rect x={fx + fw / 4} y="186" width={fw / 4} height={98 + Math.cos(rad) * 20 - 18} fill="#2d1b4e" opacity="0.2" />
              </g>
            );
          })}
          {/* cornice + upper drum */}
          <ellipse cx={cx} cy="182" rx={R + 10} ry="24" fill="#d9cfc0" />
          <ellipse cx={cx} cy="178" rx={R + 10} ry="22" fill="#f6efe2" />
          <path d={`M${cx - R - 10} 178 A${R + 10} 22 0 0 0 ${cx + R + 10} 178 L${cx + R + 10} 184 A${R + 10} 24 0 0 1 ${cx - R - 10} 184Z`} fill="#b5552b" />
          <path d={`M${cx - 72} 150 L${cx - 72} 176 A72 14 0 0 0 ${cx + 72} 176 L${cx + 72} 150Z`} fill="url(#museum-drum)" />
          {[-60, -40, -20, 0, 20, 40, 60].map((a) => (
            <rect key={a} x={cx + 72 * Math.sin((a * Math.PI) / 180) - 5} y="156" width="10" height="14" fill="#4a5f80" opacity="0.85" />
          ))}
          <ellipse cx={cx} cy="150" rx="78" ry="14" fill="#efe6d6" />
          <ellipse cx={cx} cy="147" rx="58" ry="9" fill="#d9cfc0" />
          <path d={`M${cx - 70} 186 L${cx + 70} 186`} stroke="none" />
          <rect x={cx - 84} y="186" width="168" height="15" fill="#b5552b" />
          <rect x={cx - 84} y="199" width="168" height="2" fill={PAL.gold} />
          <Txt x={cx} y={198} size={10.5} fill="#fff6e0" spacing={1.5}>NATIONAL MUSEUM</Txt>
          {/* entrance + steps */}
          <rect x={cx - 26} y="246" width="52" height="40" fill="#2c3558" />
          <rect x={cx - 30} y="240" width="60" height="7" fill={PAL.bronze} />
          <path d={`M${cx - 36} 290 L${cx + 36} 290 L${cx + 44} 302 L${cx - 44} 302Z`} fill="#efe6d6" />
          <path d={`M${cx - 44} 302 L${cx + 44} 302 L${cx + 52} 312 L${cx - 52} 312Z`} fill="#d9cfc0" />
        </g>

        {/* statues on the green */}
        <IdiaBust x={232} y={318} s={0.85} />
        <Warrior x={572} y={318} s={0.85} />
        <Palm x={150} y={300} s={0.75} lean={-0.6} />
        <Palm x={655} y={298} s={0.75} lean={0.6} />
        {[[300, 318], [500, 318], [190, 300], [612, 300]].map(([x, y]) => (
          <g key={x}>
            <ellipse cx={x} cy={y} rx="16" ry="6" fill="#2f6f3a" />
            <circle cx={x - 5} cy={y - 3} r="2" fill="#f2c230" />
            <circle cx={x + 4} cy={y - 2} r="2" fill="#e0402a" />
          </g>
        ))}

        {/* near-side traffic */}
        <Bus x={430} y={400} s={0.95} body={PAL.ects} stripe="#f4f4f4" label="ECTS • RING ROAD" labelColor="#ffffff" />
        <Car x={120} y={384} s={0.9} flip body="#f2f2f6" />
        <Car x={640} y={420} s={1} body="#3a6fb5" dark="#22436f" />

        {/* foreground pavement */}
        <path d="M0 360 Q120 420 320 432 L320 450 L0 450Z" fill="#cfc4b4" />
        <path d="M800 370 Q700 420 520 440 L520 450 L800 450Z" fill="#cfc4b4" />
        <path d="M0 360 Q120 420 320 432" stroke="#2a2433" strokeWidth="5" strokeDasharray="10 10" fill="none" />
        <path d="M800 370 Q700 420 520 440" stroke="#2a2433" strokeWidth="5" strokeDasharray="10 10" fill="none" />
        <LampPost x={60} y={420} h={150} night={night} />
        <LampPost x={745} y={418} h={150} night={night} flip />
        <Person x={150} y={438} s={1.25} top="#ffffff" bottom="#2c2f5c" head="beret" headColor="#2c2f5c" skin="#4e2a18" arm="up" />
        <Person x={250} y={446} s={1.35} top="#d2342a" wrapper bottom="#f2c230" head="gele" headColor="#d2342a" skin="#6e3b22" />
        <Person x={600} y={446} s={1.3} top="#1f7a3f" bottom="#d9cdb8" head="cap" headColor="#f2c230" skin="#5a301c" arm="phone" />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="warm" cx={400} cy={230} rx={190} ry={90} o={0.55} />
          <path d={`M${cx - R + 8} 196 L${cx - R + 8} 270 A${R - 8} 18 0 0 0 ${cx + R - 8} 270 L${cx + R - 8} 196Z`} fill="#ffcf86" opacity="0.28" />
          <rect x={cx - 26} y="246" width="52" height="40" fill="#ffe2a8" opacity="0.75" />
          <Txt x={cx} y={198} size={10.5} fill="#ffe9b8" spacing={1.5}>NATIONAL MUSEUM</Txt>
          <Glow p={P} kind="warm" cx={232} cy={270} rx={34} ry={50} o={0.6} />
          <Glow p={P} kind="warm" cx={572} cy={270} rx={34} ry={50} o={0.6} />
          {/* lamp pools */}
          <Glow p={P} kind="warm" cx={82} cy={263} rx={22} o={1} />
          <Glow p={P} kind="warm" cx={82} cy={410} rx={120} ry={36} o={0.6} />
          <Glow p={P} kind="warm" cx={722} cy={261} rx={22} o={1} />
          <Glow p={P} kind="warm" cx={720} cy={410} rx={120} ry={36} o={0.6} />
          {/* headlights + taillights */}
          <Glow p={P} kind="warm" cx={433} cy={381} rx={40} ry={14} o={0.95} />
          <Glow p={P} kind="red" cx={556} cy={381} rx={16} ry={8} o={0.9} />
          <Glow p={P} kind="warm" cx={203} cy={366} rx={34} ry={12} o={0.9} />
          <Glow p={P} kind="red" cx={122} cy={366} rx={14} ry={8} o={0.9} />
          <Glow p={P} kind="warm" cx={644} cy={400} rx={34} ry={12} o={0.9} />
          <Glow p={P} kind="red" cx={90} cy={205} rx={8} ry={4} o={0.9} />
          <Glow p={P} kind="warm" cx={680} cy={210} rx={14} ry={5} o={0.9} />
          {[[20, 148], [70, 168], [150, 136], [590, 166], [640, 134], [700, 158], [760, 174]].map(([x, y]) => (
            <rect key={`${x}`} x={x} y={y} width="10" height="8" fill="#ffd27a" opacity="0.8" />
          ))}
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
