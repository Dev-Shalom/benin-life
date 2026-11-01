// V1-5: typed wrappers for the bank, PoS and transfer RPCs (server: 20261005000900_bank.sql).
import { rpc } from '../lib/api';
import type { BankInfo, BankRecipient, LedgerRow, MoneyMoveResult, TransferResult } from '../lib/types';

export const bankInfo = () => rpc<BankInfo>('bank_info');
export const bankHistory = (limit = 30) => rpc<LedgerRow[]>('bank_history', { p_limit: limit });
export const bankRecipient = (username: string) => rpc<BankRecipient>('bank_recipient', { p_username: username });
export const bankDeposit = (amount: number) => rpc<MoneyMoveResult>('bank_deposit', { p_amount: amount });
export const bankWithdraw = (amount: number) => rpc<MoneyMoveResult>('bank_withdraw', { p_amount: amount });
export const posCashout = (amount: number) => rpc<MoneyMoveResult>('pos_cashout', { p_amount: amount });
export const posDeposit = (amount: number) => rpc<MoneyMoveResult>('pos_deposit', { p_amount: amount });
export const bankTransfer = (username: string, amount: number, note: string) =>
  rpc<TransferResult>('bank_transfer', { p_username: username, p_amount: amount, p_note: note || null });

export interface PhoneBankInfo { enabled: boolean; fee_pct: number; fee_min: number; max_amount: number; min_amount: number; cash: number; bank: number }
export const phoneBankInfo = () => rpc<PhoneBankInfo>('phone_bank_info');
export const phoneBankDeposit = (amount: number) => rpc<MoneyMoveResult & { fee: number }>('phone_bank_deposit', { p_amount: amount });
export const phoneBankWithdraw = (amount: number) => rpc<MoneyMoveResult & { fee: number }>('phone_bank_withdraw', { p_amount: amount });

/** PoS charge, same as the server's bl_pos_fee: max(min, pct %) rounded up to ₦10. */
export function posFee(amount: number, pct: number, min: number): number {
  const raw = Math.max(min, (amount * pct) / 100);
  return Math.ceil(Math.round((raw / 10) * 1e6) / 1e6) * 10;
}

/** '8:00 AM', '4:00 PM' for a whole game hour. */
export function hourText(h: number): string {
  const x = ((h % 24) + 24) % 24;
  if (x === 0) return '12:00 midnight';
  if (x === 12) return '12:00 noon';
  return x < 12 ? `${x}:00 AM` : `${x - 12}:00 PM`;
}

/** Fix it 12: the money history (docs/FIXIT.md). */
export interface MoneyHistoryRow {
  key: string; account: 'cash' | 'bank' | 'yahoo' | string; delta: number; balance_after: number; reason: string; label: string;
  detail: string | null; category: string; own_move: boolean; created_at: string;
}
export interface MoneyHistorySummary {
  days: number; money_in: number; money_out: number; moved_between_accounts: number; yahoo_seized: number;
  top_out: { category: string; amount: number }[];
}
export const moneyHistory = (limit = 30, filter: 'all' | 'in' | 'out' = 'all', before?: string, beforeKey?: string) =>
  rpc<{ rows: MoneyHistoryRow[]; more: boolean }>('money_history', { p_limit: limit, p_filter: filter, p_before: before ?? null, p_before_key: beforeKey ?? null });
export const moneyHistorySummary = (days = 7) => rpc<MoneyHistorySummary>('money_history_summary', { p_days: days });
