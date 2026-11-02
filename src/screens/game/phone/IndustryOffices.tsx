// Industry offices (docs/OFFICES.md). Two views of the same server state (ind_status):
//   <IndustrySection/>  the public list in Benin Votes -> Government: every office, its holder, approval, statement, what they changed, Apply.
//   <IndustryHolder/>   the holder's panel in My Office: levers with a slider inside the band, cooldown timers, a confirm card in plain words,
//                       the official statement, approval and recent changes.
// Everything is decided on the server (ind_*); this only shows it.
import { useCallback, useEffect, useState } from 'react';
import {
  fmtLever, indApply, indResign, indSetLever, indStatement, indStatus, indVote, indWithdraw, type IndLever, type IndMe, type IndOffice, type IndStatus,
} from '../../../api/offices';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { naira } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { useOffices } from '../../../state/offices';
import { Button, OfficeTag, toast } from '../../../ui';
import './IndustryOffices.css';

function span(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h ${m} min`;
  return `${Math.max(1, m)} min`;
}

/** The status, loaded on mount and refreshed after every action. */
export function useIndStatus() {
  const [s, setS] = useState<IndStatus | null>(null);
  const reload = useCallback(async () => {
    try { setS(await indStatus()); } catch { /* offline */ }
  }, []);
  useEffect(() => { void reload(); }, [reload]);
  return { s, reload };
}

function useIndAct(reload: () => Promise<void>) {
  const [busy, setBusy] = useState<string | null>(null);
  const refresh = useGame((g) => g.refresh);
  const loadMine = useOffices((o) => o.load);
  const act = useCallback(async (key: string, fn: () => Promise<{ message?: string }>, after?: () => void) => {
    setBusy(key);
    try { const r = await fn(); if (r?.message) toast(r.message, 'good'); after?.(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); void reload(); void refresh(); void loadMine(); }
  }, [reload, refresh, loadMine]);
  return { busy, act };
}

function Approval({ o, reload }: { o: IndOffice; reload: () => Promise<void> }) {
  const h = o.holder;
  const { busy, act } = useIndAct(reload);
  const myId = useGame((g) => g.state?.profile?.id);
  if (!h) return null;
  const a = h.approval;
  const mine = myId === h.user_id;
  return (
    <div className="io-approval" data-testid={`io-approval-${o.id}`}>
      <span className="io-approval__pct">{a.pct == null ? 'No ratings yet' : `${a.pct}% approve`}</span>
      <small>{a.votes} vote{a.votes === 1 ? '' : 's'}</small>
      {!mine && (
        <span className="io-approval__btns">
          <button type="button" className={`io-thumb${a.mine === true ? ' is-on' : ''}`} aria-label={`Thumbs up for ${o.name}`} disabled={busy !== null}
            onClick={() => void act(`u${o.id}`, () => indVote(h.id, true))}>👍</button>
          <button type="button" className={`io-thumb${a.mine === false ? ' is-on' : ''}`} aria-label={`Thumbs down for ${o.name}`} disabled={busy !== null}
            onClick={() => void act(`d${o.id}`, () => indVote(h.id, false))}>👎</button>
        </span>
      )}
    </div>
  );
}

function ApplyForm({ o, s, reload }: { o: IndOffice; s: IndStatus; reload: () => Promise<void> }) {
  const { busy, act } = useIndAct(reload);
  const [open, setOpen] = useState(false);
  const [pitch, setPitch] = useState('');
  const mineHere = s.my_application?.office_id === o.id;
  if (mineHere) {
    return (
      <div className="io-apply">
        <p className="po-ok">Your application is in: “{s.my_application!.pitch}”. An admin will decide.</p>
        <Button size="sm" variant="ghost" loading={busy === 'w'} onClick={() => void act('w', () => indWithdraw())}>Withdraw</Button>
      </div>
    );
  }
  if (!open) {
    return <Button size="sm" variant="gold" disabled={Boolean(s.my_application)} onClick={() => setOpen(true)} data-testid={`io-apply-${o.id}`}>{o.holder ? 'Apply for when it opens' : 'Apply'}</Button>;
  }
  const req = o.requirements;
  return (
    <div className="io-apply" data-testid="io-apply-form">
      <ul className="po-checks">{req.checks.map((c) => <li key={c.key} className={c.ok ? 'is-ok' : 'is-bad'}>{c.ok ? '✓' : '✗'} {c.label}</li>)}</ul>
      <label className="po-field"><span>Your pitch ({pitch.length}/{s.settings.pitch_max_len})</span>
        <textarea value={pitch} maxLength={s.settings.pitch_max_len} onChange={(e) => setPitch(e.target.value)} placeholder="Why you? Keep it short, clean and fictional." /></label>
      <div className="po-actions">
        <Button size="sm" variant="gold" loading={busy === 'a'} disabled={!req.ok || pitch.trim().length < 10} onClick={() => void act('a', () => indApply(o.id, pitch), () => { setOpen(false); setPitch(''); })}>Send application</Button>
        <Button size="sm" variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
      </div>
    </div>
  );
}

function OfficeCard({ o, s, reload }: { o: IndOffice; s: IndStatus; reload: () => Promise<void> }) {
  const [more, setMore] = useState(false);
  const now = useNow(60_000);
  const h = o.holder;
  const changed = o.levers.filter((l) => l.changed);
  return (
    <article className={`po-card io-card${h ? '' : ' is-vacant'}`} data-testid={`io-office-${o.id}`}>
      <div className="po-row">
        <span className="po-icon" aria-hidden>{o.icon}</span>
        <span className="po-row__who">
          <b>{o.name}</b>
          {h ? <small><OfficeTag title={o.title} />@{h.username} · {span((Date.parse(h.term_end) - now) / 1000)} left</small> : <small>Vacant · {naira(o.salary_per_day)} a day</small>}
        </span>
      </div>
      {h && <Approval o={o} reload={reload} />}
      {h?.statement && <p className="io-statement">“{h.statement.body}”</p>}
      {changed.length > 0 && (
        <ul className="io-changes">
          {changed.map((l) => <li key={l.id}><b>{l.label}</b> {fmtLever(l.unit, l.baseline)} → <b>{fmtLever(l.unit, l.current)}</b><small> by @{l.changed_by}</small></li>)}
        </ul>
      )}
      <button type="button" className="po-link" onClick={() => setMore(!more)}>{more ? 'Hide what this office controls' : 'What this office controls'}</button>
      {more && (
        <div className="io-more">
          <p className="po-hint">{o.blurb}</p>
          <ul className="io-levers-list">{o.levers.map((l) => <li key={l.id}><b>{l.label}</b><small>{fmtLever(l.unit, l.current)} now · can go from {fmtLever(l.unit, l.lo)} to {fmtLever(l.unit, l.hi)}</small></li>)}</ul>
          <p className="po-fine">Salary {naira(o.salary_per_day)} a day for a {o.term_days}-day term. Needs an account {o.min_account_days}+ days old{o.min_level > 0 ? ` and career level ${o.min_level}` : ''}. An admin appoints.</p>
        </div>
      )}
      {!h || !s.me ? <ApplyForm o={o} s={s} reload={reload} /> : null}
    </article>
  );
}

/** Benin Votes -> Government: the public "Industry offices" list. */
export function IndustrySection() {
  const { s, reload } = useIndStatus();
  if (!s || !s.enabled || s.offices.length === 0) return null;
  return (
    <section className="io-section" data-testid="industry-offices">
      <h4 className="po-h">Industry offices</h4>
      <p className="po-fine">Heads of the bank, transport, health, markets, schools and housing. Each can change a few settings of their industry, inside strict limits, and everything they change is listed here.</p>
      {s.me && <p className="po-ok">You hold {s.me.office}. Do your work in the My Office app.</p>}
      <div className="po-list">{s.offices.map((o) => <OfficeCard key={o.id} o={o} s={s} reload={reload} />)}</div>
      {s.recent.length > 0 && (
        <div className="po-card" data-testid="io-recent">
          <h4>Latest changes</h4>
          <ul className="io-changes">
            {s.recent.slice(0, 8).map((c, i) => (
              <li key={i}>
                <b>{c.lever}</b> {fmtLever(c.unit, c.old)} → <b>{fmtLever(c.unit, c.new)}</b>
                <small> {c.kind === 'restore' ? 'back to normal' : `${c.office} · @${c.by ?? ''}`} · {new Date(c.at).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</small>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}

// ------------------------------------------------------------------------------------------------ holder panel
function LeverCard({ l, me, reload }: { l: IndLever; me: IndMe; reload: () => Promise<void> }) {
  const now = useNow(1000);
  const { busy, act } = useIndAct(reload);
  const [val, setVal] = useState<number>(l.current);
  const [confirm, setConfirm] = useState(false);
  useEffect(() => { setVal(l.current); setConfirm(false); }, [l.current, l.id]);
  const left = l.next_at ? (Date.parse(l.next_at) - now) / 1000 : 0;
  const cooling = left > 0;
  const capped = me.changes_today >= me.max_changes;
  const locked = l.frozen || me.frozen;
  const lo = l.lo; const hi = l.hi;
  const step = l.step;
  const clamp = (v: number) => Math.min(hi, Math.max(lo, Number((Math.round((v - l.band_min) / step) * step + l.band_min).toFixed(4))));
  const effect = l.effect.replace('{old}', fmtLever(l.unit, l.current)).replace('{new}', fmtLever(l.unit, val));
  const disabled = locked || cooling || capped;
  const pct = hi > lo ? ((val - lo) / (hi - lo)) * 100 : 0;
  const basePct = hi > lo ? ((l.baseline - lo) / (hi - lo)) * 100 : 0;
  return (
    <article className={`po-card io-lever${disabled ? ' is-locked' : ''}`} data-testid={`io-lever-${l.id}`}>
      <div className="io-lever__top">
        <b>{l.label}</b>
        <span className="io-lever__now">{fmtLever(l.unit, l.current)}</span>
      </div>
      <p className="po-fine">{l.blurb} {l.direction}</p>
      <div className="io-slider">
        <button type="button" className="io-step" aria-label="Lower" disabled={disabled || val <= lo} onClick={() => { setVal(clamp(val - step)); setConfirm(false); }}>−</button>
        <div className="io-track">
          <input type="range" min={lo} max={hi} step={step} value={val} disabled={disabled} aria-label={l.label}
            onChange={(e) => { setVal(clamp(Number(e.target.value))); setConfirm(false); }} />
          <span className="io-base" style={{ left: `${Math.min(100, Math.max(0, basePct))}%` }} title="Normal value" />
          <span className="io-fill" style={{ width: `${Math.min(100, Math.max(0, pct))}%` }} />
        </div>
        <button type="button" className="io-step" aria-label="Higher" disabled={disabled || val >= hi} onClick={() => { setVal(clamp(val + step)); setConfirm(false); }}>+</button>
      </div>
      <div className="io-range"><span>{fmtLever(l.unit, lo)}</span><span>normal {fmtLever(l.unit, l.baseline)}</span><span>{fmtLever(l.unit, hi)}</span></div>
      {locked && <p className="po-warn">An admin froze this. You cannot change it for now.</p>}
      {!locked && cooling && <p className="po-warn" data-testid="io-cooldown">You can change this again in {span(left)}.</p>}
      {!locked && !cooling && capped && <p className="po-warn">Your office used its {me.max_changes} changes for today.</p>}
      {!disabled && val !== l.current && !confirm && (
        <Button size="sm" variant="gold" onClick={() => setConfirm(true)}>Review change</Button>
      )}
      {!disabled && val !== l.current && confirm && (
        <div className="io-confirm" data-testid="io-confirm">
          <b>Confirm the change</b>
          <p>{effect}</p>
          <small>It is live for everybody at once, and it goes back to normal when your term ends. Everybody can see who changed it.</small>
          <div className="po-actions">
            <Button size="sm" variant="gold" loading={busy === l.id} onClick={() => void act(l.id, () => indSetLever(l.id, val))}>Confirm</Button>
            <Button size="sm" variant="ghost" onClick={() => { setConfirm(false); setVal(l.current); }}>Cancel</Button>
          </div>
        </div>
      )}
    </article>
  );
}

/** My Office -> an industry holder: levers, statement, approval, recent changes. */
export function IndustryHolder() {
  const { s, reload } = useIndStatus();
  const { busy, act } = useIndAct(reload);
  const now = useNow(1000);
  const [text, setText] = useState('');
  if (!s) return <div className="panel-skel"><span /><span /><span /></div>;
  const me = s.me;
  if (!me) return <p className="po-warn">You no longer hold this office.</p>;
  const a = me.holder.approval;
  const next = me.statement_next_at ? (Date.parse(me.statement_next_at) - now) / 1000 : 0;
  return (
    <div className="po-stack" data-testid="industry-holder">
      <section className="po-card">
        <h4>Your settings</h4>
        <p className="po-hint">Move a setting inside its limits. Changes today: {me.changes_today} of {me.max_changes}. Total distance from normal: {Math.round(me.drift_used)} of {Math.round(me.drift_budget)}.</p>
        <div className="po-bar" aria-hidden><span style={{ width: `${Math.min(100, (me.drift_used / Math.max(1, me.drift_budget)) * 100)}%` }} /></div>
        {me.frozen && <p className="po-warn">An admin froze all your settings.</p>}
      </section>
      {me.levers.map((l) => <LeverCard key={l.id} l={l} me={me} reload={reload} />)}
      <section className="po-card">
        <h4>Approval rating</h4>
        <p className="po-hint">{a.pct == null ? 'Nobody has rated you yet.' : `${a.pct}% of ${a.votes} people approve (${a.up} up, ${a.down} down).`}</p>
        {me.low_approval && <p className="po-warn">Your approval is low. An admin can see this. Talk to the city and use your settings wisely.</p>}
      </section>
      <section className="po-card">
        <h4>Official statement</h4>
        <p className="po-fine">One a day. It shows in Industry offices and goes out as a public notice.</p>
        {me.holder.statement && <p className="io-statement">“{me.holder.statement.body}”</p>}
        <label className="po-field"><span>Statement ({text.length}/{s.settings.statement_max_len})</span>
          <textarea value={text} maxLength={s.settings.statement_max_len} onChange={(e) => setText(e.target.value)} placeholder="The counter is open and the fees are fair." /></label>
        {!me.can_statement && <p className="po-warn">Next statement in {span(next)}.</p>}
        <Button size="sm" loading={busy === 'st'} disabled={!me.can_statement || text.trim().length < 10} onClick={() => void act('st', () => indStatement(text), () => setText(''))}>Post statement</Button>
      </section>
      <section className="po-card" data-testid="io-mine-recent">
        <h4>Recent changes in your office</h4>
        {me.recent.length === 0 ? <p className="po-fine">Nothing changed yet.</p> : (
          <ul className="io-changes">{me.recent.map((c, i) => <li key={i}><b>{c.lever}</b> {fmtLever(c.unit, c.old)} → <b>{fmtLever(c.unit, c.new)}</b><small> {c.kind === 'restore' ? 'back to normal' : ''} {new Date(c.at).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</small></li>)}</ul>
        )}
      </section>
      <button type="button" className="po-link" onClick={() => { if (window.confirm('Resign? Everything you changed goes back to normal.')) void act('resign', () => indResign()); }}>Resign</button>
    </div>
  );
}
