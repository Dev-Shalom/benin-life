import { useEffect, useState } from 'react';
import { policeBail, policeCases, policeReportRobbery, type PoliceCase } from '../../../api/police';
import { errorMessage } from '../../../lib/api';
import { naira } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, EmptyState, toast } from '../../../ui';

export default function PoliceApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const events = useGame((s) => s.events);
  const locations = useGame((s) => s.locations);
  const refresh = useGame((s) => s.refresh);
  const police = locations.find((l) => l.scene === 'police');
  const atPolice = state.location.scene === 'police' && !state.travel;
  const jailed = Boolean(state.profile.jailed_until && Date.parse(state.profile.jailed_until) > Date.now());
  const robbed = events.filter((e) => e.kind === 'robbed');
  const [cases, setCases] = useState<PoliceCase[]>([]);
  const [statement, setStatement] = useState<Record<number, string>>({});
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const load = () => policeCases().then(setCases).catch((e) => setError(errorMessage(e)));
  useEffect(() => { void load(); }, []);
  const file = async (id: number) => {
    setBusy(true);
    try { const r = await policeReportRobbery(id, statement[id] ?? 'Someone took cash from me while I was travelling.'); toast(r.message, 'good'); await load(); await refresh(); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(false); }
  };
  const bail = async () => {
    setLoading(true);
    try { const r = await policeBail(); toast(`${r.message} Paid ${naira(r.paid)}.`, 'good'); await refresh(); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setLoading(false); }
  };
  return <div className="phone-app__body police-app">
    <p className="phone-app__lead">File a report for a robbery alert, review your case numbers, or pay bail while in a short in-game sentence.</p>
    {error && <p className="error-text">{error}</p>}
    {jailed && <section className="police-app__bail"><b>You are in a police cell</b><p>{state.profile.jail_reason || 'Wait for the timer or pay bail.'}</p>
      <Button variant="gold" block loading={loading} onClick={() => void bail()}>Pay bail · bank first · cash second</Button></section>}
    {!atPolice && !jailed && police && <Button variant="green" block onClick={() => onGo(police.id)}>Go to Police HQ</Button>}
    {atPolice && <section className="police-app__reports"><h3>Robbery alerts</h3>
      {!robbed.length && <p className="muted">No robbery alerts to report. A report can only be filed for an event recorded on your account.</p>}
      {robbed.map((e) => {
        const filed = cases.some((c) => c.event_id === e.id);
        return <article key={e.id} className="police-case"><b>{e.title}</b><p>{e.body}</p>
          <textarea maxLength={400} minLength={8} value={statement[e.id] ?? ''} onChange={(x) => setStatement((s) => ({ ...s, [e.id]: x.target.value }))} placeholder="Add a short statement (8–400 characters)" />
          <Button size="sm" variant="green" disabled={filed || (statement[e.id] ?? '').trim().length < 8 || (statement[e.id] ?? '').length > 400} loading={busy} onClick={() => void file(e.id)}>{filed ? 'Report filed' : 'File report'}</Button>
        </article>;
      })}
    </section>}
    <section className="police-app__cases"><h3>My reports</h3>
      {!cases.length ? <EmptyState icon="info" title="No reports filed" body={atPolice ? 'Your filed reports will appear here.' : 'Go to Police HQ to file a robbery report.'} />
        : cases.map((c) => <article key={c.id} className="police-case"><b>Case #{c.id} · {c.status}</b><p>{c.event_title || 'Robbery report'}</p><p>{c.statement}</p></article>)}
    </section>
  </div>;
}
