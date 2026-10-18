// R7 The Lounge, GRA header art (800x450): warm wood bar and bottles on the left, two velvet sofas, a pool table, pendant lamps and a gold
// "THE LOUNGE" sign. The window shows GRA by day or night. Ids are prefixed "lounge-" (several scenes can be in the DOM).
const P = 'lounge';

export default function Lounge({ night }: { night: boolean; name?: string }) {
  const wall = night ? '#2a2018' : '#4a3426';
  const glow = night ? 0.95 : 0.55;
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="The Lounge, GRA">
      <defs>
        <linearGradient id={`${P}-wall`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={wall} />
          <stop offset="1" stopColor={night ? '#3a2a1e' : '#5c4130'} />
        </linearGradient>
        <linearGradient id={`${P}-sky`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#0e1430' : '#9fd3ee'} />
          <stop offset="1" stopColor={night ? '#2a2350' : '#f6e1b0'} />
        </linearGradient>
        <radialGradient id={`${P}-lamp`}>
          <stop offset="0" stopColor="#ffd88a" stopOpacity={glow} />
          <stop offset="1" stopColor="#ffd88a" stopOpacity="0" />
        </radialGradient>
        <linearGradient id={`${P}-felt`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2a8a5e" />
          <stop offset="1" stopColor="#176b46" />
        </linearGradient>
      </defs>
      <rect width="800" height="450" fill={`url(#${P}-wall)`} />
      {/* wall panels */}
      {[0, 1, 2, 3, 4, 5, 6].map((i) => <rect key={i} x={20 + i * 116} y="40" width="96" height="250" rx="4" fill="#000" opacity={night ? 0.16 : 0.1} />)}
      {/* window onto GRA */}
      <g>
        <rect x="300" y="62" width="200" height="150" rx="6" fill={`url(#${P}-sky)`} stroke="#d9b25a" strokeWidth="5" />
        {[0, 1, 2, 3, 4].map((i) => <rect key={i} x={312 + i * 36} y={150 - (i % 3) * 14} width="26" height={62 + (i % 3) * 14} fill={night ? '#171b3a' : '#9aa7b5'} />)}
        {night && [0, 1, 2, 3, 4].map((i) => <rect key={i} x={318 + i * 36} y={160 - (i % 3) * 14} width="5" height="5" fill="#ffd88a" />)}
        <path d="M400 62 V212 M300 137 H500" stroke="#d9b25a" strokeWidth="3" />
      </g>
      {/* sign */}
      <rect x="290" y="20" width="220" height="32" rx="8" fill="#1b1424" stroke="#d9b25a" strokeWidth="3" />
      <text x="400" y="43" textAnchor="middle" fontSize="20" fontWeight="900" letterSpacing="5" fontFamily="Arial Black, Arial, sans-serif" fill="#f3d28a">THE LOUNGE</text>
      {/* pendant lamps */}
      {[120, 400, 680].map((x) => (
        <g key={x}>
          <circle cx={x} cy="120" r="90" fill={`url(#${P}-lamp)`} />
          <path d={`M${x} 0 V86`} stroke="#1b1424" strokeWidth="2" />
          <path d={`M${x - 22} 106 Q${x} 74 ${x + 22} 106Z`} fill="#d9b25a" />
          <ellipse cx={x} cy="106" rx="22" ry="4" fill="#ffe7a8" />
        </g>
      ))}
      {/* floor */}
      <rect y="290" width="800" height="160" fill={night ? '#241a16' : '#6a4a34'} />
      <rect y="290" width="800" height="6" fill="#000" opacity="0.25" />
      {/* bar */}
      <g>
        <rect x="24" y="150" width="210" height="14" fill="#1b1424" />
        {[0, 1, 2, 3, 4, 5, 6].map((i) => <rect key={i} x={34 + i * 28} y={118 + (i % 2) * 10} width="9" height={32 - (i % 2) * 10} rx="3" fill={['#1f5a2a', '#9c1f19', '#c8ced4', '#7a4f00'][i % 4]} />)}
        <rect x="14" y="230" width="230" height="62" fill="#3b2418" />
        <rect x="14" y="222" width="236" height="12" fill="#d9b25a" />
        {[0, 1, 2].map((i) => (
          <g key={i}>
            <circle cx={50 + i * 70} cy="312" r="13" fill="#1b1424" />
            <rect x={46 + i * 70} y="312" width="8" height="40" fill="#3a3340" />
          </g>
        ))}
      </g>
      {/* sofas */}
      {[330, 530].map((x, i) => (
        <g key={x}>
          <rect x={x} y="268" width="150" height="50" rx="14" fill={i ? '#6d4aa0' : '#2f6fb3'} />
          <rect x={x - 8} y="286" width="22" height="46" rx="8" fill={i ? '#5a3b88' : '#245a96'} />
          <rect x={x + 136} y="286" width="22" height="46" rx="8" fill={i ? '#5a3b88' : '#245a96'} />
          <rect x={x + 10} y="296" width="130" height="34" rx="10" fill={i ? '#7d5cb3' : '#3d82c8'} />
          <rect x={x + 90} y="278" width="30" height="24" rx="6" fill="#d9b25a" />
          <rect x={x + 8} y="336" width="134" height="7" rx="3" fill="#000" opacity="0.28" />
        </g>
      ))}
      {/* coffee table */}
      <rect x="440" y="350" width="86" height="12" rx="3" fill="#d9b25a" />
      <rect x="450" y="362" width="6" height="22" fill="#1b1424" /><rect x="510" y="362" width="6" height="22" fill="#1b1424" />
      {/* pool table */}
      <g transform="translate(600 360)">
        <rect x="0" y="0" width="170" height="64" rx="8" fill="#3b2418" />
        <rect x="9" y="8" width="152" height="40" rx="5" fill={`url(#${P}-felt)`} />
        {[[30, 28, '#fff'], [110, 22, '#d2342a'], [124, 30, '#f2c230'], [96, 32, '#1b1424']].map(([x, y, c], i) => <circle key={i} cx={Number(x)} cy={Number(y)} r="5" fill={String(c)} />)}
        <path d="M-20 78 L120 20" stroke="#e9d6a8" strokeWidth="4" strokeLinecap="round" />
        <rect x="8" y="58" width="10" height="26" fill="#1b1424" /><rect x="152" y="58" width="10" height="26" fill="#1b1424" />
      </g>
    </svg>
  );
}
