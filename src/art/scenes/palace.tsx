import { CommonDefs, Finish, Glow, Haze, Person, Sky, Tree, Palm, PAL, rng } from './_sharedA';

const P = 'palace';

/** Steep stepped pyramidal turret, lit from the left. */
function Turret({ cx, base, w, h, finial = true }: { cx: number; base: number; w: number; h: number; finial?: boolean }) {
  const tiers = 3;
  const out = [];
  for (let i = 0; i < tiers; i++) {
    const t0 = i / tiers;
    const t1 = (i + 1) / tiers;
    const y0 = base - h * t0;
    const y1 = base - h * t1 + (i < tiers - 1 ? 4 : 0);
    const w0 = (w / 2) * (1 - t0 * 0.85);
    const w1 = (w / 2) * (1 - t1 * 0.85) + (i < tiers - 1 ? 3 : 0);
    out.push(
      <g key={i}>
        <path d={`M${cx - w0} ${y0} L${cx - w1} ${y1} L${cx} ${y1} L${cx} ${y0}Z`} fill={`url(#${P}-roofL)`} />
        <path d={`M${cx} ${y0} L${cx} ${y1} L${cx + w1} ${y1} L${cx + w0} ${y0}Z`} fill={`url(#${P}-roofR)`} />
        <rect x={cx - w0 - 2} y={y0 - 3} width={w0 * 2 + 4} height="4" fill="#5a2418" />
        <rect x={cx - w0 - 2} y={y0 - 3} width={w0 + 2} height="1.3" fill="#f0a56e" opacity="0.6" />
      </g>,
    );
  }
  return (
    <g>
      {out}
      {finial && (
        <g transform={`translate(${cx} ${base - h})`}>
          <rect x="-1.5" y="-12" width="3" height="12" fill={PAL.bronze} />
          {/* bronze bird of prophecy */}
          <path d="M-9 -14 Q-2 -22 4 -18 L10 -21 L7 -16 Q4 -11 -4 -12 Z" fill="url(#palace-bronze)" />
          <circle cx="3" cy="-18" r="0.9" fill="#3a1c10" />
        </g>
      )}
    </g>
  );
}

function Plaque({ x, y, s = 1, kind = 0 }: { x: number; y: number; s?: number; kind?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="-9" y="-12" width="18" height="24" rx="1" fill="url(#palace-bronze)" />
      <rect x="-9" y="-12" width="18" height="24" rx="1" fill="none" stroke="#5e3a16" strokeWidth="1" />
      <circle cx="0" cy="-6" r="2.6" fill="#6e4418" />
      <path d="M-3 -3 L3 -3 L4 7 L-4 7Z" fill="#6e4418" />
      {kind % 2 === 0 ? <ellipse cx="-5" cy="1" rx="2.2" ry="4" fill="#6e4418" /> : <path d="M4 -2 L7 -8" stroke="#6e4418" strokeWidth="1.4" />}
      <path d="M-3.4 -9 L3.4 -9" stroke="#f3d08a" strokeWidth="0.8" opacity="0.8" />
      <circle cx="-6" cy="-9" r="0.8" fill="#f3d08a" />
      <circle cx="6" cy="9" r="0.8" fill="#5e3a16" />
    </g>
  );
}

function Guard({ x, y, s }: { x: number; y: number; s: number }) {
  return (
    <g>
      <Person x={x} y={y} s={s} top="#c2261f" wrapper bottom="#f4efe6" head="beret" headColor="#c2261f" skin="#4e2a18" />
      <line x1={x - 9 * s} y1={y - 72 * s} x2={x - 9 * s} y2={y} stroke="#6e4418" strokeWidth={1.6 * s} />
      <path d={`M${x - 9 * s} ${y - 72 * s} l-2.5 -6 l2.5 -2 l2.5 2Z`} fill={PAL.bronze} />
      <path d={`M${x - 4 * s} ${y - 47 * s} Q${x} ${y - 42 * s} ${x + 4 * s} ${y - 47 * s}`} stroke="#ff6a4a" strokeWidth={1.6 * s} fill="none" strokeDasharray={`${1.2 * s} ${0.8 * s}`} />
    </g>
  );
}

export default function PalaceScene({ night }: { night: boolean }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="The Oba's Palace, Benin City">
      <defs>
        <CommonDefs p={P} night={night} />
        <linearGradient id={`${P}-bronze`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#f3d08a" />
          <stop offset="0.3" stopColor="#d9a441" />
          <stop offset="0.65" stopColor="#b0793a" />
          <stop offset="1" stopColor="#6e4418" />
        </linearGradient>
        <linearGradient id={`${P}-roofL`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c86a3e" />
          <stop offset="1" stopColor="#9a3f22" />
        </linearGradient>
        <linearGradient id={`${P}-roofR`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6a2a2a" />
          <stop offset="1" stopColor="#4a1f30" />
        </linearGradient>
        <pattern id={`${P}-ridge`} patternUnits="userSpaceOnUse" width="40" height="9">
          <rect width="40" height="9" fill="#b5552b" />
          <rect width="40" height="2" fill="#e08a5a" opacity="0.75" />
          <rect y="6.5" width="40" height="2.5" fill="#6e2a1e" opacity="0.55" />
        </pattern>
        <linearGradient id={`${P}-wallShade`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#ffd9a8" stopOpacity="0.18" />
          <stop offset="0.5" stopColor="#ffd9a8" stopOpacity="0" />
          <stop offset="1" stopColor="#2d1b4e" stopOpacity="0.3" />
        </linearGradient>
        <linearGradient id={`${P}-court`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d9946a" />
          <stop offset="0.5" stopColor="#c0703f" />
          <stop offset="1" stopColor="#8e3f1f" />
        </linearGradient>
        <linearGradient id={`${P}-door`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#5a3020" />
          <stop offset="0.5" stopColor="#7a4428" />
          <stop offset="1" stopColor="#3e2030" />
        </linearGradient>
      </defs>

      <Sky p={P} night={night} sun={[110, 78]} moon={[640, 64]} clouds={[[240, 56, 0.7], [680, 120, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far canopy */}
        <g opacity="0.75">
          <Tree x={40} y={236} s={0.9} dark="#6f8f7a" mid="#86a48d" light="#a6bf9f" />
          <Tree x={770} y={236} s={0.95} dark="#6f8f7a" mid="#86a48d" light="#a6bf9f" />
          <Palm x={720} y={232} s={0.7} tone="#7f9e86" />
        </g>
        <Haze p={P} y={150} h={110} />

        {/* outer wall */}
        <rect x="0" y="210" width="800" height="100" fill={`url(#${P}-ridge)`} />
        <rect x="0" y="210" width="800" height="100" fill={`url(#${P}-wallShade)`} />
        <rect x="0" y="204" width="800" height="8" fill="#8e3f1f" />
        <rect x="0" y="204" width="800" height="2" fill="#f0a56e" opacity="0.6" />
        {[60, 110, 160, 640, 690, 740].map((x, i) => (
          <Plaque key={x} x={x} y={258} s={1} kind={i} />
        ))}

        {/* side towers */}
        {[150, 650].map((cx) => (
          <g key={cx}>
            <rect x={cx - 42} y="150" width="84" height="160" fill={`url(#${P}-ridge)`} />
            <rect x={cx - 42} y="150" width="84" height="160" fill={`url(#${P}-wallShade)`} />
            <rect x={cx - 46} y="146" width="92" height="6" fill="#7a3418" />
            <Turret cx={cx} base={147} w={92} h={74} />
            <path d={`M${cx - 12} 310 L${cx - 12} 262 Q${cx} 248 ${cx + 12} 262 L${cx + 12} 310Z`} fill="#3e2030" />
            <Plaque x={cx} y={200} s={1.1} kind={cx} />
          </g>
        ))}

        {/* central gate pavilion */}
        <g>
          <rect x="290" y="120" width="220" height="190" fill={`url(#${P}-ridge)`} />
          <rect x="290" y="120" width="220" height="190" fill={`url(#${P}-wallShade)`} />
          <rect x="284" y="114" width="232" height="8" fill="#7a3418" />
          <rect x="284" y="114" width="232" height="2" fill="#f0a56e" opacity="0.7" />
          <Turret cx={400} base={115} w={236} h={86} />
          {/* plaque frieze */}
          <rect x="300" y="130" width="200" height="34" fill="#7a3418" opacity="0.5" />
          {[318, 345, 372, 400, 428, 455, 482].map((x, i) => (
            <Plaque key={x} x={x} y={147} s={0.95} kind={i} />
          ))}
          {/* python motif */}
          <path d="M300 174 Q312 166 324 174 T348 174 T372 174 T396 174 T420 174 T444 174 T468 174 T492 174 T500 172" stroke="url(#palace-bronze)" strokeWidth="3.5" fill="none" />
          {/* great doorway */}
          <path d="M346 310 L346 222 Q400 182 454 222 L454 310Z" fill="#5d2a2a" />
          <path d="M352 310 L352 226 Q400 190 448 226 L448 310Z" fill="url(#palace-door)" />
          <line x1="400" y1="200" x2="400" y2="310" stroke="#2d1820" strokeWidth="2" />
          {[0, 1, 2, 3, 4, 5].map((r) =>
            [0, 1, 2, 3].map((c) => (
              <circle key={`${r}-${c}`} cx={362 + c * 25.5} cy={236 + r * 12} r="1.6" fill={PAL.gold} />
            )),
          )}
          <path d="M346 222 Q400 182 454 222" stroke={PAL.gold} strokeWidth="2.5" fill="none" />
          {/* coral bead garlands */}
          <path d="M346 222 Q372 236 400 226 Q428 236 454 222" stroke="#e0402a" strokeWidth="3" strokeDasharray="2.5 1.5" fill="none" />
          <path d="M346 214 Q372 228 400 218 Q428 228 454 214" stroke="#e0402a" strokeWidth="2.4" strokeDasharray="2.5 1.5" fill="none" opacity="0.8" />
          {/* pilasters */}
          {[300, 322, 470, 492].map((x) => (
            <g key={x}>
              <rect x={x} y="190" width="10" height="120" fill="#c8673a" />
              <rect x={x + 6} y="190" width="4" height="120" fill="#4a1f30" opacity="0.35" />
              <rect x={x - 2} y="186" width="14" height="5" fill={PAL.bronze} />
            </g>
          ))}
          <rect x="505" y="120" width="5" height="190" fill="#2d1b4e" opacity="0.2" />
        </g>

        {/* steps + courtyard */}
        <rect x="0" y="308" width="800" height="142" fill={`url(#${P}-court)`} />
        <path d="M330 310 L470 310 L480 318 L320 318Z" fill="#d9a07a" />
        <path d="M320 318 L480 318 L492 328 L308 328Z" fill="#c78a62" />
        <path d="M308 328 L492 328 L506 340 L294 340Z" fill="#b5754e" />
        <path d="M294 340 L506 340 L520 450 L280 450Z" fill="#c9845a" opacity="0.55" />
        <path d="M400 340 L410 450 M360 340 L340 450 M440 340 L462 450" stroke="#8e3f1f" strokeWidth="1" opacity="0.4" />
        <ellipse cx="420" cy="312" rx="200" ry="6" fill={PAL.shadow} opacity="0.25" />
        {Array.from({ length: 46 }, (_, i) => {
          const q = rng(i * 17 + 11);
          return <ellipse key={i} cx={(q() * 800).toFixed(0)} cy={(318 + q() * 132).toFixed(0)} rx={(1 + q() * 3).toFixed(1)} ry="1" fill={q() < 0.5 ? '#7e3418' : '#f0c79c'} opacity="0.5" />;
        })}
        <path d="M250 340 Q300 352 330 360 M600 344 Q560 356 520 362" stroke="#3b2550" strokeWidth="14" opacity="0.12" fill="none" strokeLinecap="round" />
        {/* flanking ixora shrubs + palms */}
        {[[230, 330], [570, 330]].map(([x, y]) => (
          <g key={x}>
            <ellipse cx={x} cy={y} rx="36" ry="16" fill="#2f6f3a" />
            <ellipse cx={x - 8} cy={y - 6} rx="20" ry="9" fill="#4f8f3e" />
            {[-20, -10, 0, 10, 20].map((dx, i) => (
              <circle key={dx} cx={x + dx} cy={y - 8 + (i % 2) * 6} r="3" fill="#e0402a" />
            ))}
          </g>
        ))}
        <Palm x={225} y={330} s={1.1} lean={-0.8} />
        <Palm x={575} y={330} s={1.1} lean={0.8} />

        <Guard x={330} y={326} s={1.05} />
        <Guard x={470} y={326} s={1.05} />
        {/* respectful visitors */}
        <Person x={150} y={420} s={1.35} top="#f4efe6" wrapper bottom="#c2261f" head="gele" headColor="#c2261f" skin="#5a301c" />
        <Person x={186} y={424} s={1.4} top="#f4efe6" wrapper bottom="#f4efe6" head="hair" skin="#4e2a18" />
        <Person x={650} y={410} s={1.25} top="#2a4d9b" bottom="#2c2f5c" head="cap" headColor="#c2261f" skin="#6e3b22" arm="phone" />
        <Person x={90} y={360} s={0.9} top="#1f7a3f" bottom="#2c2f5c" head="hair" />
      </g>

      {night && (
        <g>
          <Glow p={P} kind="cool" cx={400} cy={60} rx={160} ry={70} o={0.25} />
          {[[338, 214], [462, 214], [110, 232], [190, 232], [610, 232], [690, 232]].map(([x, y], i) => (
            <g key={i}>
              <Glow p={P} kind="amber" cx={x} cy={y + 10} rx={70} ry={60} o={0.7} />
              <rect x={x - 3} y={y - 4} width="6" height="9" rx="1.5" fill="#ffe2a0" />
              <rect x={x - 4} y={y - 6} width="8" height="2" fill="#3a2010" />
            </g>
          ))}
          <Glow p={P} kind="warm" cx={400} cy={300} rx={120} ry={40} o={0.6} />
          <Glow p={P} kind="warm" cx={400} cy={160} rx={130} ry={40} o={0.35} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
