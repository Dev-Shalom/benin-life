// Face-me-I-face-you compound (Aduwawa / Ekenwan) — P1-SCENES-B
import { dim, Sky, NightShade, Finish, GlowDefs, Glow, Person, PlasticChair, Bucket, Bulb, Palm, Treeline, ZincPattern, SIGN_FONT, HAND_FONT } from './_sharedB';

const P = 'home_face_me';
type Pt = [number, number];
// One-point perspective. Depth z (rooms) -> t in [0,1); vanishing point (400,228).
const tz = (z: number) => z / (z + 3);
const top = (t: number) => 100 + 128 * t;
const bot = (t: number) => 470 - 242 * t;
const lx = (t: number) => 110 + 290 * t;
const rx = (t: number) => 690 - 290 * t;
const L = (z: number, v: number): Pt => { const t = tz(z); return [lx(t), top(t) + v * (bot(t) - top(t))]; };
const R = (z: number, v: number): Pt => { const t = tz(z); return [rx(t), top(t) + v * (bot(t) - top(t))]; };
const F = (z: number, u: number): Pt => { const t = tz(z); return [lx(t) + (rx(t) - lx(t)) * u, bot(t)]; };
const k = (z: number) => 1 - tz(z);
const eL = (z: number): Pt => { const t = tz(z); return [150 + 250 * t, 18 + 210 * t]; };
const eR = (z: number): Pt => { const t = tz(z); return [650 - 250 * t, 18 + 210 * t]; };
const q = (...pts: Pt[]) => 'M' + pts.map((p) => `${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' L') + ' Z';
const ZN = -1.35; // nearest depth drawn
const ZF = 7; // back wall depth

const CURTAINS = ['#d2342a', '#1f7a3f', '#e0a526', '#7a3fa0', '#2f6fd0', '#e86a9a', '#d2342a'];

export default function HomeFaceMeScene({ night }: { night: boolean }) {
  const skyHole = `M${eL(-1.2)[0]} 0 L${eL(ZF)[0]} ${eL(ZF)[1]} L${L(ZF, 0)[0]} ${L(ZF, 0)[1]} L${R(ZF, 0)[0]} ${R(ZF, 0)[1]} L${eR(ZF)[0]} ${eR(ZF)[1]} L${eR(-1.2)[0]} 0 Z`;
  // facade colours (left in shade, right sunlit)
  const litWall = '#f0dfbf';
  const shadeWall = '#b3a2b3';
  const litDado = '#3c9a8c';
  const shadeDado = '#2c5d6e';

  const facade = (side: 'L' | 'R') => {
    const S = side === 'L' ? L : R;
    const lit = side === 'R';
    const rooms = [];
    for (let i = -1; i < 7; i++) {
      const d0 = i + 0.12;
      const d1 = i + 0.47;
      const w0 = i + 0.6;
      const w1 = i + 0.86;
      const cur = CURTAINS[(i + (side === 'L' ? 1 : 4) + 7) % 7];
      // folds inside the curtain
      const folds = [0.2, 0.4, 0.6, 0.8].map((f) => {
        const z = d0 + (d1 - d0) * f;
        return `M${S(z, 0.24)[0].toFixed(1)} ${S(z, 0.24)[1].toFixed(1)} L${S(z, 0.97)[0].toFixed(1)} ${S(z, 0.97)[1].toFixed(1)}`;
      }).join(' ');
      const slats = [0.33, 0.37, 0.41, 0.45, 0.49, 0.53].map((v) => `M${S(w0, v)[0].toFixed(1)} ${S(w0, v)[1].toFixed(1)} L${S(w1, v)[0].toFixed(1)} ${S(w1, v)[1].toFixed(1)}`).join(' ');
      rooms.push(
        <g key={i}>
          {/* door frame + dark interior */}
          <path d={q(S(d0 - 0.03, 0.2), S(d1 + 0.03, 0.2), S(d1 + 0.03, 1), S(d0 - 0.03, 1))} fill={lit ? '#8a5a3a' : '#5a4050'} />
          <path d={q(S(d0, 0.23), S(d1, 0.23), S(d1, 1), S(d0, 1))} fill="#2a1d33" />
          {/* curtain */}
          <path d={q(S(d0, 0.24), S(d1, 0.24), S(d1 - 0.04, 0.97), S(d0 + 0.06, 0.95))} fill={cur} opacity={lit ? 1 : 0.8} />
          <path d={folds} stroke="#2d1b4e" strokeWidth={Math.max(0.6, 2.2 * k(i + 0.3))} opacity="0.35" />
          <path d={q(S(d0, 0.24), S(d1, 0.24), S(d1, 0.3), S(d0, 0.3))} fill="#fff" opacity="0.18" />
          {night && <path className="fm-lit" d={q(S(d0, 0.24), S(d1, 0.24), S(d1 - 0.04, 0.97), S(d0 + 0.06, 0.95))} fill="#ffb24a" opacity="0.55" style={{ mixBlendMode: 'screen' }} />}
          {/* room number */}
          <text x={S(d0 + 0.17, 0.15)[0]} y={S(d0 + 0.17, 0.15)[1]} fontSize={Math.max(4, 11 * k(i + 0.3))} fontFamily={HAND_FONT} fill={lit ? '#7a3519' : '#4a2a40'} textAnchor="middle">{`RM ${side === 'L' ? i * 2 + 3 : i * 2 + 4}`}</text>
          {/* louvre window */}
          <path d={q(S(w0, 0.29), S(w1, 0.29), S(w1, 0.57), S(w0, 0.57))} fill={lit ? '#7d5a3e' : '#4b3a4a'} />
          <path d={q(S(w0 + 0.01, 0.31), S(w1 - 0.01, 0.31), S(w1 - 0.01, 0.55), S(w0 + 0.01, 0.55))} fill={night ? '#ffcf73' : lit ? '#6f8fa8' : '#3f4f68'} />
          <path d={slats} stroke={night ? '#a8661d' : '#e8eef2'} strokeWidth={Math.max(0.5, 2.6 * k(i + 0.7))} opacity={night ? 0.6 : 0.75} />
          {/* burglary-proof bars */}
          <path d={[0.25, 0.5, 0.75].map((f) => { const z = w0 + (w1 - w0) * f; return `M${S(z, 0.3)[0]} ${S(z, 0.3)[1]} L${S(z, 0.56)[0]} ${S(z, 0.56)[1]}`; }).join(' ')} stroke="#2a2a3a" strokeWidth={Math.max(0.5, 1.8 * k(i + 0.7))} />
        </g>,
      );
    }
    return rooms;
  };

  // clothes on a line between left and right walls at depth z
  const line = (z: number, colors: string[]) => {
    const a = L(z, 0.1);
    const b = R(z + 0.25, 0.1);
    const s = k(z + 0.12);
    const mid: Pt = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + 30 * s];
    const items = colors.map((c, i) => {
      const f = (i + 1) / (colors.length + 1);
      const x = (1 - f) * (1 - f) * a[0] + 2 * f * (1 - f) * mid[0] + f * f * b[0];
      const y = (1 - f) * (1 - f) * a[1] + 2 * f * (1 - f) * mid[1] + f * f * b[1];
      const w = (i % 3 === 1 ? 46 : 62) * s;
      const h = (i % 2 ? 66 : 88) * s;
      return (
        <g key={i}>
          {i % 3 === 1 ? (
            <path d={`M${x - w / 2} ${y} l${w * 0.15} ${h * 0.2} v${h * 0.8} h${w * 0.7} v${-h * 0.8} l${w * 0.15} ${-h * 0.2} l${-w * 0.25} 0 q${-w * 0.25} ${h * 0.18} ${-w * 0.5} 0 Z`} fill={dim(c, night)} />
          ) : (
            <path d={`M${x - w / 2} ${y} h${w} l${-w * 0.04} ${h} q${-w * 0.46} ${-h * 0.08} ${-w * 0.92} 0 Z`} fill={dim(c, night)} />
          )}
          <path d={`M${x + w * 0.1} ${y} l${-w * 0.04} ${h} l${w * 0.44} 0 l${-w * 0.04} ${-h} Z`} fill="#2d1b4e" opacity="0.22" />
          {i % 2 === 0 && <path d={`M${x - w / 2 + 3 * s} ${y + h * 0.3} h${w - 6 * s} M${x - w / 2 + 3 * s} ${y + h * 0.6} h${w - 6 * s}`} stroke="#fff" strokeWidth={2 * s} strokeDasharray={`${4 * s} ${3 * s}`} opacity={night ? 0.12 : 0.35} />}
          <rect x={x - 2 * s} y={y - 3 * s} width={4 * s} height={6 * s} fill={dim('#ffd34a', night)} />
        </g>
      );
    });
    return (
      <g>
        <path d={`M${a[0]} ${a[1]} Q${mid[0]} ${mid[1] + 30 * s} ${b[0]} ${b[1]}`} stroke="#3a3346" strokeWidth={Math.max(0.6, 1.4 * s)} fill="none" />
        {items}
      </g>
    );
  };

  const fl = (z: number, u: number) => F(z, u);
  const lines = (
    <g>
      {line(4.6, ['#e86a9a', '#e0a526', '#2f6fd0', '#f2f0ea'])}
      {line(2.2, ['#7a3fa0', '#f2f0ea', '#d2342a', '#1f7a3f', '#e0a526'])}
      {line(-0.2, ['#d2342a', '#f2f0ea', '#2f6fd0'])}
    </g>
  );

  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" role="img" aria-label="Face-me-I-face-you compound">
      <defs>
        <linearGradient id={`${P}-floor`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#a99682" />
          <stop offset="0.5" stopColor="#bba58a" />
          <stop offset="1" stopColor="#9a8270" />
        </linearGradient>
        <linearGradient id={`${P}-litw`} x1="1" y1="0" x2="0" y2="0">
          <stop offset="0" stopColor="#f7e7c6" />
          <stop offset="0.6" stopColor={litWall} />
          <stop offset="1" stopColor="#d8c2a4" />
        </linearGradient>
        <linearGradient id={`${P}-shw`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#a594ad" />
          <stop offset="0.7" stopColor={shadeWall} />
          <stop offset="1" stopColor="#c7b0a8" />
        </linearGradient>
        <linearGradient id={`${P}-sof`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3e3048" />
          <stop offset="1" stopColor="#6a5246" />
        </linearGradient>
        <linearGradient id={`${P}-dust`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor="#b5552b" stopOpacity="0.55" />
          <stop offset="1" stopColor="#b5552b" stopOpacity="0" />
        </linearGradient>
      </defs>
      <GlowDefs p={P} />
      <ZincPattern p={P} night={night} />
      <Sky p={P} night={night} sunX={250} sunY={40} moonX={430} moonY={60} clouds={!night} />

      {/* beyond the back wall: neighbour roofs, palm */}
      <Treeline y={196} fill={night ? '#22304a' : '#6f9a72'} seed={11} amp={9} step={20} base={300} />
      <path d="M300 200 L350 178 L420 182 L470 172 L520 196 L520 260 L300 260 Z" fill={`url(#${P}-zinc)`} opacity="0.85" />
      <path d="M300 200 L350 178 L420 182 L470 172 L520 196 L520 260 L300 260 Z" fill={`url(#${P}-rust)`} />
      <Palm x={455} y={205} s={0.55} night={night} lean={10} />

      {/* back wall with shared toilet & bathroom */}
      <path d={q(L(ZF, 0), R(ZF, 0), R(ZF, 1), L(ZF, 1))} fill={night ? '#cbbba0' : '#e6d3b0'} />
      <path d={q(L(ZF, 0.62), R(ZF, 0.62), R(ZF, 1), L(ZF, 1))} fill="#3c9a8c" opacity="0.85" />
      <rect x="337" y="222" width="34" height="74" fill="#6e4a32" />
      <rect x="340" y="225" width="28" height="71" fill="#8f6542" />
      <rect x="402" y="222" width="34" height="74" fill="#6e4a32" />
      <rect x="405" y="225" width="28" height="71" fill="#4f7aa0" />
      <text x="354" y="240" fontSize="6.5" fontFamily={SIGN_FONT} fill="#f6e8c8" textAnchor="middle">TOILET</text>
      <text x="419" y="240" fontSize="5.5" fontFamily={SIGN_FONT} fill="#f6e8c8" textAnchor="middle">BAFROOM</text>
      <text x="354" y="252" fontSize="4.2" fontFamily={HAND_FONT} fill="#ffe9a8" textAnchor="middle">pls flush o!!</text>
      <rect x="448" y="262" width="22" height="30" rx="4" fill="#2f6fd0" />
      <ellipse cx="459" cy="262" rx="11" ry="3" fill="#24539c" />
      <path d={q(L(ZF, 0), R(ZF, 0), R(ZF, 0.06), L(ZF, 0.06))} fill="#2d1b4e" opacity="0.25" />

      {/* floor */}
      <path d={q(F(ZN, 0), F(ZF, 0), F(ZF, 1), F(ZN, 1))} fill={`url(#${P}-floor)`} />
      <path d={`M0 450 L${fl(ZN, 0)[0]} ${fl(ZN, 0)[1]} L${fl(ZF, 0)[0]} ${fl(ZF, 0)[1]} L${fl(ZF, 0.12)[0]} ${fl(ZF, 0.12)[1]} L${fl(ZN, 0.25)[0]} 450 Z`} fill={`url(#${P}-dust)`} opacity="0.7" />
      {/* cracks */}
      <path d="M420 330 l-14 18 l6 10 l-20 26 M500 400 l18 12 l-4 14 l22 20 M300 360 l10 14 l-8 20" stroke="#6e5a52" strokeWidth="1.2" fill="none" opacity="0.6" />
      {/* shadow of left roof on floor (sun from upper-left is blocked) */}
      <path d={q(F(ZN, 0), F(ZF, 0), F(ZF, 0.35), F(ZN, 0.42))} fill="#3b2a5e" opacity="0.28" />
      <path d={q(F(ZN, 0.55), F(ZF, 0.5), F(ZF, 1), F(ZN, 1))} fill="#ffe0a8" opacity={night ? 0 : 0.22} />
      {/* puddle near tap */}
      <ellipse cx={fl(2.3, 0.38)[0]} cy={fl(2.3, 0.38)[1] + 4} rx="48" ry="8" fill={night ? '#6a74b8' : '#9fc4d8'} opacity="0.55" />
      <ellipse cx={fl(2.3, 0.38)[0] - 10} cy={fl(2.3, 0.38)[1] + 2} rx="18" ry="2" fill="#fff" opacity="0.4" />

      {/* left facade (shade) */}
      <path d={q(L(ZN, 0), L(ZF, 0), L(ZF, 1), L(ZN, 1))} fill={`url(#${P}-shw)`} />
      <path d={q(L(ZN, 0.66), L(ZF, 0.66), L(ZF, 1), L(ZN, 1))} fill={shadeDado} />
      <path d={q(L(ZN, 0.66), L(ZF, 0.66), L(ZF, 0.675), L(ZN, 0.675))} fill="#1e3e4f" opacity="0.6" />
      {/* reflected warm bounce from sunlit floor */}
      <path d={q(L(ZN, 0.75), L(ZF, 0.75), L(ZF, 1), L(ZN, 1))} fill="#ffb27a" opacity="0.12" />
      {facade('L')}
      {/* right facade (sunlit) */}
      <path d={q(R(ZN, 0), R(ZF, 0), R(ZF, 1), R(ZN, 1))} fill={`url(#${P}-litw)`} />
      <path d={q(R(ZN, 0.66), R(ZF, 0.66), R(ZF, 1), R(ZN, 1))} fill={litDado} />
      <path d={q(R(ZN, 0.66), R(ZF, 0.66), R(ZF, 0.675), R(ZN, 0.675))} fill="#e8f6ee" opacity="0.5" />
      {/* peeling paint patches */}
      <path d={`M${R(0.55, 0.45)[0]} ${R(0.55, 0.45)[1]} q-10 4 -6 12 q-8 6 2 10 q10 -2 12 -12 Z`} fill="#c9a882" opacity="0.7" />
      <path d={`M${R(-0.9, 0.5)[0]} ${R(-0.9, 0.5)[1]} q-14 6 -8 18 q-10 8 4 14 q14 -4 16 -18 Z`} fill="#c9a882" opacity="0.7" />
      {facade('R')}
      {/* roof shadow band on the right wall */}
      <path d={q(R(ZN, 0), R(ZF, 0), R(ZF, 0.16), R(ZN, 0.2))} fill="#3b2a5e" opacity="0.3" />

      {/* landlord notice */}
      <g transform={`translate(${R(-0.68, 0.3)[0] - 34} ${R(-0.68, 0.3)[1] - 26}) skewY(-6)`}>
        <rect width="62" height="50" fill="#fbf6e6" />
        <rect width="62" height="50" fill="#2d1b4e" opacity="0.06" />
        <text x="31" y="11" fontSize="8" fontFamily={SIGN_FONT} fill="#d2342a" textAnchor="middle">NOTICE!!</text>
        <text x="31" y="21" fontSize="5.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">Light bill ₦3,500</text>
        <text x="31" y="29" fontSize="5.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">pay b4 Friday o</text>
        <text x="31" y="37" fontSize="5.5" fontFamily={HAND_FONT} fill="#2a2440" textAnchor="middle">No gen after 11pm</text>
        <text x="31" y="46" fontSize="5" fontFamily={HAND_FONT} fill="#7a3519" textAnchor="middle">— LANDLORD</text>
        <circle cx="5" cy="4" r="1.6" fill="#d2342a" />
        <circle cx="57" cy="4" r="1.6" fill="#d2342a" />
      </g>
      {/* electricity meter + wires on left wall */}
      <rect x={L(-0.62, 0.22)[0] - 10} y={L(-0.62, 0.22)[1]} width="22" height="30" rx="2" fill="#d9d4c4" />
      <rect x={L(-0.62, 0.22)[0] - 6} y={L(-0.62, 0.22)[1] + 6} width="14" height="7" fill="#2f3a4a" />
      <path d={`M${L(-0.62, 0.22)[0]} ${L(-0.62, 0.22)[1]} L${L(-0.62, 0.05)[0]} ${L(-0.62, 0.05)[1]} L${L(3, 0.06)[0]} ${L(3, 0.06)[1]}`} stroke="#1d1a28" strokeWidth="1.4" fill="none" />

      {/* soffits / eaves (zinc overhangs) */}
      <path d={q(eL(ZN), eL(ZF), L(ZF, 0), L(ZN, 0))} fill={`url(#${P}-sof)`} />
      <path d={q(eR(ZN), eR(ZF), R(ZF, 0), R(ZN, 0))} fill={`url(#${P}-sof)`} />
      {/* rafters */}
      {[-1, 0, 1, 2, 3, 4, 5, 6].map((z) => (
        <g key={z}>
          <path d={`M${eL(z)[0]} ${eL(z)[1]} L${L(z, 0)[0]} ${L(z, 0)[1]}`} stroke="#2a1f30" strokeWidth={Math.max(1, 6 * k(z))} />
          <path d={`M${eR(z)[0]} ${eR(z)[1]} L${R(z, 0)[0]} ${R(z, 0)[1]}`} stroke="#2a1f30" strokeWidth={Math.max(1, 6 * k(z))} />
        </g>
      ))}
      {/* zinc fascia edge */}
      <path d={`M${eL(ZN)[0]} ${eL(ZN)[1]} L${eL(ZF)[0]} ${eL(ZF)[1]} L${eL(ZF)[0] + 3} ${eL(ZF)[1] - 5} L${eL(ZN)[0] + 26} ${eL(ZN)[1] - 40} Z`} fill={`url(#${P}-zinc)`} />
      <path d={`M${eL(ZN)[0]} ${eL(ZN)[1]} L${eL(ZF)[0]} ${eL(ZF)[1]} L${eL(ZF)[0] + 3} ${eL(ZF)[1] - 5} L${eL(ZN)[0] + 26} ${eL(ZN)[1] - 40} Z`} fill={`url(#${P}-rust)`} />
      <path d={`M${eR(ZN)[0]} ${eR(ZN)[1]} L${eR(ZF)[0]} ${eR(ZF)[1]} L${eR(ZF)[0] - 3} ${eR(ZF)[1] - 5} L${eR(ZN)[0] - 26} ${eR(ZN)[1] - 40} Z`} fill={`url(#${P}-zinc)`} />
      <path d={`M${eR(ZN)[0]} ${eR(ZN)[1]} L${eR(ZF)[0]} ${eR(ZF)[1]} L${eR(ZF)[0] - 3} ${eR(ZF)[1] - 5} L${eR(ZN)[0] - 26} ${eR(ZN)[1] - 40} Z`} fill={`url(#${P}-rust)`} />

      {/* washing lines */}
      {!night && lines}

      {/* shared tap + jerrycan queue */}
      <g>
        <rect x={fl(2.3, 0.42)[0] - 3} y={fl(2.3, 0.42)[1] - 58} width="6" height="58" fill="#7d8090" />
        <path d={`M${fl(2.3, 0.42)[0]} ${fl(2.3, 0.42)[1] - 56} h14 v8`} stroke="#9a9db0" strokeWidth="5" fill="none" />
        <rect x={fl(2.3, 0.42)[0] + 9} y={fl(2.3, 0.42)[1] - 64} width="10" height="5" rx="1" fill="#d2342a" />
        <path d={`M${fl(2.3, 0.42)[0] + 14} ${fl(2.3, 0.42)[1] - 46} v24`} stroke="#bfe3f5" strokeWidth="2" opacity="0.8" />
        <Bucket x={fl(2.3, 0.42)[0] + 14} y={fl(2.3, 0.42)[1]} s={1.15} />
        {[0, 1, 2, 3].map((i) => {
          const [x, y] = fl(2.7 + i * 0.35, 0.36 - i * 0.02);
          const s = 1.5 * k(2.7 + i * 0.35);
          const c = ['#e0a526', '#2f6fd0', '#1f7a3f', '#d2342a'][i];
          return (
            <g key={i} transform={`translate(${x} ${y}) scale(${s})`}>
              <ellipse cx="2" cy="0" rx="12" ry="2.5" fill="#2d1b4e" opacity="0.3" />
              <rect x="-9" y="-26" width="18" height="26" rx="3" fill={c} />
              <rect x="2" y="-26" width="7" height="26" rx="2" fill="#2d1b4e" opacity="0.25" />
              <rect x="-4" y="-31" width="5" height="6" fill="#3a3346" />
              <path d="M2 -26 q4 -6 6 0" stroke={c} strokeWidth="2.5" fill="none" />
            </g>
          );
        })}
      </g>

      {/* woman at tap */}
      <Person x={fl(2.9, 0.3)[0]} y={fl(2.9, 0.3)[1]} s={2.0} skin="#5a3624" top="#e0a526" wrapper="#1f7a3f" headwrap="#d2342a" pose="work" facing={1} night={night} />
      {/* man reading paper on chair (right side, sunlit) */}
      <PlasticChair x={fl(1.3, 0.78)[0]} y={fl(1.3, 0.78)[1]} s={1.75} />
      <Person x={fl(1.3, 0.78)[0] + 4} y={fl(1.3, 0.78)[1]} s={2.0} skin="#4a2c1e" top="#f2f0ea" bottom="#3a4468" pose="sit" facing={-1} night={night}
        extra={<g transform="translate(14 -30) rotate(-10)"><rect x="-2" y="-9" width="13" height="11" fill="#efe9d8" /><path d="M0 -6 h9 M0 -3 h8 M0 0 h9" stroke="#7a7a8a" strokeWidth="0.8" /></g>} />
      {/* kid chasing a ball */}
      <Person x={fl(4.4, 0.6)[0]} y={fl(4.4, 0.6)[1]} s={1.05} skin="#5a3624" top="#2f6fd0" bottom="#d9d4c4" pose="walk" night={night} />
      <circle cx={fl(4.6, 0.68)[0]} cy={fl(4.6, 0.68)[1] - 5} r="5" fill="#f2f0ea" />
      <path d={`M${fl(4.6, 0.68)[0] - 5} ${fl(4.6, 0.68)[1] - 5} h10`} stroke="#d2342a" strokeWidth="1.5" />

      {/* kerosene stove + pot by left door */}
      <g transform={`translate(${fl(0.6, 0.1)[0]} ${fl(0.6, 0.1)[1]}) scale(1.6)`}>
        <ellipse cx="2" cy="0" rx="18" ry="3.5" fill="#2d1b4e" opacity="0.35" />
        <rect x="-13" y="-10" width="26" height="10" rx="2" fill="#2f6fd0" />
        <rect x="-11" y="-14" width="22" height="4" fill="#3a3346" />
        <path d="M-8 -14 q2 -5 4 0 q2 -5 4 0 q2 -5 4 0 q2 -5 4 0" fill={night ? '#5aa8ff' : '#7fb3ff'} opacity="0.8" />
        <path d="M-14 -16 h28 l-3 -16 h-22 Z" fill="#9a9db0" />
        <path d="M2 -32 h9 l3 16 h-12 Z" fill="#2d1b4e" opacity="0.25" />
        <ellipse cx="0" cy="-32" rx="12" ry="2.5" fill="#6d7084" />
        <path d="M-4 -38 q-4 -8 2 -14 q6 -6 0 -12" stroke="#f2f0f8" strokeWidth="3" fill="none" opacity="0.4" strokeLinecap="round" />
      </g>
      {/* slippers (kids + adult) */}
      {[[0.35, 0.05, '#d2342a'], [0.45, 0.07, '#2f6fd0'], [1.45, 0.94, '#e86a9a'], [2.0, 0.93, '#e0a526'], [3.35, 0.06, '#1f7a3f']].map(([z, u, c], i) => {
        const [x, y] = fl(z as number, u as number);
        const s = 1.4 * k(z as number);
        return (
          <g key={i} transform={`translate(${x} ${y}) scale(${s})`}>
            <ellipse cx="-5" cy="0" rx="6" ry="2.4" fill={c as string} transform="rotate(-12)" />
            <ellipse cx="6" cy="1" rx="6" ry="2.4" fill={c as string} transform="rotate(10)" />
            <path d="M-8 -1 q3 -3 6 0 M3 0 q3 -3 6 0" stroke="#fff" strokeWidth="1" fill="none" opacity="0.6" />
          </g>
        );
      })}
      {/* chair near camera, left */}
      <PlasticChair x={fl(-0.25, 0.1)[0]} y={fl(-0.25, 0.1)[1]} s={2.6} color="#d2342a" shade="#7a1f2a" />

      {night && (
        <g>
          <NightShade p={P} exclude={skyHole} />
          {lines}
          {/* lit curtains + window glow */}
          {[-1, 0, 1, 2, 3, 4, 5, 6].map((i) => (
            <g key={i}>
              <Glow p={P} cx={L(i + 0.3, 0.6)[0]} cy={L(i + 0.3, 0.6)[1]} r={60 * k(i + 0.3)} ry={110 * k(i + 0.3)} o={0.55} />
              <Glow p={P} cx={R(i + 0.3, 0.6)[0]} cy={R(i + 0.3, 0.6)[1]} r={60 * k(i + 0.3)} ry={110 * k(i + 0.3)} o={0.55} />
              <Glow p={P} cx={L(i + 0.73, 0.43)[0]} cy={L(i + 0.73, 0.43)[1]} r={34 * k(i + 0.7)} o={0.5} />
              <Glow p={P} cx={R(i + 0.73, 0.43)[0]} cy={R(i + 0.73, 0.43)[1]} r={34 * k(i + 0.7)} o={0.5} />
            </g>
          ))}
          <Bulb p={P} x={L(0.3, 0.06)[0] + 20} y={L(0.3, 0.06)[1] + 6} night={night} />
          <Bulb p={P} x={R(2.3, 0.06)[0] - 12} y={R(2.3, 0.06)[1] + 6} night={night} />
          <Bulb p={P} x={R(-0.8, 0.06)[0] - 30} y={R(-0.8, 0.06)[1] + 10} night={night} wire={20} />
          {/* stove flame glow */}
          <Glow p={P} cx={fl(0.6, 0.1)[0]} cy={fl(0.6, 0.1)[1] - 22} r={50} kind="gc" o={0.6} />
          {/* moonlight wash in courtyard */}
          <path d={q(F(ZN, 0.4), F(ZF, 0.3), F(ZF, 1), F(ZN, 1))} fill="#8fa0ff" opacity="0.08" style={{ mixBlendMode: 'screen' }} />
        </g>
      )}
      <Finish p={P} night={night} />
    </svg>
  );
}
