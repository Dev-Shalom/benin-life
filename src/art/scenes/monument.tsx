// L2 header: the Emotan Statue (1954) opposite Oba Market: a respectful bronze figure on a white plinth,
// flowers at the base, market umbrellas behind. Fallback / Lite header.
import { Glow, Person, Tree } from './_sharedA';
import { Frame, Ground, SignBoard } from './_sharedL2';

const P = 'monument';

export default function MonumentScene({ night }: { night: boolean }) {
  return (
    <Frame p={P} night={night} label="Emotan Statue opposite Oba Market" sun={[650, 70]} moon={[120, 60]}
      body={
        <g>
          {/* market umbrellas behind */}
          {[60, 150, 240, 560, 650, 740].map((x, i) => (
            <g key={x}>
              <rect x={x - 1} y="230" width="3" height="70" fill="#6a4a2a" />
              <path d={`M${x - 44} 236 Q${x} 200 ${x + 44} 236Z`} fill={['#d2342a', '#1f7a3f', '#f2c230'][i % 3]} />
              <rect x={x - 30} y="276" width="60" height="24" fill="#8a5a33" />
            </g>
          ))}
          <Tree x={320} y={300} s={1.2} />
          <Tree x={490} y={300} s={1.1} />
          <Ground p={P} tone="#d8ccb6" y={300} road={false} />
          {/* plaza ring */}
          <ellipse cx="400" cy="372" rx="210" ry="44" fill="#cdbfa7" />
          <ellipse cx="400" cy="368" rx="150" ry="30" fill="#e8e2d6" />
          {/* plinth */}
          <rect x="350" y="300" width="100" height="62" fill="#f4f0e8" />
          <rect x="340" y="356" width="120" height="12" fill="#e2dccf" />
          <rect x="350" y="300" width="18" height="62" fill="#2d1b4e" opacity="0.08" />
          {/* Emotan figure (bronze) */}
          <path d="M378 300 Q372 250 384 222 L416 222 Q428 250 422 300Z" fill="#8a5a2a" />
          <path d="M400 222 L416 222 Q428 250 422 300 L404 300Z" fill="#5a3a1a" opacity="0.45" />
          <rect x="386" y="192" width="28" height="32" rx="8" fill="#9c6a2e" />
          <rect x="394" y="182" width="12" height="12" fill="#8a5a2a" />
          <circle cx="400" cy="172" r="12" fill="#8a5a2a" />
          <path d="M386 168 Q400 150 414 168 Q400 160 386 168Z" fill="#b0793a" />
          <path d="M414 198 Q428 214 424 236" stroke="#8a5a2a" strokeWidth="7" strokeLinecap="round" fill="none" />
          {/* flowers */}
          {[360, 378, 396, 414, 432].map((x, i) => <circle key={x} cx={x} cy="356" r="5" fill={['#d2342a', '#f2a516', '#f3f0e8'][i % 3]} />)}
          <Person x={250} y={392} s={1.05} top="#d2342a" bottom="#f3d28a" wrapper head="tray" />
          <Person x={560} y={396} s={1.05} top="#1f7a3f" bottom="#2c2f5c" arm="phone" flip />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={330} y={110} w={140} h={26} bg="#6e4f26" ink="#fff6dc" text="EMOTAN" size={16} night={night} glow="warm" />
          {night && <Glow p={P} kind="warm" cx={400} cy={250} rx={110} ry={130} o={0.5} />}
        </g>
      }
    />
  );
}
