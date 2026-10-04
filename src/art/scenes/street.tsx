import { CommonDefs, Finish, Glow, Haze, Person, Sky, Palm, Tree, Car, Keke, LampPost, ZincPattern, Txt, PAL, rng } from './_sharedA';

const P = 'street';

/** Single-storey compound house: hip zinc roof, painted wall, dado band, louvre windows with burglary bars. */
function Bungalow({ x, y, w, wall, band, door = '#2f6b3a' }: { x: number; y: number; w: number; wall: string; band: string; door?: string }) {
  const h = 80;
  return (
    <g>
      <path d={`M${x - 10} ${y - h} L${x + 30} ${y - h - 40} L${x + w - 30} ${y - h - 40} L${x + w + 10} ${y - h}Z`} fill={`url(#${P}-rust)`} />
      <path d={`M${x - 10} ${y - h} L${x + w + 10} ${y - h} L${x + w + 10} ${y - h + 4} L${x - 10} ${y - h + 4}Z`} fill="#4a2a1a" />
      <rect x={x} y={y - h + 4} width={w} height={h - 4} fill={wall} />
      <rect x={x} y={y - 22} width={w} height="22" fill={band} />
      {[0.15, 0.62].map((t) => (
        <g key={t}>
          <rect x={x + w * t} y={y - 62} width="34" height="30" fill="#3a3a4e" />
          {[0, 1, 2, 3, 4].map((l) => <rect key={l} x={x + w * t} y={y - 60 + l * 6} width="34" height="2" fill="#a9b4c6" opacity="0.8" />)}
          {[0, 1, 2, 3].map((b) => <rect key={b} x={x + w * t + 4 + b * 8} y={y - 62} width="1.5" height="30" fill="#1f1a26" />)}
        </g>
      ))}
      <rect x={x + w * 0.42} y={y - 56} width="26" height="56" fill={door} />
      <rect x={x + w * 0.42 + 2} y={y - 54} width="10" height="52" fill="#fff" opacity="0.08" />
      <rect x={x + w - 14} y={y - h + 4} width="14" height={h - 4} fill={PAL.shadow} opacity="0.18" />
      <rect x={x} y={y - h + 4} width={w} height="6" fill={PAL.shadow} opacity="0.22" />
    </g>
  );
}

function Poster({ x, y, c1, c2, t, rot = 0 }: { x: number; y: number; c1: string; c2: string; t: string; rot?: number }) {
  return (
    <g transform={`rotate(${rot} ${x + 13} ${y + 17})`}>
      <rect x={x} y={y} width="26" height="34" fill={c1} />
      <rect x={x} y={y + 22} width="26" height="12" fill={c2} />
      <circle cx={x + 13} cy={y + 11} r="6" fill="#6e3b22" />
      <Txt x={x + 13} y={y + 31} size={5} fill="#fff" family="Arial, sans-serif" weight={900}>{t}</Txt>
    </g>
  );
}

export default function StreetScene({ night }: { night: boolean }) {
  const r = rng(43);
  const potholes = [[150, 368, 30], [470, 404, 44], [690, 372, 24], [300, 430, 26]];
  const grit = Array.from({ length: 50 }, () => ({ x: r() * 800, y: 330 + r() * 120 }));
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Busy Benin City street">
      <defs>
        <CommonDefs p={P} night={night} />
        <ZincPattern id={`${P}-rust`} base="#9a5a3a" dark="#6e3a26" light="#c08a5e" w={6} />
        <ZincPattern id={`${P}-zinc`} base="#9aa3ad" dark="#6b7480" light="#d4dae0" w={6} />
        <linearGradient id={`${P}-tar`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6f6a78" />
          <stop offset="0.5" stopColor="#56506a" />
          <stop offset="1" stopColor="#3a3450" />
        </linearGradient>
        <linearGradient id={`${P}-side`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d7976a" />
          <stop offset="1" stopColor="#b36238" />
        </linearGradient>
        <radialGradient id={`${P}-hole`} cx="50%" cy="45%" r="50%">
          <stop offset="0" stopColor="#7c8aa8" />
          <stop offset="0.6" stopColor="#4a4a66" />
          <stop offset="1" stopColor="#2e2a40" />
        </radialGradient>
        <radialGradient id={`${P}-dark`} cx="50%" cy="50%" r="50%">
          <stop offset="0" stopColor="#0a0820" stopOpacity="0.55" />
          <stop offset="1" stopColor="#0a0820" stopOpacity="0" />
        </radialGradient>
      </defs>

      <Sky p={P} night={night} sun={[690, 66]} moon={[690, 58]} clouds={[[180, 60, 0.75], [440, 34, 0.5]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far rooftops, church, water tank */}
        <g fill="#a99cb4" opacity="0.85">
          <path d="M0 220 L40 196 L110 196 L150 220Z" />
          <path d="M520 214 L560 190 L640 190 L680 214Z" />
          <rect x="600" y="120" width="10" height="70" />
          <path d="M594 120 L605 96 L616 120Z" />
          <rect x="603" y="100" width="4" height="12" fill="#c9bcd0" />
          <rect x="230" y="150" width="26" height="22" />
          <rect x="234" y="172" width="3" height="40" />
          <rect x="249" y="172" width="3" height="40" />
        </g>
        <Tree x={720} y={230} s={0.9} dark="#5f8060" mid="#6f9a6a" light="#98b886" />
        <Palm x={180} y={226} s={0.6} lean={0.5} tone="#4f8a5a" />
        <Haze p={P} y={140} h={110} />

        {/* compound houses */}
        <Bungalow x={14} y={300} w={190} wall="#e9d6a8" band="#8e5a3a" />
        {/* storey building with balcony */}
        <g>
          <rect x="232" y="130" width="170" height="170" fill="#c9d8c0" />
          <path d="M222 132 L412 132 L404 116 L230 116Z" fill={`url(#${P}-zinc)`} />
          <rect x="232" y="196" width="170" height="8" fill="#e9eee4" />
          <rect x="226" y="204" width="182" height="4" fill="#5a5a6a" />
          {Array.from({ length: 16 }, (_, i) => <rect key={i} x={230 + i * 11.5} y="186" width="2" height="18" fill="#5a5a6a" />)}
          <rect x="226" y="184" width="182" height="3" fill="#5a5a6a" />
          {[248, 300, 352].map((wx) => (
            <g key={wx}>
              <rect x={wx} y="146" width="34" height="34" fill="#3a3a4e" />
              {[0, 1, 2, 3, 4].map((l) => <rect key={l} x={wx} y={148 + l * 7} width="34" height="2" fill="#a9b4c6" opacity="0.8" />)}
              <rect x={wx} y="226" width="34" height="34" fill="#3a3a4e" />
              {[0, 1, 2, 3, 4].map((l) => <rect key={l} x={wx} y={228 + l * 7} width="34" height="2" fill="#a9b4c6" opacity="0.8" />)}
            </g>
          ))}
          <rect x="232" y="276" width="170" height="24" fill="#8e5a3a" />
          {/* clothes line on balcony */}
          <path d="M240 168 Q300 176 390 168" stroke="#3a3340" strokeWidth="0.8" fill="none" />
          {[[252, PAL.coral], [272, '#2a5aa8'], [312, '#f2c230'], [350, '#ffffff'], [372, '#1f7a3f']].map(([cx, c]) => (
            <rect key={cx as number} x={cx as number} y="170" width="12" height="16" fill={c as string} />
          ))}
          <rect x="384" y="130" width="18" height="170" fill={PAL.shadow} opacity="0.18" />
        </g>
        <Bungalow x={430} y={300} w={180} wall="#d9a7a0" band="#5a3a5a" door="#7a2a2a" />
        {/* container kiosk */}
        <g>
          <rect x="626" y="230" width="120" height="70" fill="#2a6ab8" />
          {Array.from({ length: 20 }, (_, i) => <rect key={i} x={628 + i * 6} y="232" width="2" height="66" fill="#1a4a8a" />)}
          <rect x="640" y="248" width="92" height="34" fill="#1f1a26" />
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <rect key={i} x={644 + i * 15} y="252" width="10" height="12" fill={['#f2c230', PAL.coral, '#59c06a', '#ffffff', '#f08a1a', '#8ad0ff'][i]} />
          ))}
          <rect x="640" y="268" width="92" height="3" fill="#8e5a3a" />
          {[0, 1, 2, 3].map((i) => <rect key={i} x={648 + i * 20} y="272" width="14" height="8" fill="#cfd6e2" />)}
          <rect x="620" y="214" width="132" height="18" fill="#f2c230" />
          <Txt x={686} y={227} size={8} fill="#1f1a26" family="Arial, sans-serif" weight={900}>RECHARGE CARD • POS</Txt>
          <rect x="730" y="230" width="16" height="70" fill={PAL.shadow} opacity="0.2" />
        </g>
        {/* posters */}
        <Poster x={170} y={244} c1="#1f7a3f" c2="#d2342a" t="VOTE" rot={-3} />
        <Poster x={240} y={266} c1="#1f7a3f" c2="#d2342a" t="VOTE" rot={2} />
        <Poster x={340} y={266} c1="#4a2a8a" c2="#f2c230" t="CRUSADE" rot={-2} />
        <Poster x={580} y={246} c1="#d2342a" c2="#1f1a26" t="SHOW!" rot={3} />
        {/* utility poles + sagging wires */}
        {[110, 420, 780].map((x) => (
          <g key={x}>
            <rect x={x - 3} y="104" width="6" height="210" fill="#5b3f2c" />
            <rect x={x - 18} y="112" width="36" height="4" fill="#4a3424" />
            <rect x={x + 1} y="104" width="2" height="210" fill={PAL.shadow} opacity="0.35" />
          </g>
        ))}
        {[-14, 0, 14].map((d) => (
          <g key={d} stroke="#2a2433" strokeWidth="0.9" fill="none" opacity="0.8">
            <path d={`M0 ${130 + d * 0.3} Q55 ${140 + d * 0.3} ${110 + d} 114`} />
            <path d={`M${110 + d} 114 Q265 ${150 + d * 0.5} ${420 + d} 114`} />
            <path d={`M${420 + d} 114 Q600 ${154 + d * 0.5} ${780 + d} 114`} />
          </g>
        ))}

        {/* gutter + sidewalk */}
        <rect x="0" y="298" width="800" height="22" fill="url(#street-side)" />
        <rect x="0" y="318" width="800" height="8" fill="#5a4a4a" />
        {[40, 140, 240, 340, 440, 540, 640, 740].map((x) => <rect key={x} x={x} y="318" width="60" height="5" fill="#9a8a7a" />)}
        {/* road */}
        <rect x="0" y="326" width="800" height="124" fill="url(#street-tar)" />
        <path d="M0 326 Q200 334 400 328 T800 330 L800 336 Q600 340 400 334 T0 334Z" fill="#c9875a" opacity="0.6" />
        {grit.map((g, i) => <circle key={i} cx={g.x} cy={g.y} r="1" fill="#9a8e9e" opacity="0.5" />)}
        {potholes.map(([x, y, w]) => (
          <g key={x}>
            <ellipse cx={x} cy={y} rx={w + 6} ry={w * 0.24 + 3} fill="#8a7a72" opacity="0.6" />
            <ellipse cx={x} cy={y} rx={w} ry={w * 0.24} fill={`url(#${P}-hole)`} />
            <ellipse cx={x - w * 0.3} cy={y - 2} rx={w * 0.3} ry="1.5" fill="#d9e4ff" opacity="0.35" />
          </g>
        ))}
        <path d="M0 390 L800 384" stroke="#e9dfa0" strokeWidth="2.5" strokeDasharray="26 22" opacity="0.4" />
        <path d="M560 340 l14 6 l-6 10 l12 4" stroke="#2e2a40" strokeWidth="1.2" fill="none" opacity="0.6" />

        <LampPost x={300} y={322} h={190} night={night} />
        <LampPost x={640} y={322} h={190} night={false} flip />
      </g>

      {night && (
        <g>
          {/* lantern/candle windows + generator glow */}
          <rect x="42" y="238" width="34" height="30" fill="#ffb35a" opacity="0.55" />
          <rect x="300" y="226" width="34" height="34" fill="#ffcf86" opacity="0.5" />
          <rect x="248" y="146" width="34" height="34" fill="#cfe6ff" opacity="0.35" />
          <rect x="542" y="238" width="34" height="30" fill="#ffb35a" opacity="0.4" />
          <rect x="640" y="248" width="92" height="34" fill="#ffe2a8" opacity="0.35" />
          <Glow p={P} kind="amber" cx={60} cy={254} rx={40} o={0.6} />
          <Glow p={P} kind="warm" cx={686} cy={266} rx={90} ry={50} o={0.6} />
          <Glow p={P} kind="warm" cx={686} cy={222} rx={80} ry={16} o={0.4} />
          {/* only one street light works */}
          <Glow p={P} kind="warm" cx={318} cy={124} rx={22} o={1} />
          <Glow p={P} kind="warm" cx={318} cy={350} rx={150} ry={48} o={0.75} />
          <path d="M312 128 L250 360 L390 360 L326 128Z" fill="#ffe2a0" opacity="0.08" />
          {/* deep shadows between pools */}
          <ellipse cx="500" cy="350" rx="140" ry="90" fill={`url(#${P}-dark)`} />
          <ellipse cx="120" cy="380" rx="140" ry="80" fill={`url(#${P}-dark)`} />
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {night ? (
          <>
            <Keke x={600} y={392} s={1.15} flip />
            <Person x={330} y={344} s={1.15} top="#2a5aa8" bottom="#2c2f5c" head="cap" headColor="#1b1424" skin="#4e2a18" arm="phone" />
            {/* figure lingering in the dark */}
            <Person x={500} y={330} s={1.05} top="#1a1424" bottom="#1a1424" head="cap" headColor="#1a1424" skin="#2a1a1a" />
            <rect x="490" y="268" width="1.5" height="2" fill="#ff7a3a" />
            <Car x={20} y={440} s={1.25} body="#c8ccd6" />
          </>
        ) : (
          <>
            <Keke x={80} y={378} s={1.15} />
            <Keke x={600} y={392} s={1.15} flip />
            <Car x={330} y={440} s={1.25} body="#f2c230" dark="#8a6a10" />
            <Person x={200} y={330} s={1.1} top={PAL.coral} wrapper bottom="#2a4d9b" head="tray" headColor="#1b1424" tray="#f2c230" skin="#6e3b22" />
            <Person x={460} y={332} s={1.1} top="#f4f4f4" bottom="#3a3340" head="hair" skin="#4e2a18" arm="phone" />
            <Person x={560} y={328} s={1.05} top="#1f7a3f" bottom="#d9cdb8" head="cap" headColor="#f2c230" skin="#5a301c" />
            <Person x={700} y={330} s={1.1} top="#8a3aa8" wrapper bottom="#8a3aa8" head="gele" headColor="#8a3aa8" skin="#6e3b22" />
            <Person x={740} y={446} s={1.4} top="#2a5aa8" bottom="#2c2f5c" head="hair" skin="#5a301c" flip />
          </>
        )}
      </g>

      {night && (
        <g>
          <Glow p={P} kind="warm" cx={604} cy={375} rx={30} ry={10} o={0.85} />
          <Glow p={P} kind="warm" cx={22} cy={420} rx={34} ry={12} o={0.85} />
          <Glow p={P} kind="red" cx={128} cy={420} rx={14} ry={7} o={0.9} />
          <Glow p={P} kind="cool" cx={326} cy={292} rx={10} o={0.8} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
