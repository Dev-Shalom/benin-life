// Iguobazuwa farm settlement — P1-SCENES-B
import { Sky, NightShade, Finish, GlowDefs, Glow, Person, Palm, Treeline, Haze, rng, dim } from './_sharedB';

const P = 'farm';
const HZ = 246; // horizon (field top)
const sc = (y: number) => Math.max(0.12, (y - HZ + 14) / 220);

function Cassava({ x, y, s, night }: { x: number; y: number; s: number; night: boolean }) {
  const h = 62 * s;
  // palmate leaf: 5-7 lanceolate lobes radiating from (cx,cy)
  const fine = s > 0.5;
  const f0 = (v: number) => v.toFixed(0);
  const leaf = (cx: number, cy: number, r: number, rot: number, n = 5) => {
    let d = '';
    for (let i = 0; i < n; i++) {
      const a = ((rot - 90 + (i - (n - 1) / 2) * 30) * Math.PI) / 180;
      const len = r * (1 - Math.abs(i - (n - 1) / 2) * 0.12);
      const tx = cx + Math.cos(a) * len;
      const ty = cy + Math.sin(a) * len;
      const w = len * 0.2;
      const mx = cx + Math.cos(a) * len * 0.5;
      const my = cy + Math.sin(a) * len * 0.5;
      const px = -Math.sin(a) * w;
      const py = Math.cos(a) * w;
      d += fine
        ? `M${f0(cx)} ${f0(cy)}Q${f0(mx + px)} ${f0(my + py)} ${f0(tx)} ${f0(ty)}Q${f0(mx - px)} ${f0(my - py)} ${f0(cx)} ${f0(cy)}Z`
        : `M${f0(cx)} ${f0(cy)}L${f0(tx)} ${f0(ty)}`;
    }
    return d;
  };
  const g1 = night ? '#1d3a3a' : '#3f8a3a';
  const g2 = night ? '#163030' : '#2c6a33';
  const g3 = night ? '#24463e' : '#6cb24a';
  const stem = night ? '#3a2a40' : '#8a4a4a';
  const sw = Math.max(0.7, 2.2 * s);
  const paint = (c: string) => (fine ? { fill: c } : { stroke: c, strokeWidth: Math.max(1, 4 * s), strokeLinecap: 'round' as const });
  return (
    <g>
      <ellipse cx={x + 6 * s} cy={y} rx={18 * s} ry={3 * s} fill="#2d1b4e" opacity="0.3" />
      <path d={`M${x} ${y} Q${x - 3 * s} ${y - h * 0.5} ${x - 10 * s} ${y - h} M${x} ${y} Q${x + 4 * s} ${y - h * 0.6} ${x + 12 * s} ${y - h * 0.82} M${x} ${y} Q${x} ${y - h * 0.4} ${x + 2 * s} ${y - h * 0.55}`} stroke={stem} strokeWidth={sw} fill="none" />
      <path d={`M${x - 10 * s} ${y - h} l${-8 * s} ${8 * s} M${x - 6 * s} ${y - h * 0.8} l${9 * s} ${4 * s} M${x + 12 * s} ${y - h * 0.82} l${8 * s} ${6 * s}`} stroke={stem} strokeWidth={sw * 0.6} />
      <path d={leaf(x + 2 * s, y - h * 0.55, 20 * s, 60) + leaf(x - 6 * s, y - h * 0.8, 22 * s, -70)} {...paint(g2)} />
      <path d={leaf(x - 10 * s, y - h, 27 * s, -15, 7) + leaf(x + 12 * s, y - h * 0.82, 25 * s, 25, 7)} {...paint(g1)} />
      {fine && <path d={leaf(x - 22 * s, y - h + 10 * s, 17 * s, -75) + leaf(x + 26 * s, y - h * 0.82 + 8 * s, 17 * s, 80)} fill={g2} />}
      {fine && <path d={leaf(x - 10 * s, y - h, 16 * s, -25)} fill={g3} opacity="0.7" />}
    </g>
  );
}

function Mound({ x, y, s, night, stake }: { x: number; y: number; s: number; night: boolean; stake: boolean }) {
  const w = 36 * s;
  const h = 21 * s;
  return (
    <g>
      <path d={`M${x - w} ${y} Q${x - w * 0.6} ${y - h * 1.3} ${x} ${y - h} Q${x + w * 0.6} ${y - h * 1.2} ${x + w} ${y} Z`} fill={night ? '#5a2e2a' : '#b5552b'} />
      <path d={`M${x} ${y - h} Q${x + w * 0.6} ${y - h * 1.2} ${x + w} ${y} L${x + w * 0.2} ${y} Z`} fill="#3b2a5e" opacity="0.3" />
      <path d={`M${x - w * 0.8} ${y - h * 0.3} Q${x - w * 0.5} ${y - h * 1.05} ${x - w * 0.05} ${y - h * 0.95}`} stroke={night ? '#7a4a4a' : '#e08a52'} strokeWidth={Math.max(0.6, 2.2 * s)} fill="none" opacity="0.8" />
      {stake && (
        <g>
          <path d={`M${x} ${y - h} L${x + 4 * s} ${y - h - 64 * s}`} stroke={night ? '#3a2a30' : '#7a5a3a'} strokeWidth={Math.max(0.6, 2.2 * s)} />
          <path d={`M${x} ${y - h} q${-6 * s} ${-12 * s} ${2 * s} ${-22 * s} q${8 * s} ${-10 * s} ${-1 * s} ${-22 * s} q${-6 * s} ${-10 * s} ${4 * s} ${-18 * s}`} stroke={night ? '#1f3a30' : '#3f8a3a'} strokeWidth={Math.max(0.6, 1.4 * s)} fill="none" />
          <path d={[0.25, 0.45, 0.62, 0.8, 0.95].map((f, i) => {
            const sg = i % 2 ? -1 : 1;
            return `M${(x + sg * 5 * s).toFixed(1)} ${(y - h - 62 * s * f).toFixed(1)}q${(sg * 6 * s).toFixed(1)} ${(-3 * s).toFixed(1)} ${(sg * 5 * s).toFixed(1)} ${(4 * s).toFixed(1)}q${(-sg * 2 * s).toFixed(1)} ${(4 * s).toFixed(1)} ${(-sg * 5 * s).toFixed(1)} ${(-4 * s).toFixed(1)}Z`;
          }).join('')} fill={night ? '#1f3a30' : '#448a3a'} />
        </g>
      )}
    </g>
  );
}

function Plantain({ x, y, s, night }: { x: number; y: number; s: number; night: boolean }) {
  const g = night ? ['#1a3434', '#14282c'] : ['#5aa043', '#3f7f37'];
  const leaves = [-150, -115, -70, -35, -10, 200];
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <ellipse cx="6" cy="0" rx="22" ry="4" fill="#2d1b4e" opacity="0.3" />
      <path d="M-5 0 Q-4 -50 -2 -95 L4 -95 Q6 -50 6 0 Z" fill={night ? '#2a3a30' : '#7d9a4a'} />
      <path d="M1 0 Q2 -50 4 -95 L4 -95 Q6 -50 6 0 Z" fill="#2d1b4e" opacity="0.25" />
      {leaves.map((a, i) => (
        <g key={i} transform={`translate(1 -95) rotate(${a})`}>
          <path d="M0 0 Q30 -14 62 -6 Q74 0 66 8 Q36 12 0 3 Z" fill={g[i % 2]} />
          <path d="M0 1 Q34 -4 68 2" stroke={night ? '#2a4a3a' : '#c9d97a'} strokeWidth="1.2" fill="none" />
          <path d="M20 -6 l2 10 M36 -8 l1 13 M50 -7 l0 12" stroke={night ? '#0f2020' : '#2f6a33'} strokeWidth="0.8" opacity="0.6" />
        </g>
      ))}
      <path d="M4 -90 Q16 -70 12 -52" stroke={night ? '#2a3a30' : '#6a7a3a'} strokeWidth="2.5" fill="none" />
      <g fill={night ? '#2a3a2a' : '#8db34a'}>
        <path d="M4 -86 q10 2 12 12 q-12 0 -12 -12 Z" />
        <path d="M6 -80 q12 2 13 12 q-12 0 -13 -12 Z" />
        <path d="M8 -73 q11 2 12 11 q-11 0 -12 -11 Z" />
      </g>
      <path d="M12 -52 q-4 6 0 12 q4 -6 0 -12 Z" fill={night ? '#3a2030' : '#7a2a4a'} />
    </g>
  );
}

function RubberTree({ x, y, s, night }: { x: number; y: number; s: number; night: boolean }) {
  return (
    <g transform={`translate(${x} ${y}) scale(${s})`}>
      <path d="M-4 0 L-2 -120 L3 -120 L5 0 Z" fill={night ? '#2c2a3e' : '#7d7470'} />
      <path d="M1 0 L1.5 -120 L3 -120 L5 0 Z" fill="#2d1b4e" opacity="0.3" />
      <path d="M-4 -30 L5 -40" stroke={night ? '#3a3a4a' : '#e8e2d0'} strokeWidth="1.2" />
      <path d="M-3 -24 h6 l-1 4 h-4 Z" fill="#f2f0ea" opacity={night ? 0.3 : 0.9} />
    </g>
  );
}

export default function FarmScene({ night }: { night: boolean }) {
  const r = rng(77);
  // yam mound rows (left of path) + cassava rows (right of path)
  const rows = [262, 276, 296, 324, 362, 412];
  const pathX = (y: number) => 470 + (y - 450) * -0.55 - Math.sin((y - HZ) / 40) * 12; // centre of footpath
  const pathW = (y: number) => 6 + (y - HZ) * 0.42;
  const yams = [];
  const cass = [];
  for (const [ri, y] of rows.entries()) {
    const s = Math.round(sc(y) * 100) / 100;
    const step = Math.max(28, 68 * s);
    const pxL = pathX(y) - pathW(y) - 22 * s;
    for (let x = pxL; x > -40; x -= step) {
      yams.push(<Mound key={`m${ri}-${x.toFixed(0)}`} x={Math.round(x + (r() - 0.5) * 6 * s)} y={y} s={s} night={night} stake={ri > 1 && (ri + Math.round(x / step)) % 2 === 0} />);
    }
    const pxR = pathX(y) + pathW(y) + 26 * s;
    const step2 = Math.max(24, 62 * s);
    for (let x = pxR; x < 840; x += step2) {
      if (y < 290 && x > 500 && x < 720) continue; // keep hut clear
      cass.push(<Cassava key={`c${ri}-${x.toFixed(0)}`} x={Math.round(x + (r() - 0.5) * 8 * s)} y={y} s={s} night={night} />);
    }
  }
  const pathPts = [HZ, 256, ...rows, 460];
  const pathL = pathPts.map((y) => `${(pathX(y) - pathW(y)).toFixed(1)} ${y}`);
  const pathR = pathPts.slice().reverse().map((y) => `${(pathX(y) + pathW(y)).toFixed(1)} ${y}`);
  const fireflies = night ? Array.from({ length: 14 }, () => ({ x: r() * 800, y: 260 + r() * 170, s: 0.8 + r() * 1.6 })) : [];

  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Iguobazuwa farm settlement">
      <defs>
        <linearGradient id={`${P}-earth`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#c7744a" />
          <stop offset="0.25" stopColor="#b85a30" />
          <stop offset="0.7" stopColor="#a84a24" />
          <stop offset="1" stopColor="#82361d" />
        </linearGradient>
        <linearGradient id={`${P}-forest`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={night ? '#1d2a48' : '#6f9e86'} />
          <stop offset="1" stopColor={night ? '#16223a' : '#4f7f5c'} />
        </linearGradient>
        <linearGradient id={`${P}-thatch`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#e2b86a" />
          <stop offset="0.5" stopColor="#c08f45" />
          <stop offset="1" stopColor="#7a5530" />
        </linearGradient>
        <linearGradient id={`${P}-mud`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#c46a3c" />
          <stop offset="1" stopColor="#9a4a2a" />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />
      <Sky p={P} night={night} sunX={150} sunY={70} moonX={620} moonY={64} />

      {/* rainforest edge: far, emergent trees */}
      <Treeline y={212} fill={night ? '#1a2440' : '#8fb3a0'} seed={21} amp={14} step={40} base={260} />
      {[[80, 190, 1], [270, 180, 1.2], [520, 186, 1], [700, 176, 1.3]].map(([x, y, s], i) => (
        <g key={i} transform={`translate(${x} ${y}) scale(${s})`} fill={night ? '#1a2440' : '#86ab98'}>
          <rect x="-2" y="0" width="4" height="40" />
          <ellipse cx="0" cy="0" rx="34" ry="10" />
          <ellipse cx="-14" cy="-6" rx="18" ry="8" />
          <ellipse cx="14" cy="-5" rx="18" ry="8" />
        </g>
      ))}
      <Treeline y={234} fill={`url(#${P}-forest)`} seed={22} amp={12} step={28} base={262} />
      <Haze p={P} y={190} h={80} night={night} o={0.5} />

      {/* field */}
      <path d={`M-10 ${HZ} H810 V460 H-10 Z`} fill={`url(#${P}-earth)`} />
      {/* rubber plantation (left, far) */}
      <g>
        {Array.from({ length: 11 }, (_, i) => (
          <g key={i}>
            <RubberTree x={10 + i * 24} y={HZ + 6 + (i % 2) * 3} s={0.62} night={night} />
          </g>
        ))}
        {Array.from({ length: 13 }, (_, i) => {
          const cx = -14 + i * 23 + ((i * 7) % 5) * 3;
          const cy = HZ - 66 - ((i * 5) % 3) * 7;
          return (
            <g key={`c${i}`}>
              <ellipse cx={cx + 6} cy={cy + 10} rx="30" ry="14" fill={night ? '#122232' : '#2c5a36'} />
              <ellipse cx={cx} cy={cy} rx="26" ry="17" fill={night ? '#16283a' : '#3c7442'} />
              <ellipse cx={cx - 10} cy={cy - 4} rx="15" ry="11" fill={night ? '#1b2e40' : '#4e8a48'} />
              <ellipse cx={cx - 12} cy={cy - 9} rx="9" ry="5" fill={night ? '#203448' : '#78b45c'} opacity="0.8" />
            </g>
          );
        })}
        {/* light shafts between the rubber rows */}
        {!night && <path d={`M40 ${HZ - 56} L30 ${HZ + 4} L46 ${HZ + 4} Z M136 ${HZ - 56} L126 ${HZ + 4} L142 ${HZ + 4} Z M208 ${HZ - 56} L200 ${HZ + 4} L214 ${HZ + 4} Z`} fill="#fff1c2" opacity="0.25" />}
      </g>
      {/* far furrows: cheap stripes instead of plants */}
      <path d={Array.from({ length: 5 }, (_, i) => `M-10 ${HZ + 2 + i * 3.2} H810`).join(' ')} stroke={night ? '#2a3a34' : '#5f8a3a'} strokeWidth="1.6" strokeDasharray="3 2" opacity="0.8" />
      <Haze p={P} y={HZ - 10} h={40} night={night} o={0.35} />

      {/* footpath */}
      <path d={`M${pathL.join(' L')} L${pathR.join(' L')} Z`} fill={night ? '#6a3a34' : '#d48c5c'} />
      <path d={`M${pathL.join(' L')}`} stroke="#7a3519" strokeWidth="1.2" fill="none" opacity="0.4" />

      {/* mid: oil palms, hut, plantain */}
      <Palm x={318} y={262} s={0.75} night={night} lean={-6} />
      <Palm x={770} y={262} s={0.7} night={night} lean={8} />
      <Plantain x={505} y={282} s={0.75} night={night} />
      {/* hut: mud walls + thatch */}
      <g>
        <ellipse cx="620" cy="288" rx="78" ry="8" fill="#2d1b4e" opacity="0.3" />
        <rect x="560" y="238" width="112" height="50" fill={`url(#${P}-mud)`} />
        <rect x="640" y="238" width="32" height="50" fill="#3b2a5e" opacity="0.3" />
        <path d="M566 252 q20 4 40 0 M600 270 q20 3 50 -1" stroke="#7a3519" strokeWidth="1.5" fill="none" opacity="0.5" />
        <rect x="596" y="252" width="22" height="36" fill={night ? '#ffb24a' : '#2a1d24'} />
        <rect x="630" y="252" width="16" height="12" fill={night ? '#ffcf73' : '#2a1d24'} />
        <path d="M546 244 L616 196 L688 244 Q680 248 672 245 Q664 250 656 245 Q648 250 640 245 Q632 250 624 245 Q616 250 608 245 Q600 250 592 245 Q584 250 576 245 Q568 250 560 245 Q552 249 546 244 Z" fill={`url(#${P}-thatch)`} />
        <path d="M616 196 L688 244 Q680 248 672 245 Q664 250 656 245 Q648 250 640 245 L616 200 Z" fill="#3b2a5e" opacity="0.25" />
        <path d="M570 230 L616 202 M586 236 L616 214 M600 240 L616 228 M630 206 L668 236" stroke="#f2d38a" strokeWidth="1.2" opacity="0.6" />
        {/* open shed with harvest */}
        <path d="M672 252 L742 246 L742 252 L672 258 Z" fill={night ? '#4c4f72' : '#a9acb8'} />
        <path d="M676 256 V288 M738 250 V288" stroke="#5a3a2a" strokeWidth="3" />
        <path d="M684 288 q8 -14 18 0 Z M702 288 q8 -12 16 0 Z M718 288 q7 -10 14 0 Z" fill={night ? '#4a3a30' : '#a07040'} />
      </g>
      <Plantain x={712} y={300} s={0.95} night={night} />
      <Plantain x={790} y={312} s={1.1} night={night} />

      {/* rows */}
      {yams}
      {cass}

      {/* farmer with hoe (mid) */}
      <Person x={pathX(318) - 70} y={318} s={1.1} skin="#4a2c1e" top="#e8e2cf" bottom="#4a5a7a" pose="work" facing={1} night={night}
        extra={<path d="M16 -34 L30 -2 M26 -4 l10 -2 l-2 6 Z" stroke="#6a4a2a" strokeWidth="2.4" fill="#8a8ca0" />} />

      {/* foreground props: stump with hoe + cutlass, baskets */}
      <g>
        <ellipse cx="112" cy="436" rx="60" ry="9" fill="#2d1b4e" opacity="0.35" />
        <path d="M70 438 Q72 396 80 386 L140 386 Q148 400 150 438 Z" fill={night ? '#3a2a30' : '#7a5236'} />
        <ellipse cx="110" cy="386" rx="30" ry="7" fill={night ? '#5a4a40' : '#d4a86a'} />
        <ellipse cx="110" cy="386" rx="18" ry="4" fill="none" stroke={night ? '#4a3a30' : '#a07a48'} strokeWidth="1.5" />
        <path d="M125 390 Q140 404 150 438 L140 438 Q134 410 122 396 Z" fill="#2d1b4e" opacity="0.3" />
        {/* hoe */}
        <path d="M150 440 L178 352" stroke={night ? '#4a3a30' : '#9a6a3a'} strokeWidth="5" strokeLinecap="round" />
        <path d="M172 356 L196 350 L202 372 L178 370 Z" fill={night ? '#4a4a60' : '#7d8090'} />
        <path d="M176 360 L198 356" stroke="#fff" strokeWidth="1.2" opacity={night ? 0.2 : 0.5} />
        {/* cutlass */}
        <path d="M64 440 L60 418" stroke={night ? '#2a2030' : '#3a2a20'} strokeWidth="6" strokeLinecap="round" />
        <path d="M59 418 L50 340 Q48 326 56 330 L66 418 Z" fill={night ? '#6a6e90' : '#b8bcc8'} />
        <path d="M52 336 L60 410" stroke="#fff" strokeWidth="1.2" opacity={night ? 0.25 : 0.7} />
      </g>
      {[[230, 438, 1.15, 'yam'], [312, 444, 1, 'cassava']].map(([x, y, s, kind], i) => (
        <g key={i} transform={`translate(${x} ${y}) scale(${s})`}>
          <ellipse cx="4" cy="0" rx="40" ry="6" fill="#2d1b4e" opacity="0.35" />
          {kind === 'yam' ? (
            <g fill={night ? '#4a3428' : '#8a5a36'}>
              <path d="M-26 -38 q10 -22 40 -18 q8 4 -2 10 q-24 -4 -38 8 Z" />
              <path d="M-14 -40 q20 -26 44 -12 q4 6 -6 8 q-20 -8 -38 4 Z" fill={night ? '#3a2a20' : '#6e4426'} />
              <path d="M-30 -36 q4 -16 22 -18" stroke="#c9a070" strokeWidth="1" fill="none" opacity="0.6" />
            </g>
          ) : (
            <g>
              <path d="M-28 -38 q16 -18 36 -10 l14 -10 q-6 12 -14 14 q-18 -4 -36 6 Z" fill={night ? '#4a3a34' : '#6a3a2a'} />
              <path d="M-18 -40 q18 -20 40 -4" stroke={night ? '#5a4040' : '#7d4630'} strokeWidth="7" strokeLinecap="round" fill="none" />
              <ellipse cx="24" cy="-43" rx="3" ry="2.5" fill="#f2e6cc" opacity={night ? 0.4 : 1} />
            </g>
          )}
          <path d="M-32 -34 L-24 0 L28 0 L34 -34 Z" fill={night ? '#5a4a30' : '#c89a52'} />
          <path d="M-32 -34 L-24 0 M-18 -34 L-12 0 M-4 -34 L0 0 M10 -34 L12 0 M22 -34 L22 0 M-30 -24 H32 M-28 -12 H30" stroke={night ? '#3a2e20' : '#8a6630'} strokeWidth="1.5" />
          <path d="M10 -34 L34 -34 L28 0 L12 0 Z" fill="#3b2a5e" opacity="0.25" />
          <ellipse cx="1" cy="-34" rx="33" ry="5" fill="none" stroke={night ? '#6a5a40' : '#e2bb72'} strokeWidth="3" />
        </g>
      ))}

      {night && (
        <g>
          <NightShade p={P} exclude={`M0 0 H800 V250 H0 Z`} feather={[180, 250]} />
          <Glow p={P} cx={607} cy={272} r={80} o={0.95} />
          <Glow p={P} cx={638} cy={258} r={36} o={0.7} />
          <rect x="596" y="252" width="22" height="36" fill="#ffb24a" opacity="0.7" />
          {/* hurricane lantern hanging at doorway */}
          <path d="M592 246 v6" stroke="#2a2232" strokeWidth="1" />
          <rect x="589" y="252" width="6" height="9" rx="2" fill="#ffe9a8" />
          <Glow p={P} cx={592} cy={256} r={50} kind="gf" o={0.9} />
          {fireflies.map((f, i) => (
            <g key={i}>
              <circle cx={f.x} cy={f.y} r={f.s * 3} fill="#d9ff7a" opacity="0.12" />
              <circle cx={f.x} cy={f.y} r={f.s * 0.9} fill="#f4ffb0" />
            </g>
          ))}
          {/* moon rim on stump + baskets */}
          <path d="M80 388 Q96 380 112 380" stroke={dim('#c9d2ff', false)} strokeWidth="1.5" opacity="0.35" fill="none" />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
