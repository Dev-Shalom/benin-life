// PHASE 0 STUB — P1-AVATAR replaces this file. Keep these export names/signatures.
import type { AvatarConfig, Gender } from '../../lib/types';

export interface AvatarOption {
  id: string;
  label: string; // Pidgin-friendly label
  gender?: Gender; // omit = both
  swatch?: string; // hex for colour pickers
}

export const AVATAR_OPTIONS: Record<
  'skin' | 'body' | 'hair' | 'hairColor' | 'eyes' | 'brows' | 'mouth' | 'facialHair' | 'outfit' | 'outfitColor' | 'accessories',
  AvatarOption[]
> = {
  skin: [{ id: 'tone4', label: 'Chocolate', swatch: '#7a4a2a' }],
  body: [{ id: 'average', label: 'Normal' }],
  hair: [{ id: 'low_cut', label: 'Low cut' }],
  hairColor: [{ id: '#1b1410', label: 'Black', swatch: '#1b1410' }],
  eyes: [{ id: 'round', label: 'Round' }],
  brows: [{ id: 'soft', label: 'Soft' }],
  mouth: [{ id: 'smile', label: 'Smile' }],
  facialHair: [{ id: 'none', label: 'None' }],
  outfit: [{ id: 'ankara', label: 'Ankara' }],
  outfitColor: [{ id: '#d2342a', label: 'Coral red', swatch: '#d2342a' }],
  accessories: [{ id: 'coral_beads', label: 'Coral beads' }],
};

export function defaultAvatar(gender: Gender): AvatarConfig {
  return {
    gender, skin: 'tone4', body: 'average', hair: 'low_cut', hairColor: '#1b1410', eyes: 'round', brows: 'soft',
    mouth: 'smile', facialHair: 'none', outfit: 'ankara', outfitColor: '#d2342a', accessories: [],
  };
}

export function randomAvatar(gender: Gender): AvatarConfig {
  return defaultAvatar(gender);
}

export function normalizeAvatar(raw: unknown): AvatarConfig {
  const base = defaultAvatar('male');
  if (!raw || typeof raw !== 'object') return base;
  return { ...base, ...(raw as Partial<AvatarConfig>) };
}
