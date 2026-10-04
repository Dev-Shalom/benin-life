// Layered, fully parametric SVG avatar. Light comes from the top-left; shadows are
// indigo-tinted (never black). Every <defs> id is prefixed per instance (React useId).
import { useId, useMemo, type ReactNode } from 'react';
import type { AvatarConfig } from '../../lib/types';
import { normalizeAvatar, skinTone } from './catalog';
import { makeBody } from './geometry';
import { makeCtx } from './ctx';
import { arms, ears, hands, head, legs, neck, torso } from './body';
import { blush, brows, eyes, facialHair, mouth, nose } from './face';
import { hairBack, hairFront } from './hair';
import { outfit } from './outfits';
import { accessoriesBody, accessoriesHead, accessoriesHand } from './accessories';

export type AvatarView = 'full' | 'portrait';

/** Styles that rise well above the crown: the portrait frame drops a little so they aren't cropped. */
const TALL_HAIR = new Set(['high_top', 'gele']);

/** Pure render of the avatar layers (exported for tests / static rendering). */
export function renderAvatarLayers(config: AvatarConfig, view: AvatarView, uid: string): ReactNode {
  const cfg = normalizeAvatar(config);
  const b = makeBody(cfg.gender, cfg.body);
  const portrait = view === 'portrait';
  const c = makeCtx(uid, cfg, b, skinTone(cfg.skin), portrait);
  const o = outfit(c);

  const layers = (
    <g>
      {!portrait && <ellipse cx="100" cy="388" rx="46" ry="7" fill={c.def('ground', (id) => (
        <radialGradient id={id}>
          <stop offset="0" stopColor="#2a1b4d" stopOpacity="0.38" />
          <stop offset="0.6" stopColor="#2a1b4d" stopOpacity="0.16" />
          <stop offset="1" stopColor="#2a1b4d" stopOpacity="0" />
        </radialGradient>
      ))} />}
      {hairBack(c)}
      {o.back}
      {!portrait && !o.hideLegs && legs(c, { feet: o.bareFeet })}
      {!portrait && o.shoes}
      {arms(c, 'under')}
      {torso(c, { chest: o.bareChest })}
      {!portrait && o.lower}
      {neck(c)}
      {o.upper}
      {o.collar}
      {arms(c, 'over')}
      {o.sleeves}
      {!portrait && accessoriesHand(c, 'under')}
      {hands(c)}
      {o.overHands}
      {!portrait && accessoriesHand(c, 'over')}
      {accessoriesBody(c)}
      {ears(c)}
      {head(c)}
      {blush(c)}
      {nose(c)}
      {eyes(c)}
      {brows(c)}
      {facialHair(c)}
      {mouth(c)}
      {hairFront(c)}
      {o.head}
      {accessoriesHead(c)}
    </g>
  );
  const defs = <defs>{[...c.defs.entries()].map(([k, v]) => <g key={k}>{v}</g>)}</defs>;
  return (
    <>
      {defs}
      {portrait ? <g transform={`translate(-50 ${TALL_HAIR.has(cfg.hair) ? 3 : -6}) scale(1.5)`}>{layers}</g> : layers}
    </>
  );
}

export function Avatar({ config, view = 'full', size, className }: {
  config: AvatarConfig; view?: 'full' | 'portrait'; size?: number; className?: string;
}) {
  const rawId = useId();
  const uid = 'av' + rawId.replace(/[^a-zA-Z0-9_-]/g, '');
  const full = view === 'full';
  const key = JSON.stringify(config) + '|' + view;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const tree = useMemo(() => renderAvatarLayers(config, view, uid), [key, uid]);
  return (
    <svg viewBox={full ? '0 0 200 400' : '0 0 200 200'} width={size} height={size ? (full ? size * 2 : size) : undefined}
      className={className} role="img" aria-label="Avatar" xmlns="http://www.w3.org/2000/svg">
      {tree}
    </svg>
  );
}
