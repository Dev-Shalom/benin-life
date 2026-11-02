// The HUD "Today" card, extra rows (docs/DAILY_RETURN.md part 4). The Today pill and list live in LeftRail (Hud.tsx); this file adds
//   TodaySync     loads today_card() (on mount, every 5 min while visible, on tab focus)
//   useTodayRows  the rows the daily chips do not cover: today's weekly event, the welcome-back gift, a child / rent / takings that need you
//   TodayRows     those rows as the same one-tap chips as the rest of the list, plus "This week in Benin"
import { useEffect, useMemo } from 'react';
import { canPoll } from '../../lib/activity';
import { errorMessage } from '../../lib/api';
import { useConfig } from '../../lib/config';
import { nairaShort } from '../../lib/format';
import { useGame } from '../../state/game';
import { useReturnGift } from '../../state/returnGift';
import { useToday } from '../../state/today';
import { useUi } from '../../state/ui';
import { useWeekly } from '../../state/weekly';
import { toast } from '../../ui';

export function TodaySync() {
  const load = useToday((s) => s.load);
  const { cfg } = useConfig();
  const on = cfg('return.today_enabled', true);
  useEffect(() => {
    if (!on) return;
    void load();
    const id = window.setInterval(() => { if (canPoll()) void load(); }, 5 * 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [load, on]);
  return null;
}

export interface TodayRowsInfo { count: number; icons: string[]; ready: boolean; loaded: boolean; day: string | undefined }

/** How many extra rows, their pill icons, and whether something is ready to collect. */
export function useTodayRows(): TodayRowsInfo {
  const card = useToday((s) => s.card);
  const { cfg } = useConfig();
  return useMemo(() => {
    if (!card || !card.enabled || !cfg('return.today_enabled', true)) return { count: 0, icons: [], ready: false, loaded: Boolean(card), day: card?.date };
    const icons: string[] = [];
    const ev = card.event;
    if (ev) icons.push(ev.icon);
    if (card.gift) icons.push('🎁');
    for (const n of card.needs ?? []) icons.push(n.icon);
    return { count: icons.length, icons, ready: Boolean(card.gift) || Boolean(ev && ev.checkin && !ev.checked_in), loaded: true, day: card.date };
  }, [card, cfg]);
}

export function TodayRows({ onPick }: { onPick?: () => void }) {
  const card = useToday((s) => s.card);
  const loadToday = useToday((s) => s.load);
  const openPhone = useUi((s) => s.openPhone);
  const setWeek = useWeekly((s) => s.setOpen);
  const { cfg } = useConfig();
  if (!card || !card.enabled || !cfg('return.today_enabled', true)) return null;
  const ev = card.event;
  const gift = card.gift;

  const collect = async () => {
    onPick?.();
    try {
      await useReturnGift.getState().claim();
      toast('🎁 Gift don land. Welcome back!', 'good');
      await useGame.getState().refresh();
      void loadToday();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    }
  };

  return (
    <>
      {gift && (
        <button type="button" className="wish-chip wish-chip--daily" onClick={() => void collect()} aria-label="Collect your welcome-back gift">
          <span className="wish-chip__icon" aria-hidden>🎁</span>
          <span className="wish-chip__text">
            <span className="wish-chip__title">Welcome-back gift</span>
            <span className="wish-chip__sub">{nairaShort(gift.cash)}{gift.item_name ? ` + ${gift.item_name}` : ''} · tap to collect</span>
          </span>
          <span className="daily-dot" aria-hidden />
        </button>
      )}
      {ev && (
        <button type="button" className="wish-chip wish-chip--event" onClick={() => { onPick?.(); setWeek(true); }}
          aria-label={`${ev.title} is on today. Open this week in Benin`}>
          <span className="wish-chip__icon" aria-hidden>{ev.icon}</span>
          <span className="wish-chip__text">
            <span className="wish-chip__title">{ev.title} is on</span>
            <span className="wish-chip__sub">{ev.checkin ? (ev.checked_in ? 'You checked in ✓' : `Check in${ev.where ? ` · ${ev.where}` : ''}`) : ev.reward ?? ev.blurb}</span>
          </span>
          {ev.checkin && !ev.checked_in && <span className="daily-dot" aria-hidden />}
        </button>
      )}
      {(card.needs ?? []).map((n) => (
        <button key={n.kind} type="button" className="wish-chip wish-chip--need" onClick={() => { onPick?.(); openPhone(n.go); }} aria-label={`${n.text}. Open`}>
          <span className="wish-chip__icon" aria-hidden>{n.icon}</span>
          <span className="wish-chip__text">
            <span className="wish-chip__title">{n.text}</span>
          </span>
        </button>
      ))}
    </>
  );
}

export function TodayWeekLink({ onPick }: { onPick?: () => void }) {
  const setWeek = useWeekly((s) => s.setOpen);
  const { cfg } = useConfig();
  if (!cfg('weekly.enabled', true)) return null;
  return <button type="button" className="today-week" onClick={() => { onPick?.(); setWeek(true); }}>📅 This week in Benin ›</button>;
}
