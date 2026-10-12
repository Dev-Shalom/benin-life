// Brand art for the shell screens (logo + landing go-slow). Pure SVG, no network.
// The logo (Ada + Eben swords with a coral bead) lives in src/ui/Logo.tsx; see docs/BRAND.md.
export { Logo } from '../ui/Logo';

/** ECTS bus body, drawn around (0,0) = left end of the chassis line. */
function BusBody({ grad = 'hero-bus' }: { grad?: string }) {
  return (
    <>
      <ellipse cx="80" cy="34" rx="88" ry="6" fill="#0a3f24" opacity="0.18" />
      <rect x="0" y="-38" width="160" height="66" rx="12" fill={`url(#${grad})`} />
      <rect x="10" y="-28" width="120" height="22" rx="4" fill="#bfe7f2" opacity="0.85" />
      <rect x="136" y="-28" width="16" height="30" rx="3" fill="#bfe7f2" opacity="0.85" />
      <rect x="0" y="0" width="160" height="6" fill="#f3d28a" />
      <circle cx="34" cy="28" r="11" fill="#283041" />
      <circle cx="128" cy="28" r="11" fill="#283041" />
      <circle cx="34" cy="28" r="4" fill="#9c8f88" />
      <circle cx="128" cy="28" r="4" fill="#9c8f88" />
      <circle cx="156" cy="14" r="3.5" fill="#fff4c9" />
    </>
  );
}

function KekeBody({ grad = 'hero-keke' }: { grad?: string }) {
  return (
    <>
      <ellipse cx="38" cy="26" rx="44" ry="5" fill="#0a3f24" opacity="0.18" />
      <path d="M6 18 V-12 C6 -26 20 -34 36 -34 H52 C66 -34 74 -24 76 -10 L80 18Z" fill={`url(#${grad})`} />
      <path d="M14 -6 V-24 C20 -28 28 -29 36 -29 V-6Z" fill="#bfe7f2" opacity="0.8" />
      <path d="M42 -6 V-29 H52 C62 -29 68 -22 70 -6Z" fill="#bfe7f2" opacity="0.8" />
      <rect x="6" y="4" width="74" height="4" fill="#1f7a3f" />
      <circle cx="18" cy="20" r="9" fill="#283041" />
      <circle cx="68" cy="20" r="9" fill="#283041" />
    </>
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
      <path d="M-10 40 H410" stroke="#0a6f40" strokeOpacity="0.25" strokeWidth="2" />
      <g transform="translate(0 10)"><KekeBody grad="goslow-keke" /></g>
      <g transform="translate(100 2)"><BusBody grad="goslow-bus" /></g>
      <g transform="translate(286 10)"><KekeBody grad="goslow-keke" /></g>
    </svg>
  );
}
