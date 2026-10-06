// Payments (PAY, docs/PAYMENTS.md): top-ups of virtual naira (game money, no cash value) with Paystack.
// Flow: payment_init RPC (server makes a pending payment + reference, price from topup_packs)
//   -> Paystack Inline v2 checkout (public key, loaded lazily)
//   -> Edge Function paystack-verify (secret key, server side) checks Paystack and credits ONCE.
// The webhook (paystack-webhook) is the backup if the tab closes before verify runs.
// The client never credits money; it only asks the server to check.
//
// Swapping provider = set VITE_PAYMENT_PROVIDER and add a case in `getPaymentProvider()`.
import { rpc } from './api';
import { getCfg } from './config';
import { supabase } from './supabase';

export type PaymentProviderId = 'paystack' | 'none';

/** A naira pack the player can buy. `price_kobo` is real money (NGN × 100). */
export interface TopUpPack {
  id: string;
  label: string;
  game_naira: number;
  price_kobo: number;
  tag?: string | null;
}

export type TopUpResult =
  | { status: 'success'; reference: string; credited: boolean; bank?: number; message: string }
  | { status: 'pending'; reference: string; message: string }
  | { status: 'cancelled' }
  | { status: 'unavailable'; message: string }
  | { status: 'error'; message: string };

export interface PaymentProvider {
  id: PaymentProviderId;
  name: string;
  /** True when the provider is configured AND an admin has turned payments on. Read it at render time. */
  readonly ready: boolean;
  startTopUp(pack: TopUpPack, customer: { email: string; userId: string }): Promise<TopUpResult>;
}

/** Fallback packs (the live list is the topup_packs table, editable in admin). */
export const TOP_UP_PACKS: TopUpPack[] = [
  { id: 'small', label: 'Small chops', game_naira: 20_000, price_kobo: 20_000 },
  { id: 'medium', label: 'Correct money', game_naira: 120_000, price_kobo: 100_000, tag: '+20% bonus' },
  { id: 'big', label: 'Big boy pack', game_naira: 650_000, price_kobo: 500_000, tag: '+30% bonus' },
  { id: 'oga', label: 'Oga pack', game_naira: 1_500_000, price_kobo: 1_000_000, tag: '+50% bonus' },
  { id: 'odogwu', label: 'Odogwu pack', game_naira: 3_500_000, price_kobo: 2_000_000, tag: '+75% bonus' },
];

/** Active packs from the server (RLS: players read active rows only), falling back to the list above. */
export async function loadTopUpPacks(): Promise<TopUpPack[]> {
  const { data, error } = await supabase.from('topup_packs')
    .select('id, label, game_naira, price_kobo, bonus_tag, sort').order('sort').order('id');
  if (error || !data || data.length === 0) return TOP_UP_PACKS;
  return data.map((r) => ({ id: r.id, label: r.label, game_naira: Number(r.game_naira), price_kobo: Number(r.price_kobo), tag: r.bonus_tag }));
}

const COMING_SOON = 'Top-ups are coming soon. Hold on to your naira for now.';
const INLINE_SRC = 'https://js.paystack.co/v2/inline.js';

interface PaystackTx { reference?: string; status?: string; message?: string }
interface PaystackPopInstance {
  newTransaction(opts: {
    key: string; email: string; amount: number; reference: string; currency?: string;
    metadata?: Record<string, unknown>;
    onSuccess?: (tx: PaystackTx) => void; onCancel?: () => void; onError?: (e: { message?: string }) => void;
  }): void;
}
type PaystackPopCtor = new () => PaystackPopInstance;

let inlineLoading: Promise<PaystackPopCtor> | null = null;
function loadInline(): Promise<PaystackPopCtor> {
  const w = window as unknown as { PaystackPop?: PaystackPopCtor };
  if (w.PaystackPop) return Promise.resolve(w.PaystackPop);
  if (inlineLoading) return inlineLoading;
  inlineLoading = new Promise<PaystackPopCtor>((resolve, reject) => {
    const s = document.createElement('script');
    s.src = INLINE_SRC;
    s.async = true;
    s.onload = () => (w.PaystackPop ? resolve(w.PaystackPop) : reject(new Error('Paystack did not load')));
    s.onerror = () => reject(new Error('Paystack did not load'));
    document.head.appendChild(s);
  }).catch((e) => {
    inlineLoading = null;
    throw e;
  });
  return inlineLoading;
}

/** Ask the server to verify + credit. Returns the function's JSON (or an error shape). */
async function verifyOnServer(reference: string): Promise<{ ok: boolean; credited?: boolean; already?: boolean; bank?: number; error?: string }> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { data, error } = await supabase.functions.invoke('paystack-verify', { body: { reference } });
    if (!error && data) return data;
    // 402 = Paystack hasn't marked it paid yet (bank transfer / USSD): wait a moment and ask again
    await new Promise((r) => setTimeout(r, 2500 * (attempt + 1)));
  }
  return { ok: false, error: 'unconfirmed' };
}

function paystackProvider(): PaymentProvider {
  const key = String(import.meta.env.PAYSTACK_PUBLIC_KEY || import.meta.env.VITE_PAYSTACK_PUBLIC_KEY || '').trim();
  return {
    id: 'paystack',
    name: 'Paystack',
    get ready() {
      return key.startsWith('pk_') && getCfg<boolean>('payments.enabled', false) === true;
    },
    async startTopUp(pack) {
      if (!this.ready) return { status: 'unavailable', message: COMING_SOON };
      let init: { reference: string; amount_kobo: number; email: string; currency: string };
      let Pop: PaystackPopCtor;
      try {
        [init, Pop] = await Promise.all([
          rpc<{ reference: string; amount_kobo: number; email: string; currency: string }>('payment_init', { p_pack: pack.id }),
          loadInline(),
        ]);
      } catch (e) {
        return { status: 'error', message: e instanceof Error && e.message ? e.message : 'Could not start the payment. Try again.' };
      }
      const outcome = await new Promise<'success' | 'cancelled' | { error: string }>((resolve) => {
        new Pop().newTransaction({
          key,
          email: init.email,
          amount: init.amount_kobo,
          currency: init.currency || 'NGN',
          reference: init.reference,
          metadata: { pack: pack.id },
          onSuccess: () => resolve('success'),
          onCancel: () => resolve('cancelled'),
          onError: (e) => resolve({ error: e?.message || 'Paystack could not open.' }),
        });
      });
      if (outcome === 'cancelled') return { status: 'cancelled' };
      if (typeof outcome === 'object') return { status: 'error', message: outcome.error };
      const v = await verifyOnServer(init.reference);
      if (v.ok) {
        return { status: 'success', reference: init.reference, credited: Boolean(v.credited || v.already), bank: v.bank,
                 message: `${'₦' + pack.game_naira.toLocaleString('en-NG')} is in your bank. Thank you!` };
      }
      return { status: 'pending', reference: init.reference,
               message: 'Payment received. Your naira lands as soon as Paystack confirms it (usually under a minute).' };
    },
  };
}

function noProvider(): PaymentProvider {
  return {
    id: 'none',
    name: 'None',
    ready: false,
    async startTopUp() {
      return { status: 'unavailable', message: COMING_SOON };
    },
  };
}

let cached: PaymentProvider | null = null;

export function getPaymentProvider(): PaymentProvider {
  if (cached) return cached;
  const id = (import.meta.env.VITE_PAYMENT_PROVIDER ?? 'paystack').trim() as PaymentProviderId;
  cached = id === 'paystack' ? paystackProvider() : noProvider();
  return cached;
}

/** Real money price, e.g. 100000 kobo -> "₦1,000". */
export function formatKobo(kobo: number): string {
  return '₦' + Math.round(kobo / 100).toLocaleString('en-NG');
}
