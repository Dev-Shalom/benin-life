// L2 header: Samuel Ogbemudia Stadium: stands, floodlights, the pitch, Bendel Insurance fans. Fallback / Lite header.
import { Glow } from './_sharedA';
import { Frame, SignBoard } from './_sharedL2';

const P = 'stadium';

export default function StadiumScene({ night }: { night: boolean }) {
  const fans: [number, number, string][] = [];
  const cols = ['#1f7a3f', '#f4f2ee', '#1f7a3f', '#d2342a', '#f3d28a'];
  for (let r = 0; r < 6; r++) for (let i = 0; i < 52; i++) if ((i * 7 + r * 3) % 5 !== 0) fans.push([20 + i * 15 + (r % 2) * 7, 150 + r * 22, cols[(i + r) % 5]]);
  return (
    <Frame p={P} night={night} label="Samuel Ogbemudia Stadium" sun={[680, 60]} moon={[110, 56]}
      body={
        <g>
          {/* stand + roof */}
          <path d="M0 140 L800 140 L800 290 L0 290Z" fill="#c8c2b6" />
          {Array.from({ length: 7 }, (_, r) => <rect key={r} x="0" y={140 + r * 22} width="800" height="4" fill="#9a948a" />)}
          {fans.map(([x, y, c], i) => (
            <g key={i}>
              <rect x={x - 3} y={y + 4} width="7" height="9" rx="2" fill={c} />
              <circle cx={x + 0.5} cy={y + 1} r="3" fill="#5a3a26" />
            </g>
          ))}
          <path d="M-10 128 L810 128 L800 112 L0 112Z" fill="#2c3540" />
          {[80, 720].map((x) => (
            <g key={x}>
              <rect x={x} y="20" width="8" height="120" fill="#59616b" />
              <rect x={x - 22} y="14" width="52" height="22" fill="#3a3f48" />
            </g>
          ))}
          {/* track + pitch */}
          <rect x="0" y="290" width="800" height="26" fill="#b5552b" />
          {[0, 1, 2].map((i) => <rect key={i} x="0" y={294 + i * 8} width="800" height="1.5" fill="#f2efe6" opacity="0.6" />)}
          <rect x="0" y="316" width="800" height="134" fill="#3e9a4a" />
          {Array.from({ length: 8 }, (_, i) => <rect key={i} x={i * 100} y="316" width="50" height="134" fill="#469f52" />)}
          <rect x="0" y="330" width="800" height="3" fill="#f2efe6" />
          <ellipse cx="400" cy="400" rx="90" ry="26" fill="none" stroke="#f2efe6" strokeWidth="3" />
          <rect x="398" y="330" width="4" height="120" fill="#f2efe6" />
          {[[300, 380, '#1f7a3f'], [470, 410, '#d2342a'], [560, 372, '#1f7a3f']].map(([x, y, c], i) => (
            <g key={i}>
              <rect x={(x as number) - 4} y={(y as number) - 22} width="9" height="14" fill={c as string} />
              <rect x={(x as number) - 3} y={(y as number) - 9} width="7" height="10" fill="#f4f2ee" />
              <circle cx={(x as number) + 0.5} cy={(y as number) - 26} r="4" fill="#5a3a26" />
            </g>
          ))}
          <circle cx="420" cy="398" r="4" fill="#fff" />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={250} y={84} w={300} h={26} bg="#125a38" ink="#fff" text="SAMUEL OGBEMUDIA STADIUM" size={13} night={night} glow="green" />
          {[[58, 25], [698, 25]].map(([x, y]) => (
            <g key={x}>
              {night && <Glow p={P} kind="sun" cx={x + 26} cy={y} rx={120} o={0.8} />}
              {[0, 1, 2, 3].map((i) => <circle key={i} cx={x + 8 + i * 12} cy={y} r="4" fill={night ? '#fffbe6' : '#e6e8ec'} />)}
            </g>
          ))}
          {night && <Glow p={P} kind="cool" cx={400} cy={390} rx={420} ry={70} o={0.35} />}
        </g>
      }
    />
  );
}
