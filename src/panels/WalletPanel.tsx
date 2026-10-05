// Wallet — balances + top-up packs. Phase 1 placeholder (top-up says "coming soon");
// P2-PAY owns this file and wires the real provider through src/lib/payments.ts.
import { useState } from 'react';
import { formatKobo, getPaymentProvider, TOP_UP_PACKS, type TopUpPack } from '../lib/payments';
import { naira } from '../lib/format';
import type { PanelProps } from '../lib/types';
import { useGame } from '../state/game';
import { Button, Icon, Money, toast } from '../ui';

export default function WalletPanel({ state }: PanelProps) {
  const provider = getPaymentProvider();
  const session = useGame((s) => s.session);
  const [busy, setBusy] = useState<string | null>(null);

  const topUp = async (pack: TopUpPack) => {
    setBusy(pack.id);
    try {
      const res = await provider.startTopUp(pack, { email: session?.user.email ?? '', userId: state.profile.id });
      if (res.status === 'unavailable') toast(res.message, 'info');
      else if (res.status === 'cancelled') toast('Payment cancelled.', 'info');
      else toast('Payment received! Confirming it now…', 'good');
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

      <div className="wallet__head">
        <h4 className="act__name">Top up naira</h4>
        <span className="chip warn"><Icon name="clock" size={12} /> Coming soon</span>
      </div>
      <p className="act__desc">
        Buy game naira to move faster. It is game money only: it has no real cash value and can't be withdrawn.
      </p>

      <div className="acts">
        {TOP_UP_PACKS.map((p) => (
          <article key={p.id} className="act wallet__pack">
            <div className="act__top">
              <div className="grow">
                <h4 className="act__name">{naira(p.game_naira)}</h4>
                <div className="act__meta">
                  <span className="chip">{p.label}</span>
                  {p.tag && <span className="chip good">{p.tag}</span>}
                </div>
              </div>
              <Button size="sm" variant="gold" loading={busy === p.id} onClick={() => void topUp(p)}>
                {formatKobo(p.price_kobo)}
              </Button>
            </div>
          </article>
        ))}
      </div>
      <p className="wallet__fine">
        Payments go through {provider.name === 'None' ? 'our payment partner' : provider.name}. We confirm every payment on our server before the naira lands.
      </p>
    </div>
  );
}
