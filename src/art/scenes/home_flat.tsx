// Mission Road mini flats (New Benin) — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, PlasticChair, Bucket, Generator, Car, Treeline, Haze, Bulb, SIGN_FONT } from './_sharedB';

const P = 'home_flat';

function Window({ x, y, w, h, night, lit, cool = false }: { x: number; y: number; w: number; h: number; night: boolean; lit: boolean; cool?: boolean }) {
  const glass = night ? (lit ? (cool ? '#cfe8ff' : '#ffd27a') : '#1c2244') : '#4d6a8c';
  return (
    <g>
      <rect x={x - 4} y={y - 4} width={w + 8} height={h + 8} fill="#c9a77d" />
      <rect x={x - 4} y={y + h} width={w + 8} height="5" fill="#f6e8cc" />
      <rect x={x} y={y} width={w} height={h} fill={glass} />
      {!night && <path d={`M${x} ${y + h * 0.7} L${x + w * 0.5} ${y} L${x + w * 0.7} ${y} L${x} ${y + h}`} fill="#b9d4ea" opacity="0.35" />}
      {night && lit && <rect x={x} y={y} width={w} height={h * 0.45} fill={cool ? '#e9f6ff' : '#ffe9b0'} opacity="0.5" />}
      {/* curtains */}
      <path d={`M${x} ${y} h${w * 0.22} q-3 ${h * 0.5} 2 ${h} h${-w * 0.22} Z M${x + w} ${y} h${-w * 0.22} q3 ${h * 0.5} -2 ${h} h${w * 0.22} Z`} fill={night && lit ? '#e8913a' : '#b8473a'} opacity="0.85" />
      {/* burglary-proof: bars with a swirl */}
      <path d={`M${x + w / 4} ${y} v${h} M${x + w / 2} ${y} v${h} M${x + (3 * w) / 4} ${y} v${h} M${x} ${y + h / 2} h${w}`} stroke="#2b2a3a" strokeWidth="1.6" />
      <circle cx={x + w / 2} cy={y + h / 2} r={Math.min(w, h) * 0.14} stroke="#2b2a3a" strokeWidth="1.4" fill="none" />
      <rect x={x - 4} y={y - 4} width={w + 8} height="3" fill="#2d1b4e" opacity="0.25" />
    </g>
  );
}

function Railing({ x, y, w }: { x: number; y: number; w: number }) {
  const n = Math.floor(w / 9);
  return (
    <g>
      <rect x={x} y={y} width={w} height="4" fill="#f4ead6" />
      <path d={Array.from({ length: n }, (_, i) => `M${x + 5 + i * 9} ${y + 4} v24`).join(' ')} stroke="#e9dcc2" strokeWidth="4" />
      <path d={Array.from({ length: n }, (_, i) => `M${x + 7 + i * 9} ${y + 4} v24`).join(' ')} stroke="#8a7a96" strokeWidth="1.4" opacity="0.6" />
      <rect x={x} y={y + 28} width={w} height="5" fill="#d8c6a6" />
    </g>
  );
}

export default function HomeFlatScene({ night }: { night: boolean }) {
  const tiles = [];
  for (let r = 0; r < 9; r++) {
    const y0 = 352 + r * r * 1.3 + r * 9;
    const y1 = 352 + (r + 1) * (r + 1) * 1.3 + (r + 1) * 9;
    const half0 = 46 + (y0 - 352) * 1.15;
    const half1 = 46 + (y1 - 352) * 1.15;
    tiles.push(<path key={`r${r}`} d={`M${400 - half0} ${y0} L${400 + half0} ${y0}`} stroke="#7a5a52" strokeWidth="0.9" opacity="0.6" />);
    const cols = 6;
    for (let c = 0; c <= cols; c++) {
      const off = r % 2 ? 0.5 : 0;
      const f = Math.min(1, (c + off) / cols);
      tiles.push(<path key={`c${r}-${c}`} d={`M${400 - half0 + 2 * half0 * f} ${y0} L${400 - half1 + 2 * half1 * f} ${y1}`} stroke="#7a5a52" strokeWidth="0.8" opacity="0.5" />);
    }
  }
  const skyHole = 'M0 0 H800 V290 H668 L604 165 L500 95 L300 95 L196 168 L196 290 H0 Z';
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Mission Road mini flats">
      <defs>
        <linearGradient id={`${P}-front`} x1="0" y1="0" x2="1" y2="0.3">
          <stop offset="0" stopColor="#fbe3bb" />
          <stop offset="0.5" stopColor="#f2cfa0" />
          <stop offset="1" stopColor="#e3b98c" />
        </linearGradient>
        <linearGradient id={`${P}-side`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#8d7697" />
          <stop offset="0.7" stopColor="#9a7f92" />
          <stop offset="1" stopColor="#b08a7e" />
        </linearGradient>
        <linearGradient id={`${P}-roof`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c0573c" />
          <stop offset="0.6" stopColor="#9c3b2a" />
          <stop offset="1" stopColor="#7a2a22" />
        </linearGradient>
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="0.4" stopColor="#b5552b" />
          <stop offset="1" stopColor="#8e3f22" />
        </linearGradient>
        <linearGradient id={`${P}-paving`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c99a86" />
          <stop offset="1" stopColor="#a8746a" />
        </linearGradient>
        <pattern id={`${P}-breeze`} patternUnits="userSpaceOnUse" width="12" height="12">
          <rect width="12" height="12" fill="#efdcbc" />
          <circle cx="6" cy="6" r="4" fill={night ? '#ffcf73' : '#3d3350'} />
          <path d="M0 0 L12 12 M12 0 L0 12" stroke="#efdcbc" strokeWidth="2" />
        </pattern>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={120} sunY={60} moonX={690} moonY={70} />

      {/* distant city: cathedral spire + rooftops */}
      <g opacity="0.75">
        <path d="M712 250 V176 L724 140 L736 176 V250 Z" fill={night ? '#2c2f5c' : '#b7b5c4'} />
        <path d="M719 160 h10 M724 152 v16" stroke={night ? '#3b3f74' : '#9896ad'} strokeWidth="2" />
        <Treeline y={262} fill={night ? '#1f2a48' : '#8fae95'} seed={4} amp={14} step={34} base={330} />
        {[[-10, 70, 262], [52, 64, 270], [108, 80, 258], [600, 70, 266], [660, 66, 256], [722, 90, 264]].map(([x, w, y], i) => (
          <g key={i}>
            <rect x={x + 6} y={y + 10} width={w - 12} height={340 - y} fill={night ? '#30335e' : '#d6c3ae'} />
            <path d={`M${x} ${y + 12} L${x + w * 0.5} ${y - 8} L${x + w} ${y + 12} Z`} fill={night ? '#3a3d6a' : '#a9aab8'} />
            <path d={`M${x + w * 0.5} ${y - 8} L${x + w} ${y + 12} L${x + w * 0.5} ${y + 12} Z`} fill={night ? '#2a2c55' : '#8e8fa2'} />
            <rect x={x + w * 0.3} y={y + 20} width="9" height="9" fill={night ? (i % 2 ? '#ffcf73' : '#1c2244') : '#7d7a90'} />
          </g>
        ))}
      </g>
      <Haze p={P} y={220} h={120} night={night} o={0.4} />

      {/* electric pole + sagging wires */}
      <g>
        <rect x="150" y="120" width="6" height="230" fill={night ? '#3b3348' : '#6f5a4a'} />
        <rect x="132" y="128" width="42" height="4" fill={night ? '#3b3348' : '#5c4a3e'} />
        <path d="M0 140 Q80 160 135 130 M0 150 Q80 172 170 130 Q400 175 800 120 M174 132 Q420 190 800 140" stroke="#2a2232" strokeWidth="1.2" fill="none" />
      </g>

      {/* water tank on steel stand */}
      <g>
        <path d="M672 345 L680 205 M720 345 L712 205 M676 270 L716 300 M716 270 L676 300" stroke={night ? '#3c3a4a' : '#5b5e6e'} strokeWidth="3" />
        <rect x="668" y="196" width="56" height="10" fill="#5b5e6e" />
        <path d="M672 196 Q670 150 696 146 Q722 150 720 196 Z" fill={night ? '#16182a' : '#2a2a38'} />
        <path d="M676 194 Q674 155 690 150" stroke="#8a8ca8" strokeWidth="3" fill="none" opacity="0.5" />
        <path d="M673 165 h46 M672 180 h48" stroke="#1a1a26" strokeWidth="2" />
        <text x="696" y="176" fontSize="6" fontFamily={SIGN_FONT} fill="#e0a526" textAnchor="middle">GeePee</text>
      </g>

      {/* boundary wall with the classic warning */}
      <path d="M-10 288 H215 V352 H-10 Z" fill="#e7cfa6" />
      <path d="M-10 288 H215 V296 H-10 Z" fill="#c9a77d" />
      <path d="M-10 340 H215 V352 H-10 Z" fill="#8e5a3e" opacity="0.6" />
      <text x="100" y="316" fontSize="12.5" fontFamily={SIGN_FONT} fill="#c0281f" textAnchor="middle" transform="rotate(-1 100 316)">THIS HOUSE IS</text>
      <text x="100" y="332" fontSize="12.5" fontFamily={SIGN_FONT} fill="#c0281f" textAnchor="middle" transform="rotate(-1 100 332)">NOT FOR SALE!!</text>

      {/* building — side wall (shadow) */}
      <path d="M590 172 L662 180 L662 340 L590 346 Z" fill={`url(#${P}-side)`} />
      <path d="M612 205 L640 208 L640 238 L612 236 Z" fill={night ? '#1c2244' : '#4a4466'} />
      <path d="M612 270 L640 272 L640 302 L612 301 Z" fill={night ? '#ffcf73' : '#4a4466'} />
      {/* front facade */}
      <rect x="210" y="170" width="380" height="176" fill={`url(#${P}-front)`} />
      {/* corner quoins */}
      <path d="M210 180 h10 v16 h-10 Z M210 212 h10 v16 h-10 Z M210 244 h10 v16 h-10 Z M210 276 h10 v16 h-10 Z M210 308 h10 v16 h-10 Z M580 180 h10 v16 h-10 Z M580 212 h10 v16 h-10 Z M580 244 h10 v16 h-10 Z M580 276 h10 v16 h-10 Z M580 308 h10 v16 h-10 Z" fill="#c98f5a" />
      {/* plinth */}
      <rect x="210" y="328" width="380" height="18" fill="#8e5a3e" />
      <rect x="210" y="328" width="380" height="3" fill="#b07a55" />
      {/* floor slab band */}
      <rect x="204" y="252" width="392" height="10" fill="#f6e8cc" />
      <rect x="204" y="260" width="392" height="5" fill="#2d1b4e" opacity="0.28" />
      {/* roof */}
      <path d="M196 168 L604 168 L500 96 L300 96 Z" fill={`url(#${P}-roof)`} />
      <path d="M604 168 L668 176 L500 96 Z" fill="#6a2620" />
      <path d={Array.from({ length: 22 }, (_, i) => { const x0 = 206 + i * 18.4; const x1 = 304 + i * 8.9; return `M${x0} 168 L${x1} 97`; }).join(' ')} stroke="#d97a55" strokeWidth="1.4" opacity="0.6" />
      <path d="M300 96 L500 96" stroke="#e08a62" strokeWidth="3" />
      <rect x="194" y="166" width="412" height="7" fill="#f4ead6" />
      <path d="M604 166 L670 174 L670 180 L604 173 Z" fill="#c8b8b6" />
      <rect x="200" y="173" width="400" height="6" fill="#2d1b4e" opacity="0.22" />

      {/* ground floor */}
      <Window x={240} y={282} w={70} h={40} night={night} lit />
      <Window x={490} y={282} w={70} h={40} night={night} lit={false} />
      {/* stairwell entrance + porch */}
      <rect x="360" y="268" width="80" height="78" fill="#c98f5a" />
      <rect x="368" y="276" width="64" height="70" fill={night ? '#2a2034' : '#2f2a3c'} />
      <path d="M368 276 h64 v70 h-64 Z" fill="none" stroke="#1e1a28" strokeWidth="2" />
      <path d="M376 282 v58 M386 282 v58 M396 282 v58 M406 282 v58 M416 282 v58 M424 282 v58 M368 300 h64 M368 320 h64" stroke="#4a4458" strokeWidth="1.6" />
      <path d="M348 268 L452 268 L446 258 L354 258 Z" fill="#f4ead6" />
      <rect x="348" y="268" width="104" height="4" fill="#2d1b4e" opacity="0.3" />
      <text x="400" y="266" fontSize="6" fontFamily={SIGN_FONT} fill="#8e3f22" textAnchor="middle">No. 14 MISSION RD</text>

      {/* first floor: breeze-block stair window */}
      <rect x="378" y="182" width="44" height="66" fill={`url(#${P}-breeze)`} />
      <rect x="378" y="182" width="44" height="66" fill="none" stroke="#c9a77d" strokeWidth="3" />
      {/* balconies */}
      <rect x="236" y="186" width="96" height="62" fill={night ? '#3a2a40' : '#5b4a62'} />
      <rect x="244" y="192" width="38" height="56" fill={night ? '#ffd27a' : '#4d6a8c'} />
      <rect x="286" y="192" width="38" height="56" fill={night ? '#ffc76a' : '#4d6a8c'} />
      <path d="M244 192 h80 v56" stroke="#e9dcc2" strokeWidth="2" fill="none" />
      <path d="M248 192 L268 248 M290 192 L310 248" stroke="#b9d4ea" strokeWidth="5" opacity={night ? 0 : 0.3} />
      <rect x="468" y="186" width="96" height="62" fill={night ? '#3a2a40' : '#5b4a62'} />
      <rect x="476" y="192" width="38" height="56" fill={night ? '#cfe8ff' : '#4d6a8c'} />
      <rect x="518" y="192" width="38" height="56" fill={night ? '#cfe8ff' : '#4d6a8c'} />
      <path d="M476 192 h80 v56" stroke="#e9dcc2" strokeWidth="2" fill="none" />
      <path d="M480 192 L500 248 M522 192 L542 248" stroke="#b9d4ea" strokeWidth="5" opacity={night ? 0 : 0.3} />
      {/* balcony life: chair + man, clothes, plant */}
      <PlasticChair x={262} y={250} s={0.8} color="#2f6fd0" shade="#1d3f7a" />
      <Person x={300} y={250} s={0.62} skin="#4a2c1e" top="#1f7a3f" bottom="#2b3350" pose="stand" night={night} />
      <path d="M470 214 Q516 222 562 214" stroke="#3a3346" strokeWidth="1" fill="none" />
      <path d="M478 216 h14 v16 h-14 Z" fill={night ? '#5a3a4a' : '#d2342a'} />
      <path d="M498 218 h12 l-1 22 h-10 Z" fill={night ? '#5a5a6a' : '#f2f0ea'} />
      <path d="M516 219 h16 v14 h-16 Z" fill={night ? '#5a4a3a' : '#e0a526'} />
      <path d="M538 218 h12 v18 h-12 Z" fill={night ? '#2a4a3a' : '#1f7a3f'} />
      <Railing x={228} y={222} w={112} />
      <Railing x={460} y={222} w={112} />
      <path d="M548 222 q-6 -14 4 -22 q2 10 -4 22 q10 -12 18 -10 q-8 6 -18 10" fill="#3f8a3a" />
      <rect x="544" y="214" width="14" height="10" fill="#b5552b" />
      {/* split AC + satellite dish */}
      <g>
        <rect x="216" y="202" width="16" height="22" fill="#e9e6e0" />
        <path d="M219 206 h10 M219 210 h10 M219 214 h10 M219 218 h10" stroke="#9b97b0" strokeWidth="1" />
        <g transform="translate(588 196) rotate(-30)">
          <ellipse cx="0" cy="0" rx="16" ry="18" fill="#e8e6e1" />
          <ellipse cx="2" cy="1" rx="12" ry="14" fill="#c8c6d0" />
          <path d="M0 0 L18 4" stroke="#7d8090" strokeWidth="2" />
          <circle cx="18" cy="4" r="2.5" fill="#3a3a4a" />
          <text x="-3" y="-4" fontSize="4" fontFamily={SIGN_FONT} fill="#1f4fa0" transform="rotate(30)">DStv</text>
        </g>
        <path d="M596 206 L606 214" stroke="#7d8090" strokeWidth="2" />
      </g>
      {/* cast shadows on facade (colored) */}
      <path d="M332 186 L346 186 L346 252 L332 252 Z M564 186 L578 186 L578 252 L564 252 Z" fill="#3b2a5e" opacity="0.18" />

      {/* ground */}
      <path d="M-10 346 H810 V460 H-10 Z" fill={`url(#${P}-ground)`} />
      <path d="M210 346 H662 L700 360 L180 362 Z" fill="#2d1b4e" opacity="0.25" />
      <path d="M346 346 L454 346 L560 460 L240 460 Z" fill={`url(#${P}-paving)`} />
      {tiles}
      <path d="M0 395 Q120 385 250 400 M0 430 Q140 420 300 440" stroke="#7a3519" strokeWidth="5" opacity="0.25" fill="none" />
      {/* puddle */}
      <ellipse cx="560" cy="420" rx="40" ry="6" fill={night ? '#6a74b8' : '#a9c8de'} opacity="0.6" />

      {/* parked car (Corolla) + car-wash boy */}
      <Car p={P} x={130} y={402} s={1.05} color="#3a6fb0" dark="#24467a" night={night} />
      <Bucket x={248} y={410} s={1} color="#e0a526" dark="#9a6b12" />
      <Person x={268} y={412} s={1.2} skin="#4a2c1e" top="#f2f0ea" bottom="#5a4a3a" pose="work" facing={-1} night={night} />

      {/* generator house */}
      <g>
        <path d="M600 420 V360 L680 352 L760 360 V420" fill="none" stroke="#3b3a46" strokeWidth="3" />
        <path d="M594 362 L680 348 L766 362 L766 368 L680 355 L594 368 Z" fill={night ? '#3d3f60' : '#9fa3b0'} />
        <path d="M600 372 V420 M620 372 V420 M640 372 V420 M720 372 V420 M740 372 V420 M760 372 V420 M600 390 H760" stroke="#3b3a46" strokeWidth="1.4" opacity="0.7" />
        <Generator p={P} x={680} y={418} s={1.5} night={night} color="#e0a526" />
        <path d="M712 405 Q730 390 700 370 Q660 350 662 320" stroke="#1a1824" strokeWidth="2" fill="none" />
      </g>

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[190, 290]} />
          <Glow p={P} cx={275} cy={302} r={80} o={0.75} />
          <Glow p={P} cx={284} cy={220} r={110} o={0.8} />
          <Glow p={P} cx={516} cy={220} r={100} kind="gc" o={0.6} />
          <Glow p={P} cx={400} cy={215} r={60} o={0.55} />
          <Glow p={P} cx={626} cy={287} r={40} o={0.6} />
          <Bulb p={P} x={400} y={272} night={night} wire={4} />
          <Glow p={P} cx={680} cy={400} r={40} o={0.5} />
          {/* moonlit rim on roof + tank */}
          <path d="M500 96 L604 168" stroke="#b9c2ff" strokeWidth="2" opacity="0.35" />
          <path d="M716 160 Q720 175 719 196" stroke="#b9c2ff" strokeWidth="2" fill="none" opacity="0.4" />
          {/* window panes re-lit after shading */}
          <rect x="244" y="192" width="80" height="56" fill="#ffd27a" opacity="0.35" />
          <rect x="476" y="192" width="80" height="56" fill="#cfe8ff" opacity="0.3" />
          <rect x="240" y="282" width="70" height="40" fill="#ffd27a" opacity="0.35" />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
