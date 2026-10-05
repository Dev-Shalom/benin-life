// Brand art for the shell screens (logo + dusk skyline). Pure SVG, no network.

/** Bronze medallion with a ring of coral beads around a map pin. */
export function Logo({ size = 56 }: { size?: number }) {
  const beads = Array.from({ length: 12 }, (_, i) => {
    const a = (i / 12) * Math.PI * 2;
    return { x: 32 + Math.cos(a) * 22, y: 32 + Math.sin(a) * 22 };
  });
  return (
    <svg viewBox="0 0 64 64" width={size} height={size} aria-hidden>
      <defs>
        <radialGradient id="logo-disc" cx="38%" cy="30%" r="75%">
          <stop offset="0%" stopColor="#f6dc9a" />
          <stop offset="45%" stopColor="#d9a441" />
          <stop offset="80%" stopColor="#9a6328" />
          <stop offset="100%" stopColor="#6e431a" />
        </radialGradient>
        <radialGradient id="logo-bead" cx="35%" cy="30%" r="70%">
          <stop offset="0%" stopColor="#ffb3a1" />
          <stop offset="50%" stopColor="#d2342a" />
          <stop offset="100%" stopColor="#8a1a14" />
        </radialGradient>
        <linearGradient id="logo-pin" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#3a2a6a" />
          <stop offset="100%" stopColor="#141634" />
        </linearGradient>
      </defs>
      <circle cx="32" cy="33.5" r="30" fill="#3b1d10" opacity="0.35" />
      <circle cx="32" cy="32" r="30" fill="url(#logo-disc)" />
      <circle cx="32" cy="32" r="27.5" fill="none" stroke="#fff3cf" strokeOpacity="0.45" strokeWidth="1" />
      {beads.map((b, i) => (
        <circle key={i} cx={b.x} cy={b.y} r="4.2" fill="url(#logo-bead)" stroke="#6e1410" strokeOpacity="0.4" strokeWidth="0.6" />
      ))}
      <path d="M32 45s9-8.2 9-15.2a9 9 0 1 0-18 0C23 36.8 32 45 32 45Z" fill="url(#logo-pin)" />
      <circle cx="32" cy="29.6" r="3.6" fill="#f3d28a" />
    </svg>
  );
}

/** Dusk skyline of Benin: sun, the Oba's palace in silhouette, buildings, palms, Ring Road traffic. */
export function Skyline({ className, vehicles = true, anchor = 'center' }: {
  className?: string;
  vehicles?: boolean;
  /** Which part stays in view when a narrow screen crops the sides ('right' keeps the sun and palace). */
  anchor?: 'center' | 'right';
}) {
  const windows: { x: number; y: number }[] = [];
  const blocks = [
    { x: 40, w: 90, h: 120 }, { x: 140, w: 60, h: 170 }, { x: 210, w: 110, h: 95 }, { x: 330, w: 70, h: 210 },
    { x: 410, w: 120, h: 130 }, { x: 545, w: 80, h: 180 }, { x: 640, w: 140, h: 110 }, { x: 900, w: 90, h: 150 },
    { x: 1000, w: 70, h: 200 }, { x: 1080, w: 110, h: 120 },
  ];
  blocks.forEach((b, bi) => {
    for (let y = 330 - b.h + 16; y < 316; y += 22) {
      for (let x = b.x + 10; x < b.x + b.w - 10; x += 18) {
        if ((x * 7 + y * 3 + bi * 11) % 5 < 2) windows.push({ x, y });
      }
    }
  });
  return (
    <svg
      className={className}
      viewBox="0 0 1200 420"
      preserveAspectRatio={anchor === 'right' ? 'xMaxYMax slice' : 'xMidYMax slice'}
      aria-hidden
    >
      <defs>
        <radialGradient id="hero-sun" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#fff1c4" />
          <stop offset="45%" stopColor="#f7b552" />
          <stop offset="100%" stopColor="#e2672f" />
        </radialGradient>
        <radialGradient id="hero-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#ffb25c" stopOpacity="0.55" />
          <stop offset="100%" stopColor="#ffb25c" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="hero-hill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#8c3a3a" />
          <stop offset="100%" stopColor="#4a1f33" />
        </linearGradient>
        <linearGradient id="hero-city" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#3a2347" />
          <stop offset="100%" stopColor="#1d1530" />
        </linearGradient>
        <linearGradient id="hero-road" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#7c3216" />
          <stop offset="100%" stopColor="#3c160b" />
        </linearGradient>
        <linearGradient id="hero-bus" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#46ad66" />
          <stop offset="100%" stopColor="#13512a" />
        </linearGradient>
        <linearGradient id="hero-keke" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#ffd25e" />
          <stop offset="100%" stopColor="#c98a12" />
        </linearGradient>
      </defs>

      <ellipse cx="850" cy="270" rx="300" ry="150" fill="url(#hero-glow)" />
      <circle cx="850" cy="250" r="92" fill="url(#hero-sun)" />

      <path d="M0 300 C120 250 220 270 330 240 C450 205 560 260 680 235 C800 210 930 250 1040 225 C1110 210 1160 220 1200 230 V420 H0Z"
        fill="url(#hero-hill)" opacity="0.85" />

      <g fill="url(#hero-city)">
        {blocks.map((b, i) => (
          <rect key={i} x={b.x} y={330 - b.h} width={b.w} height={b.h} rx="3" />
        ))}
        {/* water tank + mast */}
        <rect x="362" y="96" width="6" height="30" />
        <ellipse cx="365" cy="96" rx="16" ry="8" />
        <rect x="1032" y="110" width="4" height="25" />
      </g>
      <g fill="#ffcf73">
        {windows.map((w, i) => (
          <rect key={i} x={w.x} y={w.y} width="8" height="10" rx="1" opacity={0.55 + ((i * 37) % 40) / 100} />
        ))}
      </g>


      {/* The Oba's palace: pyramid roofs silhouetted against the setting sun, gate glowing. */}
      <g fill="url(#hero-city)">
        <rect x="772" y="298" width="156" height="42" />
        <rect x="781" y="268" width="22" height="72" />
        <path d="M775 270 L792 236 L809 270Z" />
        <rect x="897" y="268" width="22" height="72" />
        <path d="M891 270 L908 236 L925 270Z" />
        <rect x="817" y="256" width="66" height="84" />
        <path d="M807 258 L850 206 L893 258Z" />
        <path d="M824 236 L850 205 L876 236Z" opacity="0.6" />
        {/* bronze bird on the apex (not a spire) */}
        <path d="M841 205 C843 199 849 196 854 198 L860 195 L857 200 C858 203 856 206 852 207 L846 207 L838 210Z" />
      </g>
      <path d="M838 340 V318 a12 12 0 0 1 24 0 V340Z" fill="#ffcf73" opacity="0.7" />
      <g fill="#ffcf73" opacity="0.5">
        <rect x="788" y="284" width="8" height="10" rx="1" />
        <rect x="904" y="284" width="8" height="10" rx="1" />
      </g>

      {/* palms */}
      {[
        { x: 110, s: 1 }, { x: 752, s: 1.1 }, { x: 948, s: 0.85 }, { x: 1150, s: 1 },
      ].map((p, i) => (
        <g key={i} transform={`translate(${p.x} 340) scale(${p.s})`} fill="#150f22">
          <path d="M-3 0 C-1 -60 4 -110 10 -150 L14 -150 C9 -110 5 -60 5 0Z" />
          <path d="M12 -150 C-10 -170 -40 -160 -60 -135 C-35 -150 -12 -152 12 -146Z" />
          <path d="M12 -150 C30 -175 62 -170 80 -140 C55 -155 32 -155 12 -146Z" />
          <path d="M12 -150 C0 -185 20 -200 34 -205 C22 -190 18 -170 14 -148Z" />
          <path d="M12 -150 C-15 -150 -38 -125 -45 -100 C-28 -125 -10 -138 12 -144Z" />
          <path d="M12 -150 C38 -150 60 -128 66 -104 C48 -126 30 -138 12 -144Z" />
        </g>
      ))}

      {/* road */}
      <path d="M0 340 H1200 V420 H0Z" fill="url(#hero-road)" />
      <path d="M0 338 H1200" stroke="#d9a441" strokeOpacity="0.5" strokeWidth="2" />
      <g stroke="#f3d28a" strokeOpacity="0.55" strokeWidth="4" strokeDasharray="34 26">
        <path d="M0 382 H1200" />
      </g>

      {vehicles && (
        <>
          <g transform="translate(250 334)"><BusBody /></g>
          <g transform="translate(690 350)"><KekeBody /></g>
        </>
      )}
    </svg>
  );
}

/** ECTS bus body, drawn around (0,0) = left end of the chassis line. */
function BusBody({ grad = 'hero-bus' }: { grad?: string }) {
  return (
    <>
      <ellipse cx="80" cy="34" rx="88" ry="6" fill="#1a0a05" opacity="0.45" />
      <rect x="0" y="-38" width="160" height="66" rx="12" fill={`url(#${grad})`} />
      <rect x="10" y="-28" width="120" height="22" rx="4" fill="#bfe7f2" opacity="0.85" />
      <rect x="136" y="-28" width="16" height="30" rx="3" fill="#bfe7f2" opacity="0.85" />
      <rect x="0" y="0" width="160" height="6" fill="#f3d28a" />
      <circle cx="34" cy="28" r="11" fill="#1d1530" />
      <circle cx="128" cy="28" r="11" fill="#1d1530" />
      <circle cx="34" cy="28" r="4" fill="#9c8f88" />
      <circle cx="128" cy="28" r="4" fill="#9c8f88" />
      <circle cx="156" cy="14" r="3.5" fill="#fff4c9" />
    </>
  );
}

function KekeBody({ grad = 'hero-keke' }: { grad?: string }) {
  return (
    <>
      <ellipse cx="38" cy="26" rx="44" ry="5" fill="#1a0a05" opacity="0.45" />
      <path d="M6 18 V-12 C6 -26 20 -34 36 -34 H52 C66 -34 74 -24 76 -10 L80 18Z" fill={`url(#${grad})`} />
      <path d="M14 -6 V-24 C20 -28 28 -29 36 -29 V-6Z" fill="#bfe7f2" opacity="0.8" />
      <path d="M42 -6 V-29 H52 C62 -29 68 -22 70 -6Z" fill="#bfe7f2" opacity="0.8" />
      <rect x="6" y="4" width="74" height="4" fill="#1f7a3f" />
      <circle cx="18" cy="20" r="9" fill="#1d1530" />
      <circle cx="68" cy="20" r="9" fill="#1d1530" />
    </>
  );
}

/** Standalone ECTS bus (own SVG so it can be moved as a composited layer). */
export function EctsBus({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="-10 -40 180 82" aria-hidden>
      <defs>
        <linearGradient id="veh-bus" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#46ad66" />
          <stop offset="100%" stopColor="#13512a" />
        </linearGradient>
      </defs>
      <BusBody grad="veh-bus" />
    </svg>
  );
}

/** Standalone keke. */
export function Keke({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="-8 -36 92 68" aria-hidden>
      <defs>
        <linearGradient id="veh-keke" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#ffd25e" />
          <stop offset="100%" stopColor="#c98a12" />
        </linearGradient>
      </defs>
      <KekeBody grad="veh-keke" />
    </svg>
  );
}

/** Bumper-to-bumper traffic: the Ramat Park go-slow. */
export function GoSlow({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="-10 -44 420 86" aria-hidden>
      <defs>
        <linearGradient id="goslow-bus" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#46ad66" />
          <stop offset="100%" stopColor="#13512a" />
        </linearGradient>
        <linearGradient id="goslow-keke" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#ffd25e" />
          <stop offset="100%" stopColor="#c98a12" />
        </linearGradient>
      </defs>
      <path d="M-10 40 H410" stroke="#0b3a1c" strokeOpacity="0.5" strokeWidth="2" />
      <g transform="translate(0 10)"><KekeBody grad="goslow-keke" /></g>
      <g transform="translate(100 2)"><BusBody grad="goslow-bus" /></g>
      <g transform="translate(286 10)"><KekeBody grad="goslow-keke" /></g>
    </svg>
  );
}

/** Row of coral beads used as a divider. */
export function BeadRow({ count = 9 }: { count?: number }) {
  return (
    <div className="bead-row" aria-hidden>
      {Array.from({ length: count }, (_, i) => (
        <span key={i} className={i % 4 === 2 ? 'bead bead--gold' : 'bead'} />
      ))}
    </div>
  );
}
