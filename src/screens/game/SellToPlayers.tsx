// R9: "Sell to players" next to every "Sell to shop" (Bag, Cars / garage, My items, Invest land). One small sheet:
// the server quote (what it is worth, the price band, the fee, or why it can't be listed), a price, optional "open to
// offers" and "only my friend". The thing is locked on the market until it sells or the player takes it down.
// Server: market_quote / market_list (docs/MARKET.md).
import { useEffect, useMemo, useState } from 'react';
import { dropMarketInfoCache, marketList, marketQuote, useMarketInfo, type MarketKind, type MarketQuote } from '../../api/market';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Modal, Switch, toast } from '../../ui';
import './market.css';

export interface SellToPlayersProps {
  kind: MarketKind;
  /** item id / car id / furniture id / land area id */
  refId: string;
  /** How many the player holds (items and land plots). Cars and furniture are always 1. */
  maxQty?: number;
  /** Furniture copy key (own_tv_75-2). */
  itemKey?: string | null;
  /** Shown while the quote loads. */
  name: string;
  icon?: string;
  size?: 'sm' | 'md';
  label?: string;
  block?: boolean;
  variant?: 'ghost' | 'gold' | 'green';
  onListed?: () => void;
}

export function SellToPlayersButton({ kind, refId, maxQty = 1, itemKey, name, icon, size = 'sm', label = 'Sell to players', block, variant = 'ghost', onListed }: SellToPlayersProps) {
  const [open, setOpen] = useState(false);
  const info = useMarketInfo();
  if (info && !info.enabled) return null;
  if (info && !info.kinds.find((k) => k.kind === kind)?.enabled) return null;
  return (
    <>
      <Button size={size} variant={variant} block={block} onClick={() => setOpen(true)} data-testid={`sell-players-${kind}`}>{label}</Button>
      {open && <SellSheet kind={kind} refId={refId} maxQty={maxQty} itemKey={itemKey ?? null} name={name} icon={icon} onClose={() => setOpen(false)} onListed={onListed} />}
    </>
  );
}

function SellSheet({ kind, refId, maxQty, itemKey, name, icon, onClose, onListed }: {
  kind: MarketKind; refId: string; maxQty: number; itemKey: string | null; name: string; icon?: string; onClose: () => void; onListed?: () => void;
}) {
  const info = useMarketInfo();
  const [qty, setQty] = useState(1);
  const [quote, setQuote] = useState<MarketQuote | null>(null);
  const [price, setPrice] = useState('');
  const [offers, setOffers] = useState(false);
  const [friend, setFriend] = useState('');
  const [busy, setBusy] = useState(false);
  const [priceTouched, setPriceTouched] = useState(false);

  useEffect(() => {
    let alive = true;
    setQuote(null);
    marketQuote(kind, refId, qty, itemKey).then((q) => {
      if (!alive) return;
      setQuote(q);
      if (q.ok && q.value) setPrice((p) => (priceTouched && p ? p : String(q.value)));
    }).catch((e) => { if (alive) setQuote({ ok: false, message: errorMessage(e) }); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, refId, qty, itemKey]);

  const n = Number(price) || 0;
  const fee = quote?.ok ? Math.floor((n * (quote.fee_pct ?? 0)) / 100) : 0;
  const inBand = quote?.ok && n >= (quote.min_price ?? 0) && n <= (quote.max_price ?? Infinity);
  const blockedNew = info && !info.can_sell;
  const hours = info ? Math.ceil(info.sell_wait_seconds / 3600) : 0;
  const hint = useMemo(() => {
    if (!quote?.ok || !n) return '';
    if (n < (quote.min_price ?? 0)) return `Lowest allowed is ${naira(quote.min_price)}.`;
    if (n > (quote.max_price ?? Infinity)) return `Highest allowed is ${naira(quote.max_price)}.`;
    return '';
  }, [quote, n]);

  const submit = async () => {
    if (!quote?.ok || !inBand) return;
    setBusy(true);
    try {
      const r = await marketList({ kind, ref: refId, qty, price: n, offers: offers && !friend.trim(), to: friend, key: itemKey });
      toast(r.message, 'good');
      dropMarketInfoCache();
      await useGame.getState().refresh();
      onListed?.();
      onClose();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const title = quote?.ok ? quote.title : name;
  return (
    <Modal open onClose={() => !busy && onClose()} title={`Sell ${title} to players`}
      art={<span className="sell-dialog__emoji" aria-hidden>{quote?.ok ? quote.icon || icon : icon || '🛒'}</span>}
      actions={
        <>
          <Button variant="ghost" disabled={busy} onClick={onClose}>Not now</Button>
          <Button variant="gold" loading={busy} disabled={!quote?.ok || !inBand || Boolean(blockedNew)} onClick={() => void submit()}>
            {n > 0 ? `List for ${naira(n)}` : 'Put a price'}
          </Button>
        </>
      }>
      <div className="mk-sell">
        {!quote && <p className="muted">Checking with the market…</p>}
        {quote && !quote.ok && <p className="mk-sell__no" role="alert">{quote.message}</p>}
        {blockedNew && <p className="mk-sell__no" role="alert">New accounts can sell to other players after about {hours} hour{hours === 1 ? '' : 's'} of playing. Buying is open now.</p>}
        {quote?.ok && (
          <>
            {kind === 'item' || kind === 'land' ? (
              <div className="mk-sell__qty">
                <span>{kind === 'land' ? 'Plots' : 'How many'}</span>
                <span className="mk-sell__stepper">
                  <button type="button" aria-label="One less" disabled={qty <= 1} onClick={() => setQty((q) => Math.max(1, q - 1))}>−</button>
                  <b>{qty}</b>
                  <button type="button" aria-label="One more" disabled={qty >= maxQty} onClick={() => setQty((q) => Math.min(maxQty, q + 1))}>+</button>
                </span>
              </div>
            ) : null}
            {quote.cond && quote.cond !== 'Used' && quote.cond !== `×${qty}` && <div className="sell-dialog__row"><span>Condition</span><b>{quote.cond}</b></div>}
            <div className="sell-dialog__row"><span>Worth about</span><span>{naira(quote.value)}</span></div>
            <label className="mk-sell__price">
              <span>Your price</span>
              <input className="input" inputMode="numeric" enterKeyHint="done" autoComplete="off" value={price} aria-label="Your price in naira"
                onChange={(e) => { setPriceTouched(true); setPrice(e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, 13)); }} />
            </label>
            <p className={`mk-sell__range${hint ? ' is-bad' : ''}`}>{hint || `Allowed: ${naira(quote.min_price)} to ${naira(quote.max_price)} (${quote.floor_pct}% to ${quote.ceiling_pct}% of what it is worth).`}</p>
            <div className="sell-dialog__row"><span>Market fee ({quote.fee_pct}%)</span><span>−{naira(fee)}</span></div>
            <div className="sell-dialog__row sell-dialog__row--total"><span>You get (into your bank)</span><b>{naira(Math.max(0, n - fee))}</b></div>
            {!friend.trim() && <Switch checked={offers} onChange={setOffers} label="Open to offers" hint="Buyers can offer less. You choose to accept or decline." />}
            {info?.private_enabled && (
              <label className="mk-sell__price">
                <span>Only for a friend (optional)</span>
                <input className="input" enterKeyHint="done" autoComplete="off" autoCapitalize="none" placeholder="@username" value={friend} aria-label="Friend username"
                  onChange={(e) => setFriend(e.target.value.replace(/[^A-Za-z0-9_@]/g, '').slice(0, 24))} />
              </label>
            )}
            <p className="sell-dialog__note">
              It is locked while listed: you can't use, place or drive it. If nobody buys it in {info?.expire_days ?? 7} days it comes back to you.
              {' '}
              <button type="button" className="mk-link" onClick={() => { onClose(); useUi.getState().openPhone('market'); }}>Open Benin Market</button>
            </p>
          </>
        )}
      </div>
    </Modal>
  );
}
