// The Bag (global panel `inventory`, V1-4): everything you own. Eat, drink or use one at a time;
// sell to traders when you stand in a market. Data comes from get_my_state().inventory.
import { useMemo, useState } from 'react';
import { CATEGORY_ORDER, canSellAt, itemSell, itemUse } from '../api/shops';
import { errorMessage } from '../lib/api';
import { useGameClock } from '../lib/clock';
import { getCfg } from '../lib/config';
import { naira } from '../lib/format';
import type { InventoryItem, PanelProps } from '../lib/types';
import { useUi } from '../state/ui';
import { Button, EmptyState, toast } from '../ui';
import { ItemCard } from './shop/ShopUI';

function verbFor(it: InventoryItem): string {
  if (it.kind !== 'use') return '';
  return it.category === 'food' ? 'Eat' : it.category === 'drink' ? 'Drink' : 'Use';
}

function Row({ it, sellHere, busyNow, busy, onUse, onSell }: {
  it: InventoryItem; sellHere: boolean; busyNow: boolean; busy: string | null;
  onUse: (id: string) => void; onSell: (id: string) => void;
}) {
  const verb = verbFor(it);
  const note = it.kind === 'boost' ? 'Used up on your next bath at home' : undefined;
  const canSell = sellHere && it.sellable && it.resale_price > 0;
  return (
    <ItemCard item={it} owned={undefined} kind={it.kind} action={verb} note={note}
      actionVariant="green" blocked={verb && busyNow ? 'Busy right now' : null} busy={busy === `use:${it.id}`}
      onAction={() => onUse(it.id)}
      extra={
        <>
          <span className="item__qty">×{it.qty}</span>
          {canSell && (
            <Button size="sm" variant="ghost" loading={busy === `sell:${it.id}`} disabled={busyNow} onClick={() => onSell(it.id)}>
              Sell {naira(it.resale_price)}
            </Button>
          )}
        </>
      } />
  );
}

export default function InventoryPanel({ state, location, refresh }: PanelProps) {
  const openPhone = useUi((s) => s.openPhone);
  const closePanel = useUi((s) => s.closePanel);
  const [busy, setBusy] = useState<string | null>(null);
  const { now } = useGameClock(5000);
  const p = state.profile;
  const busyNow = Boolean(p.busy_until && Date.parse(p.busy_until) > now);
  const here = state.location.id === location.id && !state.travel;
  const sellHere = here && canSellAt(location.scene, String(getCfg('shop.sell_scenes', 'market')));
  const items = useMemo(() => state.inventory ?? [], [state.inventory]);
  const groups = useMemo(() => {
    const known = CATEGORY_ORDER.map(([id, label]) => ({ id, label, items: items.filter((i) => i.category === id) }));
    const other = items.filter((i) => !CATEGORY_ORDER.some(([id]) => id === i.category));
    return [...known, { id: 'other', label: 'Other', items: other }].filter((g) => g.items.length > 0);
  }, [items]);

  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  if (items.length === 0) {
    return (
      <div className="stack">
        <EmptyState icon="bag" title="Your Bag is empty"
          body="Buy food and other things at markets, bukas and PoS stands, or order food to your door on Chowdeck." />
        <Button variant="green" block onClick={() => { closePanel(); openPhone('food'); }}>Order on Chowdeck</Button>
      </div>
    );
  }

  const count = items.reduce((n, i) => n + i.qty, 0);
  return (
    <div className="bag stack">
      <p className="bag__lead">
        {count} {count === 1 ? 'thing' : 'things'} in your Bag.
        {sellHere ? ' Traders here buy things back for part of the price.' : ' Sell things back at any market.'}
      </p>
      {groups.map((g) => (
        <section key={g.id} className="shop__group">
          <h4 className="shop__cat">{g.label}</h4>
          <div className="items">
            {g.items.map((it) => (
              <Row key={it.id} it={it} sellHere={sellHere} busyNow={busyNow} busy={busy}
                onUse={(id) => void run(`use:${id}`, () => itemUse(id))}
                onSell={(id) => void run(`sell:${id}`, () => itemSell(id, 1))} />
            ))}
          </div>
        </section>
      ))}
      <Button variant="ghost" block onClick={() => { closePanel(); openPhone('food'); }}>Hungry? Order on Chowdeck</Button>
    </div>
  );
}
