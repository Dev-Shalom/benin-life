// Wallet (PAY, docs/PAYMENTS.md): balances + Paystack top-ups. Packs come from the topup_packs table
// (admin: Content -> Top-up packs). The server makes the payment, Paystack takes the money, and an Edge
// Function verifies it before any naira lands; this panel only starts checkout and refreshes afterwards.
import { useEffect, useState } from 'react';
import { formatKobo, getPaymentProvider, loadTopUpPacks, TOP_UP_PACKS, type TopUpPack } from '../lib/payments';
import { useConfig } from '../lib/config';
import { naira } from '../lib/format';
import type { PanelProps } from '../lib/types';
import { useGame } from '../state/game';
import { useUi } from '../state/ui';
import { Icon, Money, toast } from '../ui';
import '../styles/pay.css';

export default function WalletPanel({ state, refresh }: PanelProps) {
  const provider = getPaymentProvider();
  useConfig(); // re-render when payments.enabled flips
  const live = provider.ready;
  const session = useGame((s) => s.session);
  const [packs, setPacks] = useState<TopUpPack[]>(TOP_UP_PACKS);
  const [busy, setBusy] = useState<string | null>(null);
  const openPhone = useUi((s) => s.openPhone);
  const closePanel = useUi((s) => s.closePanel);

  useEffect(() => {
    let alive = true;
    void loadTopUpPacks().then((p) => alive && setPacks(p));
    return () => { alive = false; };
  }, []);

  const best = packs.length > 2 ? packs[packs.length - 2]?.id : null;

  const topUp = async (pack: TopUpPack) => {
    if (busy) return;
    setBusy(pack.id);
    try {
      const res = await provider.startTopUp(pack, { email: session?.user.email ?? '', userId: state.profile.id });
      if (res.status === 'unavailable') toast(res.message, 'info');
      else if (res.status === 'cancelled') toast('Payment cancelled. No money was taken.', 'info');
      else if (res.status === 'error') toast(res.message, 'bad');
      else {
        toast(res.message, res.status === 'success' ? 'good' : 'info');
        await refresh();
      }
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="wallet">
      <div className="wallet__balances">
        <div className="wallet__bal">
          <span className="wallet__label">Cash</span>
          <Money amount={state.profile.cash} kind="cash" />
        </div>
        <div className="wallet__bal">
          <span className="wallet__label">Bank</span>
          <Money amount={state.profile.bank} kind="bank" />
        </div>
      </div>
      <button type="button" className="wallet__bank-link" onClick={() => { closePanel(); openPhone('bank'); }}>
        <span aria-hidden>🏦</span>
        <span className="grow">
          <b>Open the Bank app</b>
          <span>Send money to friends, see your history, find a bank or PoS.</span>
        </span>
        <Icon name="chevronRight" size={18} />
      </button>

      <div className="wallet__head">
        <h4 className="act__name">Top up naira</h4>
        {live
          ? <span className="chip good"><Icon name="check" size={12} /> Secure checkout</span>
          : <span className="chip warn"><Icon name="clock" size={12} /> Coming soon</span>}
      </div>
      <p className="act__desc">
        Naira lands in your bank. It is game money only: it has no real cash value and can't be withdrawn.
      </p>

      <div className="topup-grid">
        {packs.map((p) => (
          <button key={p.id} type="button" className={`topup${p.id === best ? ' is-best' : ''}${busy === p.id ? ' is-busy' : ''}`}
            disabled={Boolean(busy)} onClick={() => void topUp(p)}
            aria-label={`${naira(p.game_naira)} game naira for ${formatKobo(p.price_kobo)}`}>
            {p.id === best && <span className="topup__ribbon">Best value</span>}
            <span className="topup__label">{p.label}</span>
            <span className="topup__naira">{naira(p.game_naira)}</span>
            {p.tag ? <span className="topup__tag">{p.tag}</span> : <span className="topup__tag topup__tag--none">Game naira</span>}
            <span className="topup__price">{busy === p.id ? <span className="topup__spin" aria-hidden /> : null}{formatKobo(p.price_kobo)}</span>
          </button>
        ))}
      </div>
      <p className="wallet__fine">
        <Icon name="lock" size={12} /> Payments go through {provider.id === 'paystack' ? 'Paystack' : 'our payment partner'} (card, bank transfer, USSD).
        We confirm every payment on our server before the naira lands.
      </p>
    </div>
  );
}
