// Y1 Yahoo app (docs/YAHOO.md): a dark "laptop screen" with the gear (laptop, MiFi, cybercafe desk, status phone), the dirty
// yahoo balance, the jobs with their real odds, Cash out (R6: a sheet with three options and their real numbers), R6 group
// missions with friends, the rank ladder and the yahoo balance history.
// Satire only: the jobs are abstract buttons; nothing explains how any real scam works.
import { useEffect, useState } from 'react';
import { yahooBuyPass, yahooJobStart, type YahooJob, type YahooStatus } from '../../../api/yahoo';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { countdown, naira, nairaShort, secondsUntil } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { useYahoo } from '../../../state/yahoo';
import { Button, toast } from '../../../ui';
import { CashOutSheet } from './YahooCashOut';
import YahooGroups from './YahooGroups';
import './YahooApp.css';

function left(iso: string | null, now: number): string {
  const s = secondsUntil(iso, now);
  if (s <= 0) return '';
  if (s >= 86400) return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h left`;
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m left`;
  return `${countdown(s)} left`;
}

function oddsTone(p: number): string {
  return p >= 30 ? 'is-hot' : p >= 18 ? 'is-warm' : 'is-cool';
}

export default function YahooApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const s = useYahoo((x) => x.status);
  const run = useYahoo((x) => x.run);
  const last = useYahoo((x) => x.last);
  const refresh = useGame((x) => x.refresh);
  const now = useNow(1000);
  const [busy, setBusy] = useState<string | null>(null);
  const [cashOpen, setCashOpen] = useState(false);

  useEffect(() => { void useYahoo.getState().load(); }, [state.profile.location_id]);

  if (!s) {
    return <div className="phone-app__body yh"><div className="yh-skel"><span /><span /><span /></div></div>;
  }
  const free = !run && !(state.profile.busy_until && Date.parse(state.profile.busy_until) > now)
    && !(state.profile.jailed_until && Date.parse(state.profile.jailed_until) > now) && !state.travel;

  const buy = async (kind: 'mifi' | 'desk') => {
    setBusy(kind);
    try {
      const r = await yahooBuyPass(kind);
      toast(r.message, 'good');
      await Promise.all([useYahoo.getState().load(), refresh()]);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };

  const start = async (j: YahooJob) => {
    if (j.kind === 'cashout') { setCashOpen(true); return; }
    setBusy(j.id);
    try {
      const r = await yahooJobStart(j.id, null);
      toast(r.message, 'info');
      useYahoo.getState().started({ id: r.run_id, job_id: r.job_id, name: r.name, icon: j.icon, started_at: new Date(now).toISOString(),
        resolve_at: r.resolve_at, status: 'running', caught_pct: r.caught_pct, skill_caught_pct: r.skill_caught_pct, amount: r.amount });
      void refresh();
    } catch (e) { toast(errorMessage(e), 'bad'); void useYahoo.getState().load(); } finally { setBusy(null); }
  };

  const rankPct = s.next_rank
    ? Math.min(100, Math.max(0, ((s.total_earned - s.rank.min_earned) / Math.max(1, s.next_rank.min_earned - s.rank.min_earned)) * 100))
    : 100;
  const cafeNames = s.cafes.map((c) => c.name).join(' / ') || 'cybercafe';

  return (
    <div className="phone-app__body yh" data-testid="yahoo-app">
      {/* the laptop screen: balance + rank */}
      <section className="yh-screen" aria-label="Yahoo balance">
        <div className="yh-screen__glass">
          <div className="yh-screen__top">
            <span className="yh-rank" data-testid="yahoo-rank">{s.rank.icon} {s.rank.name}</span>
            <span className="yh-screen__cam" aria-hidden />
            <span className="yh-screen__where">{s.where.ok ? (s.where.place === 'home' ? '🏠 Home · MiFi' : state.profile.location_id === 'hk_quarters' ? '🧢 HK Quarters desk' : '🖥️ Cybercafe desk') : 'Offline'}</span>
          </div>
          <div className="yh-bal">
            <small>Yahoo balance</small>
            <b data-testid="yahoo-dirty" title={naira(s.dirty)}>{naira(s.dirty)}</b>
            <span>Dirty money. You can't spend am until you cash out.</span>
          </div>
          <div className="yh-rankbar">
            <div className="yh-rankbar__track"><span style={{ width: `${rankPct}%` }} /></div>
            <small>
              {s.next_rank
                ? <>{nairaShort(s.total_earned)} earned · {s.next_rank.icon} {s.next_rank.name} at {nairaShort(s.next_rank.min_earned)}</>
                : <>{nairaShort(s.total_earned)} earned · top rank</>}
            </small>
          </div>
        </div>
        <div className="yh-screen__base" aria-hidden />
      </section>

      {/* running job */}
      {run && <RunBar run={run} now={now} />}
      {!run && last && last.status !== 'none' && (
        <p className={`yh-last yh-last--${last.status}`}>
          {last.status === 'paid' ? `✅ ${last.name}: +${naira(last.amount)} into your yahoo balance.`
            : last.status === 'cashed' ? `💸 Cashed out ${naira(last.amount - (last.fee ?? 0))} into your pocket${last.fee ? ` (${naira(last.fee)} fee)` : ''}.`
              : `🚨 EFCC caught you.${last.laptop_seized ? ` ${last.laptop_seized} seized.` : ''}${last.seized ? ` ${naira(last.seized)} confiscated.` : ''}`}
        </p>
      )}

      {/* gear */}
      <h4 className="yh-h">Your gear</h4>
      <div className="yh-gear">
        <div className={`yh-gear__row${s.laptop ? '' : ' is-missing'}`} data-testid="yahoo-laptop">
          <span className="yh-gear__icon" aria-hidden>💻</span>
          <span className="grow">
            <b>{s.laptop ? s.laptop.name : 'No laptop'}</b>
            <small>{s.laptop
              ? (s.laptop.pay_bonus_pct || s.laptop.efcc_minus_pts || s.laptop.speed_pct
                ? `${s.laptop.label} · +${s.laptop.pay_bonus_pct}% pay · −${s.laptop.efcc_minus_pts} pts EFCC · ${s.laptop.speed_pct}% faster`
                : `${s.laptop.label} · no Yahoo bonus · small jobs only`)
              : 'Buy one at Bronze Tech Hub, Benin City Mall or the Wi-Fi Joint.'}</small>
          </span>
        </div>
        <div className={`yh-gear__row${s.mifi_until ? '' : ' is-missing'}`}>
          <span className="yh-gear__icon" aria-hidden>📶</span>
          <span className="grow">
            <b>MiFi + data</b>
            <small>{s.mifi_until ? `${left(s.mifi_until, now)} · work from home` : `${naira(s.prices.mifi)} / ${s.prices.mifi_days} days · work from home`}</small>
          </span>
          <Button size="sm" variant={s.mifi_until ? 'ghost' : 'gold'} loading={busy === 'mifi'} disabled={busy !== null} onClick={() => void buy('mifi')}
            data-testid="yahoo-buy-mifi">{s.mifi_until ? 'Top up' : 'Buy'}</Button>
        </div>
        <div className={`yh-gear__row${s.desk_until ? '' : ' is-missing'}`}>
          <span className="yh-gear__icon" aria-hidden>🖥️</span>
          <span className="grow">
            <b>Cybercafe desk</b>
            <small>{s.desk_until ? `${left(s.desk_until, now)} · ${cafeNames}` : `${naira(s.prices.desk)} / day · ${cafeNames}`}</small>
          </span>
          <Button size="sm" variant={s.desk_until ? 'ghost' : 'gold'} loading={busy === 'desk'} disabled={busy !== null} onClick={() => void buy('desk')}
            data-testid="yahoo-buy-desk">{s.desk_until ? 'Extend' : 'Rent'}</Button>
        </div>
        {s.iphone && (
          <div className="yh-gear__row">
            <span className="yh-gear__icon" aria-hidden>📱</span>
            <span className="grow"><b>iPhone 18 (Burgundy)</b><small>Status don land · extra club hype</small></span>
          </div>
        )}
        {(s.charms.blindfold || s.charms.bad_luck) && (
          <div className="yh-gear__row">
            <span className="yh-gear__icon" aria-hidden>{s.charms.blindfold ? '🙈' : '🐈‍⬛'}</span>
            <span className="grow">
              <b>Charms on you</b>
              <small>
                {s.charms.blindfold ? `EFCC blindfold −${s.charms.blindfold} pts` : ''}
                {s.charms.blindfold && s.charms.bad_luck ? ' · ' : ''}
                {s.charms.bad_luck ? `Bad luck +${s.charms.bad_luck} pts` : ''}
              </small>
            </span>
          </div>
        )}
      </div>
      <p className={`yh-where${s.where.ok ? ' is-ok' : ''}`} data-testid="yahoo-where">
        {s.where.ok ? '🟢 ' : '🔴 '}{s.where.message}
        {!s.where.ok && s.cafes.filter((c) => c.id !== state.profile.location_id).map((c) => (
          <button key={c.id} type="button" className="yh-link" onClick={() => onGo(c.id)}>Go to {c.name}</button>
        ))}
      </p>

      {/* jobs */}
      <h4 className="yh-h">Jobs</h4>
      <div className="yh-jobs">
        {s.jobs.map((j) => {
          const cd = secondsUntil(j.cooldown_until, now);
          const cash = j.kind === 'cashout';
          const reason = !s.enabled ? 'Switched off'
            : j.locked === 'no_laptop' ? 'Need a laptop'
              : j.locked === 'laptop_too_weak' ? `Need ${j.min_laptop ?? 'a better laptop'}+`
              : j.locked === 'skill_level' ? `Needs Yahoo lvl ${j.min_skill_level ?? 1}`
              : j.locked === 'cert' ? (j.cert_short ?? 'Needs a certificate')
                : j.locked === 'daily_cap' ? 'Done for today'
                : cash && s.dirty <= 0 ? 'Nothing to cash'
                  : !s.where.ok ? (s.where.hint === 'no_mifi' ? 'Need MiFi' : s.where.hint === 'no_desk' ? 'Need a desk' : 'Home or a work spot')
                    : cd > 0 ? `Wait ${countdown(cd)}`
                      : !free ? 'Busy' : null;
          return (
            <div key={j.id} className={`yh-job${reason ? ' is-locked' : ''}`} data-testid={`yahoo-job-${j.id}`}>
              <span className="yh-job__icon" aria-hidden>{j.icon}</span>
              <span className="yh-job__body">
                <b>{j.name}</b>
                <small>
                  {j.seconds}s · {cash ? 'moves yahoo balance to cash' : `${nairaShort(j.pay_min)}–${nairaShort(j.pay_max)}`}{!cash && j.min_skill_level && j.min_skill_level > 1 ? ` · Yahoo lvl ${j.min_skill_level}+` : ''}{!cash && j.daily_cap ? ` · ${j.cap_left ?? 0}/${j.daily_cap} left today` : ''}
                </small>
                <span className={`yh-odds ${oddsTone(j.caught_pct)}`} title={`Base ${j.base_caught_pct}%${j.skill?.caught_cut_pct ? ` · Yahoo lvl ${j.skill.level} cuts it ${j.skill.caught_cut_pct}%` : ''}`}>
                  🚨 EFCC {Math.round(j.skill_caught_pct ?? j.caught_pct)}%{(j.skill_caught_pct ?? j.caught_pct) !== j.base_caught_pct ? <s>{j.base_caught_pct}%</s> : null}
                </span>
                {cash && s.dirty > 0 && <span className="yh-cash-hint">Full, half, or launder through a contact. See the odds first.</span>}
              </span>
              <Button size="sm" variant={cash ? 'gold' : 'green'} disabled={Boolean(reason) || busy !== null} loading={busy === j.id}
                onClick={() => void start(j)} data-testid={`yahoo-start-${j.id}`}>{reason ?? (cash ? 'Cash out…' : 'Start')}</Button>
            </div>
          );
        })}
      </div>
      <p className="yh-fine">
        Caught = EFCC case: bail from {nairaShort(s.prices.bail)}, escape {100 - s.prices.escape_caught_pct}% chance, your laptop may be seized and part of your yahoo balance taken.
        Cash out in full, in half, or launder through a contact for a fee: less risk, longer wait. In a group mission everybody in the gang gets the case.
      </p>

      <YahooGroups onGo={onGo} locationId={state.profile.location_id} />
      <CashOutSheet open={cashOpen} onClose={() => setCashOpen(false)} />

      {/* ranks */}
      <h4 className="yh-h">Rank</h4>
      <ol className="yh-ranks">
        {s.ranks.map((r) => (
          <li key={r.id} className={r.id === s.rank.id ? 'is-on' : s.total_earned >= r.min_earned ? 'is-done' : ''}>
            <span aria-hidden>{r.icon}</span>
            <span className="grow"><b>{r.name}</b><small>{r.perks}</small></span>
            <em>{r.min_earned > 0 ? nairaShort(r.min_earned) : 'Start'}</em>
          </li>
        ))}
      </ol>

      {/* laptops */}
      <h4 className="yh-h">Laptops</h4>
      <ul className="yh-laptops">
        {s.laptops.map((l) => (
          <li key={l.item_id} className={l.owned ? 'is-owned' : ''}>
            <span className="grow">
              <b>{l.name}</b>
              <small>+{l.pay_bonus_pct}% pay · −{l.efcc_minus_pts} pts EFCC · {l.speed_pct}% faster{s.jobs.some((j) => j.min_tier > 0 && l.tier >= j.min_tier) ? ' · Big job ✓' : ''}</small>
            </span>
            <em>{l.owned ? 'Yours' : nairaShort(l.price ?? 0)}</em>
          </li>
        ))}
      </ul>

      {s.ledger.length > 0 && <>
        <h4 className="yh-h">Yahoo balance history</h4>
        <ul className="yh-ledger">
          {s.ledger.map((l) => (
            <li key={l.id}>
              <span className="grow">{l.label}</span>
              <b className={l.delta >= 0 ? 'is-in' : 'is-out'}>{l.delta >= 0 ? '+' : '−'}{naira(Math.abs(l.delta))}</b>
            </li>
          ))}
        </ul>
      </>}
    </div>
  );
}

function RunBar({ run, now }: { run: NonNullable<YahooStatus['run']>; now: number }) {
  const start = Date.parse(run.started_at);
  const end = Date.parse(run.resolve_at);
  const frac = end > start ? Math.min(1, Math.max(0, (now - start) / (end - start))) : 1;
  return (
    <div className="yh-run" role="status" data-testid="yahoo-run">
      <span className="yh-run__icon" aria-hidden>{run.icon}</span>
      <span className="grow">
        <b>{run.name}{run.mode ? ` · ${run.mode === 'launder' ? 'Launder' : run.mode === 'half' ? 'Half' : 'Full'}` : ''}…</b>
        <small>{Math.max(0, Math.ceil((end - now) / 1000))}s · EFCC {Math.round(run.skill_caught_pct ?? run.caught_pct)}%</small>
        <span className="yh-run__bar"><span style={{ transform: `scaleX(${frac})` }} /></span>
      </span>
    </div>
  );
}
