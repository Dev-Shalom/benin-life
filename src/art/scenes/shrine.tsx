// Baba Osagie's shrine (native doctor, Sakponba) — light-hearted — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Treeline, Haze, SIGN_FONT, HAND_FONT, rng } from './_sharedB';

const P = 'shrine';

function Carving({ x, y, s = 1, c = '#6b3f22' }: { x: number; y: number; s?: number; c?: string }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="2" cy="0" rx="9" ry="2" fill="#2d1b4e" opacity="0.35" />
      <rect x="-7" y="-4" width="14" height="4" fill={c} />
      <path d="M-4 -4 L-5 -16 Q-6 -24 -4 -28 L4 -28 Q6 -24 5 -16 L4 -4 Z" fill={c} />
      <path d="M-5 -24 Q-9 -18 -5 -14 M5 -24 Q9 -18 5 -14" stroke={c} strokeWidth="2.4" fill="none" />
      <ellipse cx="0" cy="-34" rx="6" ry="7.5" fill={c} />
      <path d="M-6 -38 Q0 -46 6 -38 L5 -41 Q0 -48 -5 -41 Z" fill="#3a2214" />
      <path d="M-3 -35 h2 M1 -35 h2 M-1 -31 h2" stroke="#f2e6cc" strokeWidth="1" />
      <path d="M1 -40 Q6 -36 4 -28 L4 -4 L2 -4 Z" fill="#2d1b4e" opacity="0.3" />
      <path d="M-4 -20 h8" stroke="#f2f0ea" strokeWidth="1.4" />
    </g>
  );
}

function Calabash({ x, y, s = 1, night }: { x: number; y: number; s?: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="2" cy="0" rx="15" ry="3" fill="#2d1b4e" opacity="0.35" />
      <path d="M-14 -10 Q-14 0 0 0 Q14 0 14 -10 Z" fill={night ? '#a8782e' : '#d9a441'} />
      <path d="M4 -10 Q14 -10 14 -10 Q14 0 0 0 Q8 -2 4 -10 Z" fill="#7a4a1a" opacity="0.45" />
      <ellipse cx="0" cy="-10" rx="14" ry="3.5" fill="#8a5a22" />
      <path d="M-10 -6 q5 3 10 0 q5 3 10 0" stroke="#7a3519" strokeWidth="1" fill="none" />
    </g>
  );
}

function Bottle({ x, y, c, label, s = 1 }: { x: number; y: number; c: string; label: string; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <path d="M-6 0 V-20 Q-6 -24 -2 -26 V-32 H2 V-26 Q6 -24 6 -20 V0 Z" fill={c} />
      <rect x="-2.5" y="-35" width="5" height="4" fill="#c9a070" />
      <rect x="-5" y="-17" width="10" height="9" fill="#f6ecd2" />
      <text x="0" y="-11" fontSize="3.4" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">{label}</text>
      <path d="M2 -24 V-2 H5 V-20 Z" fill="#2d1b4e" opacity="0.25" />
      <path d="M-4 -20 V-3" stroke="#fff" strokeWidth="1" opacity="0.5" />
    </g>
  );
}

export default function ShrineScene({ night }: { night: boolean }) {
  const r = rng(909);
  const cowries = Array.from({ length: 16 }, (_, i) => {
    const a = (i / 16) * Math.PI * 2 + r() * 0.3;
    const d = 6 + r() * 12;
    return { x: 452 + Math.cos(a) * d, y: 376 + Math.sin(a) * d * 0.35, rot: r() * 180 };
  });
  const leaves = Array.from({ length: 26 }, () => ({ x: r() * 800, y: 392 + r() * 56, rot: r() * 180, c: r() > 0.5 ? '#a8742e' : '#7a5a2a' }));
  const flags = [
    [120, 238, '#d2342a'], [150, 244, '#f6f2ea'], [180, 238, '#d2342a'], [210, 230, '#f6f2ea'],
    [470, 226, '#f6f2ea'], [500, 232, '#d2342a'], [530, 238, '#f6f2ea'], [560, 246, '#d2342a'], [590, 254, '#e0a526'],
  ] as const;
  const skyHole = 'M0 0 H800 V236 H437 L300 151 L169 236 H0 Z';
  const blobs = Array.from({ length: 26 }, (_, i) => {
    const a = r() * Math.PI * 2;
    const d = Math.sqrt(r());
    return { x: Math.round(650 + Math.cos(a) * d * 170), y: Math.round(78 + Math.sin(a) * d * 70), r: Math.round(26 + r() * 22), t: i % 3 === 0 };
  }).sort((a, b) => a.y - b.y);

  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Baba Osagie's shrine">
      <defs>
        <linearGradient id={`${P}-earth`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.5" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        <linearGradient id={`${P}-mud`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c87a4a" />
          <stop offset="0.6" stopColor="#a85a34" />
          <stop offset="1" stopColor="#80422a" />
        </linearGradient>
        <linearGradient id={`${P}-thatch`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#e9c27a" />
          <stop offset="0.5" stopColor="#c0904a" />
          <stop offset="1" stopColor="#7a5530" />
        </linearGradient>
        <linearGradient id={`${P}-bark`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor={night ? '#4a4058' : '#8a6a54'} />
          <stop offset="0.5" stopColor={night ? '#383048' : '#6a4c3a'} />
          <stop offset="1" stopColor={night ? '#262036' : '#4a3242'} />
        </linearGradient>
        <radialGradient id={`${P}-smoke`} cx="0.5" cy="0.5" r="0.5">
          <stop offset="0" stopColor={night ? '#c9b8e8' : '#f2eef6'} stopOpacity="0.55" />
          <stop offset="1" stopColor={night ? '#c9b8e8' : '#f2eef6'} stopOpacity="0" />
        </radialGradient>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={120} sunY={70} moonX={440} moonY={58} />

      {/* bush behind the compound */}
      <Treeline y={222} fill={night ? '#18243e' : '#7aa686'} seed={51} amp={22} step={46} base={300} />
      <Treeline y={246} fill={night ? '#142034' : '#4f8a5a'} seed={52} amp={16} step={30} base={300} />
      <Haze p={P} y={190} h={80} night={night} o={0.4} />

      {/* ground */}
      <rect x="-10" y="262" width="820" height="200" fill={`url(#${P}-earth)`} />
      <path d="M40 300 Q240 290 420 306 Q600 320 780 300 M0 340 Q200 330 400 344 M200 420 Q420 404 700 424" stroke="#7a3519" strokeWidth="2" opacity="0.25" fill="none" />
      {/* broom-swept arcs */}
      <path d="M520 420 q30 -10 60 0 M540 430 q30 -10 60 0 M80 380 q30 -8 60 0 M100 390 q30 -8 60 0" stroke="#e08a52" strokeWidth="1.2" opacity="0.5" fill="none" />

      {/* sacred iroko tree with red-and-white wrap */}
      <g>
        <path d="M612 352 Q626 260 620 120 L676 120 Q668 260 690 352 Q650 360 612 352 Z" fill={`url(#${P}-bark)`} />
        <path d="M612 352 Q590 346 584 356 L620 358 Z M690 352 Q712 344 720 356 L680 358 Z" fill="#5a3c30" />
        <path d="M632 140 Q636 240 628 340 M656 150 Q650 250 664 340" stroke="#3a2232" strokeWidth="2" opacity="0.35" fill="none" />
        <path d="M618 252 Q648 262 676 252 L678 274 Q648 284 618 274 Z" fill="#d2342a" />
        <path d="M618 274 Q648 284 678 274 L679 292 Q648 302 617 292 Z" fill="#f6f2ea" />
        <path d="M618 252 L604 300 L612 302 L622 266 Z" fill="#d2342a" />
        <path d="M660 260 L676 252 L678 292 L662 300 Z" fill="#3b2a5e" opacity="0.2" />
        {/* canopy */}
        <ellipse cx="660" cy="80" rx="190" ry="90" fill={night ? '#122036' : '#2f6a3a'} />
        <ellipse cx="580" cy="96" rx="110" ry="56" fill={night ? '#16263e' : '#3c7c44'} />
        <ellipse cx="720" cy="50" rx="120" ry="60" fill={night ? '#16263e' : '#3c7c44'} />
        {blobs.map((b, i) => (
          <g key={i}>
            <ellipse cx={b.x + 5} cy={b.y + 6} rx={b.r} ry={b.r * 0.62} fill={night ? '#0f1a2e' : '#24552f'} opacity="0.7" />
            <ellipse cx={b.x} cy={b.y} rx={b.r} ry={b.r * 0.6} fill={night ? (b.t ? '#1a2a44' : '#16263e') : b.t ? '#4a8c48' : '#3c7c44'} />
            <ellipse cx={b.x - b.r * 0.3} cy={b.y - b.r * 0.22} rx={b.r * 0.5} ry={b.r * 0.28} fill={night ? '#22344e' : '#6aac5a'} opacity={b.t ? 0.9 : 0.5} />
          </g>
        ))}
        <path d="M470 120 Q560 170 660 150 Q760 160 820 130 L820 172 Q700 186 640 170 Q540 180 470 120 Z" fill="#2d1b4e" opacity="0.25" />
      </g>

      {/* bunting of cloth flags on a rope */}
      <path d="M100 232 Q160 252 230 226" stroke="#3a2a30" strokeWidth="1" fill="none" />
      <path d="M440 222 Q520 246 620 262" stroke="#3a2a30" strokeWidth="1" fill="none" />
      {flags.map(([x, y, c], i) => (
        <path key={i} d={`M${x - 8} ${y} h16 l-2 18 l-6 -5 l-6 5 Z`} fill={night ? (c === '#d2342a' ? '#7a2a3a' : '#7a7a9a') : c} />
      ))}

      {/* signboard */}
      <g>
        <path d="M44 312 V236 M150 312 V236" stroke="#5a3a2a" strokeWidth="5" />
        <rect x="30" y="228" width="134" height="64" fill="#f6f2ea" />
        <rect x="30" y="228" width="134" height="64" fill="none" stroke="#d2342a" strokeWidth="3" />
        <text x="97" y="243" fontSize="10" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">BABA OSAGIE</text>
        <text x="97" y="253" fontSize="6.5" fontFamily={SIGN_FONT} fill="#2a2440" textAnchor="middle">NATIVE DOCTOR</text>
        <text x="97" y="263" fontSize="5.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Love • Money • Promotion</text>
        <text x="97" y="272" fontSize="5.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Visa wahala? Come in!</text>
        <text x="97" y="284" fontSize="5" fontFamily={HAND_FONT} fill="#7a3519" textAnchor="middle">NO REFUND o • 0803-OSAGIE</text>
      </g>

      {/* hut */}
      <g>
        <ellipse cx="300" cy="350" rx="170" ry="12" fill="#2d1b4e" opacity="0.3" />
        <rect x="176" y="236" width="252" height="114" fill={`url(#${P}-mud)`} />
        <rect x="370" y="236" width="58" height="114" fill="#3b2a5e" opacity="0.18" />
        {/* chalk decoration */}
        <path d="M186 300 h232 M186 306 h232" stroke="#f6f2ea" strokeWidth="2" opacity="0.8" />
        <path d={Array.from({ length: 18 }, (_, i) => `M${192 + i * 13} 318 l5 8 l5 -8`).join('')} stroke="#f6f2ea" strokeWidth="1.6" fill="none" opacity="0.7" />
        <path d={Array.from({ length: 10 }, (_, i) => `M${198 + i * 24} 280 a2 2 0 1 0 0.1 0`).join('')} stroke="#f6f2ea" strokeWidth="2.4" fill="none" opacity="0.8" />
        {/* doorway with red curtain */}
        <path d="M268 350 V270 Q302 252 336 270 V350 Z" fill="#2a1626" />
        <path d="M272 350 V274 Q288 264 302 263 L300 350 Z" fill="#d2342a" />
        <path d="M332 350 V274 Q316 264 302 263 L304 350 Z" fill="#b8241e" />
        <path d="M280 276 V350 M292 270 V350 M314 270 V350 M324 276 V350" stroke="#7a1518" strokeWidth="1.2" opacity="0.6" />
        <path d="M272 330 h60" stroke="#f6f2ea" strokeWidth="5" opacity="0.9" />
        {/* small window with skull-free charms: cowrie strings */}
        <rect x="370" y="262" width="34" height="26" fill="#2a1626" />
        <path d="M378 262 v24 M387 262 v20 M396 262 v24" stroke="#f6f2ea" strokeWidth="2.2" strokeDasharray="2.5 2" />
        {/* thatch */}
        <path d="M150 248 L300 150 L456 248 Q440 256 426 250 Q410 258 394 250 Q378 258 362 250 Q346 258 330 250 Q314 258 298 250 Q282 258 266 250 Q250 258 234 250 Q218 258 202 250 Q186 258 170 250 Q158 256 150 248 Z" fill={`url(#${P}-thatch)`} />
        <path d="M300 150 L456 248 Q440 256 426 250 Q410 258 394 250 L300 156 Z" fill="#3b2a5e" opacity="0.22" />
        <path d="M176 232 L300 158 M206 242 L300 176 M240 246 L300 204 M330 172 L420 236 M350 196 L400 232" stroke="#f6d896" strokeWidth="1.3" opacity="0.6" />
        <path d="M296 150 L300 132 L304 150 Z" fill="#7a5530" />
        <circle cx="300" cy="130" r="5" fill="#f6f2ea" />
        <rect x="176" y="250" width="252" height="10" fill="#2d1b4e" opacity="0.28" />
        {/* tender palm fronds (omu) over the door */}
        <path d={Array.from({ length: 13 }, (_, i) => `M${266 + i * 6} 258 q${(i % 2 ? 2 : -2)} 14 ${(i % 3) - 1} ${22 + (i % 4) * 4}`).join('')} stroke={night ? '#8a8a5a' : '#e8d468'} strokeWidth="2" fill="none" />
      </g>

      {/* raffia mat */}
      <path d="M160 424 L196 384 L560 384 L600 424 Z" fill={night ? '#6a5a3a' : '#d8b878'} opacity="0.85" />
      <path d={Array.from({ length: 18 }, (_, i) => `M${170 + i * 24} 424 L${200 + i * 20.5} 384`).join('')} stroke="#a8823e" strokeWidth="1.2" opacity="0.6" />
      <path d="M178 404 H580 M168 414 H590" stroke="#a8823e" strokeWidth="1" opacity="0.5" />
      {/* altar platform */}
      <g>
        <path d="M352 392 L360 362 L548 362 L556 392 Z" fill="#9a4a28" />
        <path d="M360 362 L548 362 L546 368 L362 368 Z" fill="#d07a4a" />
        <path d="M500 362 L548 362 L556 392 L504 392 Z" fill="#3b2a5e" opacity="0.2" />
        <path d="M352 392 h204" stroke="#f6f2ea" strokeWidth="3" opacity="0.7" />
        {/* white cloth runner */}
        <path d="M380 364 L404 364 L400 390 L376 390 Z" fill="#f6f2ea" />
        <path d="M376 384 L400 384" stroke="#d2342a" strokeWidth="3" />
      </g>
      {/* altar items */}
      <Carving x={384} y={364} s={1.1} c="#6b3f22" />
      <Carving x={408} y={364} s={0.85} c="#8a5232" />
      <Bottle x={430} y={364} c="#2f7a3f" label="AGBO" />
      <Bottle x={526} y={364} c="#6a3a1a" label="WORK!" s={1.1} />
      <Bottle x={540} y={366} c="#2f4a7a" label="LUV" s={0.85} />
      {/* cowrie tray */}
      <ellipse cx="454" cy="378" rx="26" ry="8" fill="#a8742e" />
      <ellipse cx="454" cy="377" rx="22" ry="6" fill="#d9a441" />
      {cowries.map((c, i) => (
        <ellipse key={i} cx={c.x.toFixed(1)} cy={c.y.toFixed(1)} rx="2.4" ry="1.5" fill="#fbf4e2" stroke="#b9a07a" strokeWidth="0.5" transform={`rotate(${c.rot.toFixed(0)} ${c.x.toFixed(1)} ${c.y.toFixed(1)})`} />
      ))}
      <Calabash x={496} y={392} s={1} night={night} />
      <Calabash x={372} y={400} s={0.9} night={night} />
      {/* kola nuts */}
      <ellipse cx="478" cy="368" rx="3" ry="2.2" fill="#c0503a" />
      <ellipse cx="484" cy="369" rx="3" ry="2.2" fill="#e8c8a0" />
      {/* clay pot with smouldering herbs + smoke */}
      <g transform="translate(590 410)">
        <ellipse cx="3" cy="0" rx="24" ry="4" fill="#2d1b4e" opacity="0.35" />
        <path d="M-18 -20 Q-24 -6 -12 0 L12 0 Q24 -6 18 -20 Z" fill="#8a3a1e" />
        <ellipse cx="0" cy="-20" rx="18" ry="4.5" fill="#5a2414" />
        <ellipse cx="0" cy="-20" rx="14" ry="3" fill={night ? '#ff8a2a' : '#e0632a'} />
        <path d="M-14 -14 q14 4 28 0" stroke="#f6f2ea" strokeWidth="1.6" fill="none" opacity="0.7" />
        <path d="M6 -20 Q18 -8 12 0" fill="#3b2a5e" opacity="0.25" />
      </g>
      <g opacity={night ? 0.8 : 0.9}>
        <ellipse cx="594" cy="372" rx="16" ry="12" fill={`url(#${P}-smoke)`} />
        <ellipse cx="586" cy="342" rx="22" ry="16" fill={`url(#${P}-smoke)`} />
        <ellipse cx="600" cy="306" rx="30" ry="20" fill={`url(#${P}-smoke)`} />
        <ellipse cx="584" cy="266" rx="38" ry="24" fill={`url(#${P}-smoke)`} />
        <path d="M592 388 q-10 -14 2 -28 q12 -14 -2 -30 q-12 -16 4 -32 q14 -14 -4 -34" stroke={night ? '#b9a8d8' : '#f2eef6'} strokeWidth="3" fill="none" opacity="0.5" strokeLinecap="round" />
      </g>

      {/* Baba on his stool with fly-whisk */}
      <g>
        <path d="M206 410 h40 l-4 -18 h-32 Z" fill="#6b3f22" />
        <ellipse cx="226" cy="392" rx="22" ry="4" fill="#8a5232" />
      </g>
      <Person x={224} y={410} s={1.55} skin="#4a2c1e" top="#f6f2ea" bottom="#f6f2ea" pose="sit" facing={1} night={night}
        extra={
          <g>
            <path d="M-5 -49 Q0 -60 6 -49 Z" fill="#d2342a" />
            <path d="M-5 -36 Q0 -30 5 -36" stroke="#d2342a" strokeWidth="1.6" fill="none" strokeDasharray="1.6 1" />
            <path d="M-5 -33 Q0 -26 5 -33" stroke="#e0a526" strokeWidth="1.4" fill="none" strokeDasharray="1.4 1" />
            <path d="M15 -24 L22 -40" stroke="#6b3f22" strokeWidth="1.6" />
            <path d="M22 -40 q6 -4 4 -14 M22 -40 q2 -6 -2 -14 M22 -40 q4 -6 8 -10" stroke={night ? '#9a9ab8' : '#f6f2ea'} strokeWidth="1.4" fill="none" />
          </g>
        } />
      {/* client with phone, a bit nervous */}
      <Person x={664} y={424} s={1.5} skin="#5a3624" top="#2f6fd0" bottom="#3a4468" pose="stand" facing={-1} night={night}
        extra={<g><rect x="8" y="-30" width="4" height="7" rx="1" fill="#1a1a26" /><path d="M-9 -60 q2 -4 4 0 M6 -62 q2 -3 4 0" stroke="#7fc4ff" strokeWidth="1.2" fill="none" /></g>} />
      {/* speech bubble */}
      <g transform="translate(696 324)">
        <path d="M0 0 h84 v26 h-60 l-10 8 l2 -8 h-16 Z" fill="#fffaf0" />
        <text x="42" y="11" fontSize="6" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Baba, na only</text>
        <text x="42" y="20" fontSize="6" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">small luck I want o</text>
      </g>

      {/* white chicken + fallen leaves */}
      <g transform="translate(110 418)">
        <ellipse cx="2" cy="0" rx="14" ry="2.5" fill="#2d1b4e" opacity="0.3" />
        <path d="M-12 -12 Q-14 -24 -4 -24 Q2 -30 6 -22 L12 -20 L7 -18 Q10 -6 0 -4 Q-10 -2 -12 -12 Z" fill={night ? '#9a9ab8' : '#fbf8f0'} />
        <path d="M2 -28 l2 -4 l2 4 Z" fill="#d2342a" />
        <path d="M-12 -12 q-6 -6 -4 -12" stroke={night ? '#9a9ab8' : '#fbf8f0'} strokeWidth="4" fill="none" />
        <path d="M-2 -4 v4 M3 -4 v4" stroke="#e0a526" strokeWidth="1.4" />
        <circle cx="5" cy="-23" r="0.9" fill="#1a1a26" />
      </g>
      {/* foreground: water pot, gourd rattle, grass tufts */}
      <g transform="translate(40 446)">
        <ellipse cx="4" cy="0" rx="34" ry="5" fill="#2d1b4e" opacity="0.35" />
        <path d="M-26 -30 Q-34 -6 -16 0 L16 0 Q34 -6 26 -30 Q20 -40 10 -42 L-10 -42 Q-20 -40 -26 -30 Z" fill="#9a4426" />
        <ellipse cx="0" cy="-42" rx="11" ry="3" fill="#5a2414" />
        <path d="M-26 -24 q26 8 52 0" stroke="#f6f2ea" strokeWidth="2" fill="none" opacity="0.8" />
        <path d="M8 -42 Q28 -36 26 -10 Q20 -2 14 0 Q24 -20 8 -42 Z" fill="#3b2a5e" opacity="0.25" />
        <path d="M-20 -30 Q-24 -18 -18 -8" stroke="#e08a52" strokeWidth="2.4" fill="none" opacity="0.6" />
      </g>
      <g transform="translate(272 420) rotate(-20)">
        <ellipse cx="0" cy="-8" rx="10" ry="12" fill={night ? '#a8782e' : '#d9a441'} />
        <path d="M-10 -10 q10 6 20 0 M-9 -4 q9 6 18 0" stroke="#f6f2ea" strokeWidth="1.5" strokeDasharray="1.5 1.5" fill="none" />
        <rect x="-2" y="-28" width="4" height="10" fill="#8a5a22" />
      </g>
      <path d={[[12, 400], [150, 446], [330, 444], [700, 446], [770, 404], [460, 440]].map(([x, y]) => `M${x} ${y} l-4 -12 M${x} ${y} l1 -15 M${x} ${y} l6 -11 M${x} ${y} l-8 -6`).join('')} stroke={night ? '#24443a' : '#6a9a3a'} strokeWidth="1.8" strokeLinecap="round" />
      {leaves.map((l, i) => (
        <ellipse key={i} cx={l.x.toFixed(0)} cy={l.y.toFixed(0)} rx="4" ry="1.6" fill={night ? '#3a2a30' : l.c} transform={`rotate(${l.rot.toFixed(0)} ${l.x.toFixed(0)} ${l.y.toFixed(0)})`} opacity="0.8" />
      ))}

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[180, 236]} />
          {/* hut interior + doorway lantern */}
          <Glow p={P} cx={302} cy={316} r={70} ry={60} kind="gf" o={0.7} />
          <path d="M262 246 v14" stroke="#2a2232" strokeWidth="1" />
          <rect x="257" y="260" width="10" height="13" rx="3" fill="#ffe9a8" />
          <Glow p={P} cx={262} cy={266} r={110} o={0.95} />
          {/* altar lantern */}
          <rect x="414" y="346" width="9" height="12" rx="3" fill="#ffe9a8" />
          <Glow p={P} cx={418} cy={352} r={120} ry={80} o={0.9} />
          {/* fire pot + lit smoke */}
          <Glow p={P} cx={590} cy={390} r={80} kind="gf" o={0.95} />
          <Glow p={P} cx={590} cy={320} r={60} ry={90} kind="gf" o={0.25} />
          {/* window glow */}
          <Glow p={P} cx={387} cy={275} r={36} kind="gf" o={0.6} />
          {/* a few fireflies */}
          {[[90, 330], [160, 300], [520, 300], [720, 380], [760, 300], [40, 380]].map(([x, y], i) => (
            <g key={i}>
              <circle cx={x} cy={y} r="3" fill="#d9ff7a" opacity="0.15" />
              <circle cx={x} cy={y} r="1.1" fill="#f4ffb0" />
            </g>
          ))}
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
