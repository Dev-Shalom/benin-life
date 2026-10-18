// E2 Hustles app (docs/HUSTLES.md): every side hustle with where to go, pay range, cooldown and requirements, the Bolt car
// card (class, wear, service), a live bar for the running hustle, and the referral card ("Invite & earn").
import { useCallback, useEffect, useState } from 'react';
import { hustleBuy, hustleStart, referralStatus, type Hustle, type HustleStatus, type ReferralStatus } from '../../../api/hustles';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { countdown, naira, nairaShort, secondsUntil } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { useHustles } from '../../../state/hustles';
import { toast } from '../../../ui';
import './HustlesApp.css';

const GROUPS: { id: string; title: string; kinds: string[] }[] = [
  { id: 'road', title: 'On the road', kinds: ['bolt'] },
  { id: 'market', title: 'Markets', kinds: ['pos', 'pass', 'vending'] },
  { id: 'night', title: 'Clubs at night', kinds: ['dj', 'mc'] },
  { id: 'day', title: 'Daytime work', kinds: ['tutor', 'fishing', 'mechanic', 'service', 'job'] },
];

function payText(h: Hustle): string {
  if (h.kind === 'pass') return `${naira(h.cost)} for ${h.pass_hours ?? 24} h`;
  if (h.kind === 'service') return `${naira(h.cost)}`;
  if (h.kind === 'fishing') return 'Fish worth ₦150–₦30k';
  return `${nairaShort(h.pay_min)}–${nairaShort(h.pay_max)}`;
}

function HustleCard({ h, st, free, now, busy, onStart, onGo }: {
  h: Hustle; st: HustleStatus; free: boolean; now: number; busy: string | null; onStart: (h: Hustle) => void; onGo: (id: string) => void;
}) {
  const instant = h.kind === 'pass' || h.kind === 'service';
  const cool = secondsUntil(h.cooldown_until, now);
  const capped = h.cap_left === 0;
  const blocker = h.locked && h.locked.hint !== 'wrong_place' ? h.locked : null;
  const nearest = h.places.find((p) => p.open) ?? h.places[0];
  const where = h.anywhere ? 'Any public place' : h.places.map((p) => p.name).slice(0, 2).join(' · ') || h.where_text;
  let action: React.ReactNode;
  if (!h.here && !h.anywhere && nearest) {
    action = <button type="button" className="hs-btn hs-btn--ghost" onClick={() => onGo(nearest.id)}>Go to {nearest.name.replace(/\s*\(.*\)$/, '')}</button>;
  } else if (!h.here && h.anywhere) {
    action = <button type="button" className="hs-btn hs-btn--ghost" disabled>{h.here_why?.short ?? 'Leave home first'}</button>;
  } else if (blocker) {
    const need = blocker.hint === 'no_item' && h.item?.sold_at[0];
    action = need
      ? <button type="button" className="hs-btn hs-btn--ghost" onClick={() => onGo(h.item!.sold_at[0].id)}>{blocker.short} · {h.item!.sold_at[0].name.replace(/\s*\(.*\)$/, '')}</button>
      : <button type="button" className="hs-btn hs-btn--ghost" disabled>{blocker.short}</button>;
  } else if (capped) {
    action = <button type="button" className="hs-btn hs-btn--ghost" disabled>Done for today</button>;
  } else if (cool > 0) {
    action = <button type="button" className="hs-btn hs-btn--ghost" disabled>Wait {countdown(cool)}</button>;
  } else if (!free) {
    action = <button type="button" className="hs-btn hs-btn--ghost" disabled>Busy</button>;
  } else {
    action = (
      <button type="button" className="hs-btn" data-testid={`hustle-start-${h.id}`} disabled={busy === h.id} onClick={() => onStart(h)}>
        {instant ? (h.kind === 'pass' ? 'Rent' : 'Service') : `Start · ${h.seconds}s`}
      </button>
    );
  }
  return (
    <article className="hs-card" data-testid={`hustle-${h.id}`}>
      <div className="hs-card__top">
        <span className="hs-card__icon" aria-hidden>{h.icon}</span>
        <span className="hs-card__main">
          <b>{h.name}</b>
          <small>{h.blurb}</small>
        </span>
      </div>
      <div className="hs-chips">
        <span className="hs-chip is-pay">{payText(h)}</span>
        <span className="hs-chip">📍 {where}</span>
        {!instant && <span className="hs-chip">⏱ {h.seconds}s · cooldown {h.cooldown_seconds}s</span>}
        {h.daily_cap > 0 && !instant && <span className="hs-chip">{h.cap_left ?? h.daily_cap}/{h.daily_cap} left today</span>}
        {h.hours && <span className="hs-chip">🕗 {h.hours}</span>}
        {h.cost > 0 && !instant && <span className="hs-chip">Costs {naira(h.cost)} a run</span>}
        {h.item && <span className={`hs-chip${h.item.owned ? ' is-ok' : h.item.optional ? '' : ' is-need'}`}>{h.item.icon} {h.item.name}{h.item.owned ? ' ✓' : h.item.optional ? ` (full pay needs it, ${nairaShort(h.item.price)})` : ` ${nairaShort(h.item.price)}`}</span>}
        {h.needs_car && <span className={`hs-chip${st.car ? ' is-ok' : ' is-need'}`}>🚗 {st.car ? st.car.class_name : 'Needs your own car'}</span>}
        {h.pass && <span className={`hs-chip${h.pass.until ? ' is-ok' : ' is-need'}`}>🏪 {h.pass.until ? 'Stall rented' : 'Rent a stall first'}</span>}
        {h.risk && <span className="hs-chip is-risk" title={h.risk.text}>{h.risk.pct}% {h.risk.pay_mult === 0 ? 'no pay' : `×${h.risk.pay_mult} pay`}</span>}
        {h.loss && <span className="hs-chip is-risk" title={h.loss.text}>{h.loss.pct}% fraud −{nairaShort(h.loss.min)}–{nairaShort(h.loss.max)}</span>}
        {h.bonus && <span className="hs-chip is-ok" title={h.bonus.text}>{h.bonus.pct}% tip +{nairaShort(h.bonus.min)}–{nairaShort(h.bonus.max)}</span>}
        {h.skill && h.skill.pay_boost_pct > 0 && !instant && <span className="hs-chip is-ok">{h.skill.icon} +{Math.round(h.skill.pay_boost_pct)}% from skill</span>}
        {h.skill && !h.skill.ok && <span className="hs-chip is-need">{h.skill.icon} Needs {h.skill.name} lvl {h.skill.min_level}</span>}
        {h.pay_mult_now !== 1 && !instant && h.kind !== 'fishing' && <span className="hs-chip">now ×{h.pay_mult_now.toFixed(2).replace(/0$/, '')}</span>}
      </div>
      {action}
    </article>
  );
}

function ReferralCard({ r }: { r: ReferralStatus | null }) {
  if (!r) return <div className="hs-skel"><span /><span /></div>;
  if (!r.enabled) return <p className="hs-note">Referral bonuses are off for now.</p>;
  const copy = async () => {
    try { await navigator.clipboard.writeText(r.link); toast('Link copied. Send am to your people.', 'good'); } catch { toast(r.link, 'info'); }
  };
  const share = async () => {
    const nav = navigator as Navigator & { share?: (d: { title?: string; text?: string; url?: string }) => Promise<void> };
    if (nav.share) { try { await nav.share({ title: 'Benin Life', text: `Join me on Benin Life and we both get ${naira(r.bonus_referred)}.`, url: r.link }); return; } catch { /* cancelled */ } }
    await copy();
  };
  const by = r.referred_by;
  return (
    <div className="hs-ref" data-testid="referral-card">
      <section className="hs-ref__hero">
        <small>Your invite link</small>
        <b className="hs-ref__code" data-testid="referral-code">{r.code}</b>
        <code className="hs-ref__link">{r.link.replace(/^https?:\/\//, '')}</code>
        <div className="hs-ref__btns">
          <button type="button" className="hs-btn" onClick={() => void copy()}>Copy link</button>
          <button type="button" className="hs-btn hs-btn--ghost" onClick={() => void share()}>Share</button>
        </div>
        <p>Friend signs up with your link and finishes {r.milestone.shifts > 0 ? `their first shift` : 'the first steps'}
          {r.milestone.hustles > 0 ? `, ${r.milestone.hustles} hustles` : ''}{r.milestone.minutes > 0 ? ` or ${r.milestone.minutes} minutes of play` : ''}:
          you get <b>{naira(r.bonus_referrer)}</b> and they get <b>{naira(r.bonus_referred)}</b>. Up to {r.daily_cap} friends a day.</p>
      </section>
      {by && (
        <section className="hs-card">
          <b>You joined through @{by.username}</b>
          {by.status === 'rewarded'
            ? <small>Bonus paid: {naira(by.bonus)}. Nice one!</small>
            : <>
                <small>Reach the milestone for your {naira(r.bonus_referred)}: {by.progress.pct}% there</small>
                <div className="hs-bar"><span style={{ width: `${by.progress.pct}%` }} /></div>
                <small>{by.progress.shifts}/{by.progress.need_shifts} shifts · {by.progress.hustles}/{by.progress.need_hustles} hustles · {by.progress.play_minutes}/{by.progress.need_minutes} min played (any one does it)</small>
              </>}
        </section>
      )}
      <div className="hs-stats">
        <span><b>{r.invited}</b><small>invited</small></span>
        <span><b>{r.rewarded}</b><small>paid</small></span>
        <span><b>{nairaShort(r.earned)}</b><small>earned</small></span>
        <span><b>{r.today}/{r.daily_cap}</b><small>today</small></span>
      </div>
      {r.rows.length > 0 && (
        <ul className="hs-list">
          {r.rows.map((x) => (
            <li key={x.username}>
              <span>@{x.username}</span>
              <small>{x.status === 'rewarded' ? '✅ paid' : x.status === 'rejected' ? 'not eligible' : `${x.progress.pct}%`}</small>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export default function HustlesApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const s = useHustles((x) => x.status);
  const run = useHustles((x) => x.run);
  const last = useHustles((x) => x.last);
  const refresh = useGame((x) => x.refresh);
  const now = useNow(1000);
  const [tab, setTab] = useState<'hustles' | 'invite'>('hustles');
  const [busy, setBusy] = useState<string | null>(null);
  const [ref, setRef] = useState<ReferralStatus | null>(null);

  useEffect(() => { void useHustles.getState().load(); }, [state.profile.location_id]);
  const loadRef = useCallback(async () => { try { setRef(await referralStatus()); } catch { /* retry on the next open */ } }, []);
  useEffect(() => {
    if (tab !== 'invite') return;
    void loadRef();
    const t = window.setInterval(() => { if (document.visibilityState === 'visible') void loadRef(); }, 90_000);
    return () => window.clearInterval(t);
  }, [tab, loadRef]);

  if (!s) return <div className="phone-app__body hs"><div className="hs-skel"><span /><span /><span /></div></div>;
  const free = !run && !(state.profile.busy_until && Date.parse(state.profile.busy_until) > now)
    && !(state.profile.jailed_until && Date.parse(state.profile.jailed_until) > now) && !state.travel;

  const start = async (h: Hustle) => {
    setBusy(h.id);
    try {
      if (h.kind === 'pass' || h.kind === 'service') {
        const r = await hustleBuy(h.id);
        toast(r.message, 'good');
        await Promise.all([useHustles.getState().load(), refresh()]);
      } else {
        const r = await hustleStart(h.id);
        toast(r.message, 'info');
        useHustles.getState().started({ id: r.run_id, hustle_id: r.hustle_id, name: r.name, icon: r.icon, started_at: r.started_at, resolve_at: r.resolve_at,
          status: 'running', cost: r.cost, amount: 0, outcome: null });
        void refresh();
      }
    } catch (e) { toast(errorMessage(e), 'bad'); void useHustles.getState().load(); } finally { setBusy(null); }
  };

  const car = s.car;
  const runLeft = run ? secondsUntil(run.resolve_at, now) : 0;
  const runPct = run ? Math.min(100, Math.max(0, (1 - runLeft / Math.max(1, (Date.parse(run.resolve_at) - Date.parse(run.started_at)) / 1000)) * 100)) : 0;
  return (
    <div className="phone-app__body hs" data-testid="hustles-app">
      <div className="hs-tabs" role="tablist" aria-label="Hustles">
        <button type="button" role="tab" aria-selected={tab === 'hustles'} className={`hs-tab${tab === 'hustles' ? ' is-on' : ''}`} onClick={() => setTab('hustles')}>💪 Hustles</button>
        <button type="button" role="tab" aria-selected={tab === 'invite'} className={`hs-tab${tab === 'invite' ? ' is-on' : ''}`} onClick={() => setTab('invite')} data-testid="hustles-invite-tab">🎁 Invite & earn</button>
      </div>
      {tab === 'invite' ? <ReferralCard r={ref} /> : (
        <>
          <section className="hs-top">
            <div><small>Earned from hustles</small><b data-testid="hustle-total">{naira(s.total_earned)}</b></div>
            <div><small>Jobs done</small><b>{s.runs_done}</b></div>
          </section>
          {run && (
            <section className="hs-run" role="status" data-testid="hustle-run">
              <span aria-hidden>{run.icon}</span>
              <span className="hs-run__main"><b>{run.name}</b><div className="hs-bar"><span style={{ width: `${runPct}%` }} /></div></span>
              <span className="hs-run__t">{countdown(runLeft)}</span>
            </section>
          )}
          {!run && last && last.status === 'done' && (
            <p className={`hs-last${last.outcome === 'loss' ? ' is-bad' : ''}`}>{last.icon} {last.message}{last.net != null && last.kind !== 'fishing' && (last.cost ?? 0) > 0 ? ` (net ${naira(last.net)})` : ''}</p>
          )}
          {car ? (
            <section className="hs-car" data-testid="hustle-car">
              <span aria-hidden>{car.class_icon}</span>
              <span className="hs-car__main">
                <b>{car.name}</b>
                <small>{car.class_name} · pays ×{car.pay_mult} · fuel ×{car.fuel_mult}</small>
                <div className="hs-bar hs-bar--wear"><span style={{ width: `${Math.min(100, car.wear)}%` }} /></div>
                <small>Wear {Math.round(car.wear)}%{car.wear >= 100 ? ' · needs a service at the Mechanic Village' : ''}</small>
              </span>
            </section>
          ) : (
            <p className="hs-note">No car yet. Bolt shifts need your own car (Phone → Cars).</p>
          )}
          {GROUPS.map((g) => {
            const list = s.hustles.filter((h) => g.kinds.includes(h.kind));
            if (!list.length) return null;
            return (
              <section key={g.id}>
                <h4 className="hs-h">{g.title}</h4>
                {list.map((h) => <HustleCard key={h.id} h={h} st={s} free={free} now={now} busy={busy} onStart={(x) => void start(x)} onGo={onGo} />)}
              </section>
            );
          })}
          <p className="hs-note">Every pay, cooldown and daily cap is set by the admin. Cooldowns reset at once; caps reset at midnight Benin time.</p>
        </>
      )}
    </div>
  );
}
