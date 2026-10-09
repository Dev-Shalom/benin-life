import { useEffect, useMemo, useState } from 'react';
import { shopBuy, shopList } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { naira } from '../../../lib/format';
import type { GameState, ShopItem, ShopList } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { EmptyState, toast } from '../../../ui';
import { ItemCard } from '../../../panels/shop/ShopUI';

export default function CarsApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const locations = useGame((s) => s.locations);
  const refresh = useGame((s) => s.refresh);
  const dealers = useMemo(() => locations.filter((l) => l.scene === 'car_dealer'), [locations]);
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
    shopList(dealerId).then((r) => { if (alive) { setCatalog(r); setError(''); } })
      .catch((e) => { if (alive) setError(errorMessage(e)); });
    return () => { alive = false; };
  }, [dealerId]);
  const here = state.profile.location_id === dealerId && !state.travel;
  const inventory = state.inventory ?? [];
  const cars = (catalog?.items ?? []).filter((item) => item.category === 'vehicle');
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

  if (!dealers.length) return <div className="phone-app__body"><EmptyState icon="car" title="No dealership available" body="Dealership locations are still loading. Try again in a moment." /></div>;
  return (
    <div className="phone-app__body cars-app">
      <p className="phone-app__lead">Pick a dealer, travel there, then buy a vehicle. Purchases use your bank first, then cash. A vehicle unlocks “Your car” in Ride.</p>
      <label className="cars-app__dealer">Dealership
        <select value={dealerId} onChange={(e) => setDealerId(e.target.value)}>
          {dealers.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
      </label>
      {error && <p className="error-text">{error}</p>}
      {!catalog && !error && <div className="panel-skel"><span /><span /></div>}
      {catalog && !cars.length && <EmptyState icon="car" title="No cars at this dealer" body="Check another showroom." />}
      {cars.map((item) => {
        const owned = inventory.find((i) => i.id === item.id)?.qty ?? 0;
        const enough = state.profile.cash + state.profile.bank >= item.price;
        const blocked = owned ? 'Already owned' : !enough ? `Need ${naira(item.price)}` : null;
        return <CarBuyCard key={item.id} item={item} owned={owned} here={here} blocked={blocked}
          busy={buying === item.id} onBuy={() => void buy(item)} onGo={() => onGo(dealerId)} />;
      })}
    </div>
  );
}

function CarBuyCard({ item, owned, here, blocked, busy, onBuy, onGo }: {
  item: ShopItem; owned: number; here: boolean; blocked: string | null; busy: boolean; onBuy: () => void; onGo: () => void;
}) {
  const [confirm, setConfirm] = useState(false);
  useEffect(() => { setConfirm(false); }, [here]);
  return <ItemCard item={item} price={item.price} owned={owned} kind={item.kind} blocked={blocked}
    busy={busy} action={here ? (confirm ? 'Confirm purchase' : 'Review purchase') : 'Go to dealer'}
    onAction={() => { if (!here) { onGo(); return; } if (!confirm) { setConfirm(true); return; } setConfirm(false); onBuy(); }}
    extra={<span className="cars-app__hint">{!here ? 'Buy in person at the selected dealership.' : confirm ? `Confirm ${item.name} for ${naira(item.price)}? Bank is used first.` : 'Vehicle purchases use bank first, then cash.'}</span>} />;
}
