// H2 receipts: owner-read table (RLS), written only by server functions (bl_receipt_issue). docs/RECEIPTS.md
import { supabase } from '../lib/supabase';
import type { Receipt } from '../state/receipts';

export async function myReceipts(limit = 50): Promise<Receipt[]> {
  const { data, error } = await supabase
    .from('receipts')
    .select('id, ref, kind, item_name, amount, seller, meta, created_at')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw new Error('Could not load your receipts. Check your connection and try again.');
  return (data ?? []).map((r) => ({ ...r, amount: Number(r.amount) })) as Receipt[];
}
