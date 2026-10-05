// 3D avatar catalog: every option the creator shows, the outfit presets, defaults, random looks and the
// v1 -> v2 migration. This file must stay free of three.js: the main bundle (state, HUD, creator UI) imports it.
import type { AvatarConfig, AvatarConfigV2, AvatarGarment, BodyType, FabricId, Gender } from '../../lib/types';

export interface AvatarOption {
  id: string;
  label: string;
  /** Omit = both. */
  gender?: Gender;
  /** Hex for colour swatches. */
  swatch?: string;
}

export interface SkinTone {
  id: string;
  label: string;
  base: string;
  lip: string;
  /** Slightly darker shade for creases (ears, nostrils). */
  shade: string;
}

/** West African skin tones, light caramel to deep ebony (same ids as the 2D avatar). */
export const SKIN_TONES: SkinTone[] = [
  { id: 'tone1', label: 'Light caramel', base: '#d9a47a', lip: '#a65a4f', shade: '#b97f5c' },
  { id: 'tone2', label: 'Caramel', base: '#c68a5c', lip: '#91493e', shade: '#a66d47' },
  { id: 'tone3', label: 'Honey brown', base: '#a86b40', lip: '#7a3a32', shade: '#8a5232' },
  { id: 'tone4', label: 'Chocolate', base: '#8a5131', lip: '#62302a', shade: '#6f3e26' },
  { id: 'tone5', label: 'Cocoa', base: '#6f3d22', lip: '#4f2421', shade: '#58301d' },
  { id: 'tone6', label: 'Dark chocolate', base: '#5c341e', lip: '#45211e', shade: '#4a2a1a' },
  { id: 'tone7', label: 'Ebony', base: '#4c2a17', lip: '#3a1b19', shade: '#3c2214' },
  { id: 'tone8', label: 'Deep ebony', base: '#3d2113', lip: '#301614', shade: '#2f1a0f' },
];

const OUTFIT_COLOURS: AvatarOption[] = [
  { id: '#d2342a', label: 'Coral red', swatch: '#d2342a' },
  { id: '#e8692a', label: 'Orange', swatch: '#e8692a' },
  { id: '#e0a526', label: 'Mustard gold', swatch: '#e0a526' },
  { id: '#c9dd2f', label: 'Hi-vis lime', swatch: '#c9dd2f' },
  { id: '#1f8a55', label: 'Emerald', swatch: '#1f8a55' },
  { id: '#169c97', label: 'Teal', swatch: '#169c97' },
  { id: '#5aa7e0', label: 'Sky blue', swatch: '#5aa7e0' },
  { id: '#2346a8', label: 'Royal blue', swatch: '#2346a8' },
  { id: '#1c2847', label: 'Navy', swatch: '#1c2847' },
  { id: '#6d2f9c', label: 'Purple', swatch: '#6d2f9c' },
  { id: '#7a1f33', label: 'Wine', swatch: '#7a1f33' },
  { id: '#e25a95', label: 'Pink', swatch: '#e25a95' },
  { id: '#c8b28a', label: 'Khaki', swatch: '#c8b28a' },
  { id: '#7d828c', label: 'Grey', swatch: '#7d828c' },
  { id: '#f4f1ea', label: 'White', swatch: '#f4f1ea' },
  { id: '#25232b', label: 'Black', swatch: '#25232b' },
];

export const AVATAR_OPTIONS = {
  body: [
    { id: 'slim', label: 'Slim' },
    { id: 'average', label: 'Average' },
    { id: 'thick', label: 'Thick' },
  ],
  skin: SKIN_TONES.map((t) => ({ id: t.id, label: t.label, swatch: t.base })),
  face: [
    { id: 'oval', label: 'Oval' },
    { id: 'round', label: 'Round' },
    { id: 'square', label: 'Square jaw' },
    { id: 'long', label: 'Long' },
    { id: 'heart', label: 'Heart' },
    { id: 'diamond', label: 'Diamond' },
  ],
  eyes: [
    { id: 'almond', label: 'Almond' },
    { id: 'round', label: 'Round' },
    { id: 'hooded', label: 'Hooded' },
    { id: 'wide', label: 'Wide' },
  ],
  brows: [
    { id: 'soft', label: 'Soft' },
    { id: 'thick', label: 'Thick' },
    { id: 'arched', label: 'Arched' },
    { id: 'straight', label: 'Straight' },
    { id: 'thin', label: 'Thin' },
  ],
  nose: [
    { id: 'broad', label: 'Broad' },
    { id: 'button', label: 'Button' },
    { id: 'straight', label: 'Straight' },
    { id: 'round', label: 'Rounded' },
  ],
  lips: [
    { id: 'full', label: 'Full' },
    { id: 'medium', label: 'Medium' },
    { id: 'thin', label: 'Thin' },
  ],
  mouth: [
    { id: 'smile', label: 'Smile' },
    { id: 'neutral', label: 'Calm' },
    { id: 'grin', label: 'Big grin' },
    { id: 'smirk', label: 'Smirk' },
  ],
  facialHair: [
    { id: 'none', label: 'Clean shave' },
    { id: 'stubble', label: 'Stubble', gender: 'male' },
    { id: 'moustache', label: 'Moustache', gender: 'male' },
    { id: 'goatee', label: 'Goatee', gender: 'male' },
    { id: 'chinstrap', label: 'Chin strap', gender: 'male' },
    { id: 'beard', label: 'Full beard', gender: 'male' },
  ],
  hair: [
    { id: 'low_cut', label: 'Low cut' },
    { id: 'bald', label: 'Bald', gender: 'male' },
    { id: 'waves', label: '360 waves', gender: 'male' },
    { id: 'high_top', label: 'High-top', gender: 'male' },
    { id: 'afro', label: 'Afro' },
    { id: 'twa', label: 'Short afro', gender: 'female' },
    { id: 'twists', label: 'Twists' },
    { id: 'locs', label: 'Locs (dada)' },
    { id: 'cornrows', label: 'Cornrows' },
    { id: 'braids', label: 'Box braids', gender: 'female' },
    { id: 'bone_straight', label: 'Bone straight', gender: 'female' },
    { id: 'bun', label: 'Bun', gender: 'female' },
    { id: 'ponytail', label: 'Ponytail', gender: 'female' },
    { id: 'bantu_knots', label: 'Bantu knots', gender: 'female' },
  ],
  hairColor: [
    { id: '#15100d', label: 'Black', swatch: '#15100d' },
    { id: '#2e1d14', label: 'Dark brown', swatch: '#2e1d14' },
    { id: '#5a3420', label: 'Brown', swatch: '#5a3420' },
    { id: '#7a1f2c', label: 'Burgundy', swatch: '#7a1f2c' },
    { id: '#b47b3c', label: 'Honey blonde', swatch: '#b47b3c' },
    { id: '#d9c49b', label: 'Platinum', swatch: '#d9c49b' },
    { id: '#8d8a86', label: 'Grey', swatch: '#8d8a86' },
  ],
  hat: [
    { id: 'none', label: 'None' },
    { id: 'cap', label: 'Face cap' },
    { id: 'beanie', label: 'Beanie' },
    { id: 'bucket', label: 'Bucket hat' },
    { id: 'fila', label: 'Fila cap', gender: 'male' },
    { id: 'coral_cap', label: 'Coral bead cap', gender: 'male' },
    { id: 'gele', label: 'Gele', gender: 'female' },
    { id: 'head_tie', label: 'Head tie', gender: 'female' },
    { id: 'okuku', label: 'Okuku coral crown', gender: 'female' },
    { id: 'police_cap', label: 'Police cap' },
  ],
  top: [
    { id: 'tee', label: 'T-shirt' },
    { id: 'graphic_tee', label: 'Designer tee' },
    { id: 'polo', label: 'Polo shirt' },
    { id: 'short_shirt', label: 'Short-sleeve shirt' },
    { id: 'shirt', label: 'Long-sleeve shirt' },
    { id: 'shirt_tie', label: 'Shirt and tie' },
    { id: 'blazer', label: 'Suit jacket' },
    { id: 'hoodie', label: 'Hoodie' },
    { id: 'singlet', label: 'Singlet' },
    { id: 'buba', label: 'Buba top' },
    { id: 'kaftan', label: 'Senator kaftan', gender: 'male' },
    { id: 'agbada', label: 'Agbada', gender: 'male' },
    { id: 'gown', label: 'Gown', gender: 'female' },
    { id: 'maxi', label: 'Long gown', gender: 'female' },
    { id: 'boubou', label: 'Boubou kaftan', gender: 'female' },
    { id: 'chest_wrap', label: 'Chest wrapper', gender: 'female' },
    { id: 'scrubs', label: 'Scrubs top' },
    { id: 'police', label: 'Police shirt' },
    { id: 'vest', label: 'Hi-vis vest' },
    { id: 'bare', label: 'Bare chest', gender: 'male' },
  ],
  bottom: [
    { id: 'trousers', label: 'Trousers' },
    { id: 'jeans', label: 'Jeans' },
    { id: 'joggers', label: 'Joggers' },
    { id: 'shorts', label: 'Shorts' },
    { id: 'skirt', label: 'Pencil skirt', gender: 'female' },
    { id: 'long_skirt', label: 'Long skirt', gender: 'female' },
    { id: 'wrapper', label: 'Wrapper' },
    { id: 'scrubs', label: 'Scrub trousers' },
  ],
  shoes: [
    { id: 'sneakers', label: 'Sneakers' },
    { id: 'formal', label: 'Formal shoes' },
    { id: 'sandals', label: 'Sandals' },
    { id: 'slippers', label: 'Slippers' },
    { id: 'heels', label: 'Heels', gender: 'female' },
    { id: 'boots', label: 'Boots' },
  ],
  fabric: [
    { id: 'plain', label: 'Plain' },
    { id: 'ankara', label: 'Ankara' },
    { id: 'adire', label: 'Adire' },
    { id: 'asooke', label: 'Aso-oke' },
    { id: 'lace', label: 'Lace' },
  ],
  outfitColor: OUTFIT_COLOURS,
  accent: OUTFIT_COLOURS,
  accessories: [
    { id: 'shades', label: 'Shades' },
    { id: 'glasses', label: 'Glasses' },
    { id: 'watch', label: 'Wristwatch' },
    { id: 'chain', label: 'Gold chain' },
    { id: 'coral', label: 'Coral beads' },
    { id: 'bracelet', label: 'Bracelet' },
    { id: 'earrings', label: 'Earrings' },
    { id: 'phone', label: 'Phone in hand' },
    { id: 'bag', label: 'Handbag' },
    { id: 'backpack', label: 'Backpack' },
    { id: 'lanyard', label: 'ID lanyard' },
    { id: 'towel', label: 'Shoulder towel' },
  ],
} satisfies Record<string, AvatarOption[]>;

export type AvatarSlot = keyof typeof AVATAR_OPTIONS;

/** Tops that cover the legs (bottoms barely show). */
export const FULL_LENGTH_TOPS = new Set(['maxi', 'boubou', 'agbada']);
/** Headwear that hides the hairstyle completely. */
export const HAIR_HIDING_HATS = new Set(['gele', 'head_tie', 'okuku', 'beanie', 'fila', 'coral_cap', 'police_cap', 'bucket']);

export function optionsFor(slot: AvatarSlot, gender: Gender): AvatarOption[] {
  return (AVATAR_OPTIONS[slot] as AvatarOption[]).filter((o) => !o.gender || o.gender === gender);
}

export function optionLabel(slot: AvatarSlot, id: string): string {
  return (AVATAR_OPTIONS[slot] as AvatarOption[]).find((o) => o.id === id)?.label ?? id;
}

export function skinTone(id: string): SkinTone {
  return SKIN_TONES.find((s) => s.id === id) ?? SKIN_TONES[3];
}

// ---------------------------------------------------------------------------------------------
// Outfit presets: each applies a whole look; every slot stays editable afterwards.
// ---------------------------------------------------------------------------------------------

export type PresetPatch = Pick<AvatarConfig, 'top' | 'bottom' | 'shoes' | 'hat' | 'accent' | 'accessories'>;

export interface OutfitPreset {
  id: string;
  label: string;
  emoji: string;
  /** Omit = both, with a gendered look from `build`. */
  gender?: Gender;
  build: (g: Gender) => PresetPatch;
}

const W = '#f4f1ea';
const BLACK = '#25232b';
const g = (s: string, c: string, f: FabricId = 'plain'): AvatarGarment => ({ s, f, c });

export const OUTFIT_PRESETS: OutfitPreset[] = [
  {
    id: 'bini', label: 'Bini Traditional Wear', emoji: '👑',
    build: (x) => x === 'male'
      ? { top: g('bare', W), bottom: g('wrapper', W, 'lace'), shoes: { s: 'sandals', c: '#7a4a2a' }, hat: 'coral_cap', accent: '#d2342a', accessories: ['coral', 'bracelet'] }
      : { top: g('chest_wrap', '#d2342a', 'lace'), bottom: g('wrapper', '#d2342a', 'lace'), shoes: { s: 'sandals', c: '#e0a526' }, hat: 'okuku', accent: '#d2342a', accessories: ['coral', 'bracelet', 'earrings'] },
  },
  {
    id: 'agbada', label: 'Agbada', emoji: '🕴🏾', gender: 'male',
    build: () => ({ top: g('agbada', '#5aa7e0', 'lace'), bottom: g('trousers', '#5aa7e0'), shoes: { s: 'formal', c: '#5a3420' }, hat: 'fila', accent: '#1c2847', accessories: ['watch'] }),
  },
  {
    id: 'senator', label: 'Senator', emoji: '🧔🏾‍♂️', gender: 'male',
    build: () => ({ top: g('kaftan', '#1f8a55'), bottom: g('trousers', '#1f8a55'), shoes: { s: 'formal', c: BLACK }, hat: 'none', accent: '#e0a526', accessories: ['watch'] }),
  },
  {
    id: 'owambe', label: 'Owambe (Aso-oke)', emoji: '🎉',
    build: (x) => x === 'male'
      ? { top: g('agbada', '#7a1f33', 'asooke'), bottom: g('trousers', '#7a1f33'), shoes: { s: 'formal', c: BLACK }, hat: 'fila', accent: '#7a1f33', accessories: ['watch', 'chain'] }
      : { top: g('buba', '#7a1f33', 'asooke'), bottom: g('wrapper', '#7a1f33', 'asooke'), shoes: { s: 'heels', c: '#e0a526' }, hat: 'gele', accent: '#e0a526', accessories: ['earrings', 'bracelet', 'bag'] },
  },
  {
    id: 'boubou', label: 'Boubou Kaftan', emoji: '🌺', gender: 'female',
    build: () => ({ top: g('boubou', '#169c97', 'adire'), bottom: g('wrapper', '#169c97'), shoes: { s: 'sandals', c: '#e0a526' }, hat: 'head_tie', accent: '#169c97', accessories: ['earrings', 'bracelet'] }),
  },
  {
    id: 'yahoo', label: 'Yahoo Boy', emoji: '💸', gender: 'male',
    build: () => ({ top: g('graphic_tee', BLACK), bottom: g('jeans', BLACK), shoes: { s: 'sneakers', c: W }, hat: 'cap', accent: '#e0a526', accessories: ['shades', 'watch', 'chain', 'bracelet', 'phone'] }),
  },
  {
    id: 'glam', label: 'Big Girl Glam', emoji: '💅🏾', gender: 'female',
    build: () => ({ top: g('gown', BLACK), bottom: g('skirt', BLACK), shoes: { s: 'heels', c: '#e0a526' }, hat: 'none', accent: '#e0a526', accessories: ['shades', 'watch', 'chain', 'earrings', 'bag', 'phone'] }),
  },
  {
    id: 'corporate', label: 'Corporate', emoji: '💼',
    build: (x) => x === 'male'
      ? { top: g('blazer', '#1c2847'), bottom: g('trousers', '#1c2847'), shoes: { s: 'formal', c: BLACK }, hat: 'none', accent: '#7a1f33', accessories: ['watch'] }
      : { top: g('blazer', '#25232b'), bottom: g('skirt', '#25232b'), shoes: { s: 'heels', c: BLACK }, hat: 'none', accent: W, accessories: ['watch', 'earrings', 'bag'] },
  },
  {
    id: 'student', label: 'UNIBEN Student', emoji: '🎓',
    build: (x) => x === 'male'
      ? { top: g('polo', '#2346a8'), bottom: g('jeans', '#2f4f86'), shoes: { s: 'sneakers', c: W }, hat: 'none', accent: '#e0a526', accessories: ['backpack', 'lanyard', 'glasses'] }
      : { top: g('tee', '#e8692a'), bottom: g('jeans', '#2f4f86'), shoes: { s: 'sneakers', c: W }, hat: 'none', accent: '#2346a8', accessories: ['backpack', 'lanyard', 'earrings'] },
  },
  {
    id: 'market', label: 'Market Woman', emoji: '🧺', gender: 'female',
    build: () => ({ top: g('buba', '#e0a526', 'ankara'), bottom: g('wrapper', '#2346a8', 'ankara'), shoes: { s: 'slippers', c: '#7a4a2a' }, hat: 'head_tie', accent: '#d2342a', accessories: ['earrings', 'bag'] }),
  },
  {
    id: 'keke', label: 'Keke Rider', emoji: '🛺',
    build: () => ({ top: g('vest', '#c9dd2f'), bottom: g('trousers', '#3b3f47'), shoes: { s: 'slippers', c: BLACK }, hat: 'cap', accent: '#1f8a55', accessories: ['towel'] }),
  },
  {
    id: 'nurse', label: 'Nurse', emoji: '🩺',
    build: () => ({ top: g('scrubs', '#5aa7e0'), bottom: g('scrubs', '#5aa7e0'), shoes: { s: 'sneakers', c: W }, hat: 'none', accent: W, accessories: ['watch', 'lanyard'] }),
  },
  {
    id: 'police', label: 'Police', emoji: '👮🏾',
    build: () => ({ top: g('police', '#1b1d24'), bottom: g('trousers', '#1b1d24'), shoes: { s: 'boots', c: '#15100d' }, hat: 'police_cap', accent: '#1b1d24', accessories: ['watch'] }),
  },
  {
    id: 'street', label: 'Streetwear', emoji: '🧢',
    build: (x) => x === 'male'
      ? { top: g('hoodie', '#7d828c'), bottom: g('joggers', BLACK), shoes: { s: 'sneakers', c: W }, hat: 'beanie', accent: BLACK, accessories: ['chain'] }
      : { top: g('hoodie', '#c8b28a'), bottom: g('joggers', BLACK), shoes: { s: 'sneakers', c: W }, hat: 'bucket', accent: BLACK, accessories: ['earrings', 'chain'] },
  },
  {
    id: 'ankara', label: 'Casual Ankara', emoji: '🌀',
    build: (x) => x === 'male'
      ? { top: g('short_shirt', '#e8692a', 'ankara'), bottom: g('trousers', BLACK), shoes: { s: 'sandals', c: '#7a4a2a' }, hat: 'none', accent: '#e0a526', accessories: ['watch'] }
      : { top: g('gown', '#169c97', 'ankara'), bottom: g('skirt', '#169c97'), shoes: { s: 'sandals', c: '#e0a526' }, hat: 'none', accent: '#e0a526', accessories: ['earrings', 'bag'] },
  },
];

export function presetsFor(gender: Gender): OutfitPreset[] {
  return OUTFIT_PRESETS.filter((p) => !p.gender || p.gender === gender);
}

/** Applies a preset's whole outfit; face, body and hair are kept. Gender-locked items are dropped. */
export function applyPreset(cfg: AvatarConfig, presetId: string): AvatarConfig {
  const p = OUTFIT_PRESETS.find((x) => x.id === presetId);
  if (!p) return cfg;
  const patch = p.build(cfg.gender);
  return normalizeAvatar({ ...cfg, ...patch, top: { ...patch.top }, bottom: { ...patch.bottom }, shoes: { ...patch.shoes }, accessories: [...patch.accessories], preset: p.id });
}

// ---------------------------------------------------------------------------------------------
// Defaults, random looks, validation
// ---------------------------------------------------------------------------------------------

export function defaultAvatar(gender: Gender): AvatarConfig {
  const female = gender === 'female';
  const base: AvatarConfigV2 = {
    v: 2,
    gender,
    body: 'average',
    skin: 'tone4',
    face: 'oval',
    eyes: 'almond',
    brows: female ? 'arched' : 'soft',
    nose: 'broad',
    lips: female ? 'full' : 'medium',
    mouth: 'smile',
    facialHair: 'none',
    hair: female ? 'braids' : 'low_cut',
    hairColor: '#15100d',
    hat: 'none',
    top: g('tee', '#e0a526'),
    bottom: g('jeans', '#2f4f86'),
    shoes: { s: 'sneakers', c: W },
    accent: '#d2342a',
    accessories: [],
    preset: null,
  };
  return applyPreset(base, 'ankara');
}

function rnd<T>(a: readonly T[]): T {
  return a[Math.floor(Math.random() * a.length)];
}

export function randomAvatar(gender: Gender): AvatarConfig {
  const pick = (slot: AvatarSlot) => rnd(optionsFor(slot, gender)).id;
  let cfg: AvatarConfig = {
    ...defaultAvatar(gender),
    body: pick('body') as BodyType,
    skin: pick('skin'),
    face: pick('face'),
    eyes: pick('eyes'),
    brows: pick('brows'),
    nose: pick('nose'),
    lips: pick('lips'),
    mouth: Math.random() < 0.7 ? 'smile' : pick('mouth'),
    facialHair: gender === 'male' && Math.random() < 0.55 ? pick('facialHair') : 'none',
    hair: pick('hair'),
    hairColor: Math.random() < 0.65 ? '#15100d' : pick('hairColor'),
  };
  cfg = applyPreset(cfg, rnd(presetsFor(gender)).id);
  // Half the time, shuffle the colours too so two random Sims in the same preset still differ.
  if (Math.random() < 0.5) {
    const c = pick('outfitColor');
    cfg = { ...cfg, top: { ...cfg.top, c }, bottom: cfg.bottom.c === cfg.top.c ? { ...cfg.bottom, c } : cfg.bottom };
  }
  return cfg;
}

const HEX = /^#[0-9a-f]{6}$/i;
const isHex = (x: unknown): x is string => typeof x === 'string' && HEX.test(x);
const FABRICS = new Set<string>(AVATAR_OPTIONS.fabric.map((f) => f.id));

function validId(slot: AvatarSlot, id: unknown, gender: Gender): id is string {
  return typeof id === 'string' && optionsFor(slot, gender).some((o) => o.id === id);
}

/** Fills missing or invalid fields of a v2 look. Never throws. */
export function normalizeAvatar(raw: unknown): AvatarConfig {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const gender: Gender = r.gender === 'female' ? 'female' : 'male';
  const female = gender === 'female';
  const pickId = (slot: AvatarSlot, v: unknown, d: string) => (validId(slot, v, gender) ? v : d);
  const garment = (slot: 'top' | 'bottom', v: unknown, d: AvatarGarment): AvatarGarment => {
    const o = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
    return {
      s: pickId(slot, o.s, d.s),
      f: (typeof o.f === 'string' && FABRICS.has(o.f) ? o.f : d.f) as FabricId,
      c: isHex(o.c) ? o.c.toLowerCase() : d.c,
    };
  };
  const shoesRaw = (r.shoes && typeof r.shoes === 'object' ? r.shoes : {}) as Record<string, unknown>;
  const accIds = new Set(optionsFor('accessories', gender).map((o) => o.id));
  const accessories = Array.isArray(r.accessories)
    ? [...new Set(r.accessories.filter((a): a is string => typeof a === 'string' && accIds.has(a)))].slice(0, 8)
    : [];
  const fallbackTop = female ? g('gown', '#169c97', 'ankara') : g('short_shirt', '#e8692a', 'ankara');
  const fallbackBottom = female ? g('skirt', '#169c97') : g('trousers', BLACK);
  return {
    v: 2,
    gender,
    body: pickId('body', r.body, 'average') as BodyType,
    skin: pickId('skin', r.skin, 'tone4'),
    face: pickId('face', r.face, 'oval'),
    eyes: pickId('eyes', r.eyes, 'almond'),
    brows: pickId('brows', r.brows, female ? 'arched' : 'soft'),
    nose: pickId('nose', r.nose, 'broad'),
    lips: pickId('lips', r.lips, female ? 'full' : 'medium'),
    mouth: pickId('mouth', r.mouth, 'smile'),
    facialHair: female ? 'none' : pickId('facialHair', r.facialHair, 'none'),
    hair: pickId('hair', r.hair, female ? 'braids' : 'low_cut'),
    hairColor: isHex(r.hairColor) ? r.hairColor.toLowerCase() : '#15100d',
    hat: pickId('hat', r.hat, 'none'),
    top: garment('top', r.top, fallbackTop),
    bottom: garment('bottom', r.bottom, fallbackBottom),
    shoes: { s: pickId('shoes', shoesRaw.s, 'sandals'), c: isHex(shoesRaw.c) ? shoesRaw.c.toLowerCase() : '#7a4a2a' },
    accent: isHex(r.accent) ? r.accent.toLowerCase() : '#e0a526',
    accessories,
    preset: typeof r.preset === 'string' && OUTFIT_PRESETS.some((p) => p.id === r.preset) ? r.preset : null,
  };
}

// ---------------------------------------------------------------------------------------------
// v1 (2D SVG avatar) -> v2
// ---------------------------------------------------------------------------------------------

const V1_HAIR: Record<string, { hair: string; hat?: string }> = {
  low_cut: { hair: 'low_cut' },
  skin_botcho: { hair: 'bald' },
  waves_360: { hair: 'waves' },
  dada: { hair: 'locs' },
  small_afro: { hair: 'afro' },
  high_top: { hair: 'high_top' },
  twists: { hair: 'twists' },
  braids: { hair: 'braids' },
  cornrows: { hair: 'cornrows' },
  short_afro: { hair: 'twa' },
  bone_straight: { hair: 'bone_straight' },
  bantu_knots: { hair: 'bantu_knots' },
  gele: { hair: 'cornrows', hat: 'gele' },
  packing_gel: { hair: 'bun' },
};

const V1_OUTFIT: Record<string, string> = {
  bini_traditional: 'bini',
  agbada: 'agbada',
  senator: 'senator',
  ankara: 'ankara',
  student: 'student',
  keke_rider: 'keke',
  market_woman: 'market',
  corporate: 'corporate',
  yahoo_drip: 'yahoo',
  nurse: 'nurse',
  police: 'police',
  hoodie: 'street',
};

const V1_ACC: Record<string, string> = {
  coral_beads: 'coral',
  gold_chain: 'chain',
  sunglasses: 'shades',
  wristwatch: 'watch',
  earrings: 'earrings',
  phone_in_hand: 'phone',
  bag: 'bag',
};

const V1_EYES: Record<string, string> = { round: 'round', almond: 'almond', sleepy: 'hooded', sharp: 'almond' };
const V1_MOUTH: Record<string, string> = { smile: 'smile', grin: 'grin', neutral: 'neutral', smirk: 'smirk', laughing: 'grin' };
const V1_BEARD: Record<string, string> = { none: 'none', beard: 'beard', goatee: 'goatee', moustache: 'moustache', shadow: 'stubble' };
const PINK = '#e25a95';

/**
 * Accepts anything read from the database (v1 2D look, v2 3D look, `{}` or junk) and returns a valid v2 look.
 * Never throws. v1 looks keep their skin, body, hair, colours and accessories; the old outfit becomes the
 * matching preset (pink drip becomes the black Yahoo look).
 */
export function migrateAvatar(raw: unknown): AvatarConfig {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  if (r.v === 2) return normalizeAvatar(r);
  const gender: Gender = r.gender === 'female' ? 'female' : 'male';
  const hasV1 = typeof r.outfit === 'string' || typeof r.eyes === 'string' || typeof r.hair === 'string';
  if (!hasV1) return defaultAvatar(gender);

  let cfg = defaultAvatar(gender);
  const hair = V1_HAIR[String(r.hair)];
  cfg = {
    ...cfg,
    body: (['slim', 'average', 'thick'].includes(String(r.body)) ? r.body : 'average') as BodyType,
    skin: typeof r.skin === 'string' ? r.skin : cfg.skin,
    hair: hair?.hair ?? cfg.hair,
    hairColor: isHex(r.hairColor) ? r.hairColor : cfg.hairColor,
    eyes: V1_EYES[String(r.eyes)] ?? cfg.eyes,
    brows: typeof r.brows === 'string' ? r.brows : cfg.brows,
    mouth: V1_MOUTH[String(r.mouth)] ?? cfg.mouth,
    facialHair: V1_BEARD[String(r.facialHair)] ?? 'none',
  };
  const presetId = V1_OUTFIT[String(r.outfit)];
  // A female v1 'agbada' or male 'market_woman' has no direct match: use the closest preset for that gender.
  const preset = OUTFIT_PRESETS.find((p) => p.id === presetId && (!p.gender || p.gender === gender));
  if (preset) cfg = applyPreset(cfg, preset.id);
  else if (presetId === 'agbada') cfg = applyPreset(cfg, 'boubou');
  else if (presetId === 'market') cfg = applyPreset(cfg, 'ankara');

  // Keep the player's chosen cloth colour (but no pink on the Yahoo look).
  if (isHex(r.outfitColor) && !(cfg.preset === 'yahoo' && r.outfitColor.toLowerCase() === PINK)) {
    const c = r.outfitColor.toLowerCase();
    const sameBottom = cfg.bottom.c === cfg.top.c;
    cfg = { ...cfg, top: { ...cfg.top, c }, bottom: sameBottom ? { ...cfg.bottom, c } : cfg.bottom };
  }
  // Old accessories on top of the preset's.
  if (Array.isArray(r.accessories)) {
    const acc = new Set(cfg.accessories);
    let hat = cfg.hat;
    for (const a of r.accessories) {
      if (a === 'cap') hat = 'cap';
      else if (typeof a === 'string' && V1_ACC[a]) acc.add(V1_ACC[a]);
    }
    cfg = { ...cfg, hat, accessories: [...acc] };
  }
  if (hair?.hat) cfg = { ...cfg, hat: hair.hat };
  return normalizeAvatar(cfg);
}

// ---------------------------------------------------------------------------------------------
// Stable hash (cache key for rendered portraits)
// ---------------------------------------------------------------------------------------------

/** Bumped whenever the 3D model changes so cached portraits re-render. */
export const MODEL_VERSION = 3;

function stable(x: unknown): string {
  if (Array.isArray(x)) return '[' + x.map(stable).join(',') + ']';
  if (x && typeof x === 'object') {
    const o = x as Record<string, unknown>;
    return '{' + Object.keys(o).sort().filter((k) => k !== 'preset').map((k) => k + ':' + stable(o[k])).join(',') + '}';
  }
  return String(x);
}

/** Short stable key for a look (the preset label is ignored: same clothes, same picture). */
export function avatarKey(cfg: AvatarConfig): string {
  const s = stable(cfg);
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 16777619);
    h2 = Math.imul(h2 ^ c, 2246822519);
  }
  return 'm' + MODEL_VERSION + (h1 >>> 0).toString(36) + (h2 >>> 0).toString(36);
}
