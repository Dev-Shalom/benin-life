import { CommonDefs, Finish, Glow, Haze, Person, Sky, Palm, Car, LampPost, Txt, PAL, rng } from './_sharedA';

const P = 'club';

/** Neon text: at night a blurred halo copy sits behind the crisp tube colour. */
function Neon({ x, y, size, color, night, children, spacing = 3 }: { x: number; y: number; size: number; color: string; night: boolean; children: string; spacing?: number }) {
  return (
    <g>
      {night && (
        <text x={x} y={y} fontSize={size} textAnchor="middle" fontWeight={900} letterSpacing={spacing} fontFamily="Arial Black, Arial, Helvetica, sans-serif"
          fill={color} stroke={color} strokeWidth="3" filter={`url(#${P}-soft)`} opacity="0.9">{children}</text>
      )}
      <text x={x} y={y} fontSize={size} textAnchor="middle" fontWeight={900} letterSpacing={spacing} fontFamily="Arial Black, Arial, Helvetica, sans-serif"
        fill={night ? '#fff4fb' : color} stroke={night ? color : '#3a2340'} strokeWidth={night ? 1.2 : 0.6}>{children}</text>
    </g>
  );
}

function SuyaStand({ x, y, night }: { x: number; y: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <ellipse cx="22" cy="2" rx="34" ry="4" fill={PAL.shadow} opacity="0.4" />
      {/* smoke */}
      <path d="M10 -40 Q2 -58 14 -70 Q24 -82 12 -98" stroke="#d8d2e0" strokeWidth="9" strokeLinecap="round" fill="none" opacity={night ? 0.18 : 0.35} />
      <path d="M26 -42 Q36 -60 26 -76" stroke="#d8d2e0" strokeWidth="6" strokeLinecap="round" fill="none" opacity={night ? 0.14 : 0.28} />
      <rect x="0" y="-34" width="48" height="6" fill="#3a3340" />
      <rect x="2" y="-28" width="44" height="26" fill="#6b4a36" />
      <rect x="2" y="-28" width="44" height="5" fill="#2d1b4e" opacity="0.3" />
      <rect x="4" y="-2" width="4" height="4" fill="#3a3340" />
      <rect x="40" y="-2" width="4" height="4" fill="#3a3340" />
      {[6, 14, 22, 30, 38].map((sx) => (
        <path key={sx} d={`M${sx} -36 L${sx + 6} -36`} stroke="#8a3a1a" strokeWidth="3" strokeLinecap="round" />
      ))}
      <rect x="0" y="-36" width="48" height="2" fill={night ? '#ff8a3a' : '#e04a1a'} opacity="0.9" />
      <rect x="6" y="-58" width="36" height="12" fill="#f2c230" />
      <Txt x={24} y={-49} size={8} fill="#7a1f12" family="Arial, sans-serif" weight={900}>SUYA</Txt>
      <rect x="22" y="-46" width="2" height="10" fill="#3a3340" />
    </g>
  );
}

export default function ClubScene({ night }: { night: boolean }) {
  const r = rng(31);
  const dancers = Array.from({ length: 11 }, (_, i) => ({ x: 236 + i * 32 + r() * 10, s: 0.8 + r() * 0.25, up: r() > 0.45, flip: r() > 0.5 }));
  const bulbs = Array.from({ length: 22 }, (_, i) => i);
  const bulbCol = ['#ff4fc0', '#ffd27a', '#3ff0e0', '#ffd27a'];
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Bronze Lounge nightclub">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-clad`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#4a3a5c" />
          <stop offset="0.35" stopColor="#3a2b4e" />
          <stop offset="1" stopColor="#231a36" />
        </linearGradient>
        <linearGradient id={`${P}-slat`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#e2b066" />
          <stop offset="0.5" stopColor={PAL.bronze} />
          <stop offset="1" stopColor="#6e4418" />
        </linearGradient>
        <linearGradient id={`${P}-glassDay`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#7d9cc4" />
          <stop offset="0.4" stopColor="#3e4f78" />
          <stop offset="0.55" stopColor="#5c76a4" />
          <stop offset="1" stopColor="#2a2f52" />
        </linearGradient>
        <linearGradient id={`${P}-inside`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3a0f5a" />
          <stop offset="0.45" stopColor="#a0207a" />
          <stop offset="0.8" stopColor="#ff4f9a" />
          <stop offset="1" stopColor="#ffb36b" />
        </linearGradient>
        <linearGradient id={`${P}-beam`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor="#e9d4ff" stopOpacity="0.55" />
          <stop offset="1" stopColor="#e9d4ff" stopOpacity="0" />
        </linearGradient>
        <linearGradient id={`${P}-pave`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#a49aa6" />
          <stop offset="0.5" stopColor="#7e7488" />
          <stop offset="1" stopColor="#544a66" />
        </linearGradient>
        <pattern id={`${P}-paver`} patternUnits="userSpaceOnUse" width="24" height="12">
          <path d="M0 0 H24 M0 6 H24 M6 0 V6 M18 6 V12" stroke="#3b3150" strokeOpacity="0.25" strokeWidth="1" />
        </pattern>
      </defs>

      <Sky p={P} night={night} sun={[690, 70]} moon={[96, 62]} clouds={[[220, 60, 0.7], [520, 40, 0.5]]} />

      {/* searchlight beams (night) behind everything */}
      {night && (
        <g style={{ mixBlendMode: 'screen' }}>
          <path d="M300 112 L180 0 L232 0Z" fill={`url(#${P}-beam)`} />
          <path d="M520 112 L600 0 L660 0Z" fill={`url(#${P}-beam)`} />
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* neighbours */}
        <g>
          <rect x="0" y="150" width="170" height="160" fill="#c9a98a" />
          <rect x="0" y="142" width="176" height="10" fill="#8e5a3a" />
          {[20, 70, 120].map((x) => (
            <g key={x}>
              <rect x={x} y="172" width="30" height="34" fill="#4d5c7a" />
              <rect x={x} y="230" width="30" height="34" fill="#4d5c7a" />
              <rect x={x - 2} y="170" width="34" height="3" fill="#efe1cc" />
            </g>
          ))}
          <rect x="140" y="150" width="30" height="160" fill="#2d1b4e" opacity="0.18" />
          <rect x="640" y="170" width="160" height="140" fill="#e1c7a1" />
          <path d="M630 172 L710 140 L810 172Z" fill="#9aa3ad" />
          <rect x="660" y="200" width="44" height="40" fill="#4d5c7a" />
          <rect x="726" y="200" width="44" height="40" fill="#4d5c7a" />
          <rect x="660" y="262" width="110" height="48" fill="#7d7f8a" />
          {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => (
            <rect key={i} x={662 + i * 11} y="262" width="2" height="48" fill="#5d5f6a" />
          ))}
          <rect x="640" y="170" width="16" height="140" fill="#2d1b4e" opacity="0.15" />
        </g>
        <Haze p={P} y={120} h={150} o={0.7} />

        {/* club building */}
        <rect x="176" y="96" width="460" height="214" fill="url(#club-clad)" />
        <rect x="170" y="88" width="472" height="12" fill="#1c1428" />
        {[260, 320, 380, 440, 500, 560].map((x) => (
          <rect key={x} x={x} y="100" width="1" height="120" fill="#5a4a70" opacity="0.5" />
        ))}
        {/* rooftop AC units */}
        {[250, 540].map((x) => (
          <g key={x}>
            <rect x={x} y="74" width="30" height="14" fill="#c9cbd6" />
            <circle cx={x + 10} cy="81" r="5" fill="#8a8c9a" />
            <rect x={x + 20} y="74" width="10" height="14" fill="#2d1b4e" opacity="0.2" />
          </g>
        ))}
        {/* bronze slat columns */}
        {[188, 200, 212, 600, 612, 624].map((x) => (
          <rect key={x} x={x} y="104" width="6" height="200" fill="url(#club-slat)" />
        ))}
        {/* sign fascia */}
        <rect x="232" y="112" width="348" height="54" rx="4" fill="#1a1224" />
        <rect x="236" y="116" width="340" height="46" rx="3" fill="none" stroke={night ? '#ff4fc0' : '#8a4a7a'} strokeWidth="1.5" />
        <Neon x={406} y={150} size={30} color="#ff4fc0" night={night}>BRONZE LOUNGE</Neon>
        {/* upper terrace */}
        <rect x="232" y="176" width="348" height="34" fill="#2a2038" />
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <rect key={i} x={244 + i * 56} y="180" width="44" height="26" fill={night ? '#5a2a7a' : 'url(#club-glassDay)'} />
        ))}
        <rect x="226" y="206" width="360" height="5" fill="#9a9aa8" />
        {Array.from({ length: 30 }, (_, i) => (
          <rect key={i} x={230 + i * 12} y="196" width="1.5" height="10" fill="#9a9aa8" />
        ))}
        <rect x="226" y="195" width="360" height="2" fill="#b8b8c6" />
        {/* string lights across terrace */}
        <path d="M232 178 Q320 192 406 178 Q492 192 580 178" stroke="#3a3340" strokeWidth="1" fill="none" />
        {bulbs.map((i) => {
          const t = i / 21;
          const bx = 232 + t * 348;
          const local = (t * 2) % 1;
          const by = 178 + Math.sin(local * Math.PI) * 13;
          return <circle key={i} cx={bx} cy={by + 1.5} r="1.8" fill={night ? bulbCol[i % 4] : '#f2ead8'} />;
        })}

        {/* ground-floor glass: interior */}
        <rect x="232" y="220" width="348" height="90" fill={night ? 'url(#club-inside)' : 'url(#club-glassDay)'} />
        {!night && (
          <g>
            <path d="M250 220 L300 220 L250 300Z" fill="#dfeaff" opacity="0.18" />
            <path d="M420 220 L450 220 L380 310 L360 310Z" fill="#dfeaff" opacity="0.14" />
            {/* stacked chairs + resting DJ booth visible through glass */}
            <rect x="370" y="268" width="72" height="26" fill="#1f1830" opacity="0.7" />
            <rect x="378" y="262" width="56" height="6" fill="#2e2440" opacity="0.7" />
          </g>
        )}
        {night && (
          <g>
            {/* DJ booth */}
            <rect x="366" y="262" width="80" height="34" fill="#160c26" />
            <rect x="366" y="262" width="80" height="4" fill="#3ff0e0" />
            <circle cx="386" cy="258" r="7" fill="#251838" />
            <circle cx="426" cy="258" r="7" fill="#251838" />
            <Person x={406} y={262} s={0.75} top="#140a22" bottom="#140a22" skin="#140a22" head="cap" headColor="#140a22" arm="up" />
            {dancers.map((d, i) => (
              <Person key={i} x={d.x} y={312} s={d.s} flip={d.flip} top="#1a0d2c" bottom="#1a0d2c" skin="#1a0d2c" head={i % 3 ? 'hair' : 'gele'} headColor="#1a0d2c" wrapper={i % 3 === 0} arm={d.up ? 'up' : 'out'} />
            ))}
          </g>
        )}
        {/* mullions */}
        {[290, 348, 464, 522].map((x) => (
          <rect key={x} x={x} y="220" width="3" height="90" fill="#1c1428" />
        ))}
        {/* entrance canopy + door */}
        <rect x="380" y="222" width="52" height="88" fill={night ? '#2a0d3a' : '#1c1428'} opacity={night ? 0.55 : 1} />
        <rect x="370" y="214" width="72" height="8" fill="url(#club-slat)" />
        {!night && (
          <g>
            <rect x="392" y="244" width="28" height="14" fill="#f6efe2" />
            <Txt x={406} y={252} size={4.5} fill="#7a1f12" family="Arial, sans-serif" weight={900}>CLOSED</Txt>
            <Txt x={406} y={257} size={3.6} fill="#3a3340" family="Arial, sans-serif" weight={700}>OPENS 9PM</Txt>
          </g>
        )}
        <rect x="600" y="96" width="36" height="214" fill="#120a20" opacity="0.25" />

        {/* forecourt */}
        <rect x="0" y="306" width="800" height="144" fill="url(#club-pave)" />
        <rect x="0" y="306" width="800" height="144" fill="url(#club-paver)" />
        <rect x="0" y="306" width="800" height="6" fill="#cfc6cc" />
        {/* red carpet + rope */}
        <path d="M384 310 L428 310 L452 372 L360 372Z" fill="#a8162a" />
        <path d="M384 310 L392 310 L372 372 L360 372Z" fill="#d2342a" opacity="0.6" />
        {[338, 470].map((x) => (
          <g key={x}>
            <rect x={x - 2} y="334" width="4" height="26" fill={PAL.gold} />
            <circle cx={x} cy="333" r="3.5" fill={PAL.gold} />
          </g>
        ))}
        <path d="M338 338 Q350 350 362 340" stroke="#a8162a" strokeWidth="3" fill="none" />
        <path d="M450 340 Q460 350 470 338" stroke="#a8162a" strokeWidth="3" fill="none" />
        {/* potted palms */}
        <Palm x={214} y={318} s={0.7} lean={-0.5} />
        <Palm x={600} y={318} s={0.7} lean={0.5} />
        {[214, 600].map((x) => (
          <path key={x} d={`M${x - 14} 318 L${x + 14} 318 L${x + 10} 338 L${x - 10} 338Z`} fill="#3a2b4e" />
        ))}
      </g>

      {/* night emissives (before foreground figures) */}
      {night && (
        <g>
          <Glow p={P} kind="pink" cx={406} cy={140} rx={240} ry={70} o={0.55} />
          <Neon x={406} y={150} size={30} color="#ff4fc0" night>BRONZE LOUNGE</Neon>
          <rect x="236" y="116" width="340" height="46" rx="3" fill="none" stroke="#3ff0e0" strokeWidth="2" />
          <Glow p={P} kind="pink" cx={406} cy={300} rx={260} ry={80} o={0.5} />
          <Glow p={P} kind="teal" cx={406} cy={265} rx={70} ry={30} o={0.8} />
          <Glow p={P} kind="pink" cx={406} cy={350} rx={200} ry={40} o={0.55} />
          <Glow p={P} kind="teal" cx={250} cy={360} rx={120} ry={30} o={0.35} />
          {bulbs.map((i) => {
            const t = i / 21;
            const bx = 232 + t * 348;
            const by = 178 + Math.sin(((t * 2) % 1) * Math.PI) * 13;
            return <Glow key={i} p={P} kind={i % 2 ? 'warm' : 'pink'} cx={bx} cy={by + 1.5} rx={7} o={0.9} />;
          })}
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <rect key={i} x={244 + i * 56} y="180" width="44" height="26" fill="#ff7ac8" opacity={0.25 + (i % 2) * 0.15} />
          ))}
        </g>
      )}

      <g filter={night ? `url(#${P}-night)` : undefined}>
        <SuyaStand x={110} y={360} night={night} />
        {/* plastic table + chairs */}
        <g>
          <ellipse cx="120" cy="436" rx="80" ry="8" fill={PAL.shadow} opacity="0.35" />
          <rect x="88" y="400" width="64" height="5" rx="2" fill="#f4f4f6" />
          <rect x="116" y="405" width="6" height="30" fill="#d9dae2" />
          <rect x="104" y="390" width="7" height="10" rx="1" fill="#2a7a3f" />
          <rect x="128" y="392" width="7" height="8" rx="1" fill="#c8a24a" />
          {[[60, 1], [180, -1]].map(([cx, d]) => (
            <g key={cx} transform={`translate(${cx} 438) scale(${d} 1)`}>
              <path d="M-14 -46 Q-16 -30 -12 -22 L14 -22 L14 -26 L-8 -26 Q-10 -34 -8 -46Z" fill="#d2342a" />
              <rect x="-14" y="-24" width="30" height="4" fill="#e04a3a" />
              <path d="M-12 -20 L-14 0 M14 -20 L16 0" stroke="#a8222a" strokeWidth="3" />
            </g>
          ))}
        </g>
        <LampPost x={700} y={360} h={130} night={night} flip />
        <Car x={520} y={430} s={1.25} body="#1e1e28" dark="#0f0f16" />
        {/* bouncer + guests */}
        <Person x={330} y={362} s={1.2} top="#141018" bottom="#141018" skin="#3d2014" head="hair" arm="hold" hold="#141018" />
        {night ? (
          <>
            <Person x={482} y={364} s={1.15} top="#d2342a" wrapper bottom="#d2342a" skin="#5a301c" head="hair" arm="phone" />
            <Person x={505} y={366} s={1.2} top="#f4f4f4" bottom="#2c2f5c" skin="#4e2a18" head="cap" headColor="#141018" />
            <Person x={528} y={364} s={1.15} top={PAL.gold} wrapper bottom="#1f1830" skin="#6e3b22" head="gele" headColor={PAL.gold} />
            <Person x={551} y={368} s={1.2} top="#2a5aa8" bottom="#d9cdb8" skin="#5a301c" head="hair" arm="phone" />
          </>
        ) : (
          <>
            <Person x={176} y={366} s={1.15} top="#1f7a3f" bottom="#2c2f5c" skin="#4e2a18" head="cap" headColor="#f2c230" />
            <Person x={470} y={360} s={1.1} top="#f4f4f4" bottom="#3a3340" skin="#5a301c" head="hair" arm="hold" hold="#e9e2d0" />
          </>
        )}
      </g>

      {night && (
        <g>
          <Glow p={P} kind="amber" cx={134} cy={325} rx={40} ry={22} o={0.9} />
          <Glow p={P} kind="warm" cx={680} cy={226} rx={20} o={1} />
          <Glow p={P} kind="warm" cx={680} cy={362} rx={100} ry={28} o={0.5} />
          <Glow p={P} kind="warm" cx={556} cy={399} rx={30} ry={10} o={0.6} />
          <Glow p={P} kind="red" cx={630} cy={404} rx={14} ry={7} o={0.9} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
