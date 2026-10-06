// L2 header: Kada Plaza (Kada Cinemas + Kada Fried Chicken), Old Sapele Rd. Fallback / Lite header.
import { Glow, Person, Palm } from './_sharedA';
import { Frame, Ground, SignBoard } from './_sharedL2';

const P = 'cinema';
const POSTERS = ['#d2342a', '#1f7a3f', '#6d4aa0', '#e07a2e'];

export default function CinemaScene({ night }: { night: boolean }) {
  const bulbs = Array.from({ length: 26 }, (_, i) => 176 + i * 17);
  return (
    <Frame p={P} night={night} label="Kada Plaza cinema" sun={[120, 70]} moon={[660, 64]}
      body={
        <g>
          <rect x="150" y="110" width="470" height="210" fill="#3a2f45" />
          <rect x="150" y="102" width="470" height="10" fill="#241c2e" />
          <rect x="590" y="110" width="30" height="210" fill="#140c1e" opacity="0.4" />
          {/* marquee */}
          <rect x="166" y="132" width="440" height="58" fill="#151832" />
          {/* posters */}
          {POSTERS.map((c, i) => (
            <g key={i}>
              <rect x={186 + i * 104} y="204" width="64" height="88" fill="#efe4cf" />
              <rect x={190 + i * 104} y="208" width="56" height="80" fill={c} />
              <circle cx={218 + i * 104} cy="236" r="12" fill="#2a1a12" opacity="0.6" />
              <rect x={196 + i * 104} y="270" width="44" height="6" fill="#fff" opacity="0.7" />
            </g>
          ))}
          {/* chicken shop to the right */}
          <rect x="630" y="190" width="150" height="130" fill="#f2efe6" />
          <rect x="630" y="180" width="150" height="14" fill="#d2342a" />
          <rect x="646" y="232" width="118" height="70" fill="#3e4f78" />
          <Ground p={P} tone="#bfb3a3" />
          <Palm x={70} y={340} s={1.1} />
          {/* queue */}
          {[300, 330, 360, 392, 424].map((x, i) => (
            <Person key={x} x={x} y={350} s={1} top={POSTERS[i % 4]} bottom="#2c2f5c" head={i % 2 ? 'gele' : 'cap'} headColor={i % 2 ? '#d9a441' : '#1b1424'} wrapper={i % 2 === 1} arm={i === 2 ? 'phone' : 'down'} flip />
          ))}
          <Person x={700} y={350} s={1} top="#d2342a" bottom="#2c2f5c" arm="hold" hold="#f3d28a" />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={176} y={140} w={420} h={42} bg="#151832" ink="#f3d28a" text="KADA CINEMAS" size={28} night={night} glow="warm" />
          <SignBoard p={P} x={636} y={196} w={138} h={28} bg="#d2342a" ink="#fff" text="KADA CHICKEN" size={13} night={night} glow="red" />
          {bulbs.map((x, i) => (
            <circle key={x} cx={x} cy="128" r="3" fill={night ? (i % 2 ? '#ffd27a' : '#ff9a3c') : '#f2ead8'} />
          ))}
          {night && <Glow p={P} kind="warm" cx={386} cy={320} rx={240} ry={50} o={0.45} />}
        </g>
      }
    />
  );
}
