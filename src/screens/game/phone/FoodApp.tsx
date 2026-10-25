// Phone "Chowdeck" app (V1-4): order food and drinks to wherever you are, at a delivery markup.
// Paid by transfer (bank) first, the rest in cash. The order lands straight in the Bag.
// Step C (docs/COOKING.md): the same app holds your Kitchen (cook at home) and today's grocery Prices. Deep links: food:kitchen, food:prices.
import { lazy, Suspense, useEffect, useState } from 'react';
import { foodMenu, foodOrder } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { getCfg } from '../../../lib/config';
import { naira } from '../../../lib/format';
import type { FoodMenu, GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { useUi } from '../../../state/ui';
import { toast } from '../../../ui';
import { ItemCard } from '../../../panels/shop/ShopUI';

const KitchenTab = lazy(() => import('./KitchenTab'));
const PricesTab = lazy(() => import('./PricesTab'));

type Tab = 'food' | 'drink' | 'kitchen' | 'prices';
const TAB_LABEL: Record<Tab, string> = { food: '🍲 Food', drink: '🥤 Drinks', kitchen: '🍳 Kitchen', prices: '📈 Prices' };
const HERO: Record<Tab, [string, string, string]> = {
  food: ['🛵', 'Hot food, to your door', ''],
  drink: ['🛵', 'Hot food, to your door', ''],
  kitchen: ['🍳', 'Your kitchen', 'Cook at home with ingredients from the market. Cheaper than ordering, and the pot feeds the family.'],
  prices: ['📈', 'Today\'s prices', 'Oba Market moves a little every day. The supermarket never does.'],
};
const tabFromApp = (app: string | null): Tab => (app === 'food:kitchen' ? 'kitchen' : app === 'food:prices' ? 'prices' : 'food');

export default function FoodApp({ state }: { state: GameState }) {
  const refresh = useGame((s) => s.refresh);
  const [menu, setMenu] = useState<FoodMenu | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const phoneApp = useUi((st) => st.phoneApp);
  const phoneNonce = useUi((st) => st.phoneNonce);
  const [tab, setTab] = useState<Tab>(() => tabFromApp(phoneApp));
  useEffect(() => {
    if (phoneApp?.startsWith('food:')) setTab(tabFromApp(phoneApp));
  }, [phoneApp, phoneNonce]);
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

  const items = tab === 'food' || tab === 'drink' ? (menu?.items ?? []).filter((i) => i.category === tab) : [];
  return (
    <div className="phone-app__body chop">
      <div className="chop__hero">
        <span className="chop__hero-emoji" aria-hidden>{HERO[tab][0]}</span>
        <div className="grow">
          <div className="chop__hero-title">{HERO[tab][1]}</div>
          <div className="chop__hero-sub">
            {tab === 'food' || tab === 'drink'
              ? <>{menu ? `Shop price + ${menu.markup_pct}% delivery (at least ${naira(menu.min_fee)}).` : 'Bukas and hawkers all over Benin.'}{' '}Paid from your bank first, then cash.</>
              : HERO[tab][2]}
          </div>
        </div>
      </div>
      <div className="chop__tabs" role="tablist">
        {(['food', 'drink', 'kitchen', 'prices'] as const).map((t) => (
          <button key={t} type="button" role="tab" aria-selected={tab === t} className={`chop__tab${tab === t ? ' is-on' : ''}`} onClick={() => setTab(t)} data-testid={`chop-tab-${t}`}>
            {TAB_LABEL[t]}
          </button>
        ))}
        <span className="grow" />
        {(tab === 'food' || tab === 'drink') && <span className="chop__money">You have <b>{naira(money)}</b></span>}
      </div>
      {tab === 'kitchen' && <Suspense fallback={<div className="panel-skel"><span /><span /></div>}><KitchenTab state={state} onShop={() => setTab('prices')} /></Suspense>}
      {tab === 'prices' && <Suspense fallback={<div className="panel-skel"><span /><span /></div>}><PricesTab /></Suspense>}
      {(tab === 'food' || tab === 'drink') && !menu && !err && <div className="panel-skel"><span /><span /></div>}
      {(tab === 'food' || tab === 'drink') && err && <p className="phone-app__lead">{err}</p>}
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
