// Igun Street bronze casters — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, ZincPattern, SIGN_FONT, HAND_FONT, rng } from './_sharedB';

const P = 'workshop';
const FL = 344; // workshop floor line

/** Benin-style bronze commemorative head. (x,y) = base centre; ~70px tall at s=1. */
function BronzeHead({ x, y, s = 1, kind = 'oba' }: { x: number; y: number; s?: number; kind?: 'oba' | 'idia' }) {
  const B = `url(#${P}-bronze)`;
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="3" cy="0" rx="20" ry="3" fill="#1d1230" opacity="0.4" />
      {/* flange base + coral-bead collar */}
      <path d="M-20 0 L-17 -6 L17 -6 L20 0 Z" fill={B} />
      <path d="M-13 -6 L-13 -26 Q0 -30 13 -26 L13 -6 Z" fill={B} />
      <path d="M-13 -10 Q0 -13 13 -10 M-13 -14 Q0 -17 13 -14 M-13 -18 Q0 -21 13 -18 M-13 -22 Q0 -25 13 -22" stroke="#5a3418" strokeWidth="1.2" fill="none" />
      {/* face */}
      <path d="M-10 -26 Q-12 -40 -9 -46 L9 -46 Q12 -40 10 -26 Z" fill={B} />
      <path d="M-6 -38 h4 M2 -38 h4" stroke="#3a2010" strokeWidth="1.6" />
      <path d="M-1 -36 L-2 -31 L2 -31" stroke="#3a2010" strokeWidth="1" fill="none" />
      <path d="M-4 -29 h8" stroke="#3a2010" strokeWidth="1.4" />
      <path d="M-8 -42 v8 M8 -42 v8" stroke="#3a2010" strokeWidth="0.8" opacity="0.6" />
      {kind === 'idia' ? (
        <g>
          {/* tall forward-peaked crown with bead lattice */}
          <path d="M-10 -46 Q-12 -60 -2 -74 Q8 -80 14 -76 Q12 -60 10 -46 Z" fill={B} />
          <path d="M-9 -50 L10 -64 M-8 -56 L12 -70 M-6 -62 L8 -74 M-9 -50 L4 -74 M-2 -48 L10 -66 M4 -47 L12 -58" stroke="#5a3418" strokeWidth="0.9" />
        </g>
      ) : (
        <g>
          {/* beaded cap with side wings */}
          <path d="M-11 -44 Q-12 -58 0 -60 Q12 -58 11 -44 Z" fill={B} />
          <path d="M-11 -48 h22 M-11 -52 h22 M-9 -56 h18" stroke="#5a3418" strokeWidth="1" />
          <path d="M-11 -50 l-7 -10 l2 12 Z M11 -50 l7 -10 l-2 12 Z" fill={B} />
          <path d="M-12 -44 l-2 10 M12 -44 l2 10" stroke={B} strokeWidth="2.4" />
        </g>
      )}
      {/* key-light sheen + core shadow (light from left) */}
      <path d="M-9 -44 Q-11 -36 -9 -28" stroke="#ffe6a0" strokeWidth="2" opacity="0.55" fill="none" />
      <path d="M4 -46 Q12 -40 10 -26 L13 -26 L13 -6 L17 -6 L20 0 L8 0 Z" fill="#2d1b4e" opacity="0.3" />
    </g>
  );
}

function Plaque({ x, y, w = 40, h = 52 }: { x: number; y: number; w?: number; h?: number }) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} fill={`url(#${P}-bronze)`} />
      <rect x={x + 3} y={y + 3} width={w - 6} height={h - 6} fill="none" stroke="#5a3418" strokeWidth="1" />
      {/* raised warrior chief */}
      <circle cx={x + w / 2} cy={y + h * 0.3} r={w * 0.11} fill="#c99a52" />
      <path d={`M${x + w * 0.36} ${y + h * 0.42} h${w * 0.28} l${w * 0.04} ${h * 0.4} h${-w * 0.36} Z`} fill="#c99a52" />
      <path d={`M${x + w * 0.36} ${y + h * 0.48} l${-w * 0.14} ${h * 0.14} M${x + w * 0.64} ${y + h * 0.48} l${w * 0.14} ${-h * 0.1}`} stroke="#c99a52" strokeWidth="2" />
      {[0.15, 0.85].map((f) => <circle key={f} cx={x + w * f} cy={y + h * 0.2} r="2" fill="#5a3418" />)}
      <rect x={x + w * 0.6} y={y} width={w * 0.4} height={h} fill="#2d1b4e" opacity="0.2" />
    </g>
  );
}

export default function WorkshopScene({ night }: { night: boolean }) {
  const r = rng(321);
  const sparks = Array.from({ length: 16 }, () => ({ x: 214 + (r() - 0.5) * 70, y: 250 - r() * 70, l: 2 + r() * 4 }));
  const ruts = 'M-10 410 Q300 396 810 418 M-10 432 Q320 418 810 440';
  const skyHole = 'M0 0 H800 V86 H0 Z';
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Igun Street bronze casters">
      <defs>
        <linearGradient id={`${P}-bronze`} x1="0" y1="0" x2="1" y2="0.3">
          <stop offset="0" stopColor="#e2b060" />
          <stop offset="0.35" stopColor="#b0793a" />
          <stop offset="0.75" stopColor="#7d4f24" />
          <stop offset="1" stopColor="#5a3418" />
        </linearGradient>
        <linearGradient id={`${P}-backwall`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2e2230" />
          <stop offset="0.5" stopColor="#4a3434" />
          <stop offset="1" stopColor="#6a4632" />
        </linearGradient>
        <linearGradient id={`${P}-floor`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6a4232" />
          <stop offset="1" stopColor="#8a5236" />
        </linearGradient>
        <linearGradient id={`${P}-street`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.6" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8a3a1e" />
        </linearGradient>
        <radialGradient id={`${P}-mouth`} cx="0.5" cy="0.6" r="0.6">
          <stop offset="0" stopColor="#fff6c8" />
          <stop offset="0.35" stopColor="#ffc44a" />
          <stop offset="0.8" stopColor="#ff6a1a" />
          <stop offset="1" stopColor="#a8241a" />
        </radialGradient>
      </defs>
      <GlowDefs p={P} />
      <ZincPattern p={P} night={night} />
      <Sky p={P} night={night} sunX={90} sunY={50} moonX={300} moonY={44} clouds={!night} />

      {/* neighbours: old storey building (left), mango tree (right) */}
      <rect x="-10" y="40" width="120" height="320" fill={night ? '#4a3a52' : '#d9a86a'} />
      <rect x="-10" y="40" width="120" height="10" fill={night ? '#3a2e42' : '#a8763e'} />
      <rect x="14" y="70" width="30" height="40" fill={night ? '#ffcf73' : '#3f5e84'} />
      <rect x="60" y="70" width="30" height="40" fill={night ? '#1c2244' : '#3f5e84'} />
      <path d="M14 70 v40 M29 70 v40 M60 70 v40 M75 70 v40" stroke="#2a2232" strokeWidth="1.2" />
      <ellipse cx="760" cy="80" rx="110" ry="70" fill={night ? '#152238' : '#3f7a44'} />
      <ellipse cx="730" cy="60" rx="60" ry="34" fill={night ? '#1b2c46' : '#5a9a50'} />
      <rect x="752" y="140" width="14" height="220" fill={night ? '#2a2232' : '#5a3c30'} />

      {/* shed roof: zinc seen from below the eave */}
      <path d="M70 120 L740 120 L760 88 L50 88 Z" fill={`url(#${P}-zinc)`} />
      <path d="M70 120 L740 120 L760 88 L50 88 Z" fill={`url(#${P}-rust)`} />
      {/* interior */}
      <rect x="80" y="128" width="650" height={FL - 128} fill={`url(#${P}-backwall)`} />
      {/* soot bloom above furnace */}
      <ellipse cx="210" cy="170" rx="90" ry="50" fill="#140c1a" opacity="0.55" />
      {/* fascia board with name */}
      <rect x="64" y="118" width="682" height="22" fill={night ? "#a89a8c" : "#f2e6cc"} />
      <rect x="64" y="138" width="682" height="5" fill="#2d1b4e" opacity="0.35" />
      <text x="405" y="134" fontSize="13" fontFamily={SIGN_FONT} fill="#7a3519" textAnchor="middle" letterSpacing="2">OSA & SONS BRONZE CASTING · EST. 1290</text>

      {/* shelves of heads + plaques */}
      <g>
        {[206, 270].map((y) => (
          <g key={y}>
            <rect x="436" y={y} width="270" height="6" fill="#7a4a2a" />
            <rect x="436" y={y + 6} width="270" height="4" fill="#1d1230" opacity="0.4" />
          </g>
        ))}
        <BronzeHead x={466} y={206} s={0.9} kind="oba" />
        <BronzeHead x={512} y={206} s={1} kind="idia" />
        <BronzeHead x={560} y={206} s={0.85} kind="oba" />
        <Plaque x={592} y={156} w={34} h={46} />
        <Plaque x={634} y={150} w={40} h={52} />
        <BronzeHead x={686} y={206} s={0.75} kind="idia" />
        <BronzeHead x={462} y={270} s={0.8} kind="idia" />
        <Plaque x={490} y={222} w={36} h={46} />
        <BronzeHead x={552} y={270} s={0.95} kind="oba" />
        <BronzeHead x={598} y={270} s={0.8} kind="oba" />
        <Plaque x={624} y={220} w={36} h={48} />
        <BronzeHead x={684} y={270} s={0.9} kind="idia" />
      </g>
      {/* tools on the wall */}
      <path d="M300 160 v40 M316 156 v46 M332 162 v36" stroke="#8a8ca0" strokeWidth="2.4" />
      <path d="M296 160 h8 M312 156 h8 M328 162 h8" stroke="#5a3a2a" strokeWidth="4" />
      <path d="M360 170 l20 40 M380 168 l-16 44" stroke="#7d8090" strokeWidth="2.2" />

      {/* floor */}
      <rect x="80" y={FL - 4} width="650" height="30" fill={`url(#${P}-floor)`} />
      {/* clay moulds drying */}
      {[[300, FL + 6], [324, FL + 10], [350, FL + 4]].map(([x, y], i) => (
        <g key={i}>
          <ellipse cx={x + 2} cy={y} rx="12" ry="2.5" fill="#1d1230" opacity="0.4" />
          <path d={`M${x - 10} ${y} Q${x - 12} ${y - 22} ${x} ${y - 26} Q${x + 12} ${y - 22} ${x + 10} ${y} Z`} fill="#9a6a4a" />
          <path d={`M${x + 2} ${y - 26} Q${x + 12} ${y - 22} ${x + 10} ${y} L${x + 3} ${y} Z`} fill="#2d1b4e" opacity="0.3" />
        </g>
      ))}

      {/* clay furnace with glowing mouth */}
      <g>
        <ellipse cx="214" cy={FL + 8} rx="70" ry="8" fill="#1d1230" opacity="0.45" />
        <path d={`M150 ${FL + 8} Q140 270 214 250 Q288 270 278 ${FL + 8} Z`} fill="#8a4a2e" />
        <path d={`M214 250 Q288 270 278 ${FL + 8} L230 ${FL + 8} Q262 290 214 250 Z`} fill="#2d1b4e" opacity="0.3" />
        <path d="M168 300 Q214 286 262 300" stroke="#5a2a1a" strokeWidth="2" fill="none" />
        <ellipse cx="214" cy="252" rx="26" ry="7" fill="#5a2414" />
        <ellipse cx="214" cy="252" rx="20" ry="5" fill={`url(#${P}-mouth)`} />
        <path d={`M190 ${FL + 4} Q190 312 214 308 Q238 312 238 ${FL + 4} Z`} fill={`url(#${P}-mouth)`} />
        <path d={`M196 ${FL + 4} q6 -12 10 0 q6 -14 12 0 q6 -10 12 0`} fill="#3a1a14" />
        {/* bellows pipe */}
        <path d={`M140 ${FL - 2} L176 ${FL - 12}`} stroke="#5a3a2a" strokeWidth="6" />
      </g>
      {/* sparks */}
      {sparks.map((s, i) => (
        <path key={i} d={`M${s.x.toFixed(1)} ${s.y.toFixed(1)} l${(s.l * 0.4).toFixed(1)} ${(-s.l).toFixed(1)}`} stroke="#ffd36a" strokeWidth="1.4" strokeLinecap="round" opacity={night ? 1 : 0.7} />
      ))}
      {/* smoke from furnace through the roof gap */}
      <path d="M214 244 q-14 -24 4 -46 q18 -22 -2 -48" stroke={night ? '#6a5a7a' : '#d8d0d8'} strokeWidth="10" fill="none" opacity="0.25" strokeLinecap="round" />

      {/* caster lifting crucible with long tongs */}
      <Person x={290} y={FL + 6} s={1.5} skin="#4a2c1e" top="#3a4468" bottom="#5a4a3a" pose="work" facing={-1} night={night}
        extra={<g><path d="M16 -32 L48 -46" stroke="#4a4a5a" strokeWidth="2.4" /><path d="M44 -52 h10 l-2 12 h-6 Z" fill="#7a2a1a" /><ellipse cx="49" cy="-52" rx="5" ry="1.6" fill="#ffd36a" /></g>} />
      {/* bellows boy squatting */}
      <Person x={128} y={FL + 6} s={1.15} skin="#5a3624" top="#d2342a" bottom="#2b3350" pose="sit" facing={1} night={night} />
      {/* elder chasing a head at the bench */}
      <g>
        <rect x="370" y={FL - 30} width="70" height="8" fill="#7a4a2a" />
        <path d={`M376 ${FL - 22} V${FL + 6} M434 ${FL - 22} V${FL + 6}`} stroke="#5a3418" strokeWidth="4" />
        <BronzeHead x={404} y={FL - 30} s={0.6} kind="oba" />
      </g>
      <Person x={450} y={FL + 8} s={1.45} skin="#3e2418" top="#f2f0ea" bottom="#2b3350" pose="work" facing={-1} night={night}
        extra={<g><path d="M-5 -55 h10 v-4 h-10 Z" fill="#d2342a" /><path d="M16 -30 L22 -38" stroke="#9a9db0" strokeWidth="2" /></g>} />

      {/* front posts */}
      {[84, 400, 726].map((x) => (
        <g key={x}>
          <rect x={x - 5} y="143" width="10" height={FL - 135} fill="#6a4228" />
          <rect x={x + 1} y="143" width="4" height={FL - 135} fill="#2d1b4e" opacity="0.3" />
        </g>
      ))}

      {/* street */}
      <rect x="-10" y={FL + 20} width="820" height="100" fill={`url(#${P}-street)`} />
      <path d={ruts} stroke="#7a3519" strokeWidth="6" opacity="0.25" fill="none" />
      <rect x="-10" y={FL + 18} width="820" height="4" fill="#2d1b4e" opacity="0.3" />

      {/* display table for buyers */}
      <g>
        <ellipse cx="620" cy="436" rx="150" ry="9" fill="#2d1b4e" opacity="0.35" />
        <rect x="486" y="388" width="268" height="12" fill="#8a5232" />
        <rect x="486" y="388" width="268" height="3" fill="#c48a5a" />
        <path d="M496 400 V436 M744 400 V436" stroke="#5a3418" strokeWidth="6" />
        <rect x="486" y="400" width="268" height="5" fill="#2d1b4e" opacity="0.3" />
        {/* leopard aquamanile */}
        <g transform="translate(520 388)">
          <path d="M-20 0 v-10 q-2 -10 8 -12 h24 q8 -2 10 -10 q6 2 6 8 q0 6 -6 8 v16 h-5 v-12 h-24 v12 Z" fill={`url(#${P}-bronze)`} />
          <path d="M-8 -16 h2 M0 -18 h2 M8 -16 h2 M-4 -12 h2 M4 -12 h2" stroke="#3a2010" strokeWidth="1.6" />
          <path d="M-20 -8 q-8 -4 -6 -14" stroke="#b0793a" strokeWidth="2" fill="none" />
        </g>
        <BronzeHead x={580} y={388} s={1.1} kind="idia" />
        <BronzeHead x={632} y={388} s={1.2} kind="oba" />
        {/* Queen Idia pendant mask on stand */}
        <g transform="translate(690 388)">
          <path d="M-2 0 v-10 h4 v10 Z" fill="#5a3418" />
          <ellipse cx="0" cy="-26" rx="11" ry="15" fill="#f2e6cc" />
          <path d="M-11 -32 Q0 -46 11 -32" stroke="#c9a070" strokeWidth="3" fill="none" />
          <path d="M-5 -28 h3 M2 -28 h3 M-3 -18 h6" stroke="#5a3418" strokeWidth="1.2" />
          <path d="M-8 -38 v18 M8 -38 v18" stroke="#c9a070" strokeWidth="0.8" opacity="0.6" />
        </g>
        <Plaque x={716} y={348} w={30} h={40} />
        <rect x="540" y="372" width="36" height="12" rx="1" fill="#fffaf0" transform="rotate(-6 558 378)" />
        <text x="558" y="381" fontSize="5.5" fontFamily={HAND_FONT} fill="#d2342a" textAnchor="middle" transform="rotate(-6 558 378)">price dey</text>
      </g>

      {/* IGUN STREET sign (green, as Benin street signs) */}
      <g>
        <rect x="128" y="196" width="5" height="250" fill="#5a5a6a" />
        <rect x="74" y="178" width="118" height="24" rx="2" fill="#1f7a3f" />
        <rect x="77" y="181" width="112" height="18" rx="1" fill="none" stroke="#f6f2ea" strokeWidth="1.2" />
        <text x="133" y="195" fontSize="11" fontFamily={SIGN_FONT} fill="#f6f2ea" textAnchor="middle" letterSpacing="1.5">IGUN STREET</text>
        <rect x="74" y="200" width="118" height="4" fill="#1d1230" opacity="0.4" />
      </g>
      {/* tourist with camera */}
      <Person x={430} y={440} s={1.6} skin="#7a4a32" top="#e0a526" bottom="#3a6fb0" pose="stand" facing={1} night={night}
        extra={<rect x="7" y="-36" width="9" height="6" rx="1" fill="#2a2a3a" />} />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[30, 86]} />
          {/* the furnace owns the night */}
          <Glow p={P} cx={214} cy={290} r={240} ry={170} kind="gf" o={0.95} />
          <Glow p={P} cx={230} cy={300} r={170} ry={120} kind="gf" o={1} />
          <Glow p={P} cx={300} cy={330} r={200} ry={90} kind="gw" o={0.5} />
          <Glow p={P} cx={214} cy={252} r={70} kind="gw" o={1} />
          <ellipse cx="214" cy="252" rx="20" ry="5" fill={`url(#${P}-mouth)`} />
          <path d={`M190 ${FL + 4} Q190 312 214 308 Q238 312 238 ${FL + 4} Z`} fill={`url(#${P}-mouth)`} opacity="0.9" />
          {sparks.map((s, i) => (
            <circle key={i} cx={s.x.toFixed(1)} cy={s.y.toFixed(1)} r="1.4" fill="#fff1b0" />
          ))}
          {/* crucible */}
          <Glow p={P} cx={240} cy={300} r={30} kind="gw" o={0.9} />
          {/* bulb over the shelves -> bronze glints */}
          <path d="M570 140 v18" stroke="#2a2232" strokeWidth="1" />
          <circle cx="570" cy="162" r="3.5" fill="#fff3c4" />
          <Glow p={P} cx={570} cy={210} r={170} ry={110} o={0.65} />
          {/* table lantern for late buyers */}
          <rect x="752" y="372" width="8" height="12" rx="2" fill="#ffe9a8" />
          <Glow p={P} cx={756} cy={378} r={90} o={0.8} />
          {/* neighbour window */}
          <Glow p={P} cx={29} cy={90} r={40} o={0.6} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
