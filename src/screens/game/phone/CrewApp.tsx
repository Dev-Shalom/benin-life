// R11 Crew app (docs/CREWS.md). No crew: invites, Create, Browse. In a crew: Overview, Jobs (lobby, countdown, result), Bank, Chat, Settings.
// Everything is decided on the server (crew_*); this only shows it. A game mechanic: abstract jobs, fictional crews, real jail risk.
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  crewBankLog, crewBrowse, crewCandidates, crewChatRecent, crewChatSend, crewCreate, crewDeposit, crewDisband, crewInvite, crewInviteCancel, crewInviteRespond,
  crewJobCancel, crewJobJoin, crewJobLeave, crewJobOpen, crewJobStart, crewJoinOpen, crewKick, crewLeave, crewOptions, crewRename, crewReport, crewSetRank,
  crewTransfer, crewUpgrade, RANK_LABEL, type BankRow, type Candidate, type ChatRow, type Crew, type CrewJob, type CrewListed, type CrewMember, type CrewRun,
} from '../../../api/crews';
import { canPoll } from '../../../lib/activity';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { countdown, naira, nairaShort, secondsUntil } from '../../../lib/format';
import { useCrew } from '../../../state/crew';
import { useGame } from '../../../state/game';
import { Button, CrewTag, EmptyState, Tabs, toast } from '../../../ui';
import './CrewApp.css';

const COLORS = ['#e0a030', '#d94a3d', '#2f9e6b', '#2f7fd1', '#8a5bd6', '#e0629a', '#1f2a36', '#7a8a99'];
type Tab = 'overview' | 'jobs' | 'bank' | 'chat' | 'settings';

function useAct() {
  const [busy, setBusy] = useState<string | null>(null);
  const load = useCrew((s) => s.load);
  const refresh = useGame((s) => s.refresh);
  const act = useCallback(async (key: string, fn: () => Promise<{ message?: string }>, after?: () => void) => {
    setBusy(key);
    try { const r = await fn(); if (r?.message) toast(r.message, 'good'); after?.(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); void load(); void refresh(); }
  }, [load, refresh]);
  return { busy, act };
}

// ------------------------------------------------------------------------------------------------ no crew
function Create({ s }: { s: NonNullable<ReturnType<typeof useCrew.getState>['status']> }) {
  const { busy, act } = useAct();
  const [name, setName] = useState('');
  const [tag, setTag] = useState('');
  const [color, setColor] = useState(COLORS[0]);
  const [emblem, setEmblem] = useState(s.settings.emblems[0] ?? '🦁');
  const st = s.settings;
  return (
    <form className="cr-card cr-form" onSubmit={(e) => { e.preventDefault(); void act('create', () => crewCreate(name, tag, color, emblem)); }} data-testid="crew-create">
      <h4>Start a gang</h4>
      <p className="cr-hint">Pick a name wey be yours. Starting a gang costs <b>{naira(st.found_fee)}</b>. You need Charisma level {st.found_min_charisma} or an account at least {st.found_min_account_hours} hours old.</p>
      <div className="cr-preview"><span className="cr-badge" style={{ background: color }} aria-hidden>{emblem}</span><b>{name || 'Your gang name'}</b><CrewTag tag={(tag || 'TAG').toUpperCase()} color={color} /></div>
      <label className="cr-field"><span>Gang name</span><input value={name} maxLength={20} placeholder="e.g. Ring Road Boys" onChange={(e) => setName(e.target.value)} enterKeyHint="next" /></label>
      <label className="cr-field"><span>Tag (3 or 4 letters)</span><input value={tag} maxLength={4} placeholder="RNG" onChange={(e) => setTag(e.target.value.replace(/[^a-zA-Z]/g, '').toUpperCase())} enterKeyHint="done" /></label>
      <div className="cr-field"><span>Colour</span><div className="cr-swatches">{COLORS.map((c) => <button key={c} type="button" className={c === color ? 'is-on' : ''} style={{ background: c }} aria-label={`Colour ${c}`} onClick={() => setColor(c)} />)}</div></div>
      <div className="cr-field"><span>Emblem</span><div className="cr-emblems">{st.emblems.map((m) => <button key={m} type="button" className={m === emblem ? 'is-on' : ''} onClick={() => setEmblem(m)}>{m}</button>)}</div></div>
      {!s.can_found.ok && <p className="cr-warn">{s.can_found.message}</p>}
      <Button type="submit" block loading={busy === 'create'} disabled={!s.can_found.ok || name.trim().length < 3 || tag.length < 3}>Start it for {nairaShort(st.found_fee)}</Button>
    </form>
  );
}

function Browse() {
  const { busy, act } = useAct();
  const [q, setQ] = useState('');
  const [rows, setRows] = useState<CrewListed[] | null>(null);
  const load = useCallback((text: string) => { void crewBrowse(text).then((r) => setRows(r.crews)).catch((e) => toast(errorMessage(e), 'bad')); }, []);
  useEffect(() => { load(''); }, [load]);
  return (
    <div className="cr-list">
      <input className="cr-search" value={q} placeholder="Search gangs" onChange={(e) => { setQ(e.target.value); load(e.target.value); }} enterKeyHint="search" />
      {rows && rows.length === 0 && <EmptyState title="No gangs yet" body="Be the first. Start one." />}
      {rows?.map((c) => (
        <article key={c.id} className="cr-card cr-row">
          <span className="cr-badge" style={{ background: c.color }} aria-hidden>{c.emblem}</span>
          <span className="cr-row__who"><b>{c.name} <CrewTag tag={c.tag} color={c.color} /></b><small>Level {c.level} · {c.members}/{c.max_members} members · Boss @{c.boss ?? '?'}</small></span>
          {c.recruiting ? <Button size="sm" loading={busy === `j${c.id}`} onClick={() => void act(`j${c.id}`, () => crewJoinOpen(c.id))}>Join</Button> : <small className="cr-fine">Invite only</small>}
          <button type="button" className="cr-link" onClick={() => { const r = window.prompt('Why are you reporting this gang?'); if (r !== null) void act(`r${c.id}`, () => crewReport(c.id, r)); }}>Report</button>
        </article>
      ))}
    </div>
  );
}

function NoCrew({ s }: { s: NonNullable<ReturnType<typeof useCrew.getState>['status']> }) {
  const { busy, act } = useAct();
  const [tab, setTab] = useState<'create' | 'browse'>('create');
  return (
    <div className="cr-app">
      {s.invites.length > 0 && (
        <section className="cr-list" data-testid="crew-invites">
          <h4 className="cr-h">Invites</h4>
          {s.invites.map((i) => (
            <article key={i.id} className="cr-card cr-row">
              <span className="cr-badge" style={{ background: i.crew.color }} aria-hidden>{i.crew.emblem}</span>
              <span className="cr-row__who"><b>{i.crew.name} <CrewTag tag={i.crew.tag} color={i.crew.color} /></b><small>From @{i.from ?? '?'} · level {i.crew.level} · {i.crew.members}/{i.crew.max_members}</small></span>
              <Button size="sm" loading={busy === `a${i.id}`} onClick={() => void act(`a${i.id}`, () => crewInviteRespond(i.id, true))}>Join</Button>
              <Button size="sm" variant="ghost" onClick={() => void act(`d${i.id}`, () => crewInviteRespond(i.id, false))}>Pass</Button>
            </article>
          ))}
        </section>
      )}
      {s.cooldown_until && <p className="cr-warn">You left a gang recently. You can join or start another in {countdown(secondsUntil(s.cooldown_until, Date.now()))}.</p>}
      <Tabs tabs={[{ id: 'create', label: 'Create' }, { id: 'browse', label: 'Browse' }]} value={tab} onChange={(t) => setTab(t as 'create' | 'browse')} />
      {tab === 'create' ? <Create s={s} /> : <Browse />}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ in a crew
function MemberRow({ m, crew, act, busy }: { m: CrewMember; crew: Crew; act: ReturnType<typeof useAct>['act']; busy: string | null }) {
  const [open, setOpen] = useState(false);
  const me = crew.me!;
  const canPromote = !m.me && m.rank !== 'boss' && (me.is_boss || (me.can_manage && m.rank === 'prospect'));
  const canKick = !m.me && m.rank !== 'boss' && me.can_manage && (me.is_boss || m.rank === 'member' || m.rank === 'prospect');
  return (
    <li className="cr-member">
      <span className={`cr-dot${m.online ? ' is-on' : ''}`} aria-label={m.online ? 'online' : 'offline'} />
      <span className="cr-member__who"><b>@{m.username}{m.me ? ' (you)' : ''}</b><small>{RANK_LABEL[m.rank]} · {m.jobs} jobs{m.online && m.at_spot ? ' · at the spot' : ''}</small></span>
      {(canPromote || canKick) && <button type="button" className="cr-link" onClick={() => setOpen(!open)}>{open ? 'Close' : 'Manage'}</button>}
      {open && (
        <div className="cr-manage">
          {canPromote && me.is_boss && m.rank !== 'lieutenant' && <Button size="sm" variant="ghost" onClick={() => void act('r' + m.id, () => crewSetRank(m.id, 'lieutenant'))}>Make Lieutenant</Button>}
          {canPromote && m.rank === 'prospect' && <Button size="sm" variant="ghost" onClick={() => void act('r' + m.id, () => crewSetRank(m.id, 'member'))}>Make Member</Button>}
          {canPromote && me.is_boss && m.rank !== 'prospect' && <Button size="sm" variant="ghost" onClick={() => void act('r' + m.id, () => crewSetRank(m.id, m.rank === 'lieutenant' ? 'member' : 'prospect'))}>Demote</Button>}
          {me.is_boss && m.rank !== 'prospect' && <Button size="sm" variant="ghost" onClick={() => { if (window.confirm(`Make @${m.username} the Boss? You become a Lieutenant.`)) void act('t' + m.id, () => crewTransfer(m.id)); }}>Make Boss</Button>}
          {canKick && <Button size="sm" variant="danger" loading={busy === 'k' + m.id} onClick={() => { if (window.confirm(`Remove @${m.username}?`)) void act('k' + m.id, () => crewKick(m.id)); }}>Kick</Button>}
        </div>
      )}
    </li>
  );
}

function Invite({ crew }: { crew: Crew }) {
  const { busy, act } = useAct();
  const [q, setQ] = useState('');
  const [rows, setRows] = useState<Candidate[] | null>(null);
  const load = useCallback((t: string) => { void crewCandidates(t).then((r) => setRows(r.players)).catch(() => setRows([])); }, []);
  useEffect(() => { load(q.trim().length >= 2 ? q : ''); }, [q, load]);
  return (
    <section className="cr-card" data-testid="crew-invite">
      <h4>Invite players</h4>
      <input className="cr-search" value={q} placeholder="Friends first. Type a username to find anybody" onChange={(e) => setQ(e.target.value)} enterKeyHint="search" />
      {rows && rows.length === 0 && <p className="cr-hint">{q ? 'Nobody found.' : 'No friends to show. Search by username.'}</p>}
      <ul className="cr-cands">
        {rows?.map((c) => (
          <li key={c.id}>
            <span className={`cr-dot${c.online ? ' is-on' : ''}`} />
            <span className="cr-member__who"><b>@{c.username}</b><small>{c.friend ? 'Friend' : 'Player'}{!c.eligible && c.why ? ` · ${c.why}` : ''}</small></span>
            <Button size="sm" disabled={!c.eligible || c.invited} loading={busy === 'i' + c.id} onClick={() => void act('i' + c.id, () => crewInvite(c.username), () => load(q))}>{c.invited ? 'Invited' : 'Invite'}</Button>
          </li>
        ))}
      </ul>
      {crew.pending_invites.length > 0 && (
        <div className="cr-pending"><small>Waiting: {crew.pending_invites.map((i) => `@${i.username}`).join(', ')}</small></div>
      )}
    </section>
  );
}

function Overview({ crew }: { crew: Crew }) {
  const { busy, act } = useAct();
  const me = crew.me!;
  const next = crew.next_level;
  const span = (crew.xp_to ?? crew.xp) - crew.xp_from;
  const pct = crew.xp_to == null ? 100 : Math.max(0, Math.min(100, Math.round(((crew.xp - crew.xp_from) / Math.max(1, span)) * 100)));
  return (
    <div className="cr-stack">
      <section className="cr-card" data-testid="crew-level">
        <div className="cr-level"><b>Level {crew.level} · {crew.level_name}</b><span>{crew.bonus_pct > 0 ? `+${crew.bonus_pct}% loot` : 'No loot bonus yet'}</span></div>
        <div className="cr-bar" aria-label={`Crew XP ${crew.xp}`}><span style={{ width: `${pct}%` }} /></div>
        <small className="cr-fine">{crew.xp} XP{crew.xp_to != null ? ` of ${crew.xp_to} for level ${crew.level + 1}` : ' · top level'} · {crew.jobs_done} jobs done, {crew.jobs_caught} busted · loot {nairaShort(crew.loot_total)}</small>
        {next && (
          <div className="cr-next">
            <small>Next: <b>{next.name}</b> · {next.max_members} members · +{next.bonus_pct}% loot. {next.perks}</small>
            <small className={next.xp_ok ? 'is-ok' : ''}>{next.xp_ok ? '✓' : '✗'} {next.xp_needed} XP</small>
            <small className={next.bank_ok ? 'is-ok' : ''}>{next.bank_ok ? '✓' : '✗'} {naira(next.cost)} from the gang bank</small>
            {me.can_manage && <Button size="sm" disabled={!next.xp_ok || !next.bank_ok} loading={busy === 'up'} onClick={() => void act('up', () => crewUpgrade())}>Upgrade the gang</Button>}
          </div>
        )}
      </section>
      <section className="cr-card">
        <h4>Members {crew.members_count}/{crew.max_members}</h4>
        <ul className="cr-members" data-testid="crew-members">{crew.members.map((m) => <MemberRow key={m.id} m={m} crew={crew} act={act} busy={busy} />)}</ul>
      </section>
      {me.can_manage && <Invite crew={crew} />}
      {crew.pending_invites.length > 0 && me.can_manage && (
        <section className="cr-card"><h4>Sent invites</h4>{crew.pending_invites.map((i) => <div key={i.id} className="cr-row2"><span>@{i.username}</span><button type="button" className="cr-link" onClick={() => void act('c' + i.id, () => crewInviteCancel(i.id))}>Cancel</button></div>)}</section>
      )}
      <p className="cr-fine">This week: {crew.week.jobs} jobs, {nairaShort(crew.week.loot)} loot{crew.week.rank ? ` · #${crew.week.rank} in Top gangs` : ''}.</p>
    </div>
  );
}

function Lobby({ run, crew, onGo }: { run: CrewRun; crew: Crew; onGo: (id: string) => void }) {
  const { busy, act } = useAct();
  const now = useNow(1000);
  const me = crew.me!;
  const left = secondsUntil(run.status === 'lobby' ? run.lobby_until : run.resolve_at, now);
  const total = run.status === 'lobby' ? Math.max(1, secondsUntil(run.lobby_until, Date.parse(run.created_at))) : run.duration_seconds;
  return (
    <section className="cr-card cr-lobby" data-testid="crew-lobby">
      <div className="cr-level"><b>{run.icon} {run.name}</b><span>{run.status === 'lobby' ? 'Lobby' : 'Running'}</span></div>
      <div className="cr-count">{countdown(left)}</div>
      <div className="cr-bar"><span style={{ width: `${Math.max(0, Math.min(100, 100 - (left / total) * 100))}%` }} /></div>
      <small className="cr-fine">{run.status === 'lobby' ? `Needs ${run.min_members}–${run.max_members} members at a meeting spot. Starts when the countdown ends.` : 'Nobody move. One roll decides it.'}</small>
      <ul className="cr-members">
        {run.members.map((m) => <li key={m.id} className="cr-member"><span className={`cr-dot${m.online ? ' is-on' : ''}`} /><span className="cr-member__who"><b>@{m.username}</b><small>{RANK_LABEL[m.rank]} · ready</small></span></li>)}
        {run.members.length < run.min_members && <li className="cr-fine">Waiting for {run.min_members - run.members.length} more…</li>}
      </ul>
      <div className="cr-stats">
        <span><small>Caught chance</small><b>{run.caught_pct}%</b>{run.skill_cut_pct > 0 && <small>skills −{run.skill_cut_pct}% (base {run.base_pct}%)</small>}</span>
        <span><small>Loot</small><b>{nairaShort(run.reward_min)}–{nairaShort(run.reward_max)}</b></span>
        {run.buy_in > 0 && <span><small>Supplies each</small><b>{naira(run.buy_in)}</b></span>}
      </div>
      {run.status === 'lobby' && (
        <div className="cr-actions">
          {!run.joined && <Button loading={busy === 'join'} onClick={() => void act('join', () => crewJobJoin(run.id))}>I am here, count me in</Button>}
          {run.joined && run.started_by_id !== crew.members.find((x) => x.me)?.id && <Button variant="ghost" onClick={() => void act('leave', () => crewJobLeave(run.id))}>Leave lobby</Button>}
          {me.can_manage && <Button variant="gold" disabled={run.members.length < run.min_members} loading={busy === 'start'} onClick={() => void act('start', () => crewJobStart(run.id))}>Start now</Button>}
          {me.can_manage && <Button variant="ghost" loading={busy === 'cancel'} onClick={() => void act('cancel', () => crewJobCancel(run.id))}>Call it off</Button>}
          {crew.meeting_places.map((p) => <Button key={p.id} size="sm" variant="ghost" onClick={() => onGo(p.id)}>Go to {p.name}</Button>)}
        </div>
      )}
    </section>
  );
}

function Result({ run, onClose }: { run: CrewRun; onClose: () => void }) {
  const paid = run.status === 'paid';
  return (
    <section className={`cr-card cr-result ${paid ? 'is-paid' : 'is-caught'}`} data-testid="crew-result">
      <h4>{paid ? `💰 ${run.name} paid` : `🚓 ${run.name} got busted`}</h4>
      {paid ? (
        <>
          <p className="cr-hint">Total loot <b>{naira(run.pot)}</b>. The gang bank took <b>{naira(run.bank_share)}</b> ({run.split_bank_pct}% share).</p>
          <ul className="cr-members">{run.members.map((m) => <li key={m.id} className="cr-member"><span className="cr-member__who"><b>@{m.username}</b><small>{RANK_LABEL[m.rank]}</small></span><b className="cr-plus">+{naira(m.payout)}</b></li>)}</ul>
        </>
      ) : (
        <>
          <p className="cr-hint">The police caught the whole gang. Everybody got a jail case: bail, serve time or try to escape.{run.fine > 0 ? ` The gang bank paid ${naira(run.fine)} in legal fees.` : ''} No loot.</p>
          <ul className="cr-members">{run.members.map((m) => <li key={m.id} className="cr-member"><span className="cr-member__who"><b>@{m.username}</b></span><span className="cr-minus">🚓</span></li>)}</ul>
        </>
      )}
      <Button size="sm" variant="ghost" onClick={onClose}>Close</Button>
    </section>
  );
}

function JobCard({ j, crew }: { j: CrewJob; crew: Crew }) {
  const { busy, act } = useAct();
  const me = crew.me!;
  const cd = j.cooldown_left;
  return (
    <article className={`cr-card cr-job${j.locked ? ' is-locked' : ''}`} data-testid="crew-job">
      <div className="cr-level"><b>{j.icon} {j.name}</b><span>{j.locked ? `🔒 ${j.locked_reason}` : `${j.min_members}–${j.max_members} members`}</span></div>
      <p className="cr-hint">{j.blurb}</p>
      <div className="cr-stats">
        <span><small>Loot (pot)</small><b>{nairaShort(j.reward_min)}–{nairaShort(j.reward_max)}</b>{j.bonus_pct > 0 && <small>+{j.bonus_pct}% gang bonus</small>}</span>
        <span><small>Caught chance</small><b>{j.est_pct}%</b>{j.skill_cut_pct > 0 && <small>skills −{j.skill_cut_pct}%</small>}</span>
        <span><small>Time</small><b>{countdown(j.duration_seconds)}</b></span>
      </div>
      <small className="cr-fine">{j.skills.map((s) => `${s.icon} ${s.name}`).join(' · ') || 'No skill helps'} {j.buy_in > 0 ? `· supplies ${naira(j.buy_in)} each (lost if busted)` : ''} · +{j.xp} gang XP</small>
      {me.can_manage && <Button size="sm" disabled={j.locked || cd > 0 || !!crew.run} loading={busy === j.id} onClick={() => void act(j.id, () => crewJobOpen(j.id))}>{cd > 0 ? `Lie low ${countdown(cd)}` : 'Open a lobby'}</Button>}
    </article>
  );
}

function Jobs({ crew, onGo }: { crew: Crew; onGo: (id: string) => void }) {
  const [hidden, setHidden] = useState<number | null>(() => { try { return Number(localStorage.getItem('bl.crew.result')) || null; } catch { return null; } });
  const last = crew.last_run && crew.last_run.id !== hidden && !crew.run ? crew.last_run : null;
  const close = () => { if (!crew.last_run) return; setHidden(crew.last_run.id); try { localStorage.setItem('bl.crew.result', String(crew.last_run.id)); } catch { /* ignore */ } };
  return (
    <div className="cr-stack">
      {crew.run && <Lobby run={crew.run} crew={crew} onGo={onGo} />}
      {last && <Result run={last} onClose={close} />}
      <p className="cr-fine">Meeting spots: {crew.meeting_places.map((p) => p.name).join(', ') || 'none set'}. Be there and online to join. Bank share of loot: {crew.split_bank_pct}%.</p>
      {crew.jobs.map((j) => <JobCard key={j.id} j={j} crew={crew} />)}
    </div>
  );
}

function Bank({ crew }: { crew: Crew }) {
  const { busy, act } = useAct();
  const [amt, setAmt] = useState('');
  const [rows, setRows] = useState<BankRow[] | null>(null);
  const load = useCallback(() => { void crewBankLog().then((r) => setRows(r.rows)).catch(() => setRows([])); }, []);
  useEffect(() => { load(); }, [load, crew.bank]);
  const n = Number(amt.replace(/[^\d]/g, ''));
  return (
    <div className="cr-stack">
      <section className="cr-card">
        <div className="cr-level"><b>Gang bank</b><span data-testid="crew-bank">{naira(crew.bank)}</span></div>
        <p className="cr-hint">Everybody can put money in. The Boss and Lieutenants spend it on gang upgrades. Job loot adds to it.</p>
        <div className="cr-deposit">
          <input inputMode="numeric" enterKeyHint="done" value={amt} placeholder="Amount" onChange={(e) => setAmt(e.target.value.replace(/[^\d]/g, ''))} />
          <Button loading={busy === 'dep'} disabled={!n} onClick={() => void act('dep', () => crewDeposit(n), () => { setAmt(''); load(); })}>Deposit</Button>
        </div>
      </section>
      <section className="cr-card">
        <h4>Bank log</h4>
        {rows && rows.length === 0 && <p className="cr-hint">Nothing yet.</p>}
        <ul className="cr-log" data-testid="crew-bank-log">
          {rows?.map((r) => <li key={r.id}><span><b>{r.note || r.kind}</b><small>{r.username ? `@${r.username} · ` : ''}{new Date(r.created_at).toLocaleString()}</small></span><b className={r.amount >= 0 ? 'cr-plus' : 'cr-minus'}>{r.amount >= 0 ? '+' : ''}{naira(r.amount)}</b></li>)}
        </ul>
      </section>
    </div>
  );
}

function Chat() {
  const [rows, setRows] = useState<ChatRow[]>([]);
  const [text, setText] = useState('');
  const last = useRef(0);
  const box = useRef<HTMLDivElement>(null);
  const poll = useCallback(async () => {
    try {
      const r = await crewChatRecent(last.current);
      if (r.rows.length) { last.current = r.rows[r.rows.length - 1].id; setRows((x) => [...x, ...r.rows]); }
    } catch { /* retry on the next tick */ }
  }, []);
  useEffect(() => {
    void poll();
    const id = window.setInterval(() => { if (canPoll()) void poll(); }, 6000);
    return () => window.clearInterval(id);
  }, [poll]);
  useEffect(() => { box.current?.scrollTo({ top: box.current.scrollHeight }); }, [rows.length]);
  const send = async () => {
    const t = text.trim();
    if (!t) return;
    setText('');
    try { await crewChatSend(t); await poll(); } catch (e) { toast(errorMessage(e), 'bad'); setText(t); }
  };
  return (
    <div className="cr-chat">
      <div className="cr-chat__list" ref={box} data-testid="crew-chat">
        {rows.length === 0 && <p className="cr-hint">Say something to the gang.</p>}
        {rows.map((m) => <div key={m.id} className={`cr-msg${m.mine ? ' is-mine' : ''}`}><small>@{m.username}</small><span>{m.body}</span></div>)}
      </div>
      <div className="cr-chat__box kb-composer">
        <input value={text} placeholder="Message the gang" enterKeyHint="send" readOnly={false} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void send(); }} />
        <Button onClick={() => void send()}>Send</Button>
      </div>
    </div>
  );
}

function Settings({ crew, bounds }: { crew: Crew; bounds: { min: number; max: number; fee: number } }) {
  const { busy, act } = useAct();
  const me = crew.me!;
  const [split, setSplit] = useState(crew.split_bank_pct);
  const [name, setName] = useState('');
  return (
    <div className="cr-stack">
      {me.is_boss && (
        <section className="cr-card">
          <h4>Loot split</h4>
          <p className="cr-hint">The gang bank takes <b>{split}%</b> of every payout. Members share the rest ({bounds.min}–{bounds.max}% allowed).</p>
          <input type="range" min={bounds.min} max={bounds.max} value={split} onChange={(e) => setSplit(Number(e.target.value))} aria-label="Bank share of loot" />
          <Button size="sm" disabled={split === crew.split_bank_pct} loading={busy === 'split'} onClick={() => void act('split', () => crewOptions(split, null))}>Save split</Button>
        </section>
      )}
      {me.can_manage && (
        <section className="cr-card">
          <h4>Recruiting</h4>
          <p className="cr-hint">Open gangs let anybody walk in as a Prospect. Closed gangs are invite only.</p>
          <Button size="sm" variant="ghost" loading={busy === 'rec'} onClick={() => void act('rec', () => crewOptions(null, !crew.recruiting))}>{crew.recruiting ? 'Close the door' : 'Open the door'}</Button>
        </section>
      )}
      {me.is_boss && (
        <section className="cr-card">
          <h4>Rename the gang</h4>
          <p className="cr-hint">The gang bank pays {naira(bounds.fee)}.</p>
          <div className="cr-deposit"><input value={name} maxLength={20} placeholder="New name" onChange={(e) => setName(e.target.value)} /><Button size="sm" disabled={name.trim().length < 3} loading={busy === 'ren'} onClick={() => void act('ren', () => crewRename(name), () => setName(''))}>Rename</Button></div>
        </section>
      )}
      <section className="cr-card">
        <h4>Leave</h4>
        {me.is_boss
          ? <><p className="cr-hint">Make another member the Boss (Overview, Manage), or disband the gang. The bank is shared out to the members.</p>
            <Button variant="danger" loading={busy === 'dis'} onClick={() => { if (window.confirm('Disband the gang? This cannot be undone.')) void act('dis', () => crewDisband()); }}>Disband the gang</Button></>
          : <><p className="cr-hint">You cannot join or start another gang for a while after you leave.</p>
            <Button variant="danger" loading={busy === 'leave'} onClick={() => { if (window.confirm('Leave the gang?')) void act('leave', () => crewLeave()); }}>Leave the gang</Button></>}
      </section>
    </div>
  );
}

function InCrew({ crew, s, onGo }: { crew: Crew; s: NonNullable<ReturnType<typeof useCrew.getState>['status']>; onGo: (id: string) => void }) {
  const [tab, setTab] = useState<Tab>('overview');
  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'jobs', label: 'Jobs', badge: crew.run ? '●' : null },
    { id: 'bank', label: 'Bank' },
    { id: 'chat', label: 'Chat' },
    { id: 'settings', label: 'Settings' },
  ];
  return (
    <div className="cr-app">
      <header className="cr-head" style={{ ['--cr' as string]: crew.color }}>
        <span className="cr-badge cr-badge--lg" style={{ background: crew.color }} aria-hidden>{crew.emblem}</span>
        <span className="cr-head__who"><b>{crew.name} <CrewTag tag={crew.tag} color={crew.color} /></b><small>Level {crew.level} · {crew.members_count}/{crew.max_members} members · {RANK_LABEL[crew.me!.rank]}</small></span>
        <span className="cr-head__bank"><small>Bank</small><b>{nairaShort(crew.bank)}</b></span>
      </header>
      <Tabs tabs={tabs} value={tab} onChange={(t) => setTab(t as Tab)} />
      {tab === 'overview' && <Overview crew={crew} />}
      {tab === 'jobs' && <Jobs crew={crew} onGo={onGo} />}
      {tab === 'bank' && <Bank crew={crew} />}
      {tab === 'chat' && <Chat />}
      {tab === 'settings' && <Settings crew={crew} bounds={{ min: s.settings.bank_pct_min, max: s.settings.bank_pct_max, fee: s.settings.rename_fee }} />}
    </div>
  );
}

export default function CrewApp({ onGo }: { onGo: (id: string) => void }) {
  const s = useCrew((x) => x.status);
  useEffect(() => { void useCrew.getState().load(); }, []);
  if (!s) return <div className="phone-app__body"><div className="panel-skel"><span /><span /><span /></div></div>;
  if (!s.enabled && !s.crew) return <div className="phone-app__body"><p className="phone-app__lead">Gangs are off for now.</p></div>;
  return <div className="phone-app__body cr-body">{s.crew ? <InCrew crew={s.crew} s={s} onGo={onGo} /> : <NoCrew s={s} />}</div>;
}
