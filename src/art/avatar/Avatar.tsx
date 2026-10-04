// PHASE 0 STUB — P1-AVATAR replaces this file. Keep the export name/signature.
import type { AvatarConfig } from '../../lib/types';

export function Avatar({ config, view = 'full', size, className }: {
  config: AvatarConfig; view?: 'full' | 'portrait'; size?: number; className?: string;
}) {
  const full = view === 'full';
  return (
    <svg viewBox={full ? '0 0 200 400' : '0 0 200 200'} width={size} height={size ? (full ? size * 2 : size) : undefined}
      className={className} role="img" aria-label="Avatar">
      <circle cx="100" cy="80" r="45" fill="#7a4a2a" />
      {full && <rect x="55" y="130" width="90" height="200" rx="30" fill={config.outfitColor} />}
      {!full && <rect x="40" y="135" width="120" height="80" rx="40" fill={config.outfitColor} />}
    </svg>
  );
}
