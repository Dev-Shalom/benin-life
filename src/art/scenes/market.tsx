import type { ReactNode } from 'react';
import { CommonDefs, Finish, Glow, Haze, Person, Sky, Bus, ZincPattern, Txt, PAL, rng } from './_sharedA';

const P = 'market';

function Umbrella({ x, y, s = 1, a = '#d2342a', b = '#f4e3c2' }: { x: number; y: number; s?: number; a?: string; b?: string }) {
  const segs = [-1, -0.6, -0.2, 0.2, 0.6];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <rect x="-1.2" y="-60" width="2.4" height="60" fill="#5b4a3e" />
      <path d="M-46 -52 Q0 -86 46 -52 Z" fill={a} />
      {segs.map((t, i) => (
        <path key={t} d={`M${t * 46} -52 Q${(t + 0.2) * 40} -76 0 -76 Q${(t + 0.4) * 40} -76 ${(t + 0.4) * 46} -52Z`} fill={i % 2 ? b : a} />
      ))}
      <path d="M0 -76 Q30 -74 46 -52 L20 -52Z" fill={PAL.shadow} opacity="0.22" />
      <path d="M-40 -55 Q-20 -76 0 -77" stroke="#fff" strokeOpacity="0.45" strokeWidth="1.5" fill="none" />
      <path d="M-46 -52 Q-40 -48 -34 -52 Q-28 -48 -22 -52 Q-16 -48 -10 -52 Q-4 -48 2 -52 Q8 -48 14 -52 Q20 -48 26 -52 Q32 -48 38 -52 Q42 -48 46 -52" fill={a} stroke={PAL.shadow} strokeOpacity="0.25" />
    </g>
  );
}

function Tomatoes({ x, y, s = 1, col = '#e0321f' }: { x: number; y: number; s?: number; col?: string }) {
  const pts: [number, number][] = [[-12, 0], [-4, 0], [4, 0], [12, 0], [-8, -6], [0, -6], [8, -6], [-4, -12], [4, -12], [0, -17]];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="0" cy="5" rx="21" ry="5" fill="#2f5f9e" />
      <path d="M-21 5 Q0 18 21 5 L18 11 Q0 20 -18 11Z" fill="#244b80" />
      {pts.map(([px, py], i) => (
        <g key={i}>
          <circle cx={px} cy={py} r="4.6" fill={col} />
          <circle cx={px + 1.4} cy={py + 1.2} r="3" fill="#7a1430" opacity="0.35" />
          <circle cx={px - 1.5} cy={py - 1.6} r="1.2" fill="#fff" opacity="0.7" />
          <path d={`M${px - 1.5} ${py - 4.2} l1.5 1 l1.5 -1`} stroke="#2f7a35" strokeWidth="0.9" fill="none" />
        </g>
      ))}
    </g>
  );
}

function Peppers({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  const r = rng(Math.round(x * 7 + y));
  const items = [];
  for (let i = 0; i < 26; i++) {
    const px = (r() - 0.5) * 34 * (1 - i / 40);
    const py = -r() * 12 * (1 - Math.abs(px) / 22);
    const c = r() < 0.6 ? '#e8331c' : r() < 0.5 ? '#f08a1a' : '#b81d1d';
    items.push(<ellipse key={i} cx={px.toFixed(1)} cy={py.toFixed(1)} rx="3.2" ry="1.7" transform={`rotate(${Math.round(r() * 180)} ${px.toFixed(1)} ${py.toFixed(1)})`} fill={c} />);
  }
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="0" cy="3" rx="20" ry="5" fill="#c69b5a" />
      <path d="M-20 3 Q0 14 20 3 L17 8 Q0 15 -17 8Z" fill="#8a6434" />
      {items}
      <circle cx="-5" cy="-6" r="1" fill="#fff" opacity="0.6" />
    </g>
  );
}

function Yams({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  const rows = [5, 4, 3, 2];
  const out = [];
  let k = 0;
  for (let r = 0; r < rows.length; r++) {
    for (let i = 0; i < rows[r]; i++) {
      const cx = (i - (rows[r] - 1) / 2) * 15;
      const cy = -r * 9;
      out.push(
        <g key={k++}>
          <ellipse cx={cx} cy={cy} rx="9" ry="4.8" fill="#7a5233" />
          <ellipse cx={cx - 2} cy={cy - 1.6} rx="6" ry="2.2" fill="#a77a4f" />
          <ellipse cx={cx + 3} cy={cy + 2} rx="6" ry="2" fill="#3f2a3e" opacity="0.4" />
          <circle cx={cx - 4} cy={cy} r="0.7" fill="#3a2418" />
          <circle cx={cx + 2} cy={cy - 1} r="0.7" fill="#3a2418" />
        </g>,
      );
    }
  }
  return <g transform={`translate(${x} ${y}) scale(${s})`}>{out}</g>;
}

function Bales({ x, y, s = 1 }: { x: number; y: number; s?: number }) {
  const cols: [string, string][] = [['#1f7a3f', '#f2c230'], ['#d2342a', '#f6e3c4'], ['#2a4d9b', '#ffb43a'], ['#7a2a7a', '#3fd0c0'], ['#f08a1a', '#1d3a6b'], ['#b0793a', '#fff1d0']];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      {cols.map(([a, b], i) => {
        const row = Math.floor(i / 3);
        const bx = (i % 3) * 26 - 39 + row * 13;
        const by = -row * 14 - 14;
        return (
          <g key={i}>
            <rect x={bx} y={by} width="25" height="13" rx="2" fill={a} />
            <path d={`M${bx + 3} ${by} v13 M${bx + 9} ${by} v13 M${bx + 15} ${by} v13 M${bx + 21} ${by} v13`} stroke={b} strokeWidth="2" strokeDasharray="2 2" />
            <rect x={bx} y={by + 8} width="25" height="5" rx="1" fill={PAL.shadow} opacity="0.25" />
            <rect x={bx} y={by} width="25" height="2" fill="#fff" opacity="0.3" />
          </g>
        );
      })}
    </g>
  );
}

/** Front-facing stall: zinc lean-to roof, posts, cloth-covered table. */
function Stall({ x, y, w, roofY, cloth = '#e9d8b4', zinc = true, children }: { x: number; y: number; w: number; roofY: number; cloth?: string; zinc?: boolean; children?: ReactNode }) {
  return (
    <g>
      {/* back wall / shade under roof */}
      <rect x={x + 4} y={roofY + 8} width={w - 8} height={y - roofY - 8} fill="#4a2f3e" />
      <rect x={x + 4} y={roofY + 8} width={w - 8} height={y - roofY - 8} fill={`url(#${P}-understall)`} />
      {/* posts */}
      <rect x={x + 2} y={roofY} width="5" height={y - roofY + 30} fill="#6b4a32" />
      <rect x={x + w - 7} y={roofY} width="5" height={y - roofY + 30} fill="#4a3040" />
      {/* roof */}
      <path d={`M${x - 8} ${roofY + 10} L${x + w + 8} ${roofY + 10} L${x + w + 2} ${roofY - 10} L${x - 2} ${roofY - 10}Z`} fill={zinc ? `url(#${P}-zinc)` : '#2a6db0'} />
      <path d={`M${x - 8} ${roofY + 10} L${x + w + 8} ${roofY + 10} L${x + w + 8} ${roofY + 13} L${x - 8} ${roofY + 13}Z`} fill="#5d4d55" />
      <path d={`M${x - 2} ${roofY - 10} L${x + w + 2} ${roofY - 10}`} stroke="#fff" strokeOpacity="0.5" />
      <path d={`M${x + w * 0.55} ${roofY + 10} L${x + w + 8} ${roofY + 10} L${x + w + 2} ${roofY - 10} L${x + w * 0.62} ${roofY - 10}Z`} fill="#8a4a2c" opacity="0.25" />
      {children}
      {/* table */}
      <rect x={x - 2} y={y} width={w + 4} height="7" fill="#8a6440" />
      <rect x={x - 2} y={y} width={w + 4} height="2" fill="#c49a68" />
      <path d={`M${x} ${y + 7} L${x + w} ${y + 7} L${x + w - 2} ${y + 34} L${x + 2} ${y + 34}Z`} fill={cloth} />
      <path d={`M${x} ${y + 7} L${x + w} ${y + 7} L${x + w} ${y + 13} L${x} ${y + 13}Z`} fill={PAL.shadow} opacity="0.25" />
      {[0.2, 0.4, 0.6, 0.8].map((t) => (
        <path key={t} d={`M${x + w * t} ${y + 9} L${x + w * t - 2} ${y + 34}`} stroke={PAL.shadow} strokeOpacity="0.15" strokeWidth="3" />
      ))}
    </g>
  );
}

function BackStalls() {
  const r = rng(42);
  const out = [];
  const um = ['#d2342a', '#2a6db0', '#f2c230', '#1f7a3f', '#e86a1c'];
  for (let i = 0; i < 14; i++) {
    const x = i * 60 - 20 + r() * 10;
    const h = 30 + r() * 8;
    out.push(
      <g key={i}>
        <rect x={x} y={262 - h} width="54" height={h} fill={i % 2 ? '#a58a8e' : '#b39a92'} />
        <rect x={x + 4} y={262 - h + 8} width="46" height={h - 14} fill="#6f5a76" />
        <path d={`M${x - 4} ${262 - h + 6} L${x + 58} ${262 - h + 6} L${x + 54} ${262 - h - 4} L${x} ${262 - h - 4}Z`} fill={i % 3 ? '#b8bec6' : '#b98a72'} />
        {[0, 1, 2, 3].map((k) => (
          <circle key={k} cx={x + 10 + k * 11} cy={262 - 8} r="3.4" fill={['#d2342a', '#f2c230', '#2f8a45', '#e86a1c'][(k + i) % 4]} opacity="0.8" />
        ))}
      </g>,
    );
    if (i % 3 === 1) out.push(<Umbrella key={`u${i}`} x={x + 30} y={262} s={0.55} a={um[i % 5]} b="#f5ead6" />);
  }
  return <g>{out}</g>;
}

export default function MarketScene({ night }: { night: boolean }) {
  const bulbs: [number, number][] = [[70, 228], [150, 228], [215, 228], [610, 222], [690, 222], [755, 222], [470, 250], [330, 250]];
  const farLit = [1, 3, 4, 6];
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Oba Market, Benin City">
      <defs>
        <CommonDefs p={P} night={night} />
        <ZincPattern id={`${P}-zinc`} base="#a7aab3" dark="#767a86" light="#dfe2e6" />
        <linearGradient id={`${P}-ground`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#d9a37a" />
          <stop offset="0.35" stopColor="#c47a4c" />
          <stop offset="0.7" stopColor="#a9562e" />
          <stop offset="1" stopColor="#7e3418" />
        </linearGradient>
        <linearGradient id={`${P}-understall`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#24183f" stopOpacity="0.85" />
          <stop offset="1" stopColor="#6b3a3a" stopOpacity="0.1" />
        </linearGradient>
        <linearGradient id={`${P}-hall`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#ecd2ad" />
          <stop offset="0.6" stopColor="#dcb991" />
          <stop offset="1" stopColor="#b8907a" />
        </linearGradient>
      </defs>

      <Sky p={P} night={night} clouds={[[330, 62, 0.9], [640, 110, 0.6]]} />

      <g filter={night ? `url(#${P}-night)` : undefined}>
        {/* far skyline */}
        <g fill="#a9a6c4" opacity="0.85">
          <rect x="0" y="178" width="70" height="70" />
          <rect x="60" y="160" width="46" height="90" />
          <rect x="100" y="190" width="80" height="60" />
          <rect x="560" y="170" width="60" height="80" />
          <rect x="612" y="186" width="90" height="64" />
          <rect x="700" y="158" width="44" height="92" />
          <rect x="740" y="182" width="70" height="68" />
          <rect x="716" y="140" width="3" height="20" />
          <rect x="72" y="146" width="22" height="14" fill="#9592b8" />
        </g>
        <path d="M720 140 L726 60 L732 140" stroke="#9a97ba" strokeWidth="1.5" fill="none" opacity="0.8" />
        <Haze p={P} y={120} h={150} />

        {/* market hall (back) */}
        <g>
          <rect x="245" y="138" width="315" height="112" fill="url(#market-hall)" />
          <rect x="245" y="138" width="315" height="8" fill="#b5552b" />
          <rect x="245" y="192" width="315" height="5" fill="#b5552b" opacity="0.8" />
          {[0, 1, 2, 3, 4, 5, 6].map((i) => (
            <g key={i}>
              <rect x={262 + i * 42} y="156" width="26" height="28" fill="#5d6f8c" />
              <rect x={262 + i * 42} y="156" width="26" height="4" fill="#2d1b4e" opacity="0.35" />
              <path d={`M${266 + i * 42} 206 Q${275 + i * 42} 198 ${284 + i * 42} 206 L${284 + i * 42} 250 L${266 + i * 42} 250Z`} fill="#4e3b52" />
            </g>
          ))}
          <rect x="300" y="112" width="205" height="30" rx="2" fill="#d2342a" />
          <rect x="300" y="112" width="205" height="5" fill="#ff7d5e" opacity="0.5" />
          <rect x="300" y="138" width="205" height="4" fill="#7a1d1a" />
          <Txt x={402} y={134} size={19} spacing={3} fill="#fff6e0">OBA MARKET</Txt>
          <rect x="520" y="138" width="40" height="112" fill="#3b2a55" opacity="0.18" />
        </g>
        <Haze p={P} y={200} h={90} o={0.7} />

        {/* ground */}
        <path d="M0 250 L800 250 L800 450 L0 450Z" fill={`url(#${P}-ground)`} />
        <path d="M330 255 L470 255 L640 450 L160 450Z" fill="#e2ad7e" opacity="0.35" />
        <BackStalls />
        <Bus x={300} y={290} s={0.62} label="OBA MKT • RING ROAD" />

        {/* mid stalls */}
        <Stall x={30} y={298} w={220} roofY={222} cloth="#3a6fb5">
          <Person x={92} y={300} s={0.95} top="#f08a1a" wrapper bottom="#1f7a3f" head="gele" headColor="#f08a1a" skin="#5a301c" />
          <Person x={190} y={300} s={0.9} top="#7a2a7a" head="hair" skin="#7a4428" arm="out" />
          <Tomatoes x={70} y={293} s={0.8} />
          <Peppers x={128} y={295} s={0.8} />
          <Tomatoes x={210} y={293} s={0.8} col="#d62d1e" />
        </Stall>
        <Stall x={555} y={292} w={215} roofY={216} cloth="#f2c230">
          <Person x={640} y={294} s={0.92} top="#2a4d9b" wrapper bottom="#d2342a" head="gele" headColor="#d2342a" skin="#4e2a18" />
          <Bales x={612} y={288} s={0.75} />
          <Yams x={720} y={286} s={0.7} />
        </Stall>
        <Umbrella x={500} y={300} s={0.95} a="#2a6db0" b="#f6efe0" />
        <Umbrella x={280} y={298} s={0.85} a="#1f7a3f" b="#f2c230" />

        {/* mid-distance shoppers */}
        <Person x={360} y={318} s={0.85} top="#e8d7b5" bottom="#3a2c58" head="cap" headColor="#d2342a" />
        <Person x={415} y={322} s={0.8} top="#1f7a3f" wrapper bottom="#f2c230" head="tray" headColor="#1f7a3f" tray="#e0321f" skin="#5e3220" />
        <Person x={520} y={328} s={0.88} top="#ffffff" bottom="#2c2f5c" head="hair" skin="#6e3b22" arm="phone" />

        {/* stall signboards + hanging goods */}
        <g>
          <rect x="70" y="236" width="120" height="16" rx="1.5" fill="#f6ecd2" />
          <rect x="70" y="236" width="120" height="16" rx="1.5" fill="none" stroke="#1f7a3f" strokeWidth="1.5" />
          <Txt x={130} y={248} size={9} fill="#1f7a3f" family="Arial, sans-serif">IYA OSAS FOODSTUFF</Txt>
          <rect x="598" y="230" width="128" height="16" rx="1.5" fill="#1f2f6b" />
          <Txt x={662} y={242} size={9} fill="#f2c230" family="Arial, sans-serif">AUNTY EFE FABRICS</Txt>
          {[44, 56, 236, 224].map((hx, i) => (
            <g key={hx}>
              <line x1={hx} y1="234" x2={hx} y2={246 + (i % 2) * 6} stroke="#3a2a2a" strokeWidth="0.8" />
              <rect x={hx - 4} y={246 + (i % 2) * 6} width="8" height="12" rx="2" fill={['#d2342a', '#2a6db0', '#f2c230', '#1f7a3f'][i]} />
            </g>
          ))}
          {[570, 582, 752, 764].map((hx, i) => (
            <path key={hx} d={`M${hx} 228 l0 6 q-5 4 0 22 q5 -18 0 -22`} fill={['#e86a1c', '#7a2a7a', '#2f8a45', '#d2342a'][i]} />
          ))}
        </g>

        {/* ground texture + cast shadows (light from upper-left) */}
        <g>
          <ellipse cx="170" cy="335" rx="150" ry="12" fill={PAL.shadow} opacity="0.3" />
          <ellipse cx="690" cy="330" rx="140" ry="12" fill={PAL.shadow} opacity="0.3" />
          {Array.from({ length: 40 }, (_, i) => {
            const r = rng(i * 31 + 5);
            const gx = r() * 800;
            const gy = 300 + r() * 150;
            return <ellipse key={i} cx={gx.toFixed(0)} cy={gy.toFixed(0)} rx={(1 + r() * 3).toFixed(1)} ry="1" fill={r() < 0.5 ? '#7e3418' : '#f0c79c'} opacity="0.55" />;
          })}
          <path d="M300 350 Q360 345 420 352 M520 372 Q560 368 600 374" stroke="#8e3f1f" strokeWidth="2" opacity="0.35" fill="none" />
        </g>

        {/* foreground: left produce table on legs */}
        <g>
          <path d="M-10 404 L292 386 L300 450 L-10 450Z" fill="#3b2550" opacity="0.4" />
          {[14, 150, 270].map((lx) => (
            <rect key={lx} x={lx} y={378 - lx * 0.03} width="7" height="70" fill="#5a3826" />
          ))}
          <g transform="translate(70 440)">
            <path d="M-22 0 Q-26 -30 -14 -38 L14 -38 Q26 -30 22 0Z" fill="#c8a46a" />
            <path d="M4 -38 L14 -38 Q26 -30 22 0 L6 0Z" fill="#3b2550" opacity="0.3" />
            <path d="M-14 -38 Q0 -46 14 -38" stroke="#8a6a3c" strokeWidth="3" fill="none" />
            <path d="M-18 -20 L18 -22 M-20 -10 L20 -12" stroke="#a4824e" strokeWidth="1" />
          </g>
          <g transform="translate(205 444)">
            <ellipse cx="0" cy="-6" rx="26" ry="7" fill="#2a6db0" />
            <path d="M-26 -6 L-22 4 L22 4 L26 -6Z" fill="#1d4f86" />
            <ellipse cx="0" cy="-7" rx="22" ry="5" fill="#f2d9a0" />
          </g>
          <path d="M-10 368 L282 356 L288 370 L-10 384Z" fill="#b8824e" />
          <path d="M-10 368 L282 356 L283 359 L-10 371Z" fill="#e2b783" />
          <path d="M-10 384 L288 370 L288 384 L-10 399Z" fill="#7d4f30" />
          <path d="M-10 391 L288 377" stroke="#5a3826" strokeWidth="1" />
          <path d="M120 377 L120 392 M220 373 L220 388" stroke="#5a3826" strokeWidth="1" />
          <Tomatoes x={40} y={362} s={1.5} />
          <Peppers x={120} y={360} s={1.45} />
          <Tomatoes x={198} y={356} s={1.4} col="#d62d1e" />
          <g transform="translate(252 352)">
            <ellipse cx="0" cy="4" rx="18" ry="6" fill="#c69b5a" />
            {[[-8, 0], [0, 0], [8, 0], [-4, -6], [4, -6], [0, -11]].map(([ox, oy], i) => (
              <g key={i}>
                <circle cx={ox} cy={oy} r="5" fill="#9b2f52" />
                <circle cx={ox + 1.5} cy={oy + 1.5} r="3" fill="#3b1640" opacity="0.3" />
                <circle cx={ox - 1.5} cy={oy - 1.5} r="1.4" fill="#f6c9d8" opacity="0.6" />
              </g>
            ))}
          </g>
        </g>
        {/* foreground: right - yams on jute mat, fabric bales on bench */}
        <g>
          <path d="M548 420 L812 402 L812 450 L536 450Z" fill="#c9a66e" />
          <path d="M548 420 L812 402" stroke="#e8cf9e" strokeWidth="2" />
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <path key={i} d={`M${546 + i * 1} ${426 + i * 4} L812 ${408 + i * 4}`} stroke="#9c7a48" strokeWidth="0.8" opacity="0.6" />
          ))}
          <ellipse cx="640" cy="425" rx="70" ry="9" fill="#3b2550" opacity="0.35" />
          <Yams x={620} y={418} s={1.4} />
          <rect x="700" y="388" width="110" height="7" fill="#9a6a42" />
          <rect x="706" y="395" width="5" height="22" fill="#5a3826" />
          <rect x="796" y="395" width="5" height="22" fill="#5a3826" />
          <Bales x={756} y={388} s={1.2} />
        </g>

        {/* lane people */}
        <g>
          {/* wheelbarrow */}
          <g transform="translate(410 412)">
            <ellipse cx="22" cy="2" rx="40" ry="4" fill={PAL.shadow} opacity="0.4" />
            <path d="M-8 -26 L44 -26 L36 -8 L0 -8Z" fill="#6f7a86" />
            <path d="M-8 -26 L44 -26 L42 -22 L-6 -22Z" fill="#c7cfd8" />
            <Yams x={18} y={-30} s={0.55} />
            <line x1="40" y1="-14" x2="66" y2="-24" stroke="#4a3a2e" strokeWidth="3" strokeLinecap="round" />
            <line x1="20" y1="-8" x2="24" y2="0" stroke="#4a3a2e" strokeWidth="3" />
            <circle cx="-6" cy="-6" r="7" fill="#1e1a26" />
            <circle cx="-6" cy="-6" r="2.5" fill="#9a9aa6" />
          </g>
          <Person x={484} y={416} s={1.35} top="#f2c230" bottom="#3a2c58" head="cap" headColor="#1f7a3f" skin="#5a301c" arm="hold" hold="#4a3a2e" />
          <Person x={330} y={424} s={1.45} top="#d2342a" wrapper bottom="#2a4d9b" head="tray" headColor="#d2342a" tray="#f08a1a" skin="#6e3b22" />
        </g>
      </g>

      {night && (
        <g>
          {farLit.map((i) => (
            <g key={i}>
              <rect x={262 + i * 42} y="156" width="26" height="28" fill="#ffcf7a" opacity="0.8" />
              <Glow p={P} kind="warm" cx={275 + i * 42} cy={170} rx={26} o={0.5} />
            </g>
          ))}
          {[[20, 200], [90, 186], [640, 205], [722, 180]].map(([x, y], i) => (
            <rect key={`f${i}`} x={x} y={y} width="6" height="8" fill="#ffd27a" opacity="0.7" />
          ))}
          <Glow p={P} kind="warm" cx={402} cy={127} rx={130} ry={30} o={0.25} />
          {bulbs.map(([x, y], i) => (
            <g key={i}>
              <Glow p={P} kind="amber" cx={x} cy={y + 30} rx={70} ry={55} o={0.65} />
              <line x1={x} y1={y - 8} x2={x} y2={y} stroke="#2a2030" />
              <circle cx={x} cy={y + 2} r="3" fill="#fff4c8" />
            </g>
          ))}
          <Glow p={P} kind="warm" cx={120} cy={370} rx={170} ry={60} o={0.55} />
          <Glow p={P} kind="warm" cx={660} cy={380} rx={170} ry={60} o={0.5} />
          {/* lantern on each foreground table */}
          {[[278, 340], [705, 372]].map(([x, y], i) => (
            <g key={i}>
              <Glow p={P} kind="amber" cx={x} cy={y} rx={60} o={0.9} />
              <rect x={x - 4} y={y - 6} width="8" height="12" rx="2" fill="#ffe3a0" />
              <rect x={x - 5} y={y - 9} width="10" height="3" fill="#3a2a2a" />
            </g>
          ))}
          <circle cx={302} cy={278} r="2.4" fill="#fff6d0" />
          <Glow p={P} kind="warm" cx={296} cy={280} rx={30} ry={14} o={0.8} />
          <Glow p={P} kind="cool" cx={516} cy={292} rx={10} o={0.9} />
        </g>
      )}

      <Finish p={P} night={night} />
    </svg>
  );
}
