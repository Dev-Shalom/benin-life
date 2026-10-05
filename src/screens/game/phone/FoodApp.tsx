// Phone "ChopNow" app (V1-4): order food and drinks to wherever you are, at a delivery markup.
// Paid by transfer (bank) first, the rest in cash. The order lands straight in the Bag.
import { useEffect, useState } from 'react';
import { foodMenu, foodOrder } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { getCfg } from '../../../lib/config';
import { naira } from '../../../lib/format';
import type { FoodMenu, GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { toast } from '../../../ui';
import { ItemCard } from '../../../panels/shop/ShopUI';

export default function FoodApp({ state }: { state: GameState }) {
  const refresh = useGame((s) => s.refresh);
  const [menu, setMenu] = useState<FoodMenu | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [tab, setTab] = useState<'food' | 'drink'>('food');
  const maxQty = Number(getCfg('shop.max_qty_per_buy', 10));
  const money = state.profile.cash + state.profile.bank;

  const [tick, setTick] = useState(0);
  const load = () => setTick((t) => t + 1);
  useEffect(() => {
    let alive = true;
    foodMenu()
      .then((m) => alive && (setMenu(m), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [tick]);

  const order = async (id: string, qty: number) => {
    setBusy(id);
    try {
      const r = await foodOrder(id, qty);
      toast(`🛵 ${r.message}`, 'good');
      await refresh();
      load();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  const items = (menu?.items ?? []).filter((i) => i.category === tab);
  return (
    <div className="phone-app__body chop">
      <div className="chop__hero">
        <span className="chop__hero-emoji" aria-hidden>🛵</span>
        <div className="grow">
          <div className="chop__hero-title">Hot food, to your door</div>
          <div className="chop__hero-sub">
            {menu ? `Shop price + ${menu.markup_pct}% delivery (at least ${naira(menu.min_fee)}).` : 'Bukas and hawkers all over Benin.'}
            {' '}Paid from your bank first, then cash.
          </div>
        </div>
      </div>
      <div className="chop__tabs" role="tablist">
        {(['food', 'drink'] as const).map((t) => (
          <button key={t} type="button" role="tab" aria-selected={tab === t} className={`chop__tab${tab === t ? ' is-on' : ''}`} onClick={() => setTab(t)}>
            {t === 'food' ? '🍲 Food' : '🥤 Drinks'}
          </button>
        ))}
        <span className="grow" />
        <span className="chop__money">You have <b>{naira(money)}</b></span>
      </div>
      {!menu && !err && <div className="panel-skel"><span /><span /></div>}
      {err && <p className="phone-app__lead">{err}</p>}
      <div className="items">
        {items.map((it) => (
          <ItemCard key={it.id} item={it} price={it.price} priceNote={`${naira(it.shop_price)} in shops`} owned={it.owned} kind="use"
            maxQty={Math.max(1, Math.min(maxQty, Math.floor(money / Math.max(1, it.price))))}
            action="Order" blocked={money < it.price ? 'Not enough money' : null} busy={busy === it.id}
            onAction={(q) => void order(it.id, q)} />
        ))}
      </div>
    </div>
  );
}
