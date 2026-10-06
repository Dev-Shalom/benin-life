// Phone "Houses" app (V1-4): your home, weekly rent, the next rent day, rent owed + Pay now.
// Moving house arrives later.
import { useEffect, useState } from 'react';
import { payRent } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { dateLabel, gameClockAt, useNow, weekdayOf } from '../../../lib/clock';
import { clockTime, naira, realDuration } from '../../../lib/format';
import { WEEKDAYS } from '../../../lib/pidgin';
import type { GameState } from '../../../lib/types';
import { useCatalog } from '../../../state/catalog';
import { useGame } from '../../../state/game';
import { Button, toast } from '../../../ui';

export default function HousesApp({ state }: { state: GameState }) {
  const refresh = useGame((s) => s.refresh);
  const byId = useGame((s) => s.locationsById);
  const catalog = useCatalog((s) => s.catalog);
  const loadCatalog = useCatalog((s) => s.loadCatalog);
  const now = useNow(15_000);
  const [paying, setPaying] = useState(false);
  useEffect(() => {
    void loadCatalog();
  }, [loadCatalog]);

  const p = state.profile;
  const rent = state.rent;
  const home = catalog?.homes.find((h) => h.id === p.start_home);
  const loc = byId[p.home_location_id];
  const weekly = rent?.weekly ?? p.weekly_rent;
  const owed = rent?.owed ?? p.rent_owed;
  const dueMs = rent?.due_at ? Date.parse(rent.due_at) : NaN;
  const due = Number.isNaN(dueMs) ? null : gameClockAt(dueMs);
  const enabled = rent?.enabled ?? false;
  const sleepPct = rent?.owed_sleep_pct ?? 60;

  const pay = async () => {
    setPaying(true);
    try {
      const r = await payRent();
      toast(r.message, r.owed > 0 ? 'info' : 'good');
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setPaying(false);
    }
  };

  return (
    <div className="phone-app__body houses">
      <div className="house-card">
        <span className="house-card__emoji" aria-hidden>{home?.emoji ?? '🏠'}</span>
        <div className="grow">
          <div className="house-card__label">Your home</div>
          <div className="house-card__name">{home?.name ?? loc?.name ?? 'Your place'}</div>
          {loc && home && <div className="house-card__sub">{loc.name}</div>}
        </div>
      </div>

      {owed > 0 && (
        <section className="rent-owed" role="alert">
          <div className="rent-owed__top">
            <span aria-hidden>🚪</span>
            <div className="grow">
              <div className="rent-owed__title">You owe {naira(owed)} rent</div>
              <div className="rent-owed__body">
                The landlord keeps knocking: "Where my money?" Sleep gives only {sleepPct}% energy until you pay.
              </div>
            </div>
          </div>
          <Button variant="green" block loading={paying} disabled={p.cash + p.bank <= 0} onClick={() => void pay()}>
            {p.cash + p.bank <= 0 ? 'No money to pay yet'
              : p.cash + p.bank >= owed ? `Pay ${naira(owed)} now` : `Pay ${naira(p.cash + p.bank)} now (part)`}
          </Button>
          <p className="rent-owed__note">Paid from your bank first, then cash.</p>
        </section>
      )}

      <div className="rent-rows">
        <div className="bank-row"><span>Weekly rent</span><b>{weekly > 0 ? naira(weekly) : 'None'}</b></div>
        {weekly > 0 && due && (
          <div className="bank-row">
            <span>Next rent day</span>
            <b className="rent-rows__due">
              {WEEKDAYS[weekdayOf(due)]}, {dateLabel(due)} · {clockTime(due.hour, due.minute)}
              <span>in about {realDuration(Math.max(0, (dueMs - now) / 1000))} real time</span>
            </b>
          </div>
        )}
        <div className="bank-row"><span>Rent owed</span><b className={owed > 0 ? 'is-bad' : 'is-good'}>{owed > 0 ? naira(owed) : 'All paid ✓'}</b></div>
      </div>
      <p className="phone-app__lead">
        {weekly <= 0 ? 'You pay no rent here.'
          : enabled ? `Rent is collected every ${WEEKDAYS[catalog?.rent_weekday ?? 5]} at midnight, from your bank first, then cash. If you can't cover it, the rest becomes rent owed.`
            : 'Rent collection is paused right now.'}
      </p>
      <div className="soon-card">
        <span className="soon-card__emoji" aria-hidden>🔑</span>
        <div>
          <div className="soon-card__title">Moving house arrives soon</div>
          <div className="soon-card__text">Rent a bigger place, from a self-contain in Uselu to a duplex in GRA.</div>
        </div>
      </div>
    </div>
  );
}
