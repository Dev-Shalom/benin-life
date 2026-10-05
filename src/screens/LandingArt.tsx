// Landing page art that is too heavy for the first load (scenes + avatars).
// Lazy-loaded by Landing.tsx only when a card scrolls near the viewport.
import { Scene } from '../art/Scene';
import { Avatar } from '../art/avatar/Avatar';
import { defaultAvatar } from '../art/avatar/catalog';
import type { AvatarConfig, SceneType } from '../lib/types';

const LAPO_SIM: AvatarConfig = {
  ...defaultAvatar('male'),
  skin: 'tone5',
  hair: 'low_cut',
  outfit: 'keke_rider',
  outfitColor: '#d9a128',
  mouth: 'grin',
  accessories: ['cap'],
};

const NEPO_SIM: AvatarConfig = {
  ...defaultAvatar('female'),
  skin: 'tone3',
  hair: 'bone_straight',
  outfit: 'senator',
  outfitColor: '#f4f1ea',
  mouth: 'smirk',
  accessories: ['sunglasses', 'gold_chain', 'phone_in_hand'],
};

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
          <Avatar config={sim === 'nepo' ? NEPO_SIM : LAPO_SIM} view="full" />
        </div>
      )}
    </>
  );
}
