// L2 header: Benin City Mall (ShopRite anchor, Genesis Cinema) on Sapele Rd. Fallback / Lite header.
import { Car, Glow, Palm, Person } from './_sharedA';
import { Frame, Ground, SignBoard, Win } from './_sharedL2';

const P = 'mall';

export default function MallScene({ night }: { night: boolean }) {
  const glass = Array.from({ length: 9 }, (_, i) => 200 + i * 44);
  const shoppers: [number, string, string, boolean][] = [[180, '#d2342a', '#2c2f5c', false], [262, '#1f7a3f', '#f3d28a', true], [478, '#6d4aa0', '#2c2f5c', false], [560, '#e07a2e', '#1f3a5a', true], [628, '#2f6fb3', '#2a2a2a', false]];
  return (
    <Frame p={P} night={night} label="Benin City Mall with ShopRite" sun={[680, 70]} moon={[110, 60]}
      body={
        <g>
          {/* mall block */}
          <rect x="120" y="120" width="560" height="200" fill="#efe9de" />
          <rect x="120" y="112" width="560" height="12" fill="#c8c0b2" />
          <rect x="120" y="120" width="40" height="200" fill="#2d1b4e" opacity="0.08" />
          <rect x="640" y="120" width="40" height="200" fill="#2d1b4e" opacity="0.14" />
          {/* red ShopRite band */}
          <rect x="120" y="150" width="300" height="44" fill="#d2342a" />
          <rect x="430" y="150" width="250" height="44" fill="#2a2440" />
          {/* glass front */}
          <rect x="190" y="214" width="420" height="106" fill="#3e4f78" />
          {glass.map((x) => <Win key={x} x={x} y={220} w={38} h={96} night={night} />)}
          {glass.map((x) => <rect key={`m${x}`} x={x - 3} y="214" width="3" height="106" fill="#c8c0b2" />)}
          <rect x="370" y="244" width="60" height="76" fill="#22283e" />
          <rect x="360" y="236" width="80" height="8" fill="#c8c0b2" />
          {/* canopy */}
          <path d="M180 214 L620 214 L640 204 L160 204Z" fill="#9aa3ad" />
          <Ground p={P} tone="#cfc3ae" />
          {/* parking + cars */}
          <Car x={60} y={378} s={1} body="#c8ccd6" />
          <Car x={690} y={378} s={1} flip body="#d2342a" dark="#7a1f12" />
          <Palm x={92} y={330} s={1.1} />
          <Palm x={712} y={330} s={1.05} lean={-1} />
          {shoppers.map(([x, top, bottom, w], i) => (
            <Person key={i} x={x} y={350 + (i % 2) * 14} s={1.05} top={top} bottom={bottom} wrapper={w} head={w ? 'gele' : 'hair'} headColor={w ? '#d9a441' : '#1b1424'} arm={i % 2 ? 'hold' : 'phone'} hold="#d2342a" flip={i > 2} />
          ))}
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={130} y={156} w={280} h={32} bg="#d2342a" ink="#ffffff" text="ShopRite" size={22} night={night} glow="red" />
          <SignBoard p={P} x={440} y={156} w={230} h={32} bg="#2a2440" ink="#f3d28a" text="BENIN CITY MALL" size={15} night={night} glow="warm" />
          {night && (
            <g>
              {glass.map((x) => <rect key={x} x={x} y={220} width={38} height={96} fill="#ffd88a" opacity="0.55" style={{ mixBlendMode: 'screen' }} />)}
              <Glow p={P} kind="warm" cx={400} cy={300} rx={260} ry={60} o={0.5} />
            </g>
          )}
        </g>
      }
    />
  );
}
