// Benin Airport — terminal, control tower, airliner on the apron — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Palm, Treeline, Haze, SIGN_FONT, dim } from './_sharedB';

const P = 'airport';
const AP = 322; // apron far edge

function Airliner({ night }: { night: boolean }) {
  // facing left; nose ~ (150,342), tail ~ (540,300)
  const body = night ? '#c9cbe0' : '#f6f7fb';
  const belly = night ? '#8a8db0' : '#c9ccd8';
  const green = '#1f7a3f';
  const win = Array.from({ length: 26 }, (_, i) => `M${232 + i * 10.5} 334h4.5v6h-4.5Z`).join('');
  return (
    <g>
      {/* ground shadow */}
      <ellipse cx="350" cy="398" rx="230" ry="9" fill="#2d1b4e" opacity="0.35" />
      {/* far wing (behind fuselage) */}
      <path d="M318 344 L376 344 L410 312 L396 312 Z" fill={dim('#b9bccb', night)} />
      {/* tail fin + stabiliser */}
      <path d="M470 326 L548 322 L574 236 L548 236 Z" fill={night ? '#203a3a' : green} />
      <path d="M520 268 L566 266 L574 236 L556 236 Z" fill="#fff" opacity={night ? 0.25 : 0.9} />
      <circle cx="540" cy="290" r="11" fill="#d9a441" />
      <circle cx="540" cy="290" r="6" fill="#b0793a" />
      <path d="M536 287 h8 M537 292 h6" stroke="#5a3a1a" strokeWidth="1.2" />
      <path d="M512 330 L572 326 L584 316 L540 318 Z" fill={night ? '#9a9cba' : '#dfe1ea'} />
      {/* fuselage */}
      <path d="M150 352 Q150 330 178 324 L520 318 Q548 316 560 322 L560 330 Q540 352 500 360 L190 366 Q152 366 150 352 Z" fill={body} />
      <path d="M152 356 Q160 366 190 366 L500 360 Q540 352 560 330 L560 336 Q540 358 500 366 L190 372 Q156 370 152 356 Z" fill={belly} />
      <path d="M160 346 L556 330" stroke={night ? '#203a3a' : green} strokeWidth="4" />
      <path d="M160 351 L556 335" stroke="#d9a441" strokeWidth="1.6" />
      <path d={win} fill={night ? '#ffd58a' : '#2c3a58'} />
      {/* cockpit + door */}
      <path d="M160 336 Q166 328 178 327 L184 336 Z" fill={night ? '#cfe8ff' : '#2c3a58'} />
      <rect x="212" y="330" width="11" height="20" rx="2" fill="none" stroke={belly} strokeWidth="1.4" />
      <text x="330" y="331" fontSize="9" fontFamily={SIGN_FONT} fill={night ? '#2a4a4a' : green}>EDO AIR</text>
      <path d="M190 323 L520 317" stroke="#fff" strokeWidth="2" opacity="0.6" />
      {/* near wing + engine */}
      <path d="M330 356 L404 354 L470 404 L444 406 Z" fill={night ? '#a6a9c6' : '#e4e6ee'} />
      <path d="M404 354 L470 404 L456 405 L396 356 Z" fill="#3b2a5e" opacity="0.15" />
      <rect x="356" y="364" width="52" height="20" rx="10" fill={night ? '#8a8db0' : '#d6d9e4'} />
      <ellipse cx="358" cy="374" rx="5" ry="10" fill="#2a2a3a" />
      <rect x="380" y="366" width="28" height="18" rx="9" fill="#3b2a5e" opacity="0.15" />
      {/* gear */}
      <path d="M184 368 V390 M380 368 V390 M398 366 V390" stroke="#4a4a5a" strokeWidth="3" />
      <circle cx="184" cy="392" r="6" fill="#1f1d2a" />
      <circle cx="376" cy="392" r="7" fill="#1f1d2a" />
      <circle cx="396" cy="392" r="7" fill="#1f1d2a" />
      {night && (
        <g>
          <circle cx="470" cy="404" r="2.5" fill="#4dff88" />
          <circle cx="574" cy="236" r="2" fill="#fff" />
          <circle cx="350" cy="372" r="2.5" fill="#ff4a4a" />
        </g>
      )}
    </g>
  );
}

export default function AirportScene({ night }: { night: boolean }) {
  const skyHole = `M0 0 H800 V250 H726 V96 H648 V250 H0 Z`;
  const mull = Array.from({ length: 25 }, (_, i) => `M${52 + i * 22} 214V${AP - 4}`).join('');
  const board = [
    ['LAGOS', '10:40', 'ON TIME'],
    ['ABUJA', '12:15', 'BOARDING'],
    ['PORT H.', '13:05', 'DELAYED'],
    ['ACCRA', '15:30', 'ON TIME'],
  ];
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Benin Airport">
      <defs>
        <linearGradient id={`${P}-glass`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#2a3a6a' : '#9cc3e0'} />
          <stop offset="0.5" stopColor={night ? '#3a4a80' : '#5f8fb8'} />
          <stop offset="1" stopColor={night ? '#4a3a6a' : '#3c5f86'} />
        </linearGradient>
        <linearGradient id={`${P}-apron`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#b7b2b4" />
          <stop offset="0.5" stopColor="#a39c9c" />
          <stop offset="1" stopColor="#8a8282" />
        </linearGradient>
        <linearGradient id={`${P}-roof`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#f2f3f7" />
          <stop offset="1" stopColor="#b9bccb" />
        </linearGradient>
        <linearGradient id={`${P}-tower`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor={night ? '#8e8aa8' : '#f4ecdc'} />
          <stop offset="0.6" stopColor={night ? '#706c92' : '#e2d4bc'} />
          <stop offset="1" stopColor={night ? '#4a4670' : '#b8a8a8'} />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={130} sunY={60} moonX={560} moonY={64} />
      {!night && <path d="M330 34 L600 74" stroke="#fff" strokeWidth="2.5" opacity="0.6" strokeLinecap="round" />}

      {/* far treeline + haze */}
      <Treeline y={250} fill={night ? '#1a2644' : '#86ab92'} seed={41} amp={12} step={30} base={330} />
      <Haze p={P} y={200} h={90} night={night} o={0.5} />

      {/* control tower */}
      <g>
        <path d="M664 330 L670 130 L704 130 L710 330 Z" fill={`url(#${P}-tower)`} />
        <path d="M694 130 L704 130 L710 330 L698 330 Z" fill="#3b2a5e" opacity="0.18" />
        <path d="M672 180 h30 M671 230 h32 M669 280 h36" stroke="#c9b9a0" strokeWidth="2" />
        <rect x="662" y="124" width="50" height="8" fill="#d9cdbb" />
        <path d="M650 124 L724 124 L716 96 L658 96 Z" fill={night ? '#7dffd0' : '#3f7e8a'} />
        <path d={`M668 124 L670 96 M682 124 L682 96 M696 124 L694 96 M710 124 L708 96`} stroke="#2a3a4a" strokeWidth="1.6" />
        {!night && <path d="M660 120 L676 98 L682 98 L666 120 Z" fill="#e9f4ff" opacity="0.5" />}
        <path d="M652 96 h70 l-6 -8 h-58 Z" fill="#e6e2da" />
        <path d="M687 88 V64 M681 72 h12" stroke="#5a5a6a" strokeWidth="2" />
        <circle cx="687" cy="63" r="2.6" fill="#ff3a2a" />
      </g>

      {/* terminal building */}
      <g>
        <rect x="40" y="210" width="560" height={AP - 210} fill="#e9e0d0" />
        <rect x="48" y="214" width="544" height={AP - 218} fill={`url(#${P}-glass)`} />
        <path d={mull} stroke={night ? '#1e2240' : '#e8eef4'} strokeWidth="2" />
        <path d={`M48 262 H592`} stroke={night ? '#1e2240' : '#e8eef4'} strokeWidth="3" />
        {!night && <path d="M70 318 L130 214 L170 214 L110 318 Z M300 318 L360 214 L380 214 L320 318 Z" fill="#fff" opacity="0.2" />}
        {/* wave canopy roof */}
        <path d="M20 214 Q160 168 320 196 Q470 222 620 186 L626 200 Q470 236 320 210 Q160 184 20 228 Z" fill={`url(#${P}-roof)`} />
        <path d="M20 228 Q160 184 320 210 Q470 236 626 200 L626 205 Q470 242 320 216 Q160 190 20 234 Z" fill="#3b2a5e" opacity="0.3" />
        {/* support struts */}
        <path d="M80 226 L96 250 M240 200 L250 230 M400 214 L410 240 M560 196 L570 226" stroke="#c9ccd8" strokeWidth="3" />
        {/* name on the roof */}
        <rect x="186" y="150" width="168" height="34" rx="3" fill="#1f7a3f" transform="rotate(4 270 167)" />
        <text x="270" y="174" fontSize="22" fontFamily={SIGN_FONT} fill="#fffaf0" textAnchor="middle" transform="rotate(4 270 167)" letterSpacing="3">BENIN</text>
        <text x="300" y="207" fontSize="7" fontFamily={SIGN_FONT} fill={night ? '#c9d2ff' : '#3a3a4a'} textAnchor="middle" transform="rotate(5 300 207)" letterSpacing="2">AIRPORT · FEDERAL AIRPORTS AUTHORITY</text>
        {/* departures board on the facade */}
        <g transform="translate(70 236)">
          <rect x="-4" y="-4" width="148" height="84" rx="3" fill="#1e1c28" />
          <rect width="140" height="76" fill="#121018" />
          <text x="6" y="11" fontSize="8" fontFamily={SIGN_FONT} fill="#ffcf3a">DEPARTURES</text>
          <path d="M6 15 H134" stroke="#ffcf3a" strokeWidth="0.6" opacity="0.6" />
          {board.map(([c, t, s], i) => (
            <g key={c} fontFamily="'Courier New', monospace" fontSize="8" fontWeight="bold">
              <text x="6" y={27 + i * 13} fill="#ffe08a">{c}</text>
              <text x="58" y={27 + i * 13} fill="#ffe08a">{t}</text>
              <text x="92" y={27 + i * 13} fill={s === 'DELAYED' ? '#ff6a4a' : s === 'BOARDING' ? '#7dff9a' : '#ffe08a'}>{s}</text>
            </g>
          ))}
        </g>
        <rect x="40" y={AP - 6} width="560" height="6" fill="#8a8282" />
      </g>
      {/* windsock */}
      <path d="M760 330 V262" stroke="#6a6a7a" strokeWidth="2" />
      <path d="M760 262 L792 268 L790 278 L760 276 Z" fill="#ff7a1a" />
      <path d="M770 264 v13 M780 266 v12" stroke="#fff" strokeWidth="3" />

      {/* apron */}
      <rect x="-10" y={AP} width="820" height={460 - AP} fill={`url(#${P}-apron)`} />
      <rect x="-10" y={AP} width="820" height="4" fill={night ? '#203030' : '#5f8a4a'} />
      <path d="M-10 336 H810" stroke="#e8e2d0" strokeWidth="1.2" strokeDasharray="14 10" opacity="0.6" />
      <path d="M184 452 Q200 410 184 392 M60 450 Q240 400 520 400 Q700 400 810 380" stroke="#f2c81a" strokeWidth="3" fill="none" opacity="0.85" />
      <text x="250" y="440" fontSize="20" fontFamily={SIGN_FONT} fill="#f2c81a" opacity="0.7" transform="skewX(-20)">4</text>
      <path d="M0 420 Q300 404 800 430" stroke="#6a6262" strokeWidth="22" opacity="0.12" fill="none" />

      <Airliner night={night} />

      {/* boarding stairs + passengers */}
      <g>
        <path d="M218 352 L270 404 L292 404 L240 352 Z" fill="#e9e6e0" />
        <path d={Array.from({ length: 8 }, (_, i) => `M${222 + i * 6.5} ${356 + i * 6.5}h22`).join('')} stroke="#9b97b0" strokeWidth="1.5" />
        <path d="M218 352 L270 404 M240 342 L292 394" stroke="#d2342a" strokeWidth="2" />
        <rect x="262" y="398" width="40" height="10" fill="#d2342a" />
        <circle cx="270" cy="410" r="4" fill="#1f1d2a" />
        <circle cx="296" cy="410" r="4" fill="#1f1d2a" />
      </g>
      <Person x={250} y={386} s={0.5} skin="#5a3624" top="#2f6fd0" bottom="#2b3350" night={night} />
      <Person x={318} y={406} s={0.55} skin="#4a2c1e" top="#7a3fa0" wrapper="#7a3fa0" headwrap="#e0a526" pose="walk" night={night} />

      {/* palms */}
      <Palm x={18} y={336} s={1.1} night={night} kind="coconut" lean={14} />
      <Palm x={620} y={334} s={0.8} night={night} kind="coconut" lean={-10} tone={1} />

      {/* baggage tug + carts */}
      <g transform="translate(600 424)">
        <ellipse cx="60" cy="2" rx="96" ry="6" fill="#2d1b4e" opacity="0.35" />
        <rect x="0" y="-26" width="40" height="22" rx="3" fill="#e0a526" />
        <rect x="22" y="-40" width="16" height="16" fill={night ? '#1d2448' : '#5f8fb8'} />
        <path d="M20 -40 h20" stroke="#2a2a3a" strokeWidth="2" />
        <circle cx="10" cy="-4" r="6" fill="#1f1d2a" />
        <circle cx="32" cy="-4" r="6" fill="#1f1d2a" />
        {[48, 98].map((x) => (
          <g key={x}>
            <path d={`M${x - 8} -12 h-4`} stroke="#5a5a6a" strokeWidth="2" />
            <rect x={x} y="-14" width="44" height="6" fill="#7d8090" />
            <rect x={x + 3} y="-30" width="13" height="16" rx="2" fill="#d2342a" />
            <rect x={x + 17} y="-26" width="12" height="12" rx="2" fill="#2f6fd0" />
            <rect x={x + 30} y="-32" width="11" height="18" rx="2" fill="#2b3350" />
            <path d="M9 0" />
            <circle cx={x + 8} cy="-4" r="4" fill="#1f1d2a" />
            <circle cx={x + 36} cy="-4" r="4" fill="#1f1d2a" />
          </g>
        ))}
      </g>

      {/* marshaller in hi-vis with wands */}
      <Person x={110} y={438} s={1.35} skin="#4a2c1e" top="#f2c81a" bottom="#2b3350" pose="work" facing={1} night={night}
        extra={<g><path d="M-6 -40 L6 -40 M-7 -32 L7 -32" stroke="#fffbe6" strokeWidth="1.6" opacity="0.8" /><path d="M-10 -25 L-14 -12" stroke="#ff7a1a" strokeWidth="3" strokeLinecap="round" /><path d="M16 -30 L24 -40" stroke="#ff7a1a" strokeWidth="3" strokeLinecap="round" /><path d="M-5 -55 h10 v-3 h-10 Z" fill="#f2f0ea" /></g>} />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} feather={[190, 250]} />
          {/* terminal interior glow */}
          <rect x="48" y="214" width="544" height={AP - 218} fill="#ffcf73" opacity="0.28" style={{ mixBlendMode: 'screen' }} />
          <Glow p={P} cx={160} cy={270} r={140} ry={60} o={0.6} />
          <Glow p={P} cx={420} cy={270} r={160} ry={60} o={0.5} />
          {/* board glows */}
          <Glow p={P} cx={140} cy={274} r={80} ry={50} o={0.5} />
          <g transform="translate(70 236)">
            <rect width="140" height="76" fill="#121018" />
            <text x="6" y="11" fontSize="8" fontFamily={SIGN_FONT} fill="#ffcf3a">DEPARTURES</text>
            {board.map(([c, t, s], i) => (
              <g key={c} fontFamily="'Courier New', monospace" fontSize="8" fontWeight="bold">
                <text x="6" y={27 + i * 13} fill="#ffe08a">{c}</text>
                <text x="58" y={27 + i * 13} fill="#ffe08a">{t}</text>
                <text x="92" y={27 + i * 13} fill={s === 'DELAYED' ? '#ff6a4a' : s === 'BOARDING' ? '#7dff9a' : '#ffe08a'}>{s}</text>
              </g>
            ))}
          </g>
          {/* lit roof sign */}
          <Glow p={P} cx={270} cy={168} r={120} ry={40} kind="gg" o={0.35} />
          {/* tower cab */}
          <Glow p={P} cx={687} cy={110} r={60} kind="gg" o={0.6} />
          <Glow p={P} cx={687} cy={63} r={14} kind="gf" o={1} />
          {/* plane windows + nav lights */}
          <path d={Array.from({ length: 26 }, (_, i) => `M${232 + i * 10.5} 334h4.5v6h-4.5Z`).join('')} fill="#ffd58a" opacity="0.8" />
          <Glow p={P} cx={470} cy={404} r={16} kind="gg" o={0.9} />
          <Glow p={P} cx={350} cy={372} r={18} kind="gf" o={0.9} />
          {/* apron edge lights */}
          {Array.from({ length: 20 }, (_, i) => (
            <g key={i}>
              <circle cx={i * 42 + 10} cy={AP + 3} r="1.8" fill={i % 2 ? '#7aa8ff' : '#ffd27a'} />
              <Glow p={P} cx={i * 42 + 10} cy={AP + 3} r={10} kind={i % 2 ? 'gc' : 'gw'} o={0.8} />
            </g>
          ))}
          {/* floodlit apron pool + marshaller wands */}
          <Glow p={P} cx={360} cy={410} r={300} ry={50} o={0.3} />
          <Glow p={P} cx={90} cy={420} r={12} kind="gf" o={1} />
          <Glow p={P} cx={133} cy={385} r={12} kind="gf" o={1} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
