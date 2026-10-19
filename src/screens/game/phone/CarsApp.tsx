// Phone "Cars": pick a dealer, compare prices, travel there and buy; My cars lists owned vehicles with Sell.
// H2: dealers have tiers (budget Tokunbo lot / standard dealer / premium showroom) and charge base x
// multiplier (server bl_dealer_price); luxury cars are only at the premium showroom. docs/GARAGE.md
import { useEffect, useMemo, useState } from 'react';
import { shopBuy, shopList } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { dealerPrice, TIER_LABEL, useDealers } from '../../../lib/dealers';
import { naira, nairaShort } from '../../../lib/format';
import type { GameState, ShopItem, ShopList } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { EmptyState, toast } from '../../../ui';
import { ItemCard } from '../../../panels/shop/ShopUI';
import { SellCarButton } from '../SellCar';
import { Thumb } from '../../../art/thumbs/Thumb';
import { taxNote } from '../../../lib/tax';

export default function CarsApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const locations = useGame((s) => s.locations);
  const refresh = useGame((s) => s.refresh);
  const dealerRows = useDealers();
  const dealers = useMemo(() => {
    const list = locations.filter((l) => l.scene === 'car_dealer');
    const order = (id: string) => dealerRows.find((d) => d.location_id === id)?.sort ?? 999;
    return [...list].sort((a, b) => order(a.id) - order(b.id));
  }, [locations, dealerRows]);
  const [dealerId, setDealerId] = useState('');
  const [catalog, setCatalog] = useState<ShopList | null>(null);
  const [error, setError] = useState('');
  const [buying, setBuying] = useState<string | null>(null);
  useEffect(() => {
    if (!dealerId && dealers.length) setDealerId(dealers[0].id);
  }, [dealerId, dealers]);
  useEffect(() => {
    if (!dealerId) return;
    let alive = true;
    setCatalog(null);
    shopList(dealerId).then((r) => { if (alive) { setCatalog(r); setError(''); } })
      .catch((e) => { if (alive) setError(errorMessage(e)); });
    return () => { alive = false; };
  }, [dealerId]);
  const here = state.profile.location_id === dealerId && !state.travel;
  const inventory = state.inventory ?? [];
  const mine = inventory.filter((i) => i.category === 'vehicle' && i.qty > 0).sort((a, b) => b.price - a.price);
  const cars = (catalog?.items ?? []).filter((item) => item.category === 'vehicle');
  const tierOf = (id: string) => dealerRows.find((d) => d.location_id === id);
  const dealer = catalog?.dealer ?? null;
  const buy = async (item: ShopItem) => {
    if (!here) { onGo(dealerId); return; }
    setBuying(item.id);
    try {
      const result = await shopBuy(item.id);
      toast(result.message, 'good');
      await refresh();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBuying(null); }
  };

  /** "Tokunbo Lot ₦2.2M · SDD ₦3M" for the other dealers that stock it. */
  const elsewhere = (item: ShopItem) => {
    const base = item.base_price ?? item.price;
    return (item.sold_at ?? [])
      .filter((id) => id !== dealerId)
      .map((id) => {
        const d = tierOf(id);
        const loc = dealers.find((l) => l.id === id);
        if (!loc) return null;
        return { id, name: loc.name, price: d ? dealerPrice(base, d.multiplier) : base, tier: d?.tier };
      })
      .filter((x): x is { id: string; name: string; price: number; tier: 'budget' | 'mid' | 'premium' | undefined } => x !== null);
  };

  if (!dealers.length) return <div className="phone-app__body"><EmptyState icon="car" title="No dealership available" body="Dealership locations are still loading. Try again in a moment." /></div>;
  return (
    <div className="phone-app__body cars-app">
      {mine.length > 0 && (
        <section className="cars-mine">
          <h4 className="cars-mine__title">My cars</h4>
          {mine.map((c) => (
            <div key={c.id} className="cars-mine__row">
              <Thumb spec={{ type: 'car', id: c.id }} fallback={c.icon || '🚗'} className="cars-mine__thumb" />
              <span className="grow">
                <span className="cars-mine__name">{c.name}</span>
                <span className="cars-mine__sub">List price {nairaShort(c.price)}</span>
              </span>
              <SellCarButton car={{ id: c.id, name: c.name, price: c.price }} icon={c.icon} />
            </div>
          ))}
        </section>
      )}
      <p className="phone-app__lead">Pick a dealer, travel there, then buy. Tokunbo lots are cheapest; the official showroom costs more but is the only place with the luxury cars. Bank first, then cash.</p>
      <div className="cars-dealers" role="radiogroup" aria-label="Dealership">
        {dealers.map((d) => {
          const t = tierOf(d.id);
          return (
            <button key={d.id} type="button" role="radio" aria-checked={dealerId === d.id}
              className={`cars-dealer${dealerId === d.id ? ' is-on' : ''}`} onClick={() => setDealerId(d.id)}>
              <span className="cars-dealer__name">{d.name}</span>
              {t && <span className={`dealer-tier dealer-tier--${t.tier}`}>{TIER_LABEL[t.tier]}{t.multiplier !== 1 ? ` · ${t.multiplier < 1 ? '−' : '+'}${Math.round(Math.abs(t.multiplier - 1) * 100)}%` : ''}</span>}
            </button>
          );
        })}
      </div>
      {dealer && (
        <div className={`cars-banner cars-banner--${dealer.tier}`}>
          <span className={`dealer-tier dealer-tier--${dealer.tier}`}>{dealer.label || TIER_LABEL[dealer.tier]}</span>
          <span className="cars-banner__blurb">{dealer.blurb}</span>
        </div>
      )}
      {error && <p className="error-text">{error}</p>}
      {!catalog && !error && <div className="panel-skel"><span /><span /></div>}
      {catalog && !cars.length && <EmptyState icon="car" title="No cars at this dealer" body="Check another showroom." />}
      {cars.map((item) => {
        const owned = inventory.find((i) => i.id === item.id)?.qty ?? 0;
        const enough = state.profile.cash + state.profile.bank >= item.price;
        const blocked = owned ? 'Already owned' : !enough ? `Need ${naira(item.price)}` : null;
        return <CarBuyCard key={item.id} item={item} owned={owned} here={here} blocked={blocked} others={elsewhere(item)}
          exclusive={(item.sold_at ?? []).length === 1 && dealer?.tier === 'premium'}
          busy={buying === item.id} onBuy={() => void buy(item)} onGo={() => onGo(dealerId)} />;
      })}
    </div>
  );
}

function CarBuyCard({ item, owned, here, blocked, busy, others, exclusive, onBuy, onGo }: {
  item: ShopItem; owned: number; here: boolean; blocked: string | null; busy: boolean;
  others: { id: string; name: string; price: number; tier?: string }[]; exclusive: boolean;
  onBuy: () => void; onGo: () => void;
}) {
  const [confirm, setConfirm] = useState(false);
  useEffect(() => { setConfirm(false); }, [here]);
  const base = item.base_price ?? item.price;
  const diff = item.price - base;
  return <ItemCard item={item} price={item.price} taxNote={taxNote(item.vat_pct ?? 0, item.lux_pct ?? 0)} owned={owned} kind={item.kind} blocked={blocked}
    busy={busy} action={here ? (confirm ? 'Confirm purchase' : 'Review purchase') : 'Go to dealer'}
    onAction={() => { if (!here) { onGo(); return; } if (!confirm) { setConfirm(true); return; } setConfirm(false); onBuy(); }}
    extra={
      <span className="cars-app__extra">
        {(diff !== 0 || exclusive) && (
          <span className="cars-app__pricing">
            {diff !== 0 && <span className={`cars-app__diff${diff < 0 ? ' is-cheap' : ''}`}>{diff < 0 ? `${nairaShort(-diff)} below list` : `${nairaShort(diff)} above list`}</span>}
            {exclusive && <span className="cars-app__excl">Only at the showroom</span>}
          </span>
        )}
        {others.length > 0 && (
          <span className="cars-app__compare">Elsewhere: {others.map((o) => `${o.name} ${nairaShort(o.price)}`).join(' · ')}</span>
        )}
        <span className="cars-app__hint">{!here ? 'Buy in person at the selected dealership.' : confirm ? `Confirm ${item.name} for ${naira(item.price)}? Bank is used first.` : 'Vehicle purchases use bank first, then cash.'}</span>
      </span>
    } />;
}
