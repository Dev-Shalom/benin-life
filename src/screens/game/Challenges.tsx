// R5: daily and weekly challenges (docs/CHALLENGES.md).
//   ChallengeSync   loads the status (mount, every 5 min while visible, when the tab comes back)
//   ChallengeChip   the "Challenges" row in the Today list (opens the sheet)
//   ChallengeSheet  tabs Today / This week: progress bars, rewards, time left, Claim, swap, and the bonus chest
// All progress is counted by the server from real events; this file only shows it and taps Claim / Swap / Open chest.
import { useEffect, useState } from 'react';
import { useConfig } from '../../lib/config';
import { errorMessage } from '../../lib/api';
import { naira, nairaShort } from '../../lib/format';
import { serverNow } from '../../lib/clock';
import { playCue } from '../../lib/sound';
import { challengeClaim, challengeClaimChest, challengeReroll, type Challenge, type ChallengeChest, type ChallengePeriod } from '../../api/challenges';
import { challengeSummary, useChallenges } from '../../state/challenges';
import { useGame } from '../../state/game';
import { Button, Sheet, Tabs, toast } from '../../ui';
import './Challenges.css';
import { canPoll } from '../../lib/activity';

export function ChallengeSync() {
  const load = useChallenges((s) => s.load);
  useEffect(() => {
    void load();
    const id = window.setInterval(() => { if (canPoll()) void load(); }, 5 * 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [load]);
  return null;
}

/** HUD helper: should the chip show, and is something ready to collect? */
export function useChallengeChip() {
  const { cfg } = useConfig();
  const status = useChallenges((s) => s.status);
  const sum = challengeSummary(status);
  const on = Boolean(sum) && cfg('challenges.enabled', true);
  const show = on && Boolean(sum && (sum.open || sum.claimable > 0 || sum.chest));
  return { show, ready: show && Boolean(sum?.ready), sum };
}

export function ChallengeChip({ onPick }: { onPick?: () => void }) {
  const { show, ready, sum } = useChallengeChip();
  const setSheet = useChallenges((s) => s.setSheet);
  if (!show || !sum) return null;
  const sub = sum.chest ? 'Your chest is ready!' : sum.claimable > 0 ? `${sum.claimable} reward${sum.claimable === 1 ? '' : 's'} to claim` : 'Daily and weekly goals';
  return (
    <button type="button" className="wish-chip wish-chip--chal" data-testid="challenge-chip"
      onClick={() => { onPick?.(); setSheet(sum.dDone >= sum.dTotal && !sum.ready ? 'weekly' : 'daily'); }}
      aria-label={`Challenges: ${sum.dDone} of ${sum.dTotal} daily done. ${sub}`}>
      <span className="wish-chip__icon" aria-hidden>🏆</span>
      <span className="wish-chip__text">
        <span className="wish-chip__title"><span className="daily-long">Challenges · {sum.dDone}/{sum.dTotal} today</span><span className="daily-short">Challenges {sum.dDone}/{sum.dTotal}</span></span>
        <span className="wish-chip__sub">{sub}</span>
      </span>
      {ready && <span className="daily-dot" aria-hidden />}
    </button>
  );
}

/** "5h 12m" / "2d 4h" until the period ends (server time). */
function timeLeft(endsAt: string, now: number): string {
  const secs = Math.max(0, Math.floor((Date.parse(endsAt) - now) / 1000));
  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${Math.max(1, m)}m`;
}

function RewardChips({ r, cash }: { r: Challenge['reward']; cash?: number }) {
  const c = cash ?? r.cash;
  return (
    <span className="chal-rewards">
      {c > 0 && <span className="chal-chip is-cash" title={naira(c)}>{nairaShort(c)}</span>}
      {r.xp > 0 && <span className="chal-chip">{r.xp} XP</span>}
      {r.skill_xp > 0 && r.skill_name && <span className="chal-chip">{r.skill_icon} +{r.skill_xp} {r.skill_name}</span>}
      {r.item_name && <span className="chal-chip">{r.item_icon} {r.item_qty > 1 ? `${r.item_qty} x ` : ''}{r.item_name}</span>}
    </span>
  );
}

function ChallengeCard({ c, left, busy, onClaim, onReroll }: {
  c: Challenge; left: number; busy: boolean; onClaim: (c: Challenge) => void; onReroll: (c: Challenge) => void;
}) {
  const pct = Math.max(c.progress > 0 ? 4 : 0, Math.min(100, Math.round((c.progress / c.target) * 100)));
  const fmt = (n: number) => (c.money ? nairaShort(n) : n.toLocaleString('en-NG'));
  const state = c.claimed ? 'is-claimed' : c.done ? 'is-done' : '';
  return (
    <li className={`chal-card ${state}`} data-testid={`challenge-${c.template}`}>
      <div className="chal-card__top">
        <span className="chal-card__icon" aria-hidden>{c.claimed ? '✓' : c.icon}</span>
        <span className="chal-card__main">
          <b>{c.title}{c.friends && <em className="chal-friends">with friends</em>}</b>
          <small>{c.blurb}</small>
        </span>
      </div>
      <div className="chal-bar" role="progressbar" aria-valuemin={0} aria-valuemax={c.target} aria-valuenow={c.progress} aria-label={`${c.title} progress`}>
        <i style={{ width: `${pct}%` }} />
      </div>
      <div className="chal-card__foot">
        <span className="chal-count">{fmt(c.progress)} / {fmt(c.target)}</span>
        <RewardChips r={c.reward} />
        {c.done && !c.claimed && (
          <Button variant="gold" size="sm" onClick={() => onClaim(c)} disabled={busy} data-testid={`claim-${c.template}`}>Claim</Button>
        )}
        {c.claimed && <span className="chal-claimed">Claimed</span>}
        {!c.done && c.can_reroll && (
          <button type="button" className="chal-swap" onClick={() => onReroll(c)} disabled={busy} aria-label={`Swap ${c.title} for another challenge (${left} left)`}>
            ⟳ Swap · {left} left
          </button>
        )}
      </div>
    </li>
  );
}

function Chest({ kind, chest, onOpen, busy }: { kind: 'daily' | 'weekly'; chest: ChallengeChest; onOpen: () => void; busy: boolean }) {
  const label = kind === 'weekly' ? 'Weekly chest' : 'Daily chest';
  const parts = [chest.cash > 0 ? nairaShort(chest.cash) : null, chest.xp > 0 ? `${chest.xp} XP` : null, chest.item_name ? `${chest.item_icon ?? ''} ${chest.item_name}`.trim() : null].filter(Boolean);
  return (
    <div className={`chal-chest${chest.ready ? ' is-ready' : ''}${chest.claimed ? ' is-claimed' : ''}${kind === 'weekly' ? ' is-weekly' : ''}`} data-testid={`chest-${kind}`}>
      <span className="chal-chest__icon" aria-hidden>{chest.claimed ? '🎉' : chest.ready ? '🎁' : '🔒'}</span>
      <span className="chal-chest__main">
        <b>{label}</b>
        <small>{chest.claimed ? 'Opened. Come back next time.' : chest.ready ? `All done! ${parts.join(' + ')}` : `Finish all ${chest.total} to open it: ${parts.join(' + ')}`}</small>
        <span className="chal-chest__dots" aria-label={`${chest.done} of ${chest.total} done`}>
          {Array.from({ length: chest.total }, (_, i) => <i key={i} className={i < chest.done ? 'is-on' : ''} />)}
        </span>
      </span>
      {chest.ready && <Button variant="gold" size="sm" onClick={onOpen} disabled={busy} data-testid={`open-chest-${kind}`}>Open</Button>}
    </div>
  );
}

function PeriodView({ kind, p }: { kind: 'daily' | 'weekly'; p: ChallengePeriod }) {
  const load = useChallenges((s) => s.load);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => serverNow());
  useEffect(() => { const id = window.setInterval(() => setNow(serverNow()), 30_000); return () => window.clearInterval(id); }, []);
  const run = async (fn: () => Promise<{ message: string }>, tone: 'good' | 'info' = 'good') => {
    if (busy) return;
    setBusy(true);
    try {
      const r = await fn();
      toast(`${tone === 'good' ? '🎉 ' : ''}${r.message}`, tone === 'good' ? 'good' : 'info');
      if (tone === 'good') playCue('money');
      await Promise.all([load(), refresh()]);
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void load();
    } finally {
      setBusy(false);
    }
  };
  const left = timeLeft(p.ends_at, now);
  return (
    <div className="chal-period">
      <p className="chal-time"><span aria-hidden>⏳</span> {kind === 'daily' ? 'New challenges in' : 'New week in'} <b>{left}</b>{kind === 'weekly' ? ' (Monday midnight, Benin time)' : ' (midnight, Benin time)'}</p>
      {p.items.length === 0 && <p className="muted">Nothing to do right now. Check back tomorrow.</p>}
      <ul className="chal-list">
        {p.items.map((c) => (
          <ChallengeCard key={c.id} c={c} left={p.rerolls_left} busy={busy}
            onClaim={(x) => void run(() => challengeClaim(x.id))}
            onReroll={(x) => void run(() => challengeReroll(x.id), 'info')} />
        ))}
      </ul>
      {p.items.length > 0 && <Chest kind={kind} chest={p.chest} busy={busy} onOpen={() => void run(() => challengeClaimChest(kind))} />}
      {kind === 'daily' && p.rerolls_max > 0 && <p className="chal-note">Not feeling one? Swap it for another ({p.rerolls_left} free swap{p.rerolls_left === 1 ? '' : 's'} left today). Progress on a swapped one is lost.</p>}
    </div>
  );
}

export function ChallengeSheet() {
  const sheet = useChallenges((s) => s.sheet);
  const setSheet = useChallenges((s) => s.setSheet);
  const status = useChallenges((s) => s.status);
  const load = useChallenges((s) => s.load);
  useEffect(() => { if (sheet) void load(); }, [sheet, load]);
  const sum = challengeSummary(status);
  const dReady = (status?.daily?.items ?? []).filter((c) => c.done && !c.claimed).length + (status?.daily?.chest.ready ? 1 : 0);
  const wReady = (status?.weekly?.items ?? []).filter((c) => c.done && !c.claimed).length + (status?.weekly?.chest.ready ? 1 : 0);
  return (
    <Sheet open={sheet != null && Boolean(sum)} onClose={() => setSheet(null)} className="chal-sheet" size="tall"
      title="Challenges" subtitle="Real things you do in Benin. Finish, claim, collect. Finish them all for a chest.">
      <Tabs value={sheet ?? 'daily'} onChange={(id) => setSheet(id as 'daily' | 'weekly')}
        tabs={[{ id: 'daily', label: 'Today', badge: dReady || null }, { id: 'weekly', label: 'This week', badge: wReady || null }]} />
      {sheet === 'daily' && status?.daily && <PeriodView kind="daily" p={status.daily} />}
      {sheet === 'weekly' && status?.weekly && <PeriodView kind="weekly" p={status.weekly} />}
    </Sheet>
  );
}
