// L2 header: a GRA hotel (Protea / Golden Tulip): white block, pool, loungers and palms. Fallback / Lite header.
import { Glow, Palm, Person } from './_sharedA';
import { Frame, SignBoard, Win } from './_sharedL2';

const P = 'hotel';

export default function HotelScene({ night }: { night: boolean }) {
  const cols = Array.from({ length: 8 }, (_, i) => 236 + i * 42);
  const rows = [92, 132, 172, 212];
  return (
    <Frame p={P} night={night} label="Hotel with a pool" sun={[120, 72]} moon={[660, 60]}
      defs={
        <linearGradient id={`${P}-pool`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7fd3ee" />
          <stop offset="1" stopColor="#2a8fc0" />
        </linearGradient>
      }
      body={
        <g>
          <rect x="220" y="70" width="360" height="236" fill="#f6efe2" />
          <rect x="214" y="62" width="372" height="10" fill="#1d5874" />
          <rect x="550" y="70" width="30" height="236" fill="#2d1b4e" opacity="0.12" />
          {rows.map((y) => cols.map((x, i) => <Win key={`${x}-${y}`} x={x} y={y} w={28} h={26} night={night} lit={(i + y) % 3 !== 0} />))}
          {rows.map((y) => <rect key={y} x="224" y={y + 28} width="352" height="3" fill="#d6cbb6" />)}
          <rect x="360" y="256" width="80" height="50" fill="#22283e" />
          <path d="M340 256 L460 256 L470 246 L330 246Z" fill="#1d5874" />
          {/* deck + pool */}
          <rect x="0" y="306" width="800" height="144" fill="#e8dcc6" />
          <rect x="0" y="306" width="800" height="5" fill="#2d1b4e" opacity="0.12" />
          <rect x="150" y="340" width="500" height="70" rx="6" fill="#f3eee6" />
          <rect x="160" y="348" width="480" height="54" rx="4" fill={`url(#${P}-pool)`} />
          {[0, 1, 2, 3].map((i) => <path key={i} d={`M${190 + i * 120} 372 q14 -6 28 0 t28 0`} stroke="#fff" strokeOpacity="0.5" strokeWidth="2" fill="none" />)}
          {/* loungers + umbrellas */}
          {[60, 690].map((x) => (
            <g key={x}>
              <rect x={x} y="386" width="60" height="10" fill="#fff" />
              <rect x={x} y="374" width="20" height="14" fill="#fff" transform={`rotate(-25 ${x} 386)`} />
              <rect x={x + 28} y="330" width="3" height="58" fill="#7a5a3a" />
              <path d={`M${x - 4} 334 Q${x + 30} 300 ${x + 64} 334Z`} fill="#f2c230" />
            </g>
          ))}
          <Palm x={120} y={316} s={1.2} />
          <Palm x={680} y={316} s={1.15} lean={-1} />
          <Person x={420} y={380} s={0.9} top="#2f6fb3" bottom="#2f6fb3" skin="#5a3a26" arm="up" />
          <Person x={580} y={330} s={1} top="#f4f2ee" bottom="#1d5874" arm="hold" hold="#ff8a5c" />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={300} y={34} w={200} h={26} bg="#1d5874" ink="#f3d28a" text="HOTEL" size={18} night={night} glow="blue" />
          {night && (
            <g>
              {rows.map((y) => cols.map((x, i) => ((i + y) % 3 !== 0 ? <rect key={`${x}-${y}`} x={x} y={y} width={28} height={26} fill="#ffd88a" opacity="0.6" style={{ mixBlendMode: 'screen' }} /> : null)))}
              <Glow p={P} kind="teal" cx={400} cy={375} rx={260} ry={40} o={0.55} />
            </g>
          )}
        </g>
      }
    />
  );
}
