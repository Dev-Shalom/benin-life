// L2 header: a Sapele Rd car dealer: glass showroom, bunting, tokunbo cars with price boards. Fallback / Lite header.
import { Car, Glow, Palm, Person } from './_sharedA';
import { Frame, Ground, SignBoard, Win } from './_sharedL2';

const P = 'car_dealer';
const FLAGS = ['#d2342a', '#f2c230', '#1f7a3f', '#2f6fb3'];

export default function CarDealerScene({ night }: { night: boolean }) {
  return (
    <Frame p={P} night={night} label="Car dealer on Sapele Road" sun={[120, 70]} moon={[660, 60]}
      body={
        <g>
          <rect x="140" y="140" width="520" height="180" fill="#f4f6f8" />
          <rect x="134" y="132" width="532" height="12" fill="#2c3540" />
          <rect x="170" y="196" width="460" height="124" fill="#3e4f78" />
          {[0, 1, 2, 3, 4].map((i) => <Win key={i} x={176 + i * 91} y={202} w={86} h={112} night={night} />)}
          {/* cars inside the glass */}
          <Car x={260} y={312} s={0.9} body="#f4f2ee" />
          <Car x={470} y={312} s={0.9} flip body="#23262c" dark="#59616b" />
          {/* bunting */}
          <path d="M0 120 Q200 150 400 124 T800 120" stroke="#59616b" strokeWidth="1.2" fill="none" />
          {Array.from({ length: 26 }, (_, i) => {
            const x = i * 32 + 6;
            const y = 122 + Math.sin((i / 25) * Math.PI * 2) * 10 + 8;
            return <path key={i} d={`M${x} ${y} l12 0 l-6 14Z`} fill={FLAGS[i % 4]} />;
          })}
          <Ground p={P} tone="#cfc6b8" />
          {/* lot cars with price boards */}
          {[[90, '#9c1f19'], [330, '#2f6fb3'], [600, '#c8ccd6']].map(([x, c], i) => (
            <g key={i}>
              <Car x={x as number} y={378} s={1.1} body={c as string} flip={i === 1} />
              <rect x={(x as number) + 40} y="320" width="30" height="16" fill="#f3cf5e" />
              <rect x={(x as number) + 54} y="336" width="2" height="12" fill="#59616b" />
            </g>
          ))}
          <Palm x={720} y={336} s={1.05} lean={-1} />
          <Person x={250} y={370} s={1.05} top="#f4f2ee" bottom="#2c3540" head="cap" headColor="#23262c" arm="out" />
          <Person x={530} y={372} s={1.05} top="#d2342a" bottom="#2c2f5c" arm="phone" flip />
        </g>
      }
      lights={
        <g>
          <SignBoard p={P} x={250} y={150} w={300} h={34} bg="#2c3540" ink="#f3cf5e" text="CAR DEALS" size={22} night={night} glow="warm" sub="TOKUNBO · BRAND-NEW · PAPERS" />
          {night && <Glow p={P} kind="cool" cx={400} cy={260} rx={260} ry={70} o={0.5} />}
        </g>
      }
    />
  );
}
