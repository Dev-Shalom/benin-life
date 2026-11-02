// The Court phone app (docs/COURT.md): My cases, Lawyers, Live now. A 3-step "Take them to court" flow, lawyer registration and the live hearing page.
import { useCallback, useEffect, useState } from 'react';
import { courtHireRespond, courtJudgeTake, courtLive, courtStatus, type CourtLive, type CourtStatus } from '../../../api/court';
import { errorMessage } from '../../../lib/api';
import { naira } from '../../../lib/format';
import { startPoller } from '../../../lib/realtime';
import type { GameState } from '../../../lib/types';
import { Button, EmptyState, Tabs, toast } from '../../../ui';
import { Hearing } from './court/Hearing';
import { LawyerList, LawyerProfile } from './court/LawyerPanel';
import { SueFlow } from './court/SueFlow';
import { CaseCard, Face, RankBadge, useNow } from './court/courtKit';
import './court/court.css';

type View = { n: 'home' } | { n: 'sue' } | { n: 'lawyer' } | { n: 'case'; id: number };
type Tab = 'mine' | 'lawyers' | 'live';

export default function CourtApp({ state, initial }: { state: GameState; initial?: string }) {
  const [view, setView] = useState<View>(() => { const id = Number((initial ?? '').split(':')[1]); return id ? { n: 'case', id } : { n: 'home' }; });
  const [tab, setTab] = useState<Tab>('mine');
  const [status, setStatus] = useState<CourtStatus | null>(null);
  const [live, setLive] = useState<CourtLive | null>(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const now = useNow(1000);
  const myName = state.profile.username;

  const reload = useCallback(() => { courtStatus().then((r) => { setStatus(r); setErr(''); }).catch((e) => setErr(errorMessage(e))); }, []);
  const reloadLive = useCallback(() => { courtLive().then(setLive).catch((e) => setErr(errorMessage(e))); }, []);
  useEffect(() => { reload(); }, [reload]);
  useEffect(() => {
    if (view.n !== 'home' || tab !== 'live') return;
    const p = startPoller(reloadLive, () => 20_000, { immediate: true });
    return () => p.stop();
  }, [view.n, tab, reloadLive]);

  const act = async (fn: () => Promise<{ message: string }>) => {
    setBusy(true);
    try { const r = await fn(); toast(r.message, 'good'); reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };

  if (view.n === 'case') return <div className="phone-app__body court-app"><Hearing id={view.id} myName={myName} isJudge={Boolean(status?.judge)} onBack={() => { setView({ n: 'home' }); reload(); }} onChanged={reload} /></div>;
  if (!status) return <div className="phone-app__body court-app">{err ? <p className="error-text">{err}</p> : <div className="ct-skel"><span /><span /><span /></div>}</div>;
  if (view.n === 'sue') return <div className="phone-app__body court-app"><SueFlow status={status} onBack={() => setView({ n: 'home' })} onFiled={(id) => { reload(); setView({ n: 'case', id }); }} /></div>;
  if (view.n === 'lawyer') return <div className="phone-app__body court-app"><LawyerProfile status={status} reload={reload} onBack={() => setView({ n: 'home' })} /></div>;

  const open = status.cases.filter((c) => c.status === 'scheduled');
  const done = status.cases.filter((c) => c.status !== 'scheduled');
  const badge = status.hire_requests.length + (status.judge ? status.judge_queue.length : 0);
  return (
    <div className="phone-app__body court-app">
      <div className="ct-stack">
        <header className="ct-head">
          <h1 className="ct-title">High Court, Benin</h1>
          <p className="ct-lead">Sue over what the game recorded. Hire a real player as your lawyer. A judge rules, or the record does.</p>
        </header>
        <Tabs value={tab} onChange={(t) => setTab(t as Tab)} tabs={[{ id: 'mine', label: 'My cases', badge: badge || null }, { id: 'lawyers', label: 'Lawyers' }, { id: 'live', label: 'Live now' }]} />
        {err && <p className="error-text">{err}</p>}
        {!status.enabled && <p className="ct-warn">The court is closed for now.</p>}

        {tab === 'mine' && (
          <>
            <Button variant="green" size="lg" block disabled={!status.enabled} onClick={() => setView({ n: 'sue' })} data-tour="court-sue">⚖️ Sue someone</Button>
            {status.blocked && <p className="ct-meta">{status.blocked}</p>}
            {status.hire_requests.map((h) => (
              <section key={h.hire} className="ct-panel ct-panel--gold">
                <span className="ct-label">A client wants you as their lawyer</span>
                <span className="ct-main">@{h.client.username} · {h.case.case_no}</span>
                <span className="ct-meta">{h.case.title} · fee {naira(h.fee)} held in escrow. Answer before the hearing starts.</span>
                <div className="ct-row">
                  <Button size="sm" variant="green" loading={busy} onClick={() => void act(() => courtHireRespond(h.hire, true))}>Accept</Button>
                  <Button size="sm" variant="ghost" loading={busy} onClick={() => void act(() => courtHireRespond(h.hire, false))}>Decline</Button>
                  <Button size="sm" variant="ghost" onClick={() => setView({ n: 'case', id: h.case.id })}>View case</Button>
                </div>
              </section>
            ))}
            {status.judge_queue.map((c) => (
              <section key={c.id} className="ct-panel ct-panel--gold">
                <span className="ct-label">Waiting for a judge</span>
                <span className="ct-main">{c.case_no} · {c.title}</span>
                <div className="ct-row"><Button size="sm" variant="green" loading={busy} onClick={() => void act(() => courtJudgeTake(c.id))}>Take this case</Button>
                  <Button size="sm" variant="ghost" onClick={() => setView({ n: 'case', id: c.id })}>View</Button></div>
              </section>
            ))}
            {status.debts.owed > 0 && (
              <section className="ct-panel ct-panel--warn">
                <span className="ct-label">Court debt</span>
                <span className="ct-main">{naira(status.debts.owed)}</span>
                <span className="ct-meta">{status.debts.collect_pct}% of what you earn goes to it until it is paid.</span>
              </section>
            )}
            {!status.cases.length && <EmptyState icon="info" title="No cases" body="You can sue over a recorded pickpocket, a tenant who left owing rent, an unfair eviction or a Market overcharge." />}
            {open.length > 0 && <h3 className="ct-h">Open</h3>}
            {open.map((c) => <CaseCard key={c.id} c={c} now={now} onOpen={() => setView({ n: 'case', id: c.id })} />)}
            {done.length > 0 && <h3 className="ct-h">Finished</h3>}
            {done.map((c) => <CaseCard key={c.id} c={c} now={now} onOpen={() => setView({ n: 'case', id: c.id })} />)}
          </>
        )}

        {tab === 'lawyers' && (
          <>
            <section className="ct-panel">
              <span className="ct-label">{status.lawyer && !status.lawyer.retired ? 'You are a lawyer' : 'Practise law'}</span>
              {status.lawyer && !status.lawyer.retired ? (
                <span className="ct-main"><Face who={{ username: myName, avatar: status.lawyer.avatar }} size={34} /> <RankBadge rank={status.lawyer.rank} /> {status.lawyer.wins} won · {status.lawyer.losses} lost</span>
              ) : <span className="ct-meta">Register as a lawyer, set your fee and take cases from other players. Climb from Junior Lawyer to Senior Advocate by winning.</span>}
              <Button variant={status.lawyer && !status.lawyer.retired ? 'ghost' : 'gold'} block onClick={() => setView({ n: 'lawyer' })} data-tour="court-lawyer">
                {status.lawyer && !status.lawyer.retired ? 'Manage my profile' : 'Become a lawyer'}
              </Button>
            </section>
            <LawyerList />
          </>
        )}

        {tab === 'live' && (
          <>
            {!live && <div className="ct-skel"><span /><span /></div>}
            {live && !live.live.length && !live.upcoming.length && !live.recent.length && <EmptyState icon="info" title="No hearings now" body="Hearings start about half an hour after a case is filed. Anyone can watch from the gallery." />}
            {live && live.live.length > 0 && <h3 className="ct-h">Live now</h3>}
            {live?.live.map((c) => <CaseCard key={c.id} c={c} now={now} cta="Watch" onOpen={() => setView({ n: 'case', id: c.id })} />)}
            {live && live.upcoming.length > 0 && <h3 className="ct-h">Starting soon</h3>}
            {live?.upcoming.map((c) => <CaseCard key={c.id} c={c} now={now} onOpen={() => setView({ n: 'case', id: c.id })} />)}
            {live && live.recent.length > 0 && <h3 className="ct-h">Just ruled</h3>}
            {live?.recent.map((c) => <CaseCard key={c.id} c={c} now={now} onOpen={() => setView({ n: 'case', id: c.id })} />)}
          </>
        )}
      </div>
    </div>
  );
}
