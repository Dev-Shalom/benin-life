// W1 wardrobe store: the boutique catalog, what the player owns and the 7 saved outfit slots.
// Loaded once per game session (Game.tsx) so the 3D home / places can switch outfits by context.
import { useMemo } from 'react';
import { create } from 'zustand';
import { rpc } from '../lib/api';
import { outfitContext, outfitFor, PARTY_EVENT_KINDS, type OutfitPatch, type Outfits, type OutfitSlot, type WardrobeCategory } from '../lib/outfit';
import type { AvatarConfig, GameState } from '../lib/types';
import { useCatalog } from './catalog';
import { isLive, useEvents } from './events';

export interface WardrobeBrand {
  id: string;
  name: string;
  tagline: string;
  colour: string;
  is_house: boolean;
  sponsor: boolean;
}

export interface WardrobeItem {
  id: string;
  name: string;
  brand_id: string | null;
  category: WardrobeCategory;
  gender: 'male' | 'female' | null;
  patch: OutfitPatch;
  colours: string[];
  price: number;
  tag: 'basic' | 'designer' | 'owambe';
  default_slots: string[];
  icon: string;
  description: string;
  owned: boolean;
  owned_colour: string | null;
}

export interface WardrobeState {
  enabled: boolean;
  brands_enabled: boolean;
  cash: number;
  bank: number;
  gender: string;
  brands: WardrobeBrand[];
  items: WardrobeItem[];
  outfits: Outfits;
}

interface Store {
  data: WardrobeState | null;
  uid: string | null;
  loading: boolean;
  load: (uid: string, force?: boolean) => Promise<WardrobeState | null>;
  set: (data: WardrobeState) => void;
}

export const useWardrobe = create<Store>((set, get) => ({
  data: null,
  uid: null,
  loading: false,
  load: async (uid, force = false) => {
    const s = get();
    if (!force && s.uid === uid && (s.data || s.loading)) return s.data;
    set({ loading: true, uid, ...(s.uid !== uid ? { data: null } : {}) });
    try {
      const data = await rpc<WardrobeState>('wardrobe_state');
      if (get().uid === uid) set({ data, loading: false });
      return data;
    } catch {
      set({ loading: false });
      return null;
    }
  },
  set: (data) => set({ data }),
}));

export const wardrobeBuy = (item: string, colour: string | null) =>
  rpc<{ message: string; paid: number }>('wardrobe_buy', { p_item: item, p_colour: colour });
export const wardrobeSetOutfit = (slot: OutfitSlot, items: { item: string; colour: string | null }[] | null) =>
  rpc<{ message: string }>('wardrobe_set_outfit', { p_slot: slot, p_items: items });
export const wardrobeClearSlot = (slot: OutfitSlot) => rpc<{ message: string }>('wardrobe_clear_slot', { p_slot: slot });

/** The look the player's 3D Sim shows right now (home, places, house visitors). Portraits keep the everyday look. */
export function useShownAvatar(state: GameState | null, now: number, atOwnHome: boolean, inPlace: boolean): { avatar: AvatarConfig | null; slot: OutfitSlot } {
  const outfits = useWardrobe((s) => (s.data?.enabled ? s.data.outfits : null));
  const activities = useCatalog((s) => s.activities);
  const events = useEvents((s) => s.list);
  const p = state?.profile ?? null;
  const busy = Boolean(p?.busy_until && Date.parse(p.busy_until) > now);
  const label = busy ? p?.busy_label ?? null : null;
  const activityId = label ? activities?.find((a) => a.name === label)?.id ?? null : null;
  const locId = state && !state.travel ? state.location.id : null;
  const scene = inPlace && state ? state.location.scene : null;
  const partyHere = Boolean(inPlace && locId && events.some((e) => e.location_id === locId && PARTY_EVENT_KINDS.has(String(e.kind)) && isLive(e)));
  const slot = outfitContext({ activityId, busyLabel: label, busy, atOwnHome, placeScene: scene, partyHere });
  const base = p?.avatar ?? null;
  const avatar = useMemo(() => (base ? outfitFor(base, outfits, slot) : null), [base, outfits, slot]);
  return { avatar, slot };
}
