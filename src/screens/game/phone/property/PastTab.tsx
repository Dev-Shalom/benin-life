// Houses -> Past homes: the homes you moved out of. For house.return_days you can move back (normal move-in fee) and your upgrades and
// furniture spots are still there. When the days run out, or you give the home up, the upgrades are paid out at the resale %.
import { useState } from 'react';
import type { HouseOption, HouseOptions } from '../../../../api/houses';
import { housePastRelease } from '../../../../api/property';
import { errorMessage } from '../../../../lib/api';
import { useNow } from '../../../../lib/clock';
import { naira, nairaShort } from '../../../../lib/format';
import { useMove } from '../../../../state/move';
import { useProperty } from '../../../../state/property';
import { useUi } from '../../../../state/ui';
import { Button, EmptyState, Sheet, toast } from '../../../../ui';
import { daysLeft } from './util';

export default function PastTab({ opts, owed, visiting, onChanged }: { opts: HouseOptions | null; owed: number; visiting: boolean; onChanged: () => void }) {
  const now = useNow(60_000);
  const openMove = useMove((s) => s.open);
  const afterAction = useProperty((s) => s.afterAction);
  const [giveUp, setGiveUp] = useState<HouseOption | null>(null);
  const [busy, setBusy] = useState(false);
  const past = (opts?.homes ?? []).filter((h) => h.status === 'past').sort((a, b) => Date.parse(a.past_until ?? '') - Date.parse(b.past_until ?? ''));

  const release = async () => {
    if (!giveUp) return;
    setBusy(true);
    try {
      const r = await housePastRelease(giveUp.id);
      toast(r.message, 'info');
      setGiveUp(null);
      onChanged();
      await afterAction();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  if (!opts) return <div className="pp-tab"><div className="panel-skel"><span /><span /></div></div>;
  if (past.length === 0) {
    return (
      <div className="pp-tab" data-testid="prop-past">
        <EmptyState icon="clock" title="No past homes" body={`When you move out of a rented home it waits here for ${opts.return_days} days. You can move back, and your upgrades are still there.`} />
      </div>
    );
  }
  return (
    <div className="pp-tab" data-testid="prop-past">
      <p className="pp-lead">
        A home you left stays here for {opts.return_days} days. Move back for the normal move-in fee and your upgrades and furniture spots come back.
        After that, or if you give it up, the upgrades are sold and paid into your bank. Homes you own are never lost.
      </p>
      <div className="pp-list">
        {past.map((h) => (
          <div key={h.id} className="pp-prop is-open">
            <div className="pp-card pp-card--flat">
              <span className="pp-card__icon" aria-hidden>{h.emoji || '🏠'}</span>
              <span className="pp-card__main">
                <b>{h.name}{h.district ? ` · ${h.district}` : ''}</b>
                <small>{h.area} m² · {naira(h.weekly_rent)} a week</small>
                <span className="pp-tags">
                  <span className="pp-tag is-warn">{daysLeft(h.past_until, now)}</span>
                  {h.past_upgrades > 0 && <span className="pp-tag is-good">{h.past_upgrades} upgrade{h.past_upgrades === 1 ? '' : 's'} waiting</span>}
                </span>
              </span>
              <span className="pp-card__price" title={naira(h.move_in)}>{nairaShort(h.move_in)}<small>to move back</small></span>
            </div>
            <div className="pp-prop__body">
              <div className="pp-actions">
                <Button size="sm" variant="green" disabled={!opts.enabled || visiting || owed > 0 || h.status !== 'past'}
                  onClick={() => { openMove(h, opts.garage?.name ?? null, opts.move_in_weeks); useUi.getState().setOverlay(null); }}>Move back</Button>
                <Button size="sm" variant="ghost" onClick={() => setGiveUp(h)}>{h.past_value > 0 ? `Give up · get ${nairaShort(h.past_value)}` : 'Give up'}</Button>
              </div>
              {(owed > 0 || visiting) && <p className="pp-hint">{owed > 0 ? 'Pay the rent you owe first.' : 'Go home first.'}</p>}
            </div>
          </div>
        ))}
      </div>
      <Sheet open={Boolean(giveUp)} onClose={busy ? () => {} : () => setGiveUp(null)} title="Give up this past home?" subtitle={giveUp?.name}
        footer={<div className="garage-sheet__foot">
          <Button block variant="danger" loading={busy} onClick={() => void release()}>Give it up</Button>
          <Button block variant="ghost" disabled={busy} onClick={() => setGiveUp(null)}>Keep it</Button>
        </div>}>
        <p className="pp-hint">
          You can't move back for free after this. {giveUp && giveUp.past_value > 0 ? `Your ${giveUp.past_upgrades} upgrade${giveUp.past_upgrades === 1 ? '' : 's'} there will be sold: ${naira(giveUp.past_value)} into your bank.` : 'There are no upgrades to sell.'}
        </p>
      </Sheet>
    </div>
  );
}
