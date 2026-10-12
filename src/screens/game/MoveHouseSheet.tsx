// H1: "Move into your new <house>?" Confirm sheet after picking a home in the phone's Houses app. Yes rents it
// and moves in at once (house_move): furniture comes along, the old place is gone for good, the garage stays
// behind. The player then arrives home and walks in from the door (Game.tsx arrivalKey).
import { useState } from 'react';
import { houseMove } from '../../api/houses';
import { errorMessage } from '../../lib/api';
import { naira, nairaShort } from '../../lib/format';
import { useGame } from '../../state/game';
import { useGarage } from '../../state/garage';
import { useMove } from '../../state/move';
import { Button, Sheet, toast } from '../../ui';

export function MoveHouseSheet() {
  const pick = useMove((s) => s.pick);
  const close = useMove((s) => s.close);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState(false);
  const h = pick?.home ?? null;

  const move = async () => {
    if (!h) return;
    setBusy(true);
    try {
      const r = await houseMove(h.id);
      toast(r.came_with ? `${r.message} It came with ${r.came_with} ${r.came_with === 1 ? 'piece' : 'pieces'} of furniture: they are yours now.` : r.message, 'good');
      close();
      await refresh();
      useGarage.getState().bump();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={Boolean(pick)} onClose={busy ? () => {} : close} className="move-sheet"
      title={h ? `Move into your new ${h.name.toLowerCase()}?` : 'Move house?'}
      subtitle={h ? [h.district, `${h.area} m²`].filter(Boolean).join(' · ') : undefined}
      footer={
        <div className="garage-sheet__foot">
          <Button block variant="green" loading={busy} disabled={!h} onClick={() => void move()}>
            {h ? `Yes, move in · ${nairaShort(h.move_in)}` : 'Yes, move in'}
          </Button>
          <Button block variant="ghost" disabled={busy} onClick={close}>Not now</Button>
        </div>
      }>
      {h && (
        <div className="move-sheet__body">
          <div className="move-sheet__home">
            <span className="garage-opt__emoji" aria-hidden>{h.emoji || '🏠'}</span>
            <span className="grow">
              <span className="garage-opt__title">{h.name}</span>
              <span className="garage-opt__sub">{h.description}</span>
            </span>
          </div>
          <div className="rent-rows">
            <div className="bank-row"><span>Move-in fee ({pick?.weeks} weeks rent)</span><b title={naira(h.move_in)}>{naira(h.move_in)}</b></div>
            <div className="bank-row"><span>Weekly rent after</span><b>{naira(h.weekly_rent)}</b></div>
          </div>
          <p className="move-sheet__info">
            All your furniture and items will be moved to your new home. You can't go back to your old place.
          </p>
          {pick?.garage && (
            <p className="move-sheet__info move-sheet__info--warn">
              Your {pick.garage.toLowerCase()} stays behind; build a new one here. Your cars come with you.
            </p>
          )}
          <p className="move-sheet__note">Paid from your bank first, then cash.</p>
        </div>
      )}
    </Sheet>
  );
}
