// Avatar option catalog — Pidgin-friendly labels, gender-filtered where needed.
import type { AvatarConfig, Gender } from '../../lib/types';
import { isHex } from './color';

export interface AvatarOption {
  id: string;
  label: string; // Pidgin-friendly label
  gender?: Gender; // omit = both
  swatch?: string; // hex for colour pickers
}

export interface SkinTone {
  id: string;
  base: string;
  shadow: string;
  highlight: string;
  deep: string;
  lip: string;
  blush: string;
}

/** West-African-realistic skin tones, light caramel → deep ebony. */
export const SKIN_TONES: SkinTone[] = [
  { id: 'tone1', base: '#d9a47a', shadow: '#a86f55', highlight: '#f3cba3', deep: '#7f4d45', lip: '#a85a55', blush: '#e0786a' },
  { id: 'tone2', base: '#c68a5c', shadow: '#94603f', highlight: '#e6b386', deep: '#6c3f36', lip: '#94493f', blush: '#d66a52' },
  { id: 'tone3', base: '#a86b40', shadow: '#7a4632', highlight: '#d0955f', deep: '#55302d', lip: '#7c3a33', blush: '#c55a3e' },
  { id: 'tone4', base: '#8a5131', shadow: '#5f3328', highlight: '#b77a4e', deep: '#432126', lip: '#653029', blush: '#b24a35' },
  { id: 'tone5', base: '#6f3d22', shadow: '#4a2420', highlight: '#9a6340', deep: '#33181f', lip: '#552521', blush: '#9c3f2c' },
  { id: 'tone6', base: '#58301a', shadow: '#3a1c1b', highlight: '#875434', deep: '#26121a', lip: '#47201d', blush: '#873825' },
  { id: 'tone7', base: '#43230f', shadow: '#2c1418', highlight: '#73472c', deep: '#1d0d17', lip: '#3a1a18', blush: '#743020' },
  { id: 'tone8', base: '#321809', shadow: '#210e14', highlight: '#5f3a25', deep: '#170a14', lip: '#2e1414', blush: '#5f2618' },
];

export const AVATAR_OPTIONS: Record<
  'skin' | 'body' | 'hair' | 'hairColor' | 'eyes' | 'brows' | 'mouth' | 'facialHair' | 'outfit' | 'outfitColor' | 'accessories',
  AvatarOption[]
> = {
  skin: [
    { id: 'tone1', label: 'Yellow pawpaw', swatch: '#d9a47a' },
    { id: 'tone2', label: 'Caramel', swatch: '#c68a5c' },
    { id: 'tone3', label: 'Honey brown', swatch: '#a86b40' },
    { id: 'tone4', label: 'Chocolate', swatch: '#8a5131' },
    { id: 'tone5', label: 'Cocoa', swatch: '#6f3d22' },
    { id: 'tone6', label: 'Dark chocolate', swatch: '#58301a' },
    { id: 'tone7', label: 'Ebony', swatch: '#43230f' },
    { id: 'tone8', label: 'Black beauty', swatch: '#321809' },
  ],
  body: [
    { id: 'slim', label: 'Lepa (slim)' },
    { id: 'average', label: 'Normal' },
    { id: 'thick', label: 'Orobo (thick)' },
  ],
  hair: [
    { id: 'low_cut', label: 'Low cut', gender: 'male' },
    { id: 'skin_botcho', label: 'Skin botcho', gender: 'male' },
    { id: 'waves_360', label: '360 waves', gender: 'male' },
    { id: 'dada', label: 'Dada (locs)', gender: 'male' },
    { id: 'small_afro', label: 'Small afro', gender: 'male' },
    { id: 'high_top', label: 'High-top', gender: 'male' },
    { id: 'twists', label: 'Twists', gender: 'male' },
    { id: 'braids', label: 'Box braids', gender: 'female' },
    { id: 'cornrows', label: 'Shuku / cornrow', gender: 'female' },
    { id: 'short_afro', label: 'Low afro (TWA)', gender: 'female' },
    { id: 'bone_straight', label: 'Bone straight', gender: 'female' },
    { id: 'bantu_knots', label: 'Bantu knots', gender: 'female' },
    { id: 'gele', label: 'Gele', gender: 'female' },
    { id: 'packing_gel', label: 'Packing gel', gender: 'female' },
  ],
  hairColor: [
    { id: '#1b1410', label: 'Black', swatch: '#1b1410' },
    { id: '#3b2417', label: 'Dark brown', swatch: '#3b2417' },
    { id: '#6a1a2c', label: 'Burgundy', swatch: '#6a1a2c' },
    { id: '#b47b3c', label: 'Honey blonde', swatch: '#b47b3c' },
    { id: '#8a8580', label: 'Ash', swatch: '#8a8580' },
  ],
  eyes: [
    { id: 'round', label: 'Round eye' },
    { id: 'almond', label: 'Almond' },
    { id: 'sleepy', label: 'Sleepy (kolo)' },
    { id: 'sharp', label: 'Sharp eye' },
  ],
  brows: [
    { id: 'soft', label: 'Soft' },
    { id: 'thick', label: 'Thick' },
    { id: 'arched', label: 'Arched' },
    { id: 'straight', label: 'Straight' },
  ],
  mouth: [
    { id: 'smile', label: 'Smile' },
    { id: 'grin', label: 'Big grin' },
    { id: 'neutral', label: 'Calm face' },
    { id: 'smirk', label: 'Shakara smirk' },
    { id: 'laughing', label: 'Dey laugh' },
  ],
  facialHair: [
    { id: 'none', label: 'Clean' },
    { id: 'beard', label: 'Full beard', gender: 'male' },
    { id: 'goatee', label: 'Goatee', gender: 'male' },
    { id: 'moustache', label: 'Mustache', gender: 'male' },
    { id: 'shadow', label: 'Small jaga-jaga (stubble)', gender: 'male' },
  ],
  outfit: [
    { id: 'bini_traditional', label: 'Bini traditional' },
    { id: 'agbada', label: 'Agbada / Boubou' },
    { id: 'senator', label: 'Senator' },
    { id: 'ankara', label: 'Ankara' },
    { id: 'student', label: 'UNIBEN student' },
    { id: 'keke_rider', label: 'Keke rider' },
    { id: 'market_woman', label: 'Market woman', gender: 'female' },
    { id: 'corporate', label: 'Corporate' },
    { id: 'yahoo_drip', label: 'Drip (B-City)' },
    { id: 'nurse', label: 'Nurse scrubs' },
    { id: 'police', label: 'Police' },
    { id: 'hoodie', label: 'Streetwear hoodie' },
  ],
  outfitColor: [
    { id: '#d2342a', label: 'Coral red', swatch: '#d2342a' },
    { id: '#2346a8', label: 'Royal blue', swatch: '#2346a8' },
    { id: '#1f8a55', label: 'Emerald', swatch: '#1f8a55' },
    { id: '#d9a128', label: 'Mustard gold', swatch: '#d9a128' },
    { id: '#6d2f9c', label: 'Purple', swatch: '#6d2f9c' },
    { id: '#f4f1ea', label: 'White', swatch: '#f4f1ea' },
    { id: '#24222b', label: 'Black', swatch: '#24222b' },
    { id: '#e25a95', label: 'Pink', swatch: '#e25a95' },
  ],
  accessories: [
    { id: 'coral_beads', label: 'Coral beads' },
    { id: 'gold_chain', label: 'Gold chain' },
    { id: 'sunglasses', label: 'Shades' },
    { id: 'cap', label: 'Face cap' },
    { id: 'wristwatch', label: 'Wristwatch' },
    { id: 'earrings', label: 'Earrings', gender: 'female' },
    { id: 'phone_in_hand', label: 'Phone for hand' },
    { id: 'bag', label: 'Bag' },
  ],
};

type Slot = keyof typeof AVATAR_OPTIONS;

export function optionsFor(slot: Slot, gender: Gender): AvatarOption[] {
  return AVATAR_OPTIONS[slot].filter((o) => !o.gender || o.gender === gender);
}

function valid(slot: Slot, id: unknown, gender: Gender): id is string {
  return typeof id === 'string' && optionsFor(slot, gender).some((o) => o.id === id);
}

export function skinTone(id: string): SkinTone {
  return SKIN_TONES.find((s) => s.id === id) ?? SKIN_TONES[3];
}

export function defaultAvatar(gender: Gender): AvatarConfig {
  const female = gender === 'female';
  return {
    gender,
    skin: 'tone4',
    body: 'average',
    hair: female ? 'braids' : 'low_cut',
    hairColor: '#1b1410',
    eyes: female ? 'almond' : 'round',
    brows: female ? 'arched' : 'soft',
    mouth: 'smile',
    facialHair: 'none',
    outfit: 'ankara',
    outfitColor: '#d2342a',
    accessories: [],
  };
}

function rnd<T>(a: T[]): T {
  return a[Math.floor(Math.random() * a.length)];
}

export function randomAvatar(gender: Gender): AvatarConfig {
  const id = (slot: Slot) => rnd(optionsFor(slot, gender)).id;
  const pool = optionsFor('accessories', gender).map((o) => o.id);
  const accessories: string[] = [];
  const n = Math.floor(Math.random() * 3); // 0–2 accessories
  while (accessories.length < n) {
    const a = rnd(pool);
    if (!accessories.includes(a)) accessories.push(a);
  }
  const facial = gender === 'male' && Math.random() < 0.55 ? id('facialHair') : 'none';
  return {
    gender,
    skin: id('skin'),
    body: id('body') as AvatarConfig['body'],
    hair: id('hair'),
    hairColor: Math.random() < 0.6 ? '#1b1410' : id('hairColor'),
    eyes: id('eyes'),
    brows: id('brows'),
    mouth: id('mouth'),
    facialHair: facial,
    outfit: id('outfit'),
    outfitColor: id('outfitColor'),
    accessories,
  };
}

/** Fill missing / invalid fields safely (used on data from the DB). Never throws. */
export function normalizeAvatar(raw: unknown): AvatarConfig {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const gender: Gender = r.gender === 'female' ? 'female' : 'male';
  const d = defaultAvatar(gender);
  const pickSlot = (slot: Slot, key: keyof AvatarConfig) =>
    (valid(slot, r[key], gender) ? r[key] : d[key]) as string;
  const accIds = optionsFor('accessories', gender).map((o) => o.id);
  const accessories = Array.isArray(r.accessories)
    ? [...new Set(r.accessories.filter((a): a is string => typeof a === 'string' && accIds.includes(a)))]
    : [];
  return {
    gender,
    skin: pickSlot('skin', 'skin'),
    body: pickSlot('body', 'body') as AvatarConfig['body'],
    hair: pickSlot('hair', 'hair'),
    hairColor: isHex(r.hairColor) ? r.hairColor : d.hairColor,
    eyes: pickSlot('eyes', 'eyes'),
    brows: pickSlot('brows', 'brows'),
    mouth: pickSlot('mouth', 'mouth'),
    facialHair: gender === 'male' ? pickSlot('facialHair', 'facialHair') : 'none',
    outfit: pickSlot('outfit', 'outfit'),
    outfitColor: isHex(r.outfitColor) ? r.outfitColor : d.outfitColor,
    accessories,
  };
}
