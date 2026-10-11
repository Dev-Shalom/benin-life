// H2 receipts (docs/RECEIPTS.md): any RPC result that carries `receipt` (furniture_buy, shop_buy, garage_build,
// house_move, wardrobe_buy at or above receipts.min_amount) opens the receipt sheet. src/lib/api.ts calls
// noteReceipt on every RPC result, so no purchase screen has to remember to.
import { create } from 'zustand';

export interface Receipt {
  id: string;
  ref: string;
  /** furniture | car | shop | garage | house | boutique */
  kind: string;
  item_name: string;
  amount: number;
  seller: string;
  meta: Record<string, unknown>;
  created_at: string;
}

interface ReceiptStore {
  /** The receipt sheet's receipt (null = closed). */
  open: Receipt | null;
  /** Bumped when a new receipt is issued (the Receipts list reloads). */
  version: number;
  /** Open the Bank app on the Receipts tab (BankApp clears it). */
  wantList: boolean;
  show: (r: Receipt) => void;
  close: () => void;
  requestList: (on: boolean) => void;
}

export const useReceipts = create<ReceiptStore>((set) => ({
  open: null,
  version: 0,
  show: (r) => set((s) => ({ open: r, version: s.version + 1 })),
  close: () => set({ open: null }),
  wantList: false,
  requestList: (on) => set({ wantList: on }),
}));

export function noteReceipt(data: unknown) {
  if (!data || typeof data !== 'object') return;
  const r = (data as { receipt?: Receipt }).receipt;
  if (r && typeof r === 'object' && typeof r.ref === 'string') useReceipts.getState().show(r);
}
