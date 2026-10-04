import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Keke, LampPost, Txt, PAL, rng } from './_sharedA';

const P = 'campus';

function LectureHall({ x, y, w, h, fins = 12 }: { x: number; y: number; w: number; h: number; fins?: number }) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} fill="#cbb79a" />
      <rect x={x} y={y - 6} width={w} height="8" fill="#8e5a3a" />
      {[0.33, 0.66].map((t) => (
        <rect key={t} x={x + 6} y={y + h * t - 8} width={w - 12} height="14" fill="#5b6f8c" opacity="0.85" />
      ))}
      {Array.from({ length: fins }, (_, i) => (
        <rect key={i} x={x + 6 + (i * (w - 16)) / (fins - 1)} y={y + 4} width="4" height={h - 8} fill="#e2d3bb" />
      ))}
      <rect x={x + w - 18} y={y} width="18" height={h} fill="#3b2a55" opacity="0.2" />
    </g>
  );
}

export default function CampusScene({ night }: { night: boolean }) {
  const r = rng(5);
  const hallLit = Array.from({ length: 10 }, () => r());
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="University campus gate">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-gate`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#f2e6cf" />
          <stop offset="0.5" stopColor="#e2cfae" />
          <stop offset="1" stopColor="#b9a089" />
        </linearGradient>
        <linearGradient id={`${P}-pillar`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#d58e5c" />
          <stop offset="0.35" stopColor="#b5552b" />
          <stop offset="0.8" stopColor="#8e3f1f" />
          <stop offset="1" stopColor="#5d2a2a" />
        </linearGradient>
        <linearGradient id={`${P}-road`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#8d8a96" />
          <stop offset="0.6" stopColor="#5f5b6e" />
          <stop offset="1" stopColor="#433d58" />
        </linearGradient>
        <linearGradient id={`${P}-grass`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7fb557" />
          <stop offset="0.5" stopColor="#4f8f3e" />
          <stop offset="1" stopColor="#2c6235" />
        </linearGradient>
        <pattern id={`${P}-tile`} patternUnits="userSpaceOnUse" width="14" height="10">
          <rect width="14" height="10" fill="#b5552b" />
          <path d="M0 0 H14 M0 5 H14 M7 0 V5 M0 5 V10 M14 5 V10" stroke="#e8a06a" strokeOpacity="0.35" strokeWidth="0.8" />
        </pattern>
      </defs>

      <Sky p={P} night={night} sun={[100, 72]} moon={[690, 66]} clouds={[[250, 62, 0.85], [560, 40, 0.55]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far campus */}
        <g opacity="0.8">
          <rect x="40" y="170" width="16" height="70" fill="#a8a3c0" />
          <ellipse cx="48" cy="166" rx="22" ry="12" fill="#a8a3c0" />
          <Tree x={110} y={250} s={0.8} dark="#7f9a8a" mid="#8fae96" light="#a9c4a6" />
          <Tree x={700} y={250} s={0.85} dark="#7f9a8a" mid="#8fae96" light="#a9c4a6" />
        </g>
        <Haze p={P} y={150} h={120} />
        <LectureHall x={250} y={176} w={300} h={78} fins={16} />
        <Tree x={250} y={262} s={0.75} />
        <Tree x={560} y={262} s={0.7} />
        <Haze p={P} y={200} h={90} o={0.6} />

        {/* ground: lawns + road through gate */}
        <rect x="0" y="262" width="800" height="188" fill="url(#campus-grass)" />
        <path d="M352 262 L448 262 L700 450 L100 450Z" fill="url(#campus-road)" />
        <path d="M352 262 L340 262 L80 450 L100 450Z" fill="#d9cdb8" />
        <path d="M448 262 L460 262 L720 450 L700 450Z" fill="#b8ab98" />
        <path d="M400 268 L400 282 M400 296 L400 316 M400 334 L400 362 M400 384 L400 420" stroke="#f2e3a0" strokeWidth="3" />
        {/* black & white kerbs */}
        <path d="M352 262 L100 450" stroke="#f4f1ea" strokeWidth="5" />
        <path d="M352 262 L100 450" stroke="#2a2433" strokeWidth="5" strokeDasharray="10 10" />
        <path d="M448 262 L700 450" stroke="#f4f1ea" strokeWidth="5" />
        <path d="M448 262 L700 450" stroke="#2a2433" strokeWidth="5" strokeDasharray="10 10" />
        {Array.from({ length: 30 }, (_, i) => {
          const q = rng(i * 13 + 3);
          const gx = q() * 800;
          const gy = 300 + q() * 150;
          if (gx > 344 - (gy - 262) * 1.34 && gx < 456 + (gy - 262) * 1.34) return null;
          return <path key={i} d={`M${gx.toFixed(0)} ${gy.toFixed(0)} l-3 -6 M${gx.toFixed(0)} ${gy.toFixed(0)} l0 -8 M${gx.toFixed(0)} ${gy.toFixed(0)} l3 -6`} stroke="#2c6235" strokeWidth="1.4" />;
        })}
        {[[60, 330], [740, 352], [700, 330]].map(([fx, fy]) => (
          <g key={fx}>
            <circle cx={fx} cy={fy} r="2.4" fill="#f2c230" />
            <circle cx={fx + 6} cy={fy + 2} r="2.4" fill="#d2342a" />
            <circle cx={fx + 3} cy={fy - 3} r="2" fill="#fff" />
          </g>
        ))}
        {/* ochre footpaths */}
        <path d="M0 330 Q150 320 330 300 L338 306 Q160 332 0 350Z" fill="#c98a5a" opacity="0.85" />
        <path d="M800 340 Q650 326 470 300 L462 306 Q640 336 800 362Z" fill="#c98a5a" opacity="0.85" />

        {/* gate */}
        <g filter={`url(#${P}-drop)`}>
          <rect x="190" y="160" width="58" height="150" fill="url(#campus-pillar)" />
          <rect x="552" y="160" width="58" height="150" fill="url(#campus-pillar)" />
          <rect x="190" y="160" width="58" height="150" fill="url(#campus-tile)" opacity="0.5" />
          <rect x="552" y="160" width="58" height="150" fill="url(#campus-tile)" opacity="0.5" />
          <path d="M170 122 L630 122 L630 168 Q400 150 170 168Z" fill="url(#campus-gate)" />
          <path d="M170 116 L630 116 L630 124 L170 124Z" fill={PAL.ects} />
          <path d="M170 168 Q400 150 630 168 L630 174 Q400 156 170 174Z" fill={PAL.bronze} />
          <rect x="174" y="296" width="90" height="16" fill="#8e3f1f" />
          <rect x="536" y="296" width="90" height="16" fill="#8e3f1f" />
          <circle cx="400" cy="96" r="22" fill={PAL.gold} />
          <circle cx="400" cy="96" r="17" fill={PAL.ects} />
          <path d="M392 88 L408 88 L408 102 Q400 108 392 102Z" fill={PAL.gold} />
          <path d="M396 92 h8 M396 96 h8" stroke={PAL.ects} strokeWidth="1.5" />
          <rect x="396" y="116" width="8" height="6" fill={PAL.gold} />
          <Txt x={400} y={145} size={20} fill="#1f5a34" spacing={2}>UNIVERSITY OF BENIN</Txt>
          <Txt x={400} y={160} size={8} fill="#6b3a24" spacing={3} family="Arial, sans-serif">UGBOWO CAMPUS • KNOWLEDGE FOR SERVICE</Txt>
        </g>
        {/* gatehouse + boom barrier */}
        <rect x="620" y="250" width="70" height="56" fill="#efe4cf" />
        <path d="M612 250 L698 250 L690 238 L620 238Z" fill="#2f6f3a" />
        <rect x="632" y="262" width="22" height="16" fill="#4e6a8c" />
        <rect x="664" y="266" width="16" height="40" fill="#6b4a32" />
        <rect x="676" y="250" width="14" height="56" fill="#3b2a55" opacity="0.18" />
        <rect x="548" y="282" width="6" height="26" fill="#3a3a4a" />
        <path d="M452 284 L552 284" stroke="#d2342a" strokeWidth="5" strokeDasharray="12 12" />
        <path d="M452 284 L552 284" stroke="#fff" strokeWidth="5" strokeDasharray="12 12" strokeDashoffset="12" />

        {/* notice board */}
        <g>
          <rect x="70" y="282" width="5" height="40" fill="#5a3826" />
          <rect x="140" y="282" width="5" height="40" fill="#5a3826" />
          <rect x="62" y="248" width="92" height="44" fill="#3a5a3a" />
          <rect x="62" y="248" width="92" height="44" fill="none" stroke="#7a5233" strokeWidth="3" />
          <rect x="68" y="254" width="26" height="18" fill="#f6ecd2" transform="rotate(-4 81 263)" />
          <rect x="98" y="256" width="24" height="30" fill="#f2c230" />
          <rect x="126" y="254" width="22" height="16" fill="#d2342a" transform="rotate(5 137 262)" />
          <rect x="70" y="276" width="22" height="12" fill="#cfe2ff" />
          <Txt x={110} y={268} size={5} fill="#1f1a26" family="Arial, sans-serif">SUG VOTE</Txt>
          <Txt x={137} y={264} size={4} fill="#fff" family="Arial, sans-serif">EXAMS</Txt>
        </g>

        <LampPost x={300} y={330} h={120} night={night} />
        <LampPost x={505} y={320} h={110} night={night} flip />

        <Keke x={120} y={372} s={1.05} />
        <Tree x={30} y={430} s={1.5} />
        <Tree x={760} y={420} s={1.4} dark="#245e36" />

        {/* students */}
        <Person x={330} y={330} s={0.8} top="#ffffff" bottom="#2c2f5c" head="hair" skin="#6e3b22" arm="hold" hold="#2a4d9b" />
        <Person x={470} y={322} s={0.75} top="#d2342a" bottom="#2c2f5c" head="hair" skin="#4e2a18" />
        <Person x={490} y={325} s={0.75} top="#f2c230" wrapper bottom="#1f2f6b" head="hair" skin="#7a4428" arm="phone" />
        <Person x={268} y={392} s={1.3} top="#1f7a3f" bottom="#2a2a3a" head="cap" headColor="#1f2f6b" skin="#5a301c" arm="hold" hold="#f6ecd2" />
        <Person x={300} y={398} s={1.3} top="#f6ecd2" wrapper bottom="#7a2a7a" head="hair" skin="#6e3b22" arm="phone" />
        <Person x={560} y={410} s={1.35} top="#2a4d9b" bottom="#d9cdb8" head="hair" skin="#5a301c" />
        <Person x={590} y={414} s={1.35} flip top="#e86a1c" wrapper bottom="#2c2f5c" head="hair" skin="#7a4428" arm="hold" hold="#d2342a" />
        <Person x={655} y={392} s={1.15} top="#ffffff" bottom="#3a3a4a" head="beret" headColor="#1f7a3f" skin="#4e2a18" />
      </g>

      {night && (
        <g>
          {hallLit.map((v, i) =>
            v > 0.45 ? <rect key={i} x={256 + i * 29} y={192} width="22" height="14" fill="#ffe2a8" opacity="0.75" /> : null,
          )}
          {hallLit.map((v, i) =>
            v < 0.4 ? <rect key={`b${i}`} x={256 + i * 29} y={218} width="22" height="14" fill="#cfe6ff" opacity="0.6" /> : null,
          )}
          <Glow p={P} kind="warm" cx={400} cy={140} rx={250} ry={50} o={0.55} />
          <Txt x={400} y={145} size={20} fill="#fff1c4" spacing={2}>UNIVERSITY OF BENIN</Txt>
          <Glow p={P} kind="warm" cx={322} cy={204} rx={22} o={1} />
          <Glow p={P} kind="warm" cx={318} cy={338} rx={110} ry={34} o={0.65} />
          <Glow p={P} kind="warm" cx={483} cy={204} rx={22} o={1} />
          <Glow p={P} kind="warm" cx={480} cy={325} rx={100} ry={30} o={0.65} />
          <rect x="632" y="262" width="22" height="16" fill="#ffd27a" opacity="0.9" />
          <Glow p={P} kind="warm" cx={643} cy={275} rx={50} o={0.6} />
          <Glow p={P} kind="warm" cx={124} cy={354} rx={22} ry={12} o={0.9} />
          <Glow p={P} kind="cool" cx={286} cy={340} rx={10} o={0.8} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
