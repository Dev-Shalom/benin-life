// "Shop" tab in the location sheet (action id `shop`, V1-4): what this place sells, cash only.
// Items land in the Bag (InventoryPanel). Markets also buy things back (Sell lives in the Bag).
import { useEffect, useMemo, useState } from 'react';
import { CATEGORY_ORDER, shopBuy, shopList } from '../api/shops';
import { errorMessage } from '../lib/api';
import { useGameClock } from '../lib/clock';
import { getCfg } from '../lib/config';
import { naira } from '../lib/format';
import type { PanelProps, ShopList } from '../lib/types';
import { openPanel } from '../state/ui';
import { Button, EmptyState, toast } from '../ui';
import { ItemCard } from './shop/ShopUI';

const GREETING: Record<string, string> = {
  market: '"Customer, come and buy! Everything fresh, price is fair."',
  buka: '"Take-away packs dey. Hot hot!"',
  motorpark: 'Hawkers weave between the buses with trays on their heads.',
  pos: '"Recharge card, data, quick quick."',
  cyber: 'Fairly-used laptops and data for the night crawlers.',
  office: 'The hub shop: data and fairly-used laptops for the team.',
  hospital: 'The pharmacy counter by the entrance.',
  salon: 'Soap, toothpaste and small things for looking fresh.',
  workshop: 'The guild sells small castings to visitors.',
};

export default function ShopPanel({ state, location, refresh }: PanelProps) {
  const [list, setList] = useState<ShopList | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const { now } = useGameClock(5000);
  const p = state.profile;
  const busyNow = Boolean(p.busy_until && Date.parse(p.busy_until) > now);
  const maxQty = Number(getCfg('shop.max_qty_per_buy', 10));

  const [tick, setTick] = useState(0);
  const load = () => setTick((t) => t + 1);
  useEffect(() => {
    let alive = true;
    shopList(location.id)
      .then((l) => alive && (setList(l), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [location.id, tick]);

  const owned = useMemo(() => Object.fromEntries((state.inventory ?? []).map((i) => [i.id, i.qty])), [state.inventory]);
  const groups = useMemo(() => {
    const items = list?.items ?? [];
    const known = CATEGORY_ORDER.map(([id, label]) => ({ id, label, items: items.filter((i) => i.category === id) }));
    const other = items.filter((i) => !CATEGORY_ORDER.some(([id]) => id === i.category));
    return [...known, { id: 'other', label: 'Other', items: other }].filter((g) => g.items.length > 0);
  }, [list]);

  const buy = async (id: string, qty: number) => {
    setBusy(id);
    try {
      const r = await shopBuy(id, qty);
      toast(r.message, 'good');
      await refresh();
      load();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  if (!list && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (err && !list) return <EmptyState icon="info" title="Couldn't load the shop" body={err} />;
  if (!list || list.items.length === 0) {
    return <EmptyState icon="bag" title="Nothing for sale here" body="Try a market or a buka. Benin City is big." />;
  }

  const sellable = list.sell_here && (state.inventory ?? []).some((i) => i.sellable && i.resale_price > 0);
  return (
    <div className="shop stack">
      <div className="shop__head">
        <p className="shop__greet">{GREETING[location.scene] ?? 'Have a look around.'}</p>
        <span className="shop__cash">Cash <b>{naira(p.cash)}</b></span>
      </div>
      {groups.map((g) => (
        <section key={g.id} className="shop__group">
          <h4 className="shop__cat">{g.label}</h4>
          <div className="items">
            {g.items.map((it) => {
              const blocked = busyNow ? 'Busy right now' : p.cash < it.price ? 'Not enough cash' : null;
              return (
                <ItemCard key={it.id} item={it} price={it.price} owned={owned[it.id] ?? 0} kind={it.kind}
                  maxQty={it.kind === 'keep' ? 1 : Math.max(1, Math.min(maxQty, Math.floor(p.cash / Math.max(1, it.price))))}
                  action="Buy" blocked={blocked} busy={busy === it.id}
                  onAction={(q) => void buy(it.id, q)} />
              );
            })}
          </div>
        </section>
      ))}
      {sellable && (
        <div className="shop__sell">
          <span className="grow">Traders here buy things back for part of the price.</span>
          <Button size="sm" variant="ghost" icon="bag" onClick={() => openPanel('inventory')}>Sell from Bag</Button>
        </div>
      )}
    </div>
  );
}
