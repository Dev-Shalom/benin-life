// W1 wardrobe: pure outfit logic (no React, no three.js). docs/WARDROBE.md
//
//   outfitFor(base, outfits, slot)  -> the look the Sim shows in that context
//   outfitContext({...})            -> which slot applies right now (sleep / work / party / gym / home / everyday)
//   itemPatch / lookPatch / applyPatch mirror bl_wardrobe_item_patch / bl_wardrobe_apply on the server.
import { normalizeAvatar } from '../art/avatar3d/catalog';
import type { AvatarConfig } from './types';

export const OUTFIT_SLOTS = ['everyday', 'home', 'sleep', 'date', 'party', 'work', 'gym'] as const;
export type OutfitSlot = (typeof OUTFIT_SLOTS)[number];

export type WardrobeCategory = 'top' | 'bottom' | 'outfit' | 'shoes' | 'bag' | 'hat_hair';
/** Merge order (same as the server). */
export const CATEGORY_ORDER: WardrobeCategory[] = ['outfit', 'top', 'bottom', 'shoes', 'bag', 'hat_hair'];

/** A partial avatar config. Garments merge key by key; `accessories` replaces only the bag accessories. */
export interface OutfitPatch {
  top?: Partial<AvatarConfig['top']>;
  bottom?: Partial<AvatarConfig['bottom']>;
  shoes?: Partial<AvatarConfig['shoes']>;
  hat?: string;
  accent?: string;
  accessories?: string[];
}

/** A saved slot: patch null = the slot's default rule. A missing slot = the everyday look. */
export interface SavedOutfit {
  items: { item: string; colour: string | null }[] | null;
  patch: OutfitPatch | null;
}
export type Outfits = Partial<Record<OutfitSlot, SavedOutfit>>;

export const BAG_ACCESSORIES = ['bag', 'backpack'];

export function itemPatch(category: WardrobeCategory, patch: OutfitPatch, colour: string | null): OutfitPatch {
  const p: OutfitPatch = JSON.parse(JSON.stringify(patch ?? {}));
  if (!colour) return p;
  if ((category === 'top' || category === 'outfit') && p.top) p.top.c = colour;
  if (category === 'bottom' && p.bottom) p.bottom.c = colour;
  if (category === 'outfit' && p.bottom && !p.bottom.c) p.bottom.c = colour;
  if (category === 'shoes' && p.shoes) p.shoes.c = colour;
  if (category === 'bag' || category === 'hat_hair') p.accent = colour;
  return p;
}

function mergePatch(a: OutfitPatch, b: OutfitPatch): OutfitPatch {
  const out: OutfitPatch = { ...a, ...b };
  if (b.top) out.top = { ...a.top, ...b.top };
  if (b.bottom) out.bottom = { ...a.bottom, ...b.bottom };
  if (b.shoes) out.shoes = { ...a.shoes, ...b.shoes };
  if (b.accessories) out.accessories = [...(a.accessories ?? []).filter((x) => !BAG_ACCESSORIES.includes(x)), ...b.accessories];
  return out;
}

export interface LookItem {
  category: WardrobeCategory;
  patch: OutfitPatch;
  colour: string | null;
}

/** The whole look's patch, merged in CATEGORY_ORDER. */
export function lookPatch(items: LookItem[]): OutfitPatch {
  let out: OutfitPatch = {};
  for (const cat of CATEGORY_ORDER) {
    for (const it of items) if (it.category === cat) out = mergePatch(out, itemPatch(it.category, it.patch, it.colour));
  }
  return out;
}

export function applyPatch(base: AvatarConfig, patch: OutfitPatch | null | undefined): AvatarConfig {
  if (!patch || !Object.keys(patch).length) return base;
  const next: Record<string, unknown> = { ...base, preset: null };
  if (patch.top) next.top = { ...base.top, ...patch.top };
  if (patch.bottom) next.bottom = { ...base.bottom, ...patch.bottom };
  if (patch.shoes) next.shoes = { ...base.shoes, ...patch.shoes };
  if (patch.hat !== undefined) next.hat = patch.hat;
  if (patch.accent) next.accent = patch.accent;
  if (patch.accessories) next.accessories = [...base.accessories.filter((a) => !BAG_ACCESSORIES.includes(a)), ...patch.accessories];
  return normalizeAvatar(next);
}

/** Out-of-the-house extras the Sim takes off at home or in bed. */
const OUTDOOR = new Set(['shades', 'bag', 'backpack', 'phone', 'lanyard', 'towel']);
const HOME_HATS = new Set(['head_tie', 'none']);

/** "Use the default": the sensible look for a slot, built from the everyday look. */
export function defaultLook(base: AvatarConfig, slot: OutfitSlot): AvatarConfig {
  const female = base.gender === 'female';
  switch (slot) {
    case 'sleep':
      return normalizeAvatar({
        ...base, preset: null,
        top: { s: 'tee', f: 'plain', c: female ? '#e25a95' : '#5aa7e0' },
        bottom: { s: 'joggers', f: 'plain', c: female ? '#e25a95' : '#5aa7e0' },
        shoes: { s: 'slippers', c: '#7d828c' },
        hat: female && base.hat === 'head_tie' ? 'head_tie' : 'none',
        accessories: base.accessories.filter((a) => !OUTDOOR.has(a) && a !== 'watch' && a !== 'chain'),
      });
    case 'home':
      return normalizeAvatar({
        ...base, preset: null,
        shoes: { s: 'slippers', c: base.shoes.s === 'slippers' ? base.shoes.c : '#25232b' },
        hat: HOME_HATS.has(base.hat) ? base.hat : 'none',
        accessories: base.accessories.filter((a) => !OUTDOOR.has(a)),
      });
    case 'gym':
      return normalizeAvatar({
        ...base, preset: null,
        top: { s: female ? 'tee' : 'singlet', f: 'plain', c: '#25232b' },
        bottom: { s: 'shorts', f: 'plain', c: '#25232b' },
        shoes: { s: 'sneakers', c: '#f4f1ea' },
        hat: 'none',
        accessories: base.accessories.filter((a) => a === 'watch'),
      });
    default:
      return base; // work, date, party: the everyday look until the player picks one
  }
}

/** The look for a slot: a saved look, the slot's default rule, or (unset) the everyday look. */
export function outfitFor(base: AvatarConfig, outfits: Outfits | null | undefined, slot: OutfitSlot): AvatarConfig {
  if (slot === 'everyday' || !outfits) return base;
  const saved = outfits[slot];
  if (!saved) return base;
  if (saved.patch === null) return defaultLook(base, slot);
  return applyPatch(base, saved.patch);
}

export interface OutfitContextInput {
  /** Id of the activity running now (null when idle or unknown). */
  activityId: string | null;
  busyLabel: string | null;
  busy: boolean;
  /** At the player's own home (not visiting). */
  atOwnHome: boolean;
  /** Scene of the place the Sim is inside (null on the road / at home). */
  placeScene: string | null;
  /** A party-kind event is live at the current place. */
  partyHere: boolean;
}

const SLEEP_ACTS = new Set(['sleep', 'nap']);
const GYM_RE = /gym|jog|workout|exercise|training|sports/i;

export function outfitContext(c: OutfitContextInput): OutfitSlot {
  if (c.busy) {
    if ((c.activityId && SLEEP_ACTS.has(c.activityId)) || (!c.activityId && /\b(sleep|nap)\b/i.test(c.busyLabel ?? ''))) return 'sleep';
    if (/^working\b/i.test(c.busyLabel ?? '')) return 'work';
    if (GYM_RE.test(c.activityId ?? '') || GYM_RE.test(c.busyLabel ?? '')) return 'gym';
  }
  if (c.atOwnHome) return 'home';
  if (c.placeScene === 'club' || c.partyHere) return 'party';
  return 'everyday';
}

export const PARTY_EVENT_KINDS = new Set(['owambe', 'party', 'club_night', 'concert']);
