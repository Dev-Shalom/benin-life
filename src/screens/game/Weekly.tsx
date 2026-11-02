// "This week in Benin" (docs/DAILY_RETURN.md part 3): the calendar sheet and its sync.
// The slim banner on the day lives in EventBanner (src/screens/game/Events.tsx) so the two never fight for the same slot.
import { useEffect, useState } from 'react';
import { errorMessage } from '../../lib/api';
import { canPoll } from '../../lib/activity';
import { useConfig } from '../../lib/config';
import { naira } from '../../lib/format';
import { useUi } from '../../state/ui';
import { useWeekly, type WeeklyDay } from '../../state/weekly';
import { Button, Sheet, toast } from '../../ui';
import './Weekly.css';

const DAY = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/** Keeps the calendar fresh: on mount, on tab focus and every 10 minutes while visible (one cheap call). */
export function WeeklySync() {
  const load = useWeekly((s) => s.load);
  const { cfg } = useConfig();
  const on = cfg('weekly.enabled', true);
  useEffect(() => {
    if (!on) return;
    void load();
    const id = window.setInterval(() => { if (canPoll()) void load(); }, 10 * 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [load, on]);
  return null;
}

function goTo(placeId: string | null) {
  const ui = useUi.getState();
  ui.setMapOpen(true);
  if (placeId) ui.select(placeId);
}

function Row({ d, onClose }: { d: WeeklyDay; onClose: () => void }) {
  const checkin = useWeekly((s) => s.checkin);
  const [busy, setBusy] = useState(false);
  const e = d.event;
  const run = async () => {
    setBusy(true);
    try {
      const r = await checkin();
      toast(r.message, 'good');
    } catch (err) {
      toast(errorMessage(err), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <li className={`wk-row${d.today ? ' is-today' : ''}${d.past ? ' is-past' : ''}${e ? '' : ' is-empty'}`}>
      <div className="wk-row__day">
        <b>{DAY[d.weekday].slice(0, 3)}</b>
        {d.today && <span className="wk-today">Today</span>}
      </div>
      {e ? (
        <div className="wk-row__main">
          <p className="wk-row__title"><span aria-hidden>{e.icon}</span> {e.title}</p>
          <p className="wk-row__blurb">{e.blurb}</p>
          <div className="wk-row__meta">
            {e.reward && <span className="wk-chip">{e.reward}</span>}
            {e.where && <span className="wk-chip wk-chip--soft">{e.where}</span>}
          </div>
          {e.winners && e.winners.length > 0 && (
            <ol className="wk-winners">
              {e.winners.map((w) => <li key={w.rank}><span aria-hidden>{['🥇', '🥈', '🥉'][w.rank - 1] ?? '🏅'}</span> @{w.username} <b>{naira(w.total)}</b></li>)}
            </ol>
          )}
          {d.today && e.checkin && (
            e.checked_in
              ? <p className="wk-done">✅ You checked in today</p>
              : <Button size="md" variant="green" block loading={busy} onClick={() => void run()}>Check in{e.where ? ` (${e.where})` : ''}</Button>
          )}
          {d.today && !e.checkin && e.place_id && (
            <Button size="md" variant="ghost" block onClick={() => { onClose(); goTo(e.place_id); }}>Go to {e.where ?? 'the place'}</Button>
          )}
        </div>
      ) : (
        <p className="wk-row__quiet">A quiet day. Hustle, rest, explore.</p>
      )}
    </li>
  );
}

export function WeeklySheet() {
  const open = useWeekly((s) => s.open);
  const setOpen = useWeekly((s) => s.setOpen);
  const cal = useWeekly((s) => s.cal);
  const load = useWeekly((s) => s.load);
  useEffect(() => { if (open) void load(); }, [open, load]);
  return (
    <Sheet open={open} onClose={() => setOpen(false)} title="This week in Benin" subtitle="Something on most days. Come back for it." size="tall" className="wk-sheet">
      {!cal && <div className="panel-skel"><span /><span /></div>}
      {cal && !cal.enabled && <p className="wk-quiet">Weekly events are paused. Check back soon.</p>}
      {cal?.enabled && <ul className="wk-list">{cal.days.map((d) => <Row key={d.date} d={d} onClose={() => setOpen(false)} />)}</ul>}
    </Sheet>
  );
}

export function WeeklyHost() {
  return (
    <>
      <WeeklySync />
      <WeeklySheet />
    </>
  );
}
