// R12 Benin Votes app (docs/POLITICS.md). Tabs: Government (officeholders, policy, term countdown, my powers), Elections (phase, declare, campaign,
// candidates), Vote (my polling unit and the ballot), Results (history). Everything is decided on the server (pol_*); this only shows it.
// A fictional, light, satirical game: made-up parties, no real politicians, no vote buying (there is a report button instead).
import { useCallback, useEffect, useState } from 'react';
import {
  polAnnounce, polAppoint, polBack, polBallot, polCandidates, polDeclare, polPartyCreate, polPoster, polRally, polReportVoteBuying, polResign, polResults, polSack,
  polSetPolicy, polSetPromise, polUnback, polVote, polWardNotice, polWithdraw, type PartyBadge, type PolBallot, type PolCandidate, type PolHolder, type PolOffice,
  type PolResult, type PolSeat, type PolStatus,
} from '../../../api/politics';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { naira, nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { usePolitics } from '../../../state/politics';
import { useUi } from '../../../state/ui';
import { Button, CrewTag, EmptyState, OfficeTag, Tabs, toast } from '../../../ui';
import './PoliticsApp.css';

type Tab = 'gov' | 'elect' | 'vote' | 'results';

/** "2 d 4 h", "3 h 10 min", "5 min" for a number of seconds. */
function span(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h ${m} min`;
  return `${Math.max(1, m)} min`;
}
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');

function useAct() {
  const [busy, setBusy] = useState<string | null>(null);
  const load = usePolitics((s) => s.load);
  const refresh = useGame((s) => s.refresh);
  const act = useCallback(async (key: string, fn: () => Promise<{ message?: string }>, after?: () => void) => {
    setBusy(key);
    try { const r = await fn(); if (r?.message) toast(r.message, 'good'); after?.(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); void load(); void refresh(); }
  }, [load, refresh]);
  return { busy, act };
}

function PartyChip({ party }: { party: PartyBadge | null | undefined }) {
  if (!party) return <span className="po-fine">Independent</span>;
  return <span className="po-party" style={{ ['--pc' as string]: party.color }} title={party.name}>{party.abbr}</span>;
}

// ------------------------------------------------------------------------------------------------ header
function Head({ s }: { s: PolStatus }) {
  const now = useNow(1000);
  const c = s.cycle;
  const left = c ? (Date.parse(c.next_at) - now) / 1000 : 0;
  const next = !c && s.next_cycle_at ? (Date.parse(s.next_cycle_at) - now) / 1000 : 0;
  const label = !c ? 'No election right now' : c.status === 'registration' ? 'Registration is open' : c.status === 'campaign' ? 'Campaign season' : 'Voting day';
  const sub = !c ? (s.next_cycle_at ? `The next election opens in ${span(next)}.` : 'An admin will open the next election.')
    : c.status === 'registration' ? `Candidates declare. Registration closes in ${span(left)}.`
    : c.status === 'campaign' ? `Rallies, posters, endorsements. Voting day in ${span(left)}.`
    : `Polling units are open. Vote at your ward unit. Closes in ${span(left)}.`;
  return (
    <div className={`po-head${c?.status === 'voting' ? ' is-voting' : !c ? ' is-idle' : ''}`} data-testid="pol-head">
      <small>Benin Votes · fictional parties, real fun</small>
      <b>{c?.status === 'voting' ? '🗳️ ' : c ? '📣 ' : '🏛️ '}{label}</b>
      <small>{sub}</small>
      {c && <span className="po-count">{span(left)}</span>}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ government
function SeatRow({ seat }: { seat: PolSeat }) {
  const h = seat.holder;
  return (
    <article className={`po-card po-row po-seat${h ? '' : ' is-vacant'}`}>
      <span className="po-icon" aria-hidden>{seat.icon}</span>
      <span className="po-row__who">
        <b>{seat.office}{seat.ward ? ` · ${seat.ward}` : ''}</b>
        {h ? <small><OfficeTag title={h.title} />@{h.username} <PartyChip party={h.party} /></small> : <small>Vacant{seat.kind === 'commissioner' ? ' · the Governor appoints' : ''}</small>}
      </span>
    </article>
  );
}

function MyOffice({ s, h }: { s: PolStatus; h: PolHolder }) {
  const { busy, act } = useAct();
  const now = useNow(1000);
  const pw = s.me.powers;
  const [ann, setAnn] = useState('');
  const [ward, setWard] = useState('');
  const [who, setWho] = useState<Record<string, string>>({});
  const isGov = h.kind === 'governor';
  const nextAnn = pw.announce_next_at ? (Date.parse(pw.announce_next_at) - now) / 1000 : 0;
  return (
    <section className="po-card" data-testid="pol-my-office">
      <h4><OfficeTag title={h.title} />{h.office}{h.ward ? ` · ${h.ward}` : ''}</h4>
      <p className="po-hint">You hold office for another <b>{span((Date.parse(h.term_end) - now) / 1000)}</b>. Salary {naira(h.salary_per_day)} a day, paid to your bank ({naira(h.salary_paid)} so far).</p>
      {isGov && (
        <>
          <div className="po-card" style={{ boxShadow: 'none', background: 'var(--surface-2)' }}>
            <h4>Government announcement</h4>
            <p className="po-fine">One a day, to every player. Keep it clean and fictional.</p>
            <label className="po-field"><span>Message ({ann.length}/{s.settings.announce_max_len})</span>
              <textarea value={ann} maxLength={s.settings.announce_max_len} onChange={(e) => setAnn(e.target.value)} placeholder="Keke fares drop on Friday. Make everybody dey enjoy am!" /></label>
            {!pw.can_announce && <p className="po-warn">Next announcement in {span(nextAnn)}.</p>}
            <Button size="sm" loading={busy === 'ann'} disabled={!pw.can_announce || ann.trim().length < 10} onClick={() => void act('ann', () => polAnnounce(ann), () => setAnn(''))}>Send to everybody</Button>
          </div>
          <div className="po-card" style={{ boxShadow: 'none', background: 'var(--surface-2)' }}>
            <h4>Your one policy this term</h4>
            {s.policy ? <p className="po-ok">{s.policy.icon} {s.policy.name} is in force. {s.policy.blurb}</p> : (
              <div className="po-list">
                {(pw.policies ?? []).map((p) => (
                  <div key={p.id} className="po-row">
                    <span className="po-icon" aria-hidden>{p.icon}</span>
                    <span className="po-row__who"><b>{p.name}</b><small>{p.blurb}</small></span>
                    <Button size="sm" variant="gold" loading={busy === `p${p.id}`} onClick={() => { if (window.confirm(`Set ${p.name}? You get ONE policy for the whole term.`)) void act(`p${p.id}`, () => polSetPolicy(p.id)); }}>Set</Button>
                  </div>
                ))}
              </div>
            )}
          </div>
          <div className="po-card" style={{ boxShadow: 'none', background: 'var(--surface-2)' }}>
            <h4>Commissioners</h4>
            {(pw.commissioners ?? []).map((c) => (
              <div key={c.office_id} className="po-row">
                <span className="po-icon" aria-hidden>{c.icon}</span>
                <span className="po-row__who"><b>{c.office}</b><small>{c.username ? `@${c.username}` : 'Vacant'}</small></span>
                {c.username
                  ? <Button size="sm" variant="danger" loading={busy === `s${c.office_id}`} onClick={() => { if (window.confirm(`Sack @${c.username}?`)) void act(`s${c.office_id}`, () => polSack(c.office_id)); }}>Sack</Button>
                  : (
                    <span className="po-inline" style={{ flex: '1 1 150px' }}>
                      <input value={who[c.office_id] ?? ''} placeholder="username" aria-label={`Username for ${c.office}`} onChange={(e) => setWho({ ...who, [c.office_id]: e.target.value })} />
                      <Button size="sm" loading={busy === `a${c.office_id}`} disabled={!(who[c.office_id] ?? '').trim()} onClick={() => void act(`a${c.office_id}`, () => polAppoint(c.office_id, who[c.office_id]), () => setWho({ ...who, [c.office_id]: '' }))}>Appoint</Button>
                    </span>
                  )}
              </div>
            ))}
          </div>
        </>
      )}
      {h.kind === 'councillor' && (
        <div className="po-card" style={{ boxShadow: 'none', background: 'var(--surface-2)' }}>
          <h4>Ward notice</h4>
          <p className="po-fine">Sponsor ONE ward event notice this term. It goes to the recently active people of {h.ward}.</p>
          {pw.can_ward_notice ? (
            <>
              <label className="po-field"><span>Message ({ward.length}/{s.settings.ward_announce_max_len})</span>
                <textarea value={ward} maxLength={s.settings.ward_announce_max_len} onChange={(e) => setWard(e.target.value)} placeholder="Ward football match on Saturday, everybody come!" /></label>
              <Button size="sm" loading={busy === 'ward'} disabled={ward.trim().length < 10} onClick={() => void act('ward', () => polWardNotice(ward), () => setWard(''))}>Send to the ward</Button>
            </>
          ) : <p className="po-ok">You already sent your ward notice for this term.</p>}
        </div>
      )}
      <button type="button" className="po-link" onClick={() => { if (window.confirm('Resign from office? The seat stays vacant until the next election.')) void act('resign', () => polResign()); }}>Resign</button>
    </section>
  );
}

function GovTab({ s }: { s: PolStatus }) {
  const seats = s.government;
  const top = seats.filter((x) => x.kind === 'governor' || x.kind === 'chairman');
  const comm = seats.filter((x) => x.kind === 'commissioner');
  const council = seats.filter((x) => x.kind === 'councillor');
  const filled = seats.filter((x) => x.holder).length;
  const end = seats.map((x) => x.holder?.term_end).filter(Boolean).sort()[0];
  const now = useNow(1000);
  return (
    <div className="po-stack" data-testid="pol-gov">
      {s.me.office && <MyOffice s={s} h={s.me.office} />}
      {s.policy ? (
        <section className="po-card" data-testid="pol-policy">
          <h4>{s.policy.icon} Government policy: {s.policy.name}</h4>
          <p className="po-hint">{s.policy.blurb} Set by Gov. @{s.policy.by}. In force until the term ends{s.policy.term_end ? ` (${span((Date.parse(s.policy.term_end) - now) / 1000)} left)` : ''}.</p>
        </section>
      ) : filled > 0 ? <p className="po-fine">The Governor has not set a policy yet.</p> : null}
      {filled === 0 && <EmptyState icon="sparkle" title="No government yet" body="The seats are empty. Run for office, or help choose who sits in them: open the Elections tab." />}
      {filled > 0 && end && <p className="po-fine">Current term ends in {span((Date.parse(end) - now) / 1000)}.</p>}
      <h4 className="po-h">The top table</h4>
      <div className="po-list">{top.map((x) => <SeatRow key={x.office_id} seat={x} />)}</div>
      <h4 className="po-h">Commissioners</h4>
      <div className="po-list">{comm.map((x) => <SeatRow key={x.office_id} seat={x} />)}</div>
      <h4 className="po-h">Councillors, one per ward</h4>
      <div className="po-list">{council.map((x) => <SeatRow key={`${x.office_id}:${x.ward_id}`} seat={x} />)}</div>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ elections
function Steps({ s }: { s: PolStatus }) {
  const c = s.cycle;
  const order = ['registration', 'campaign', 'voting'];
  const at = c ? order.indexOf(c.status) : -1;
  const starts = c ? [c.reg_start, c.camp_start, c.vote_start] : [];
  const names = ['Registration', 'Campaign', 'Voting day'];
  return (
    <div className="po-steps" aria-label="Election phases">
      {names.map((n, i) => (
        <div key={n} className={`po-step${i === at ? ' is-on' : i < at ? ' is-done' : ''}`}><b>{n}</b>{c ? when(starts[i]) : `${[s.settings.registration_hours, s.settings.campaign_hours, s.settings.voting_hours][i]} h`}</div>
      ))}
    </div>
  );
}

function PartyForm({ fee }: { fee: number }) {
  const { busy, act } = useAct();
  const [name, setName] = useState('');
  const [abbr, setAbbr] = useState('');
  const [color, setColor] = useState('#2f9e6b');
  return (
    <form className="po-card" onSubmit={(e) => { e.preventDefault(); void act('party', () => polPartyCreate(name, abbr, color), () => { setName(''); setAbbr(''); }); }}>
      <h4>Found your own party</h4>
      <p className="po-fine">Make it fictional. Real parties and real politicians are not allowed. Costs {naira(fee)}.</p>
      <label className="po-field"><span>Party name</span><input value={name} maxLength={32} placeholder="e.g. Ugbowo Green Front" onChange={(e) => setName(e.target.value)} /></label>
      <label className="po-field"><span>Short name (2 to 5 letters)</span><input value={abbr} maxLength={5} placeholder="UGF" onChange={(e) => setAbbr(e.target.value.replace(/[^a-zA-Z]/g, '').toUpperCase())} /></label>
      <label className="po-field"><span>Colour</span><input type="color" value={color} onChange={(e) => setColor(e.target.value)} aria-label="Party colour" style={{ height: 40, padding: 2 }} /></label>
      <Button type="submit" size="sm" loading={busy === 'party'} disabled={name.trim().length < 4 || abbr.length < 2}>Found it for {nairaShort(fee)}</Button>
    </form>
  );
}

function Declare({ s }: { s: PolStatus }) {
  const { busy, act } = useAct();
  const elected = s.offices.filter((o) => o.elected);
  const [officeId, setOfficeId] = useState(elected[0]?.id ?? 'councillor');
  const [promise, setPromise] = useState('');
  const [party, setParty] = useState('');
  const [showParty, setShowParty] = useState(false);
  const o: PolOffice | undefined = elected.find((x) => x.id === officeId);
  const req = o?.requirements;
  return (
    <section className="po-card" data-testid="pol-declare">
      <h4>Declare your candidacy</h4>
      <label className="po-field"><span>Office</span>
        <select value={officeId} onChange={(e) => setOfficeId(e.target.value)}>
          {elected.map((x) => <option key={x.id} value={x.id}>{x.icon} {x.name} · fee {nairaShort(x.fee)}</option>)}
        </select></label>
      {o && <p className="po-hint">{o.blurb} Salary {naira(o.salary_per_day)} a day if you win.{o.ward_scoped ? ` You run in the ward where you live: ${s.me.ward.name}.` : ''}</p>}
      {req && (
        <ul className="po-checks" aria-label="Requirements">
          {req.checks.map((c) => <li key={c.key} className={c.ok ? 'is-ok' : 'is-bad'}>{c.ok ? '✓' : '✗'} {c.label}</li>)}
        </ul>
      )}
      <label className="po-field"><span>Campaign promise ({promise.length}/{s.settings.promise_max_len})</span>
        <textarea value={promise} maxLength={s.settings.promise_max_len} onChange={(e) => setPromise(e.target.value)} placeholder="Steady light and clean gutters for every street" /></label>
      <label className="po-field"><span>Party</span>
        <select value={party} onChange={(e) => setParty(e.target.value)}>
          <option value="">Independent</option>
          {s.parties.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.abbr}){p.mine ? ' · yours' : ''}</option>)}
        </select></label>
      {req && !req.ok && <p className="po-warn">{req.message}</p>}
      <Button loading={busy === 'declare'} disabled={!o || !req?.ok || promise.trim().length < 10}
        onClick={() => void act('declare', () => polDeclare(officeId, o?.ward_scoped ? s.me.ward.id : null, promise, party || null), () => setPromise(''))}>
        Declare for {o ? nairaShort(o.fee) : ''}
      </Button>
      <button type="button" className="po-link" onClick={() => setShowParty(!showParty)}>{showParty ? 'Hide' : 'Found your own party'}</button>
      {showParty && <PartyForm fee={s.settings.party_fee} />}
    </section>
  );
}

function MyCampaign({ s, c, reload }: { s: PolStatus; c: PolCandidate; reload: () => void }) {
  const { busy, act } = useAct();
  const now = useNow(1000);
  const [edit, setEdit] = useState(false);
  const [text, setText] = useState(c.promise);
  const phase = s.cycle?.status;
  const wait = s.me.next_rally_at ? (Date.parse(s.me.next_rally_at) - now) / 1000 : 0;
  const here = useGame((x) => x.state?.location.name);
  const done = (fn: () => Promise<{ message?: string }>, key: string) => void act(key, fn, reload);
  return (
    <section className="po-card" data-testid="pol-my-campaign">
      <h4>Your campaign: {c.office}{c.ward ? ` · ${c.ward}` : ''} <PartyChip party={c.party} /></h4>
      {edit ? (
        <>
          <label className="po-field"><span>Promise</span><textarea value={text} maxLength={s.settings.promise_max_len} onChange={(e) => setText(e.target.value)} /></label>
          <div className="po-actions">
            <Button size="sm" loading={busy === 'prom'} onClick={() => done(() => polSetPromise(text), 'prom')}>Save</Button>
            <Button size="sm" variant="ghost" onClick={() => setEdit(false)}>Cancel</Button>
          </div>
        </>
      ) : <p className="po-promise">“{c.promise}” {phase !== 'voting' && <button type="button" className="po-link" onClick={() => { setText(c.promise); setEdit(true); }}>Edit</button>}</p>}
      <div className="po-mom"><span>Momentum</span><b>{c.momentum}</b></div>
      <div className="po-bar" aria-hidden><span style={{ width: `${c.momentum_pct}%` }} /></div>
      <div className="po-chips">
        <span className="po-chip">🎤 {c.rallies} rall{c.rallies === 1 ? 'y' : 'ies'} · {c.rally_points} pts</span>
        <span className="po-chip">🪧 {c.posters} poster{c.posters === 1 ? '' : 's'}</span>
        <span className="po-chip">🙋 {c.supporters} supporter{c.supporters === 1 ? '' : 's'}</span>
        <span className="po-chip">🤝 {c.endorse_n} endorsement{c.endorse_n === 1 ? '' : 's'}</span>
      </div>
      {phase === 'campaign' && (
        <div className="po-actions">
          <Button size="sm" variant="gold" loading={busy === 'rally'} disabled={wait > 0} onClick={() => done(() => polRally(), 'rally')}>
            {wait > 0 ? `Rally in ${span(wait)}` : `Hold a rally here · ${nairaShort(s.settings.rally_cost)}`}
          </Button>
          <Button size="sm" variant="ghost" loading={busy === 'poster'} disabled={c.posters >= s.settings.poster_max} onClick={() => done(() => polPoster(), 'poster')}>Put up a poster · {nairaShort(s.settings.poster_cost)}</Button>
        </div>
      )}
      {phase === 'campaign' && <p className="po-fine">A rally happens where you stand now{here ? ` (${here})` : ''}: stand at a busy public place, and bring friends, because every player there adds points. Councillors rally inside their ward. Vote buying is not allowed.</p>}
      {phase !== 'voting' && <button type="button" className="po-link" onClick={() => { if (window.confirm('Withdraw from the election? Your fee is not refunded.')) done(() => polWithdraw(), 'wd'); }}>Withdraw</button>}
    </section>
  );
}

function CandidateCard({ c, s, reload }: { c: PolCandidate; s: PolStatus; reload: () => void }) {
  const { busy, act } = useAct();
  const phase = s.cycle?.status;
  const canBack = phase === 'registration' || phase === 'campaign';
  const done = (fn: () => Promise<{ message?: string }>, key: string) => void act(key, fn, reload);
  return (
    <article className="po-card" data-testid="pol-candidate">
      <div className="po-row">
        <span className="po-row__who"><b><OfficeTag title={c.title} />@{c.username}{c.mine ? ' (you)' : ''}</b><small><PartyChip party={c.party} /> {c.office}{c.ward ? ` · ${c.ward}` : ''}</small></span>
      </div>
      <p className="po-promise">“{c.promise}”</p>
      <div className="po-mom"><span>Momentum</span><b>{c.momentum}</b></div>
      <div className="po-bar" aria-hidden><span style={{ width: `${c.momentum_pct}%` }} /></div>
      <div className="po-chips">
        <span className="po-chip">🎤 {c.rallies}</span><span className="po-chip">🪧 {c.posters}</span><span className="po-chip">🙋 {c.supporters}</span>
        {c.endorsers.map((n) => <span key={n} className="po-chip">🤝 @{n}</span>)}
        {c.crews.map((cr) => <span key={cr.tag} className="po-chip"><CrewTag tag={cr.tag} color={cr.color} emblem={cr.emblem} />{cr.name}</span>)}
      </div>
      {!c.mine && canBack && (
        <div className="po-actions">
          {c.my_backing === 'support' || c.my_backing === 'endorse'
            ? <Button size="sm" variant="ghost" loading={busy === `u${c.id}`} onClick={() => done(() => polUnback(c.id), `u${c.id}`)}>Remove my {c.my_backing === 'endorse' ? 'endorsement' : 'support'}</Button>
            : (
              <>
                <Button size="sm" variant="ghost" loading={busy === `s${c.id}`} onClick={() => done(() => polBack(c.id, 'support'), `s${c.id}`)}>I support</Button>
                <Button size="sm" variant="ghost" loading={busy === `e${c.id}`} onClick={() => done(() => polBack(c.id, 'endorse'), `e${c.id}`)}>Endorse</Button>
              </>
            )}
          {c.my_backing === 'crew'
            ? <Button size="sm" variant="ghost" onClick={() => done(() => polUnback(c.id, 'crew'), `uc${c.id}`)}>Remove crew endorsement</Button>
            : <Button size="sm" variant="ghost" loading={busy === `c${c.id}`} onClick={() => done(() => polBack(c.id, 'crew'), `c${c.id}`)}>Endorse for my crew</Button>}
        </div>
      )}
      {!c.mine && (
        <button type="button" className="po-link" onClick={() => { const r = window.prompt('What did you see? (Vote buying is not allowed. An admin will review it.)'); if (r !== null) done(() => polReportVoteBuying(c.id, r), `r${c.id}`); }}>Report vote buying</button>
      )}
    </article>
  );
}

function ElectTab({ s }: { s: PolStatus }) {
  const [list, setList] = useState<PolCandidate[] | null>(null);
  const load = useCallback(() => { void polCandidates().then(setList).catch(() => setList([])); }, []);
  useEffect(() => { load(); const id = window.setInterval(load, 30000); return () => window.clearInterval(id); }, [load, s.cycle?.status]);
  const c = s.cycle;
  const mine = s.me.candidacy;
  const bySlot = new Map<string, PolCandidate[]>();
  for (const k of list ?? []) bySlot.set(k.slot_key, [...(bySlot.get(k.slot_key) ?? []), k]);
  const myWardSlot = `councillor:${s.me.ward.id}`;
  const slots = [...bySlot.entries()];
  const order = (key: string) => (key.startsWith('governor') ? 0 : key.startsWith('chairman') ? 1 : key === myWardSlot ? 2 : 3);
  slots.sort((a, b) => order(a[0]) - order(b[0]));
  return (
    <div className="po-stack" data-testid="pol-elect">
      <Steps s={s} />
      {!c && <EmptyState icon="sparkle" title="No election right now" body={s.next_cycle_at ? 'The next one opens soon. Check the countdown above.' : 'An admin will open the next election. Come back soon.'} />}
      {c?.status === 'registration' && !mine && <Declare s={s} />}
      {c?.status === 'registration' && mine && <p className="po-ok">You are a candidate. Campaign season starts when registration closes.</p>}
      {mine && c && <MyCampaign s={s} c={mine} reload={load} />}
      {c && (list == null ? <div className="panel-skel"><span /><span /></div> : slots.length === 0 ? <p className="po-fine">Nobody has declared yet.</p> : slots.map(([key, rows]) => (
        <details key={key} className="po-race" open={order(key) < 3}>
          <summary>{rows[0].office}{rows[0].ward ? ` · ${rows[0].ward}` : ''} ({rows.length}){key === myWardSlot ? ' · your ward' : ''}</summary>
          <div className="po-list">{rows.map((k) => <CandidateCard key={k.id} c={k} s={s} reload={load} />)}</div>
        </details>
      )))}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ vote
function VoteTab({ s, onGo }: { s: PolStatus; onGo: (id: string) => void }) {
  const { busy, act } = useAct();
  const [b, setB] = useState<PolBallot | null>(null);
  const [pick, setPick] = useState<Record<string, number>>({});
  const load = useCallback(() => { void polBallot().then(setB).catch((e) => toast(errorMessage(e), 'bad')); }, []);
  useEffect(() => { load(); const id = window.setInterval(load, 20000); return () => window.clearInterval(id); }, [load, s.me.at_polling_unit, s.cycle?.status]);
  const now = useNow(1000);
  const refreshGame = useGame((x) => x.refresh);
  if (!b) return <div className="panel-skel"><span /><span /><span /></div>;
  const open = b.voting_open;
  return (
    <div className="po-stack" data-testid="pol-vote">
      <section className={`po-card po-poll${open ? ' is-open' : ''}`}>
        <h4>🗳️ Your polling unit</h4>
        <p className="po-hint">You live in <b>{b.ward.name}</b> ward. Vote at the <b>{b.unit.name}</b>, which opens on voting day only.</p>
        {open ? <p className="po-ok">Voting is open for {span((Date.parse(b.closes_at ?? '') - now) / 1000)}. {b.at_unit ? 'You are at your polling unit.' : 'Travel to your polling unit to vote.'}</p>
          : <p className="po-warn">{b.phase === 'none' ? 'There is no election right now.' : `Voting opens ${when(b.opens_at)}. Until then the polling units are closed.`}</p>}
        {!b.eligible.ok && <p className="po-warn">{b.eligible.message}</p>}
        {open && !b.at_unit && <Button size="sm" variant="gold" onClick={() => onGo(b.unit.id)}>Go to {b.unit.name}</Button>}
        <p className="po-fine">One vote per office. Your ballot is secret: the counts are public only after voting closes. Never sell or buy a vote. You can report it from the Elections tab.</p>
      </section>
      {b.races.map((r) => {
        const key = r.slot_key;
        return (
          <section key={key} className="po-card" data-testid="pol-race">
            <h4>{r.icon} {r.office}{r.ward ? ` · ${r.ward}` : ''}</h4>
            {r.voted ? <p className="po-ok">You voted in this race. Your ballot is secret.</p> : r.candidates.length === 0 ? <p className="po-fine">No candidates in this race.</p> : (
              <>
                <div className="po-list">
                  {r.candidates.map((c) => (
                    <button key={c.id} type="button" className={`po-pick${pick[key] === c.id ? ' is-on' : ''}`} disabled={!b.can_vote} onClick={() => setPick({ ...pick, [key]: c.id })} aria-pressed={pick[key] === c.id}>
                      <span><b><OfficeTag title={c.title} />@{c.username} <PartyChip party={c.party} /></b><small className="po-fine">“{c.promise}”</small></span>
                    </button>
                  ))}
                </div>
                <Button loading={busy === key} disabled={!b.can_vote || !pick[key]} onClick={() => void act(key, () => polVote(pick[key]), () => { load(); void refreshGame(); })}>
                  {b.can_vote ? 'Cast my vote' : open ? 'Go to your polling unit to vote' : 'Voting is closed'}
                </Button>
              </>
            )}
          </section>
        );
      })}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ results
function ResultsTab() {
  const [rows, setRows] = useState<PolResult[] | null>(null);
  useEffect(() => { void polResults(5).then(setRows).catch((e) => { toast(errorMessage(e), 'bad'); setRows([]); }); }, []);
  if (!rows) return <div className="panel-skel"><span /><span /><span /></div>;
  if (rows.length === 0) return <EmptyState icon="sparkle" title="No results yet" body="The first election has not closed. When it does, every race and every tally shows here." />;
  return (
    <div className="po-stack" data-testid="pol-results">
      {rows.map((r) => (
        <section key={r.cycle_id} className="po-card">
          <h4>Election #{r.cycle_id} · {when(r.closed_at)}</h4>
          <p className="po-fine">{r.votes} vote{r.votes === 1 ? '' : 's'} from {r.voters} voter{r.voters === 1 ? '' : 's'}. Low turnout is fine.</p>
          {r.races.map((x) => (
            <details key={`${x.office_id}:${x.ward_id}`} className="po-race">
              <summary>{x.icon} {x.office}{x.ward ? ` · ${x.ward}` : ''}: <b>@{x.winner.username}</b> {x.tie && <span className="po-tie">{x.tie === 'rally' ? 'won on rally points' : 'won on a coin flip'}</span>}</summary>
              <div className="po-tally">
                {x.candidates.flatMap((c) => [
                  <span key={`${c.username}n`}>@{c.username} <PartyChip party={c.party} /> {c.won && <span className="po-win">won</span>}</span>,
                  <span key={`${c.username}v`}>{c.votes}</span>,
                ])}
              </div>
            </details>
          ))}
        </section>
      ))}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ app
export default function PoliticsApp({ onGo }: { onGo: (id: string) => void }) {
  const s = usePolitics((x) => x.status);
  const phoneApp = useUi((x) => x.phoneApp);
  const nonce = useUi((x) => x.phoneNonce);
  const [tab, setTab] = useState<Tab>('gov');
  useEffect(() => { void usePolitics.getState().load(); }, []);
  // politics:vote (the polling desk, the banner) opens on the Vote tab
  useEffect(() => {
    const m = /^politics:(gov|elect|vote|results)$/.exec(phoneApp ?? '');
    if (m) setTab(m[1] as Tab);
  }, [phoneApp, nonce]);
  if (!s) return <div className="phone-app__body"><div className="panel-skel"><span /><span /><span /></div></div>;
  if (!s.enabled) return <div className="phone-app__body"><p className="phone-app__lead">Benin Votes is closed for now.</p></div>;
  const tabs = [
    { id: 'gov', label: 'Government' },
    { id: 'elect', label: 'Elections', badge: s.cycle?.status === 'registration' && !s.me.candidacy ? '!' : null },
    { id: 'vote', label: 'Vote', badge: s.cycle?.voting_open && s.me.voted.length < 3 ? '!' : null },
    { id: 'results', label: 'Results' },
  ];
  return (
    <div className="phone-app__body po-body" data-testid="politics-app">
      <div className="po-app">
        <Head s={s} />
        <Tabs tabs={tabs} value={tab} onChange={(t) => setTab(t as Tab)} />
        {tab === 'gov' && <GovTab s={s} />}
        {tab === 'elect' && <ElectTab s={s} />}
        {tab === 'vote' && <VoteTab s={s} onGo={onGo} />}
        {tab === 'results' && <ResultsTab />}
      </div>
    </div>
  );
}

