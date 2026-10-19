// E4: the transfer fee, shown BEFORE the player confirms (server preview: bank_transfer_quote).
import { useEffect, useState } from 'react';
import { bankTransferQuote, type FeeQuote } from '../../../api/economy';
import { naira } from '../../../lib/format';

/** The server's fee preview for an amount, refreshed (debounced) as the player types. */
export function useFeeQuote(amount: number, min: number, kind: 'transfer' | 'tip' = 'transfer'): FeeQuote | null {
  const [q, setQ] = useState<FeeQuote | null>(null);
  useEffect(() => {
    if (!(amount >= Math.max(1, min))) { setQ(null); return; }
    let alive = true;
    const t = window.setTimeout(() => {
      bankTransferQuote(amount, kind).then((r) => alive && setQ(r)).catch(() => alive && setQ(null));
    }, 220);
    return () => { alive = false; window.clearTimeout(t); };
  }, [amount, min, kind]);
  return q && q.amount === amount ? q : null;
}

/** "Fee ₦750 (₦700 + ₦50 stamp duty) · you pay ₦60,750", with the doubled-fee warning past the soft cap. */
export function FeeLine({ quote }: { quote: FeeQuote | null }) {
  if (!quote) return null;
  return (
    <div className="bankx__fee" data-testid="fee-preview">
      <div><span>Transfer fee{quote.rate_pct ? ` (${quote.rate_pct}%)` : ''}</span><b>{naira(quote.tier_fee)}</b></div>
      {quote.stamp_duty > 0 && <div><span>Stamp duty (EMTL)</span><b>{naira(quote.stamp_duty)}</b></div>}
      <div><span>Total from your bank</span><b>{naira(quote.total)}</b></div>
      {quote.doubled && <p className="bankx__fine">You are past today&apos;s soft cap of {naira(quote.soft_cap)}, so the fee is doubled. It resets tomorrow.</p>}
      {!quote.doubled && quote.left_before_soft_cap != null && quote.soft_cap > 0 && quote.left_before_soft_cap > 0 && (
        <p className="bankx__fine">{naira(quote.left_before_soft_cap)} more today before the fee doubles.</p>
      )}
    </div>
  );
}
