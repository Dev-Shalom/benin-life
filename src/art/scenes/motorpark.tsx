import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Bus, Keke, LampPost, ZincPattern, Txt, PAL, rng } from './_sharedA';

const P = 'motorpark';

/** Luggage piled on a bus roof rack (bus at the same translate/scale). */
function RoofLoad({ x, y, s = 1, seed }: { x: number; y: number; s?: number; seed: number }) {
  const r = rng(seed);
  const cols = ['#2a5aa8', PAL.coral, '#f2c230', '#6b4a36', '#1f7a3f', '#e9e2d0', '#8a3aa8'];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="18" y="-60" width="100" height="3" fill="#3a3340" />
      {[22, 50, 78, 106].map((px) => <rect key={px} x={px} y="-60" width="2" height="5" fill="#3a3340" />)}
      {Array.from({ length: 7 }, (_, i) => {
        const w = 12 + r() * 10;
        const h = 8 + r() * 9;
        const bx = 20 + i * 14;
        return <rect key={i} x={bx} y={-60 - h} width={w} height={h} rx="2" fill={cols[Math.floor(r() * cols.length)]} />;
      })}
      <ellipse cx="96" cy="-76" rx="9" ry="5" fill="#8a6a3c" />
      <path d="M20 -66 L118 -72" stroke="#1a1424" strokeWidth="1" />
      <path d="M20 -62 L118 -64" stroke="#1a1424" strokeWidth="1" />
    </g>
  );
}

function RouteBoard({ x, y, text, color = PAL.coral, w = 70 }: { x: number; y: number; text: string; color?: string; w?: number }) {
  return (
    <g>
      <rect x={x - 1.5} y={y} width="3" height={70} fill="#5b3f2c" />
      <rect x={x - w / 2} y={y - 18} width={w} height="20" fill="#f6efe0" stroke="#6b4a36" strokeWidth="1.5" />
      <Txt x={x} y={y - 4} size={10} fill={color}>{text}</Txt>
    </g>
  );
}

export default function MotorparkScene({ night }: { night: boolean }) {
  const r = rng(17);
  const dust = Array.from({ length: 60 }, () => ({ x: r() * 800, y: 300 + r() * 150, s: 0.6 + r() * 1.6 }));
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Motor park with buses and keke">
      <defs>
        <CommonDefs p={P} night={night} />
        <ZincPattern id={`${P}-zinc`} base="#a08a7a" dark="#6e5a52" light="#c9b8a6" w={7} />
        <linearGradient id={`${P}-earth`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#dca070" />
          <stop offset="0.45" stopColor="#c47a4a" />
          <stop offset="1" stopColor="#8e4424" />
        </linearGradient>
        <linearGradient id={`${P}-dust`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#e8b98a" stopOpacity="0" />
          <stop offset="0.6" stopColor="#e8b98a" stopOpacity={night ? 0.12 : 0.45} />
          <stop offset="1" stopColor="#e8b98a" stopOpacity="0" />
        </linearGradient>
        <radialGradient id={`${P}-puff`} cx="50%" cy="50%" r="50%">
          <stop offset="0" stopColor="#f0c89a" stopOpacity="0.7" />
          <stop offset="1" stopColor="#f0c89a" stopOpacity="0" />
        </radialGradient>
      </defs>

      <Sky p={P} night={night} sun={[640, 70]} moon={[640, 60]} clouds={[[200, 56, 0.7], [470, 90, 0.5]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far: trees, a big coach under a second shed */}
        <g opacity="0.8">
          <Tree x={40} y={226} s={0.9} dark="#5f8060" mid="#6f9a6a" light="#98b886" />
          <Tree x={760} y={226} s={1} dark="#5f8060" mid="#6f9a6a" light="#98b886" />
        </g>
        <g opacity="0.75">
          <path d="M470 148 L800 140 L800 152 L470 160Z" fill="#8e7a70" />
          {[480, 560, 640, 720, 790].map((x) => <rect key={x} x={x} y="156" width="4" height="70" fill="#6e5a52" />)}
          <rect x="520" y="178" width="200" height="46" rx="4" fill="#e9e6f0" />
          <rect x="530" y="184" width="180" height="16" fill="#4a5a7a" />
          <rect x="520" y="206" width="200" height="6" fill={PAL.ects} />
          <Txt x={620} y={222} size={7} fill="#1f7a3f" family="Arial, sans-serif" weight={900}>EDO LINE EXPRESS</Txt>
          {[550, 690].map((cx) => <circle key={cx} cx={cx} cy="224" r="7" fill="#2a2433" />)}
        </g>
        <Haze p={P} y={130} h={120} />

        {/* ground */}
        <rect x="0" y="236" width="800" height="214" fill="url(#motorpark-earth)" />
        <path d="M0 236 Q400 226 800 240 L800 248 Q400 236 0 246Z" fill="#7e3418" opacity="0.25" />
        {dust.map((d, i) => (
          <ellipse key={i} cx={d.x} cy={d.y} rx={d.s * 2.2} ry={d.s * 0.9} fill={i % 3 ? '#7e3418' : '#f0c89a'} opacity="0.4" />
        ))}
        {/* puddle + tyre tracks */}
        <path d="M120 400 Q300 380 520 410" stroke="#8e4424" strokeWidth="3" fill="none" opacity="0.5" />
        <path d="M120 412 Q300 392 520 422" stroke="#8e4424" strokeWidth="3" fill="none" opacity="0.5" />
        <ellipse cx="610" cy="420" rx="50" ry="8" fill="#9aa6c8" opacity="0.5" />
        <ellipse cx="600" cy="418" rx="20" ry="2" fill="#fff" opacity="0.4" />

        {/* main loading shed (zinc) */}
        <path d="M10 118 L440 108 L452 132 L0 142Z" fill={`url(#${P}-zinc)`} />
        <path d="M0 142 L452 132 L452 137 L0 147Z" fill="#5a4640" />
        {[20, 120, 220, 320, 430].map((x) => (
          <g key={x}>
            <rect x={x} y="140" width="6" height="100" fill="#4a3a3a" />
            <rect x={x + 4} y="140" width="2" height="100" fill="#2d1b4e" opacity="0.4" />
          </g>
        ))}
        <rect x="0" y="146" width="452" height="96" fill="#2d1b4e" opacity="0.18" />
        {/* banner */}
        <rect x="70" y="84" width="300" height="26" fill="#f6efe0" stroke="#7e3418" strokeWidth="2" />
        <Txt x={220} y={103} size={16} fill={PAL.coral} spacing={1}>LAGOS • AUCHI • ABUJA</Txt>
        <rect x="100" y="110" width="3" height="10" fill="#5b3f2c" />
        <rect x="338" y="110" width="3" height="10" fill="#5b3f2c" />
        <path d="M220 136 L220 144" stroke="#2a2433" strokeWidth="1" />
        <circle cx="220" cy="147" r="3" fill={night ? '#fff2c4' : '#e8e2d0'} />
        {/* ticket office */}
        <rect x="30" y="170" width="80" height="70" fill="#e8d3ae" />
        <rect x="30" y="164" width="84" height="8" fill="#1f7a3f" />
        <rect x="42" y="186" width="56" height="26" fill="#3a2b3a" />
        <rect x="40" y="210" width="60" height="4" fill="#8e5a3a" />
        <Txt x={70} y={182} size={6.5} fill="#1f3a26" family="Arial, sans-serif" weight={900}>TICKET • LOADING</Txt>
        <rect x="96" y="170" width="14" height="70" fill="#2d1b4e" opacity="0.15" />

        {/* buses loading under the shed */}
        <Bus x={130} y={240} s={0.95} body="#f2f2f6" stripe={PAL.coral} label="BENIN—LAGOS" labelColor="#7a1f12" />
        <RoofLoad x={130} y={240} s={0.95} seed={3} />
        <Bus x={270} y={244} s={0.98} body="#f4c20d" stripe="#1f1a26" label="AUCHI" />
        <RoofLoad x={270} y={244} s={0.98} seed={9} />

        {/* route boards */}
        <RouteBoard x={480} y={190} text="WARRI" color="#2a5aa8" w={60} />
        <RouteBoard x={560} y={196} text="ABUJA" w={62} />
        <RouteBoard x={660} y={192} text="ONITSHA" color="#1f7a3f" w={76} />

        {/* bus on the right, side door open */}
        <Bus x={476} y={298} s={1.05} body={PAL.ects} stripe="#f4f4f4" label="UNION • ABUJA" labelColor="#ffffff" />
        <RoofLoad x={476} y={298} s={1.05} seed={21} />
        <Haze p={P} y={240} h={90} o={0.5} />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="amber" cx={70} cy={200} rx={70} ry={40} o={0.7} />
          <rect x="42" y="186" width="56" height="26" fill="#ffcf86" opacity="0.6" />
          <Glow p={P} kind="warm" cx={220} cy={97} rx={170} ry={30} o={0.35} />
          <Glow p={P} kind="warm" cx={220} cy={150} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={220} cy={230} rx={190} ry={60} o={0.4} />
          <Glow p={P} kind="warm" cx={133} cy={222} rx={30} ry={12} o={0.85} />
          <Glow p={P} kind="warm" cx={480} cy={278} rx={34} ry={12} o={0.85} />
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        <LampPost x={760} y={380} h={160} night={night} flip />
        {/* kekes */}
        <Keke x={30} y={380} s={1.15} />
        <Keke x={300} y={438} s={1.3} flip body="#f2c230" stripe={PAL.ects} />
        {/* agbero with ticket fan */}
        <g>
          <Person x={420} y={356} s={1.35} top="#f2c230" bottom="#2c2f5c" head="cap" headColor="#d2342a" skin="#4e2a18" arm="up" />
          <g transform="translate(404 274)">
            {[0, 1, 2, 3].map((i) => (
              <rect key={i} x={-4 + i * 2} y={-8} width="7" height="11" fill={['#f6efe0', '#ffd27a', '#9fe3c0', '#ffb3b3'][i]} transform={`rotate(${-20 + i * 14} 0 4)`} />
            ))}
          </g>
        </g>
        <Person x={452} y={362} s={1.3} top="#2a5aa8" bottom="#d9cdb8" head="hair" skin="#6e3b22" arm="hold" hold="#6b4a36" />
        {/* passengers with luggage */}
        <Person x={210} y={350} s={1.2} top={PAL.coral} wrapper bottom="#f2c230" head="gele" headColor={PAL.coral} skin="#5a301c" />
        <rect x="222" y="322" width="18" height="26" rx="3" fill="#2a5aa8" />
        <rect x="222" y="322" width="18" height="4" fill="#1a3a74" />
        <Person x={250} y={352} s={1.2} top="#f4f4f4" bottom="#3a3340" head="cap" headColor="#1f7a3f" skin="#4e2a18" arm="phone" />
        {/* hawker with tray of pure water */}
        <Person x={680} y={410} s={1.4} top="#8a3aa8" wrapper bottom="#2a4d9b" head="tray" headColor="#1b1424" tray="#bfe6ff" skin="#6e3b22" />
        <Person x={130} y={430} s={1.45} top="#1f7a3f" bottom="#2c2f5c" head="hair" skin="#5a301c" arm="out" flip />
        {/* dust puffs */}
        <ellipse cx="330" cy="430" rx="90" ry="22" fill={`url(#${P}-puff)`} opacity={night ? 0.3 : 0.8} />
        <ellipse cx="80" cy="378" rx="70" ry="16" fill={`url(#${P}-puff)`} opacity={night ? 0.3 : 0.7} />
        <rect x="0" y="250" width="800" height="200" fill={`url(#${P}-dust)`} />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="warm" cx={740} cy={214} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={720} cy={384} rx={130} ry={34} o={0.55} />
          <Glow p={P} kind="warm" cx={35} cy={360} rx={26} ry={10} o={0.9} />
          <Glow p={P} kind="warm" cx={386} cy={416} rx={28} ry={10} o={0.9} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
