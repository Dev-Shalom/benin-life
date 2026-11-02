// Court app: the lawyer list (search by @name, Available now, Top by wins), and registering / editing your own lawyer profile.
import { useEffect, useRef, useState } from 'react';
import { courtLawyerRegister, courtLawyerRetire, courtLawyerUpdate, courtLawyers, type CourtLawyer, type CourtStatus } from '../../../../api/court';
import { errorMessage } from '../../../../lib/api';
import { naira } from '../../../../lib/format';
import { Button, EmptyState, Segmented, toast } from '../../../../ui';
import { LawyerCard, RankBadge } from './courtKit';

type Filter = 'all' | 'available' | 'top';

export function LawyerList({ onPick, picked, action, skipMe = false }: {
  onPick?: (l: CourtLawyer) => void; picked?: string | null; action?: (l: CourtLawyer) => React.ReactNode; skipMe?: boolean;
}) {
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [rows, setRows] = useState<CourtLawyer[] | null>(null);
  const [err, setErr] = useState('');
  const seq = useRef(0);
  useEffect(() => {
    const my = ++seq.current;
    const t = window.setTimeout(() => {
      courtLawyers(q.trim(), filter).then((r) => { if (my === seq.current) { setRows(r); setErr(''); } }).catch((e) => { if (my === seq.current) setErr(errorMessage(e)); });
    }, q ? 250 : 0);
    return () => window.clearTimeout(t);
  }, [q, filter]);
  const shown = (rows ?? []).filter((l) => !(skipMe && l.me));
  return (
    <div className="ct-stack">
      <input className="ct-input" type="search" inputMode="search" autoCapitalize="none" autoComplete="off" placeholder="Search a lawyer by @name" value={q}
        onChange={(e) => setQ(e.target.value)} aria-label="Search lawyers" />
      <Segmented<Filter> label="Lawyer filter" value={filter} onChange={setFilter}
        options={[{ id: 'all', label: 'All' }, { id: 'available', label: 'Available now' }, { id: 'top', label: 'Top by wins' }]} />
      {err && <p className="error-text">{err}</p>}
      {rows === null && !err && <div className="ct-skel"><span /><span /></div>}
      {rows !== null && !shown.length && <EmptyState icon="info" title="No lawyers found" body={filter === 'available' ? 'Nobody is available right now. Try All, or come back later.' : 'Try another name.'} />}
      {shown.map((l) => <LawyerCard key={l.user_id} l={l} selected={picked === l.user_id} onPick={onPick ? () => onPick(l) : undefined} action={action?.(l)} />)}
    </div>
  );
}

/** Register as a lawyer, or manage your profile. */
export function LawyerProfile({ status, reload, onBack }: { status: CourtStatus; reload: () => void; onBack: () => void }) {
  const me = status.lawyer && !status.lawyer.retired ? status.lawyer : null;
  const s = status.settings;
  const [fee, setFee] = useState(String(me?.fee ?? 10000));
  const [bio, setBio] = useState(me?.bio ?? '');
  const [busy, setBusy] = useState(false);
  const feeN = Math.round(Number(fee.replace(/[^0-9]/g, '')) || 0);
  const run = async (fn: () => Promise<{ message: string }>, then?: () => void) => {
    setBusy(true);
    try { const r = await fn(); toast(r.message, 'good'); reload(); then?.(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <div className="ct-stack">
      <button type="button" className="ct-back" onClick={onBack}>← Back</button>
      <h2 className="ct-title">{me ? 'Your lawyer profile' : 'Become a lawyer'}</h2>
      {status.lawyer?.banned && <p className="ct-warn">The court removed you as a lawyer{status.lawyer.ban_reason ? `: ${status.lawyer.ban_reason}` : '.'}</p>}
      {me ? (
        <section className="ct-panel">
          <span className="ct-label">Your record</span>
          <span className="ct-main"><RankBadge rank={me.rank} /> {me.wins} won · {me.losses} lost</span>
          <span className="ct-meta">{me.next_rank ? `${me.wins_to_next} more win${me.wins_to_next === 1 ? '' : 's'} to ${me.next_rank}.` : 'You are a Senior Advocate, the top rank.'}</span>
        </section>
      ) : (
        <section className="ct-panel">
          <span className="ct-label">Requirements</span>
          <ul className="ct-checks">
            {status.lawyer_requirements.checks.map((c) => <li key={c.key} className={c.ok ? 'is-ok' : ''}><span aria-hidden>{c.ok ? '✓' : '○'}</span> {c.label}</li>)}
          </ul>
          <span className="ct-meta">You can take a Law and Advocacy course at UNIBEN (School app) to earn the certificate.</span>
        </section>
      )}
      <section className="ct-panel">
        <label className="ct-field"><span className="ct-label">Fee per case (₦)</span>
          <input className="ct-input" inputMode="numeric" value={fee} onChange={(e) => setFee(e.target.value)} aria-label="Fee per case" /></label>
        <span className="ct-meta">Allowed: {naira(s.lawyer_min_fee)} to {naira(s.lawyer_max_fee)}. The client pays it up front into escrow. You get it on the verdict, minus a {s.cut_pct}% court cut.</span>
        <label className="ct-field"><span className="ct-label">About you (short)</span>
          <textarea className="ct-input" rows={3} maxLength={120} value={bio} onChange={(e) => setBio(e.target.value)} placeholder="Fast, fair and always on time." aria-label="About you" /></label>
        <Button variant="green" block loading={busy} disabled={(!me && !status.lawyer_requirements.ok) || feeN < s.lawyer_min_fee || feeN > s.lawyer_max_fee}
          onClick={() => void run(() => (me ? courtLawyerUpdate(feeN, bio, null).then((r) => r) : courtLawyerRegister(feeN, bio)), onBack)}>
          {me ? 'Save' : 'Register as a lawyer'}
        </Button>
      </section>
      {me && (
        <section className="ct-panel">
          <span className="ct-label">Availability</span>
          <span className="ct-meta">{me.available ? 'Clients can see you in the list and hire you.' : 'You are hidden from "Available now". Clients can still find you by name.'}</span>
          <Button variant="ghost" block loading={busy} onClick={() => void run(() => courtLawyerUpdate(null, null, !me.available))}>{me.available ? 'Pause: I am not taking cases' : 'I am available again'}</Button>
          <Button variant="danger" block loading={busy} onClick={() => void run(() => courtLawyerRetire(), onBack)}>Retire as a lawyer</Button>
        </section>
      )}
    </div>
  );
}
