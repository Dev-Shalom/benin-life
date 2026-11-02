// New-player journey, "Your first days" (docs/JOURNEY.md).
//   JourneySync    loads journey_status() (mount, every 5 min while visible, on tab focus, after money moves)
//   JourneyCard    the compact card at the top of the Today list: progress bar, the next 1 to 3 steps, Go / Claim
//   JourneySheet   every step by day, locked days shown, the finish prize
//   JourneyFinish  the "you finished" pop-up with the badge
// Everything is counted by the server from real play; this file only shows it and taps Claim.
import { useEffect, useState } from 'react';
import { canPoll } from '../../lib/activity';
import { errorMessage } from '../../lib/api';
import { useConfig } from '../../lib/config';
import { runDeepLink } from '../../lib/deeplink';
import { naira, nairaShort } from '../../lib/format';
import { playCue } from '../../lib/sound';
import { useGame } from '../../state/game';
import { journeySummary, loadJourneySoon, useJourney, type JourneyStep } from '../../state/journey';
import { Button, Modal, Sheet, toast } from '../../ui';
import './Journey.css';

export function JourneySync() {
  const load = useJourney((s) => s.load);
  const { cfg } = useConfig();
  const on = cfg('journey.enabled', true);
  const cash = useGame((s) => s.state?.profile.cash);
  const where = useGame((s) => s.state?.profile.location_id);
  useEffect(() => {
    if (!on) return;
    void load();
    const id = window.setInterval(() => { if (canPoll()) void load(); }, 5 * 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [load, on]);
  // money moved or the player arrived somewhere: a step may have completed (the server re-checks at most every few seconds)
  const nothingToWatch = useJourney((s) => !s.status || !s.status.eligible || s.status.complete);
  useEffect(() => {
    if (!on || nothingToWatch) return;
    const t = window.setTimeout(() => loadJourneySoon(), 2500);
    return () => window.clearTimeout(t);
  }, [on, nothingToWatch, cash, where]);
  return null;
}

/** HUD helper: should the card show, and is something ready to claim? */
export function useJourneyChip() {
  const { cfg } = useConfig();
  const status = useJourney((s) => s.status);
  const sum = journeySummary(status);
  const show = Boolean(sum) && cfg('journey.enabled', true);
  return { show, ready: show && Boolean(sum && sum.claimable > 0), sum };
}

/** Run a step's Go link. Short keys are handled by runDeepLink (src/lib/deeplink.ts). */
function goStep(s: JourneyStep) {
  if (s.go) runDeepLink(s.go);
}

function rewardText(s: JourneyStep): string {
  const parts = [s.reward.cash > 0 ? nairaShort(s.reward.cash) : null, s.reward.item_name ? `${s.reward.qty > 1 ? `${s.reward.qty} x ` : ''}${s.reward.item_name}` : null].filter(Boolean);
  return parts.join(' + ') || 'A small reward';
}

function progressText(s: JourneyStep): string | null {
  if (!s.progress) return null;
  const f = (n: number) => (s.progress!.money ? nairaShort(n) : String(n));
  return `${f(s.progress.have)} of ${f(s.progress.need)}`;
}

/** A small burst of sparkles over a row that was just claimed. */
function Burst() {
  return (
    <span className="jn-burst" aria-hidden>
      {Array.from({ length: 10 }, (_, i) => <i key={i} style={{ ['--a' as string]: `${i * 36}deg`, ['--d' as string]: `${34 + (i % 3) * 10}px` }}>{['✨', '🎉', '⭐'][i % 3]}</i>)}
    </span>
  );
}

function useClaim() {
  const claim = useJourney((s) => s.claim);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState<string | null>(null);
  const run = async (id: string) => {
    if (busy) return;
    setBusy(id);
    try {
      const r = await claim(id);
      playCue('money');
      if (!r.finished) toast(`🎉 ${nairaShort(r.cash)} added${r.item_name ? ` + ${r.item_name}` : ''}`, 'good');
      void refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void useJourney.getState().load();
    } finally {
      setBusy(null);
    }
  };
  return { busy, run };
}

function useJustClaimed(step: string): boolean {
  const c = useJourney((s) => s.celebrate);
  const [on, setOn] = useState(false);
  useEffect(() => {
    if (!c || c.step !== step || Date.now() - c.at > 1600) return;
    setOn(true);
    const t = window.setTimeout(() => setOn(false), 1600);
    return () => window.clearTimeout(t);
  }, [c, step]);
  return on;
}

function CardRow({ s, busy, onClaim, onGo }: { s: JourneyStep; busy: boolean; onClaim: (id: string) => void; onGo: (s: JourneyStep) => void }) {
  const done = s.state === 'done';
  const sub = done ? `Done! ${rewardText(s)}` : progressText(s) ?? rewardText(s);
  return (
    <div className={`jn-row${done ? ' is-done' : ''}`} data-testid={`journey-row-${s.id}`}>
      <span className="jn-row__icon" aria-hidden>{done ? '✅' : s.icon}</span>
      <span className="jn-row__text">
        <span className="jn-row__title">{s.title}</span>
        <span className="jn-row__sub">{sub}</span>
      </span>
      {done ? (
        <button type="button" className="jn-btn jn-btn--claim" onClick={() => onClaim(s.id)} disabled={busy} aria-label={`Claim ${rewardText(s)} for ${s.title}`}>Claim</button>
      ) : s.go ? (
        <button type="button" className="jn-btn" onClick={() => onGo(s)} aria-label={`Go: ${s.title}`}>Go</button>
      ) : null}
    </div>
  );
}

export function JourneyCard({ onPick }: { onPick?: () => void }) {
  const { show, sum } = useJourneyChip();
  const setSheet = useJourney((s) => s.setSheet);
  const { busy, run } = useClaim();
  if (!show || !sum) return null;
  const left = sum.total - sum.claimed;
  return (
    <section className="jn-card" aria-label="Your first days" data-testid="journey-card">
      <div className="jn-card__head">
        <b>🌱 Your first days</b>
        <span className="jn-day">Day {sum.day}</span>
      </div>
      <div className="jn-bar" role="progressbar" aria-valuemin={0} aria-valuemax={sum.total} aria-valuenow={sum.claimed} aria-label="Quest line progress">
        <i style={{ width: `${Math.max(sum.claimed > 0 ? 6 : 0, sum.pct)}%` }} />
      </div>
      <p className="jn-card__count">{sum.claimed} of {sum.total} done · {left} to go</p>
      {sum.next.map((s) => (
        <CardRow key={s.id} s={s} busy={busy === s.id} onClaim={(id) => void run(id)} onGo={(x) => { onPick?.(); goStep(x); }} />
      ))}
      {sum.next.length === 0 && (
        <p className="jn-card__wait">{sum.lockedDay ? `Day ${sum.lockedDay} opens when you come back tomorrow.` : 'All caught up for now.'}</p>
      )}
      <button type="button" className="jn-more" onClick={() => { onPick?.(); setSheet(true); }}>See all steps ›</button>
    </section>
  );
}

function SheetStep({ s, busy, onClaim, onClose }: { s: JourneyStep; busy: boolean; onClaim: (id: string) => void; onClose: () => void }) {
  const just = useJustClaimed(s.id);
  const prog = progressText(s);
  return (
    <li className={`jn-step is-${s.state}`} data-testid={`journey-step-${s.id}`}>
      {just && <Burst />}
      <span className="jn-step__icon" aria-hidden>{s.state === 'claimed' ? '✓' : s.state === 'locked' ? '🔒' : s.icon}</span>
      <div className="jn-step__main">
        <b className="jn-step__title">{s.title}</b>
        <p className="jn-step__hint">{s.hint}</p>
        <div className="jn-step__meta">
          <span className="jn-chip" title={s.reward.cash > 0 ? naira(s.reward.cash) : undefined}>{rewardText(s)}</span>
          {prog && s.state === 'active' && <span className="jn-chip jn-chip--soft">{prog}</span>}
        </div>
      </div>
      <div className="jn-step__act">
        {s.state === 'done' && <Button variant="green" size="sm" disabled={busy} onClick={() => onClaim(s.id)}>Claim</Button>}
        {s.state === 'active' && s.go && <Button variant="ghost" size="sm" onClick={() => { onClose(); goStep(s); }}>Go</Button>}
        {s.state === 'claimed' && <span className="jn-step__ok">Claimed</span>}
      </div>
    </li>
  );
}

const DAY_NAME: Record<number, string> = { 1: 'Day 1: Settle in', 2: 'Day 2: Come back and earn', 3: 'Day 3: Build your life' };

export function JourneySheet() {
  const open = useJourney((s) => s.sheet);
  const setSheet = useJourney((s) => s.setSheet);
  const status = useJourney((s) => s.status);
  const load = useJourney((s) => s.load);
  const { busy, run } = useClaim();
  useEffect(() => { if (open) void load(); }, [open, load]);
  const steps = status?.steps ?? [];
  const bonus = status?.bonus;
  const bonusText = bonus ? [bonus.cash > 0 ? nairaShort(bonus.cash) : null, bonus.item_name, `the ${bonus.badge} badge`].filter(Boolean).join(' + ') : '';
  return (
    <Sheet open={open} onClose={() => setSheet(false)} title="Your first days" subtitle="Small steps. Small rewards. A real start in Benin." size="tall" className="jn-sheet">
      {!status && <div className="panel-skel"><span /><span /></div>}
      {status && (!status.enabled || !status.eligible) && <p className="jn-quiet">There is no quest line for your account right now.</p>}
      {status?.eligible && (
        <>
          <div className="jn-top">
            <div className="jn-top__row"><b>{status.claimed} of {status.total} done</b><span className="jn-day">Day {status.day}</span></div>
            <div className="jn-bar" role="progressbar" aria-valuemin={0} aria-valuemax={status.total} aria-valuenow={status.claimed} aria-label="Quest line progress">
              <i style={{ width: `${Math.max((status.claimed ?? 0) > 0 ? 6 : 0, status.pct ?? 0)}%` }} />
            </div>
            <p className="jn-top__prize">{status.complete ? `🏅 You finished! You are a ${status.badge ?? 'Benin Newcomer'}.` : `Finish every step for ${bonusText}.`}</p>
          </div>
          {[1, 2, 3].map((d) => {
            const list = steps.filter((x) => x.day === d);
            if (list.length === 0) return null;
            const locked = list.every((x) => x.state === 'locked');
            return (
              <section key={d} className={`jn-day-block${locked ? ' is-locked' : ''}`}>
                <h4 className="jn-day-block__title">{DAY_NAME[d]}{locked && <span className="jn-day-block__lock">Opens on your {d === 2 ? '2nd' : '3rd'} day</span>}</h4>
                <ul className="jn-list">
                  {list.map((s) => <SheetStep key={s.id} s={s} busy={busy === s.id} onClaim={(id) => void run(id)} onClose={() => setSheet(false)} />)}
                </ul>
              </section>
            );
          })}
        </>
      )}
    </Sheet>
  );
}

export function JourneyFinish() {
  const c = useJourney((s) => s.celebrate);
  const status = useJourney((s) => s.status);
  const [shown, setShown] = useState<number>(0);
  const open = Boolean(c?.finished && c.at !== shown);
  const bonus = status?.bonus;
  return (
    <Modal open={open} onClose={() => c && setShown(c.at)} title="You finished your first days!" tone="good"
      actions={<Button variant="gold" block onClick={() => c && setShown(c.at)}>Carry on</Button>}>
      <div className="jn-finish">
        <span className="jn-finish__badge" aria-hidden>🏅</span>
        <p>You are now a <b>{status?.badge ?? bonus?.badge ?? 'Benin Newcomer'}</b>.</p>
        <p className="jn-finish__sub">{bonus ? `Bonus: ${[bonus.cash > 0 ? nairaShort(bonus.cash) : null, bonus.item_name].filter(Boolean).join(' + ')}` : ''}</p>
        <p className="jn-finish__sub">Keep going: your dream is waiting.</p>
      </div>
    </Modal>
  );
}

export function JourneyHost() {
  return (
    <>
      <JourneySync />
      <JourneySheet />
      <JourneyFinish />
    </>
  );
}
