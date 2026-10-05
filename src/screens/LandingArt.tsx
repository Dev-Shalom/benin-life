// Landing page art that is too heavy for the first load (scenes + avatars).
// Lazy-loaded by Landing.tsx only when a card scrolls near the viewport.
import { Scene } from '../art/Scene';
import type { SceneType } from '../lib/types';

// The landing page must not load three.js, so its Sims are still images rendered from the 3D avatar
// system (regenerate them from /dev/avatars, "Landing images"; see LANDING_SIMS in src/art/avatar3d/dev).
const SIM_IMG = { lapo: '/art/sim-lapo.webp', nepo: '/art/sim-nepo.webp' } as const;

export interface LandingArtProps {
  scene: SceneType;
  night: boolean;
  /** Optional Sim standing in front of the scene. */
  sim?: 'lapo' | 'nepo';
}

export default function LandingArt({ scene, night, sim }: LandingArtProps) {
  return (
    <>
      <Scene type={scene} night={night} />
      {sim && (
        <div className="landing__sim">
          <img src={SIM_IMG[sim]} alt="" width={240} height={480} decoding="async" draggable={false} />
        </div>
      )}
    </>
  );
}
