// Welcome-back gift (docs/DAILY_RETURN.md). Server-authoritative: return_gift_status() / return_gift_claim().
import { create } from 'zustand';
import { rpc } from '../lib/api';

export interface GiftItem { id: string; name: string; icon: string | null; qty: number }
export interface ReturnGift { pending: boolean; id?: number; away_days?: number; cash?: number; item?: GiftItem | null }
export interface GiftClaimed { claimed: boolean; cash: number; away_days: number; item: GiftItem | null }

interface Store {
  gift: ReturnGift | null;
  /** The welcome-back screen (or the pop-up) already showed the gift this session, so nothing shows it twice. */
  offered: boolean;
  claimed: GiftClaimed | null;
  load: () => Promise<void>;
  claim: () => Promise<GiftClaimed>;
  markOffered: () => void;
}

export const useReturnGift = create<Store>((set, get) => ({
  gift: null,
  offered: false,
  claimed: null,
  async load() {
    try {
      set({ gift: await rpc<ReturnGift>('return_gift_status') });
    } catch {
      set({ gift: { pending: false } });
    }
  },
  async claim() {
    const res = await rpc<GiftClaimed>('return_gift_claim');
    set({ claimed: res, gift: { pending: false } });
    return res;
  },
  markOffered() {
    if (!get().offered) set({ offered: true });
  },
}));
