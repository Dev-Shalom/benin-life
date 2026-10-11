// H2: sell a car back (Phone → Cars → My cars and the garage sheet). Confirm dialog shows the payout:
// cars.resale_pct of the base price, paid into the bank by car_sell. Refused on the road / busy (server).
import { useState } from 'react';
import { carSell } from '../../api/shops';
import { errorMessage } from '../../lib/api';
import { getCfg } from '../../lib/config';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useGarage } from '../../state/garage';
import { Thumb } from '../../art/thumbs/Thumb';
import { Button, Modal, toast } from '../../ui';

export function carPayout(base: number): number {
  const pct = Math.max(0, Math.min(100, Number(getCfg('cars.resale_pct', 60))));
  return Math.floor((base * pct) / 100 / 1000) * 1000;
}

export function SellCarButton({ car, icon, size = 'sm', onSold }: {
  car: { id: string; name: string; price: number };
  icon?: string | null;
  size?: 'sm' | 'md';
  onSold?: () => void;
}) {
  const [ask, setAsk] = useState(false);
  const [busy, setBusy] = useState(false);
  const traveling = useGame((s) => Boolean(s.state?.travel));
  const pay = carPayout(car.price);
  const pct = Math.round(Number(getCfg('cars.resale_pct', 60)));
  const sell = async () => {
    setBusy(true);
    try {
      const r = await carSell(car.id);
      toast(r.message, 'good');
      setAsk(false);
      await useGame.getState().refresh();
      useGarage.getState().bump();
      onSold?.();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <Button size={size} variant="ghost" disabled={traveling} onClick={() => setAsk(true)}
        title={traveling ? 'You can sell when you arrive' : undefined}>Sell</Button>
      <Modal open={ask} onClose={() => !busy && setAsk(false)} title={`Sell your ${car.name}?`}
        art={<Thumb spec={{ type: 'car', id: car.id }} fallback={<span className="sell-dialog__emoji">{icon || '🚗'}</span>} className="sell-dialog__thumb" />}
        actions={
          <>
            <Button variant="ghost" disabled={busy} onClick={() => setAsk(false)}>Keep it</Button>
            <Button variant="gold" loading={busy} onClick={() => void sell()}>Sell for {naira(pay)}</Button>
          </>
        }>
        <div className="sell-dialog">
          <div className="sell-dialog__row"><span>List price</span><span>{naira(car.price)}</span></div>
          <div className="sell-dialog__row"><span>Dealer buys back at</span><span>{pct}%</span></div>
          <div className="sell-dialog__row sell-dialog__row--total"><span>You get (into your bank)</span><b>{naira(pay)}</b></div>
          <p className="sell-dialog__note">The car leaves your garage for good. Your garage stays.</p>
        </div>
      </Modal>
    </>
  );
}
