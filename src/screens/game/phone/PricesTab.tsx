// Prices tab of the Chowdeck app (step C, docs/COOKING.md): today's grocery prices at Oba Market (they change a little each Benin day,
// computed by the server) and at Edo Fresh Supermarket (fixed, always open), with the move since yesterday.
import { useEffect, useMemo, useState } from 'react';
import { groceryPrices, type GroceryItem, type GroceryPrices } from '../../../api/cooking';
import { errorMessage } from '../../../lib/api';
import { naira } from '../../../lib/format';
import { useUi } from '../../../state/ui';
import { Button } from '../../../ui';
import './CookingApp.css';

type Filter = 'all' | 'down' | 'up';

function Trend({ pct }: { pct: number }) {
  if (Math.abs(pct) < 0.05) return <span className="ck-trend is-flat" aria-label="Same as yesterday">– same</span>;
  const up = pct > 0;
  return <span className={`ck-trend ${up ? 'is-up' : 'is-down'}`} aria-label={`${up ? 'Up' : 'Down'} ${Math.abs(pct)} percent since yesterday`}>{up ? '▲' : '▼'} {Math.abs(pct).toFixed(1)}%</span>;
}

function Row({ it }: { it: GroceryItem }) {
  const save = it.super - it.today;
  return (
    <li className="ck-price" data-testid={`price-${it.id}`}>
      <span className="ck-price__emoji" aria-hidden>{it.icon ?? '🥣'}</span>
      <span className="ck-price__main">
        <b>{it.name}</b>
        <small>Yesterday {naira(it.yesterday)}{it.owned > 0 ? ` · you have ${it.owned}` : ''}</small>
      </span>
      <span className="ck-price__nums">
        <b className="ck-price__today">{naira(it.today)}</b>
        <Trend pct={it.change_pct} />
      </span>
      <span className="ck-price__super">
        <small>Supermarket</small>
        <b>{naira(it.super)}</b>
        {save > 0 && <small className="ck-save">save {naira(save)}</small>}
      </span>
    </li>
  );
}

export default function PricesTab() {
  const [g, setG] = useState<GroceryPrices | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  useEffect(() => {
    let alive = true;
    groceryPrices()
      .then((x) => alive && (setG(x), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => { alive = false; };
  }, []);
  const rows = useMemo(() => {
    const items = g?.items ?? [];
    const f = filter === 'down' ? items.filter((i) => i.change_pct < -0.05) : filter === 'up' ? items.filter((i) => i.change_pct > 0.05) : items;
    return [...f].sort((a, b) => (filter === 'all' ? 0 : filter === 'down' ? a.change_pct - b.change_pct : b.change_pct - a.change_pct));
  }, [g, filter]);
  const go = (id: string) => {
    const ui = useUi.getState();
    ui.closeAll();
    ui.setMapOpen(true);
    ui.select(id);
  };
  if (!g && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (!g) return <p className="phone-app__lead">{err}</p>;
  const downN = g.items.filter((i) => i.change_pct < -0.05).length;
  const upN = g.items.filter((i) => i.change_pct > 0.05).length;
  return (
    <div className="ck" data-testid="prices">
      <section className="ck-places">
        <div className={`ck-place${g.market.open_now ? ' is-open' : ' is-closed'}`}>
          <b>🧺 {g.market.name}</b>
          <small>{g.market.hours}</small>
          <span className="ck-pill">{g.market.open_now ? 'Open now' : 'Closed now'}</span>
          <Button size="sm" variant={g.market.open_now ? 'green' : 'ghost'} onClick={() => go(g.market.id)}>Go there</Button>
        </div>
        <div className="ck-place is-open">
          <b>🛒 {g.supermarket.name}</b>
          <small>{g.supermarket.hours}</small>
          <span className="ck-pill">Fixed price</span>
          <Button size="sm" variant="ghost" onClick={() => go(g.supermarket.id)}>Go there</Button>
        </div>
      </section>
      <p className="ck-fine ck-fine--top">
        Oba Market prices move up to {Math.round(g.band_pct)}% each Benin day and are the same for everybody. The supermarket costs {Math.round(g.markup_pct)}% more than the base price and never changes.
      </p>
      <div className="ck-filter" role="tablist" aria-label="Filter prices">
        {([['all', `All ${g.items.length}`], ['down', `▼ Dropped ${downN}`], ['up', `▲ Rose ${upN}`]] as [Filter, string][]).map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={filter === id} className={`ck-fchip${filter === id ? ' is-on' : ''}`} onClick={() => setFilter(id)}>{label}</button>
        ))}
      </div>
      {rows.length === 0 ? <p className="ck-empty">Nothing here today.</p> : <ul className="ck-prices">{rows.map((it) => <Row key={it.id} it={it} />)}</ul>}
    </div>
  );
}
