// Family app (docs/LOVE.md). ONE phone icon, three tabs: Link-ups (opt in, ask somebody out, answer asks), Us (flirt level, flirt menu, dates, log,
// break up) and Family (the couple card, and a "kids: coming soon" placeholder for stage 2).
// Everything is decided on the server (love_*): this file only shows it. ONE read, love_overview(), feeds Us, Family and the ask inbox; it is polled
// ONLY while the app is open (startPoller: visible tab, not AFK, backs off when idle) and refreshed at once when a love_* alert arrives.
// The Link-ups list (love_candidates) is paged and loaded on demand, never polled.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  loveAsk, loveBreakup, loveCandidates, loveDateInvite, loveDateRespond, loveFlirt, loveOverview, loveReport, loveRespond, loveSetOpen,
  loveSetShowRelationship, loveWithdraw, type LoveCandidate, type LoveDate, type LoveFlirt, type LoveFilter, type LoveOverview, type LoveRelationship,
} from '../../../api/love';
import { errorMessage, rpc } from '../../../lib/api';
import { serverNow } from '../../../lib/clock';
import { naira } from '../../../lib/format';
import { startPoller } from '../../../lib/realtime';
import { useGame } from '../../../state/game';
import { useUi } from '../../../state/ui';
import { Button, CrewTag, EmptyState, Modal, OfficeTag, Spinner, Switch, Tabs, toast } from '../../../ui';
import type { AvatarConfig } from '../../../lib/types';
import { ago, dur, face, useTick } from './familyUtil';
import { KidsSection } from './KidsSection';
import { kidsName, type KidChild, type KidsStatus } from '../../../api/kids';
import { useKids } from '../../../state/kids';
import './FamilyApp.css';

export type FamilyTab = 'linkups' | 'us' | 'family';

// ------------------------------------------------------------------------------------------------ Link-ups
function AskInbox({ ov, run, busy, onReport }: { ov: LoveOverview; run: (k: string, fn: () => Promise<{ message?: string }>) => void; busy: string | null; onReport: (id: string, name: string) => void }) {
  useTick(ov.incoming.length > 0 || ov.outgoing.length > 0);
  const now = serverNow();
  const left = (iso: string) => dur((Date.parse(iso) - now) / 1000);
  if (!ov.incoming.length && !ov.outgoing.length) return null;
  return (
    <section className="fm-sect" data-testid="fm-inbox">
      {ov.incoming.length > 0 && <h3 className="fm-h">Asked you out</h3>}
      {ov.incoming.map((a) => (
        <article key={a.id} className="fm-card fm-ask" data-testid="fm-incoming">
          <span className="fm-ask__who">
            {face(a.from.avatar, 48)}
            <span className="fm-ask__txt"><b>@{a.from.username}</b><small>wants to link up with you. Expires in {left(a.expires_at)}.</small></span>
          </span>
          <span className="fm-ask__btns">
            <Button variant="green" size="md" loading={busy === `yes:${a.id}`} disabled={busy !== null} onClick={() => run(`yes:${a.id}`, () => loveRespond(a.id, true))} data-testid="fm-accept">Accept</Button>
            <Button variant="ghost" size="md" loading={busy === `no:${a.id}`} disabled={busy !== null} onClick={() => run(`no:${a.id}`, () => loveRespond(a.id, false))}>Decline</Button>
          </span>
          <button type="button" className="fm-link" onClick={() => onReport(a.from.id, a.from.username)}>Report @{a.from.username}</button>
        </article>
      ))}
      {ov.outgoing.length > 0 && <h3 className="fm-h">Your asks</h3>}
      {ov.outgoing.map((a) => (
        <article key={a.id} className={`fm-card fm-ask fm-ask--out${a.state === 'noreply' ? ' is-quiet' : ''}`}>
          <span className="fm-ask__who">
            {face(a.to.avatar, 40)}
            <span className="fm-ask__txt">
              <b>@{a.to.username}</b>
              <small>{a.state === 'pending' ? `Waiting for a reply. ${left(a.expires_at)} left.` : 'No reply'}</small>
            </span>
          </span>
          {a.state === 'pending' && (
            <Button variant="ghost" size="sm" loading={busy === `wd:${a.id}`} disabled={busy !== null} onClick={() => run(`wd:${a.id}`, () => loveWithdraw(a.id))}>Withdraw</Button>
          )}
        </article>
      ))}
    </section>
  );
}

function LinkupsTab({ ov, run, busy, goUs, onReport, reloadKey }: {
  ov: LoveOverview; run: (k: string, fn: () => Promise<{ message?: string }>) => void; busy: string | null; goUs: () => void;
  onReport: (id: string, name: string) => void; reloadKey: number;
}) {
  const [filter, setFilter] = useState<LoveFilter>('all');
  const [rows, setRows] = useState<LoveCandidate[] | null>(null);
  const [more, setMore] = useState(false);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const taken = ov.relationships.length >= ov.max_partners;
  // the list is reloaded when my asks change (an ask sent, answered or expired), not on every poll
  const sig = `${ov.incoming.map((a) => a.id).join(',')}|${ov.outgoing.map((a) => `${a.id}${a.state}`).join(',')}`;

  const load = useCallback(async (f: LoveFilter, offset: number) => {
    setLoading(true);
    try {
      const r = await loveCandidates(f, offset);
      setRows((prev) => (offset > 0 && prev ? [...prev, ...r.rows] : r.rows));
      setMore(r.has_more);
      setErr(null);
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }, []);

  // the door is open: list people (on open, on filter, after an ask or an answer). Never polled.
  useEffect(() => {
    if (!ov.me.open || taken) return;
    const t = window.setTimeout(() => void load(filter, 0), 0);
    return () => window.clearTimeout(t);
  }, [ov.me.open, taken, filter, load, reloadKey, sig]);

  const ask = (c: LoveCandidate) => run(`ask:${c.id}`, async () => {
    const r = await loveAsk(c.id);
    setRows((prev) => prev?.map((x) => (x.id === c.id ? { ...x, state: 'pending' } : x)) ?? prev);
    return r;
  });

  return (
    <div className="fm-stack">
      <section className="fm-card fm-open">
        <Switch checked={ov.me.open} disabled={busy === 'open'} label="Open to link-ups"
          hint={ov.me.open ? 'Other players who are open can see you here and ask you out. Switch off any time.' : 'Off. Nobody can see you here or ask you out.'}
          onChange={(v) => run('open', () => loveSetOpen(v))} />
      </section>

      <AskInbox ov={ov} run={run} busy={busy} onReport={onReport} />

      {taken && (
        <section className="fm-card fm-note">
          <b>You are already with somebody 💞</b>
          <p>Spend time with them in the Us tab. If you want to ask someone new, end it there first.</p>
          <Button variant="green" onClick={goUs}>Open Us</Button>
        </section>
      )}

      {!taken && !ov.me.open && (
        <EmptyState icon="heart" title="Your door is closed"
          body="Switch on Open to link-ups to see other players who want to meet somebody, and to be asked out yourself. No money is shown, only a name and a face." />
      )}

      {!taken && ov.me.open && (
        <section className="fm-sect">
          <div className="fm-listhead">
            <h3 className="fm-h">People open to link-ups</h3>
            <span className="fm-asks" data-testid="fm-asks-left">{ov.me.asks_left} of {ov.me.asks_cap} asks left today</span>
          </div>
          {ov.me.ask_block && <p className="fm-warn">{ov.me.ask_block.msg}</p>}
          <div className="fm-filters" role="group" aria-label="Filter">
            {([['all', 'Everyone'], ['here', 'Same place'], ['online', 'Online now']] as const).map(([id, label]) => (
              <button key={id} type="button" className={`fm-chip${filter === id ? ' is-on' : ''}`} aria-pressed={filter === id} onClick={() => setFilter(id)}>{label}</button>
            ))}
          </div>
          {err && <p className="fm-warn">{err}</p>}
          {rows === null && !err && <div className="panel-skel"><span /><span /></div>}
          {rows !== null && rows.length === 0 && (
            <EmptyState icon="people" title={filter === 'all' ? 'Nobody else is open yet' : filter === 'here' ? 'Nobody open at your place' : 'Nobody open and online right now'}
              body="Come back later, or try another filter. People show up as they switch the door on." />
          )}
          <ul className="fm-list">
            {rows?.map((c) => (
              <li key={c.id} className="fm-card fm-person" data-testid="fm-candidate">
                {face(c.avatar, 48)}
                <span className="fm-person__txt">
                  <b><CrewTag tag={c.crew?.tag} color={c.crew?.color} /><OfficeTag title={c.title} />@{c.username}</b>
                  <small>
                    {c.online && <span className="fm-pill fm-pill--on">Online</span>}
                    {c.here && <span className="fm-pill fm-pill--here">Same place</span>}
                    <span>★ {c.street_cred ?? 0}</span>
                  </small>
                </span>
                {c.state === 'ask' && (
                  <Button variant="green" size="md" loading={busy === `ask:${c.id}`} disabled={busy !== null || Boolean(ov.me.ask_block)} onClick={() => ask(c)} data-testid="fm-ask">Ask out</Button>
                )}
                {c.state === 'pending' && <span className="fm-state">Asked</span>}
                {c.state === 'incoming' && <span className="fm-state is-hot">Asked you</span>}
                {c.state === 'later' && <span className="fm-state">Try later</span>}
              </li>
            ))}
          </ul>
          {more && <Button variant="ghost" block loading={loading} onClick={() => void load(filter, rows?.length ?? 0)}>Show more</Button>}
        </section>
      )}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ Us
function LevelBar({ r, coupleLevel }: { r: LoveRelationship; coupleLevel: number }) {
  const couple = r.status === 'couple';
  const max = couple ? 100 : coupleLevel;
  const pct = Math.min(1, r.level / max);
  return (
    <div className="fm-level" data-testid="fm-level">
      <div className="fm-level__row">
        <b>{couple ? 'Couple 💞' : 'Talking'}</b>
        <span>{couple ? `bond level ${r.level}/100` : `flirt level ${r.level}/${coupleLevel}`}</span>
      </div>
      <div className="fm-bar" role="progressbar" aria-valuemin={0} aria-valuemax={max} aria-valuenow={r.level}>
        <span className="fm-bar__fill" style={{ transform: `scaleX(${pct})` }} />
        {couple && <i className="fm-bar__mark" style={{ left: `${coupleLevel}%` }} aria-hidden />}
      </div>
      <small>{couple ? `Keep it warm. Bond counts up to 100.` : `At ${coupleLevel} you two become a couple.`}</small>
    </div>
  );
}

function Couple({ me, r, big }: { me: { avatar: AvatarConfig | null; username: string }; r: LoveRelationship; big?: boolean }) {
  const s = big ? 72 : 56;
  return (
    <div className={`fm-pair${r.status === 'couple' ? ' is-couple' : ''}`}>
      <span className="fm-pair__one">{face(me.avatar, s)}<small>@{me.username}</small></span>
      <span className="fm-pair__heart" aria-hidden>{r.status === 'couple' ? '💞' : '💬'}</span>
      <span className="fm-pair__one">{face(r.partner.avatar, s)}<small>@{r.partner.username}</small></span>
    </div>
  );
}

function RelCard({ r, ov, me, run, busy, loadedAt, onReport, onBreakup }: {
  r: LoveRelationship; ov: LoveOverview; me: { avatar: AvatarConfig | null; username: string };
  run: (k: string, fn: () => Promise<{ message?: string }>) => void; busy: string | null; loadedAt: number; onReport: (id: string, name: string) => void; onBreakup: (r: LoveRelationship) => void;
}) {
  const goPlace = (id: string) => { const ui = useUi.getState(); ui.closeAll(); ui.setMapOpen(true); ui.select(id); };
  const cdLeft = Math.max(0, r.flirt_cooldown_seconds - (serverNow() - loadedAt) / 1000);
  const invLeft = r.invite ? (Date.parse(r.invite.expires_at) - serverNow()) / 1000 : 0;
  useTick(cdLeft > 0 || invLeft > 0);
  const dateOf = (id: string) => ov.dates.find((d) => d.id === id);
  const inv = r.invite && invLeft > 0 ? r.invite : null;
  const invDate = inv ? dateOf(inv.date_id) : undefined;
  const noRoom = r.daily_room <= 0;
  const [allDates, setAllDates] = useState(false);

  const dates = useMemo(() => [...ov.dates].sort((a, b) => Number(Boolean(b.place_id && b.me_here)) - Number(Boolean(a.place_id && a.me_here))), [ov.dates]);

  const flirtSub = (f: LoveFlirt) => `${f.cost > 0 ? naira(f.cost) : 'Free'} · +${f.points} level`;
  const dateLeft = (d: LoveDate) => Math.max(0, (r.date_cooldowns[d.id] ?? 0) - (serverNow() - loadedAt) / 1000);

  return (
    <article className="fm-card fm-rel" data-testid="fm-rel">
      <Couple me={me} r={r} />
      <LevelBar r={r} coupleLevel={ov.couple_level} />
      <p className="fm-fine">{noRoom ? 'You two have gained all you can for today. Come back tomorrow.' : `${r.daily_room} level points left to gain today.`}</p>

      {inv && invDate && (
        <div className="fm-invite" data-testid="fm-invite">
          <span className="fm-invite__icon" aria-hidden>{invDate.icon}</span>
          <span className="fm-invite__txt">
            <b>{inv.mine ? `You invited @${r.partner.username}` : `@${r.partner.username} invites you`}</b>
            <small><strong>{invDate.name}</strong></small>
            <small>{invDate.place_name ? `At ${invDate.place_name}` : 'On the phone'} · {dur(invLeft)} left</small>
            {invDate.place_id && !invDate.me_here && <small>You both need to be at {invDate.place_name}.</small>}
          </span>
          {!inv.mine && (
            invDate.place_id && !invDate.me_here
              ? <Button variant="green" size="sm" onClick={() => goPlace(invDate.place_id!)}>Go there</Button>
              : <Button variant="green" size="sm" loading={busy === `dy:${inv.id}`} disabled={busy !== null} onClick={() => run(`dy:${inv.id}`, () => loveDateRespond(inv.id, true))} data-testid="fm-date-accept">Accept</Button>
          )}
          {!inv.mine && <Button variant="ghost" size="sm" loading={busy === `dn:${inv.id}`} disabled={busy !== null} onClick={() => run(`dn:${inv.id}`, () => loveDateRespond(inv.id, false))}>Not now</Button>}
          {inv.mine && invDate.place_id && invDate.me_here && <small className="fm-fine">Stay at the place until they arrive.</small>}
        </div>
      )}

      <h3 className="fm-h">Send a flirt</h3>
      <p className="fm-fine">Pick a line. It costs what it says and raises your level together.{cdLeft > 0 ? ` You can flirt again in ${dur(cdLeft)}.` : ''}</p>
      <ul className="fm-flirts" data-testid="fm-flirts">
        {ov.flirts.map((f) => {
          const locked = r.level < f.min_level;
          const blocked = locked || cdLeft > 0 || noRoom;
          return (
            <li key={f.id}>
              <button type="button" className={`fm-flirt${locked ? ' is-locked' : ''}`} disabled={blocked || busy !== null} aria-busy={busy === `fl:${f.id}`}
                onClick={() => run(`fl:${f.id}`, () => loveFlirt(r.id, f.id))} data-testid={`fm-flirt-${f.id}`}>
                <span className="fm-flirt__icon" aria-hidden>{f.icon}</span>
                <span className="fm-flirt__txt">
                  <span className="fm-flirt__line">“{f.text}”</span>
                  <small>{locked ? `Unlocks at level ${f.min_level}` : flirtSub(f)}</small>
                </span>
                <span className="fm-flirt__go">{locked ? '🔒' : cdLeft > 0 || noRoom ? 'Wait' : busy === `fl:${f.id}` ? <Spinner size={16} /> : 'Send'}</span>
              </button>
            </li>
          );
        })}
      </ul>

      <h3 className="fm-h">Go out together</h3>
      <p className="fm-fine">You both pay your share and both have to be at the place. Dates give Fun, Social and bond.</p>
      <ul className="fm-dates" data-testid="fm-dates">
        {(allDates ? dates : dates.slice(0, 4)).map((d) => {
          const cd = dateLeft(d);
          const coupleOnly = d.min_status === 'couple' && r.status !== 'couple';
          const cant = coupleOnly || cd > 0 || Boolean(r.invite) || !d.me_here && !d.place_id;
          return (
            <li key={d.id} className={`fm-date${coupleOnly ? ' is-locked' : ''}`}>
              <span className="fm-date__icon" aria-hidden>{d.icon}</span>
              <span className="fm-date__txt">
                <b>{d.name}</b>
                <small>{d.cost_each > 0 ? `${naira(d.cost_each)} each` : 'Free'} · Fun +{d.fun_gain} · Social +{d.social_gain} · Bond +{d.bond_points}</small>
                <small className="fm-date__hint">
                  {coupleOnly ? `For couples (level ${ov.couple_level}+)` : cd > 0 ? `Again in ${dur(cd)}` : d.place_id ? `Both of you need to be at ${d.place_name}` : 'On the phone, from anywhere'}
                </small>
              </span>
              {d.place_id && !d.me_here && !coupleOnly && cd <= 0
                ? <Button variant="ghost" size="sm" onClick={() => goPlace(d.place_id!)}>Go there</Button>
                : <Button variant="green" size="sm" disabled={cant || busy !== null} loading={busy === `dt:${d.id}`}
                    onClick={() => run(`dt:${d.id}`, () => loveDateInvite(d.id, r.id))} data-testid={`fm-date-${d.id}`}>Invite</Button>}
            </li>
          );
        })}
      </ul>
      {dates.length > 4 && <Button variant="ghost" block onClick={() => setAllDates((v) => !v)} data-testid="fm-dates-more">{allDates ? 'Show fewer dates' : `Show all ${dates.length} dates`}</Button>}

      {r.recent_dates.length > 0 && (
        <>
          <h3 className="fm-h">Recent dates</h3>
          <ul className="fm-recent">
            {r.recent_dates.map((d) => (
              <li key={d.id}><span aria-hidden>{d.icon ?? '💞'}</span><b>{d.text}</b><small>{ago(d.created_at)}</small></li>
            ))}
          </ul>
        </>
      )}

      <h3 className="fm-h">Between you two</h3>
      {r.log.length === 0 ? <p className="fm-fine">Nothing yet. Send the first flirt.</p> : (
        <ul className="fm-log" data-testid="fm-log">
          {r.log.map((l) => (
            <li key={l.id} className={`fm-log__row fm-log__row--${l.kind === 'flirt' || l.kind === 'date' ? (l.mine ? 'mine' : 'theirs') : 'sys'}`}>
              <span className="fm-bubble">
                <span>{l.icon ? `${l.icon} ` : ''}{l.kind === 'flirt' ? `“${l.text}”` : l.text}</span>
                <small>{l.points > 0 ? `+${l.points} · ` : ''}{ago(l.created_at)}</small>
              </span>
            </li>
          ))}
        </ul>
      )}

      <div className="fm-foot">
        <button type="button" className="fm-link" onClick={() => onReport(r.partner.id, r.partner.username)}>Report @{r.partner.username}</button>
        <Button variant="ghost" size="sm" className="fm-danger" onClick={() => onBreakup(r)} data-testid="fm-breakup">Break up</Button>
      </div>
    </article>
  );
}

function UsTab({ ov, me, run, busy, loadedAt, goLinkups, onReport, onBreakup }: {
  ov: LoveOverview; me: { avatar: AvatarConfig | null; username: string }; run: (k: string, fn: () => Promise<{ message?: string }>) => void; busy: string | null;
  loadedAt: number; goLinkups: () => void; onReport: (id: string, name: string) => void; onBreakup: (r: LoveRelationship) => void;
}) {
  if (ov.relationships.length === 0) {
    return (
      <div className="fm-stack">
        <EmptyState icon="heart" title="Nobody yet 💞"
          body="When somebody says yes to your ask, you two show up here. Then flirt, go on dates and build a bond together."
          action={<Button variant="green" onClick={goLinkups} data-testid="fm-cta-linkups">Find someone</Button>} />
      </div>
    );
  }
  return (
    <div className="fm-stack">
      {ov.relationships.map((r) => <RelCard key={r.id} r={r} ov={ov} me={me} run={run} busy={busy} loadedAt={loadedAt} onReport={onReport} onBreakup={onBreakup} />)}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ Family
function FamilyTab({ ov, me, run, busy, goUs, goLinkups, kids, kidsErr, kidsAt, runKids, onName }: {
  ov: LoveOverview; me: { avatar: AvatarConfig | null; username: string }; run: (k: string, fn: () => Promise<{ message?: string }>) => void; busy: string | null;
  goUs: () => void; goLinkups: () => void; kids: KidsStatus | null; kidsErr: string | null; kidsAt: number;
  runKids: (k: string, fn: () => Promise<{ message?: string }>) => void; onName: (c: KidChild) => void;
}) {
  const couples = ov.relationships.filter((r) => r.status === 'couple');
  const talking = ov.relationships.filter((r) => r.status === 'talking');
  return (
    <div className="fm-stack">
      {couples.map((r) => (
        <article key={r.id} className="fm-card fm-couplecard" data-testid="fm-couple-card">
          <Couple me={me} r={r} big />
          <div className="fm-facts">
            <span><b>{r.days_together === 0 ? 'Today' : r.days_together}</b><small>{r.days_together === 0 ? 'together since' : r.days_together === 1 ? 'day together' : 'days together'}</small></span>
            <span><b>{r.level}</b><small>bond level</small></span>
          </div>
          <div className="fm-bar" aria-hidden><span className="fm-bar__fill" style={{ transform: `scaleX(${r.level / 100})` }} /></div>
        </article>
      ))}
      {couples.length === 0 && (
        <article className="fm-card fm-note">
          <b>{talking.length ? 'Not a couple yet' : 'No family yet'}</b>
          <p>{talking.length
            ? `You are talking with @${talking[0].partner.username}. Reach flirt level ${ov.couple_level} to become a couple and it shows here.`
            : 'Ask somebody out in Link-ups. When you two become a couple, your family shows here.'}</p>
          <Button variant="green" onClick={talking.length ? goUs : goLinkups}>{talking.length ? 'Open Us' : 'Open Link-ups'}</Button>
        </article>
      )}

      <KidsSection kids={kids} err={kidsErr} at={kidsAt} run={runKids} busy={busy} onName={onName} onRetry={() => void useKids.getState().load()} />

      <section className="fm-card fm-open">
        <Switch checked={ov.me.show_relationship} disabled={busy === 'show'} label="Show my relationship on my profile"
          hint={ov.me.show_relationship ? 'Other players see “With @name” on your profile.' : 'Hidden. Your profile does not say who you are with.'}
          onChange={(v) => run('show', () => loveSetShowRelationship(v))} />
      </section>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ the app
export default function FamilyApp({ initialTab = 'linkups' }: { initialTab?: FamilyTab }) {
  const [tab, setTab] = useState<FamilyTab>(initialTab);
  const [ov, setOv] = useState<LoveOverview | null>(null);
  const [loadedAt, setLoadedAt] = useState(0);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [report, setReport] = useState<{ id: string; name: string } | null>(null);
  const [reason, setReason] = useState('');
  const [alsoBlock, setAlsoBlock] = useState(false);
  const [leave, setLeave] = useState<LoveRelationship | null>(null);
  const [nameFor, setNameFor] = useState<KidChild | null>(null);
  const [nameText, setNameText] = useState('');
  const [nameGender, setNameGender] = useState<'boy' | 'girl' | null>(null);
  const kids = useKids((s) => s.status);
  const kidsAt = useKids((s) => s.at);
  const kidsErr = useKids((s) => s.error);
  const periodRef = useRef(45_000);
  const pollRef = useRef<ReturnType<typeof startPoller> | null>(null);
  const profile = useGame((s) => s.state?.profile);
  const eventsRevision = useGame((s) => s.events[0]?.id ?? 0);
  const me = useMemo(() => ({ avatar: (profile?.avatar ?? null) as AvatarConfig | null, username: profile?.username ?? 'you' }), [profile?.avatar, profile?.username]);

  const load = useCallback(async () => {
    try {
      const r = await loveOverview();
      periodRef.current = Math.max(20, r.poll_seconds ?? 45) * 1000;
      setOv(r);
      setLoadedAt(serverNow());
      setErr(null);
    } catch (e) {
      setErr(errorMessage(e));
    }
  }, []);

  // poll only while the app is mounted (startPoller also pauses when the tab is hidden or the player is away)
  useEffect(() => {
    const p = startPoller(load, () => periodRef.current, { immediate: true });
    pollRef.current = p;
    return () => { p.stop(); pollRef.current = null; };
  }, [load]);
  // a love alert arrived (ask, accept, flirt, date, break-up): refresh now
  useEffect(() => { if (eventsRevision) pollRef.current?.kick(700); }, [eventsRevision]);

  const run = useCallback(async (key: string, fn: () => Promise<{ message?: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      if (r?.message) toast(r.message, key.startsWith('no:') || key.startsWith('wd:') ? 'info' : 'good');
      await load();
      setReloadKey((n) => n + 1);
      void useGame.getState().refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void load();
    } finally {
      setBusy(null);
    }
  }, [load]);

  // a kids action: show the answer, then re-read kids_status (and my money) at once
  const runKids = useCallback(async (key: string, fn: () => Promise<{ message?: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      if (r?.message) toast(r.message, key.startsWith('kn:') || key.startsWith('kw:') ? 'info' : 'good');
      await Promise.all([useKids.getState().load(), load()]);
      void useGame.getState().refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void useKids.getState().load();
    } finally {
      setBusy(null);
    }
  }, [load]);

  const doName = async () => {
    if (!nameFor || !nameGender) return;
    setBusy('kname');
    try {
      const r = await kidsName(nameFor.id, nameText.trim(), nameGender);
      toast(r.message, 'good');
      setNameFor(null);
      await useKids.getState().load();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void useKids.getState().load();
    } finally {
      setBusy(null);
    }
  };

  const doReport = async () => {
    if (!report) return;
    setBusy('report');
    try {
      const r = await loveReport(report.id, reason);
      if (alsoBlock) { try { await rpc('chat_block', { p_user: report.id }); } catch { /* a full block list must not lose the report */ } }
      toast(r.message, 'good');
      setReport(null);
      setReason('');
      await load();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  const doBreakup = async () => {
    if (!leave) return;
    setBusy('breakup');
    try {
      const r = await loveBreakup(leave.id);
      toast(r.message, 'info');
      setLeave(null);
      await load();
      setReloadKey((n) => n + 1);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  if (!ov) {
    return (
      <div className="phone-app__body fm-app">
        {err ? <EmptyState icon="warning" title="Could not open Family" body={err} action={<Button variant="green" onClick={() => void load()}>Try again</Button>} />
          : <div className="panel-skel"><span /><span /></div>}
      </div>
    );
  }
  if (!ov.enabled) {
    return <div className="phone-app__body fm-app"><EmptyState icon="heart" title="Family is resting" body="Link-ups and dating are switched off for now. Check back soon." /></div>;
  }

  const unreadInvite = ov.relationships.some((r) => r.invite && !r.invite.mine) ? 1 : 0;
  const tabs = [
    { id: 'linkups', label: 'Link-ups', badge: ov.incoming.length || null },
    { id: 'us', label: 'Us', badge: unreadInvite || null },
    { id: 'family', label: 'Family' },
  ];
  const rules = ov.rules;

  return (
    <div className="phone-app__body fm-app">
      <Tabs tabs={tabs} value={tab} onChange={(t) => setTab(t as FamilyTab)} className="fm-tabs" tourPrefix="family" />
      <div key={tab} className="fm-pane">
        {tab === 'linkups' && <LinkupsTab ov={ov} run={run} busy={busy} goUs={() => setTab('us')} onReport={(id, name) => setReport({ id, name })} reloadKey={reloadKey} />}
        {tab === 'us' && <UsTab ov={ov} me={me} run={run} busy={busy} loadedAt={loadedAt} goLinkups={() => setTab('linkups')} onReport={(id, name) => setReport({ id, name })} onBreakup={setLeave} />}
        {tab === 'family' && <FamilyTab ov={ov} me={me} run={run} busy={busy} goUs={() => setTab('us')} goLinkups={() => setTab('linkups')} kids={kids} kidsErr={kidsErr} kidsAt={kidsAt} runKids={runKids} onName={(c) => { setNameFor(c); setNameText(''); setNameGender(null); }} />}
      </div>

      <Modal open={Boolean(report)} onClose={() => busy !== 'report' && setReport(null)} title={report ? `Report @${report.name}` : ''}
        actions={<>
          <Button variant="ghost" disabled={busy === 'report'} onClick={() => setReport(null)}>Cancel</Button>
          <Button variant="danger" loading={busy === 'report'} disabled={reason.trim().length < 3} onClick={() => void doReport()}>Send report</Button>
        </>}>
        <div className="fm-form">
          <p className="fm-fine">A moderator reads every report. Tell us what happened, in your own words.</p>
          <textarea value={reason} maxLength={300} rows={3} onChange={(e) => setReason(e.target.value)} placeholder="What happened?" aria-label="What happened" />
          <label className="fm-check"><input type="checkbox" checked={alsoBlock} onChange={(e) => setAlsoBlock(e.target.checked)} /><span>Also block them (no more asks or messages)</span></label>
        </div>
      </Modal>

      <Modal open={Boolean(nameFor)} onClose={() => busy !== 'kname' && setNameFor(null)} title="Name your baby"
        actions={<>
          <Button variant="ghost" disabled={busy === 'kname'} onClick={() => setNameFor(null)}>Not now</Button>
          <Button variant="green" loading={busy === 'kname'} disabled={!/^\p{L}{3,16}$/u.test(nameText.trim()) || !nameGender} onClick={() => void doName()} data-testid="kids-name-save">Save name</Button>
        </>}>
        <div className="fm-form">
          <p className="fm-fine">3 to 16 letters. The first parent to save a name picks it for both of you, so talk first.</p>
          <input className="fm-input" value={nameText} maxLength={16} autoComplete="off" autoCapitalize="words" spellCheck={false} placeholder="Name"
            aria-label="Baby name" onChange={(e) => setNameText(e.target.value.replace(/[^\p{L}]/gu, ''))} data-testid="kids-name-input" />
          <div className="fm-filters" role="group" aria-label="Boy or girl">
            {([['boy', 'Boy 👦'], ['girl', 'Girl 👧']] as const).map(([id, label]) => (
              <button key={id} type="button" className={`fm-chip${nameGender === id ? ' is-on' : ''}`} aria-pressed={nameGender === id} onClick={() => setNameGender(id)} data-testid={`kids-gender-${id}`}>{label}</button>
            ))}
          </div>
          <p className="fm-fine">Boy or Girl only changes how your child looks.</p>
        </div>
      </Modal>

      <Modal open={Boolean(leave)} onClose={() => busy !== 'breakup' && setLeave(null)} tone="bad" title={leave ? `Break up with @${leave.partner.username}?` : ''}
        actions={<>
          <Button variant="ghost" disabled={busy === 'breakup'} onClick={() => setLeave(null)}>Stay together</Button>
          <Button variant="danger" loading={busy === 'breakup'} onClick={() => void doBreakup()} data-testid="fm-breakup-yes">Break up</Button>
        </>}>
        <p className="fm-fine">
          They will be told kindly. You two cannot ask each other out for {rules?.breakup_days ?? 3} days, and you cannot ask anybody for {rules?.breakup_hours ?? 24} hours.
          Your history stays on record.
        </p>
      </Modal>
    </div>
  );
}
