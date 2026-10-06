// L2 header: Ogba Zoo & Nature Park: the gate arch, big shady trees, a lion and ostriches. Fallback / Lite header.
import { Glow, Person, Tree } from './_sharedA';
import { Frame, SignBoard } from './_sharedL2';

const P = 'zoo';

function Lion({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="0" cy="2" rx="40" ry="5" fill="#2d1b4e" opacity="0.3" />
      <rect x="-30" y="-30" width="54" height="22" rx="10" fill="#d1a15a" />
      {[-26, -14, 10, 20].map((lx) => <rect key={lx} x={lx} y="-12" width="7" height="14" rx="2" fill="#c08e48" />)}
      <circle cx="30" cy="-34" r="16" fill="#8a5a2a" />
      <circle cx="33" cy="-32" r="10" fill="#d1a15a" />
      <circle cx="37" cy="-34" r="1.6" fill="#241733" />
      <path d="M-30 -24 Q-44 -30 -40 -44" stroke="#c08e48" strokeWidth="3" fill="none" />
    </g>
  );
}
function Ostrich({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="0" cy="-34" rx="16" ry="11" fill="#2a2420" />
      <path d="M8 -40 Q14 -60 10 -74" stroke="#d8b8a0" strokeWidth="4" fill="none" />
      <ellipse cx="11" cy="-76" rx="5" ry="3.5" fill="#d8b8a0" />
      <line x1="-4" y1="-26" x2="-6" y2="0" stroke="#d8b8a0" strokeWidth="3" />
      <line x1="4" y1="-26" x2="6" y2="0" stroke="#d8b8a0" strokeWidth="3" />
    </g>
  );
}

export default function ZooScene({ night }: { night: boolean }) {
  return (
    <Frame p={P} night={night} label="Ogba Zoo gate" sun={[660, 70]} moon={[120, 60]}
      body={
        <g>
          {/* far bush */}
          <path d="M0 250 Q100 200 200 236 T400 226 T600 232 T800 220 V320 H0Z" fill="#3f6e1c" />
          <path d="M0 280 Q120 240 240 268 T480 262 T800 256 V330 H0Z" fill="#4f8a2a" />
          <rect x="0" y="316" width="800" height="134" fill="#c9a77a" />
          <rect x="0" y="316" width="800" height="5" fill="#2d1b4e" opacity="0.12" />
          <Tree x={70} y={330} s={1.6} />
          <Tree x={740} y={330} s={1.5} />
          <Tree x={600} y={320} s={1.1} />
          {/* gate */}
          <rect x="250" y="150" width="34" height="170" fill="#8a6a44" />
          <rect x="516" y="150" width="34" height="170" fill="#8a6a44" />
          <path d="M240 150 Q400 90 560 150 L560 170 Q400 112 240 170Z" fill="#5a3f22" />
          <rect x="284" y="250" width="232" height="70" fill="#5a3f22" opacity="0.35" />
          {/* fence */}
          {Array.from({ length: 24 }, (_, i) => (i < 6 || i > 17 ? <rect key={i} x={i * 34 + 4} y="274" width="5" height="46" fill="#6a4a2a" /> : null))}
          <rect x="0" y="282" width="250" height="4" fill="#6a4a2a" />
          <rect x="550" y="282" width="250" height="4" fill="#6a4a2a" />
          <Lion x={150} y={372} s={1.1} />
          <Ostrich x={640} y={380} s={1} />
          <Ostrich x={690} y={392} s={0.9} />
          {[360, 392, 430].map((x, i) => (
            <Person key={x} x={x} y={360 + i * 6} s={1.05} top={['#d2342a', '#1f7a3f', '#f3d28a'][i]} bottom="#2c2f5c" wrapper={i === 1} head={i === 1 ? 'gele' : 'hair'} headColor="#d9a441" arm={i === 0 ? 'out' : 'down'} />
          ))}
          <Person x={410} y={372} s={0.6} top="#2f6fb3" bottom="#2c2f5c" arm="up" />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={300} y={110} w={200} h={34} bg="#3f6e1c" ink="#f3d28a" text="OGBA ZOO" size={22} night={night} glow="green" />
          {night && <Glow p={P} kind="warm" cx={400} cy={300} rx={160} ry={40} o={0.4} />}
        </g>
      }
    />
  );
}
