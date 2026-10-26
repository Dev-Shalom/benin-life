// H1: "Move into your new <house>?" Confirm sheet after picking a home in the phone's Houses app. Yes rents it
// and moves in at once (house_move): furniture comes along. Own your home: the old place waits in Past homes (move back within
// house.return_days, upgrades and garage stay with it). The player then arrives home and walks in from the door (Game.tsx arrivalKey).
import { useState } from 'react';
import { houseMove } from '../../api/houses';
import { errorMessage } from '../../lib/api';
import { naira, nairaShort } from '../../lib/format';
import { useGame } from '../../state/game';
import { useGarage } from '../../state/garage';
import { useMove } from '../../state/move';
import { useProperty } from '../../state/property';
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
      void useProperty.getState().load();
      useGarage.getState().bump();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={Boolean(pick)} onClose={busy ? () => {} : close} className="move-sheet"
      title={h ? (h.status === 'past' ? `Move back into your ${h.name.toLowerCase()}?` : `Move into your new ${h.name.toLowerCase()}?`) : 'Move house?'}
      subtitle={h ? [h.district, `${h.area} m²`].filter(Boolean).join(' · ') : undefined}
      footer={
        <div className="garage-sheet__foot">
          <Button block variant="green" loading={busy} disabled={!h} onClick={() => void move()}>
            {h ? `${h.status === 'past' ? 'Yes, move back' : 'Yes, move in'} · ${nairaShort(h.move_in)}` : 'Yes, move in'}
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
            {h.status === 'past'
              ? `This is one of your past homes. Your furniture comes along and goes back where it stood, and your upgrades${h.past_upgrades > 0 ? ` (${h.past_upgrades})` : ''} are still there.`
              : 'All your furniture and items will be moved to your new home. Your old place stays in Past homes, so you can move back for a while.'}
          </p>
          {pick?.garage && (
            <p className="move-sheet__info move-sheet__info--warn">
              Your {pick.garage.toLowerCase()} stays with the old home (it is there when you move back). Your cars come with you.
            </p>
          )}
          {h.status !== 'past' && (
            <p className="move-sheet__info">Upgrades you built stay with the old home too. They are only sold if you give that home up or its Past homes days run out.</p>
          )}
          <p className="move-sheet__note">Paid from your bank first, then cash.</p>
        </div>
      )}
    </Sheet>
  );
}
