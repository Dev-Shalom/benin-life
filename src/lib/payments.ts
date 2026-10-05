// Payments — provider-agnostic top-ups for virtual naira (game money, no cash value).
// Phase 1 placeholder: no real charge happens yet. P2-PAY plugs a real provider in here
// (checkout on the client, then an Edge Function verifies the payment server-side and
// credits the player — the client never credits money itself).
//
// Swapping provider = set VITE_PAYMENT_PROVIDER and add a case in `getPaymentProvider()`.

export type PaymentProviderId = 'paystack' | 'none';

/** A naira pack the player can buy. `price_kobo` is real money (NGN × 100). */
export interface TopUpPack {
  id: string;
  label: string;
  game_naira: number;
  price_kobo: number;
  tag?: string;
}

export type TopUpResult =
  | { status: 'success'; reference: string }
  | { status: 'cancelled' }
  | { status: 'unavailable'; message: string };

export interface PaymentProvider {
  id: PaymentProviderId;
  name: string;
  /** True when the provider is configured and live top-ups can start. */
  ready: boolean;
  startTopUp(pack: TopUpPack, customer: { email: string; userId: string }): Promise<TopUpResult>;
}

/** Placeholder packs; P2-PAY moves these server-side (config/table) so admins can tune them. */
export const TOP_UP_PACKS: TopUpPack[] = [
  { id: 'small', label: 'Small chops', game_naira: 20_000, price_kobo: 20_000 },
  { id: 'medium', label: 'Correct money', game_naira: 120_000, price_kobo: 100_000, tag: '+20% bonus' },
  { id: 'big', label: 'Big boy pack', game_naira: 650_000, price_kobo: 500_000, tag: '+30% bonus' },
];

/** Flip to true in P2-PAY once checkout + server verification are wired. */
const LIVE_CHECKOUT = false;

const COMING_SOON = 'Top-ups are coming soon. Hold on to your naira for now.';

function paystackProvider(): PaymentProvider {
  const key = (import.meta.env.VITE_PAYSTACK_PUBLIC_KEY ?? '').trim();
  return {
    id: 'paystack',
    name: 'Paystack',
    ready: LIVE_CHECKOUT && key.startsWith('pk_'),
    async startTopUp() {
      // P2-PAY: load Paystack Inline, open checkout with the public key, then call the
      // verify Edge Function with the reference. Never trust the client callback alone.
      return { status: 'unavailable', message: COMING_SOON };
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
