// "Take them to court": 1 what happened (only events the game recorded), 2 pick a lawyer (or speak for yourself), 3 confirm and pay.
import { useEffect, useState } from 'react';
import { courtEvents, courtFile, KIND_HELP, KIND_ICON, KIND_LABEL, type CourtEvent, type CourtEvents, type CourtLawyer, type CourtStatus } from '../../../../api/court';
import { errorMessage } from '../../../../lib/api';
import { naira, timeAgo } from '../../../../lib/format';
import { Button, EmptyState, toast } from '../../../../ui';
import { LawyerList } from './LawyerPanel';
import { LawyerCard } from './courtKit';

const STEPS = ['What happened', 'Pick a lawyer', 'Confirm and pay'];

function Steps({ n }: { n: number }) {
  return (
    <ol className="ct-steps" aria-label={`Step ${n} of 3`}>
      {STEPS.map((s, i) => <li key={s} className={i + 1 === n ? 'is-on' : i + 1 < n ? 'is-done' : ''}><b>{i + 1 < n ? '✓' : i + 1}</b><span>{s}</span></li>)}
    </ol>
  );
}

export function SueFlow({ status, onBack, onFiled }: { status: CourtStatus; onBack: () => void; onFiled: (caseId: number) => void }) {
  const [step, setStep] = useState(1);
  const [data, setData] = useState<CourtEvents | null>(null);
  const [err, setErr] = useState('');
  const [pick, setPick] = useState<CourtEvent | null>(null);
  const [lawyer, setLawyer] = useState<CourtLawyer | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { courtEvents().then(setData).catch((e) => setErr(errorMessage(e))); }, []);
  const s = status.settings;
  const total = (pick?.fee ?? 0) + (lawyer?.fee ?? 0);
  const file = async () => {
    if (!pick) return;
    setBusy(true);
    try {
      const r = await courtFile(pick.kind, pick.ref, lawyer?.user_id ?? null);
      toast(r.message, 'good');
      onFiled(r.case.id);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <div className="ct-stack">
      <button type="button" className="ct-back" onClick={step === 1 ? onBack : () => setStep(step - 1)}>← {step === 1 ? 'Back' : 'Previous step'}</button>
      <h2 className="ct-title">Take them to court</h2>
      <Steps n={step} />

      {step === 1 && (
        <>
          <p className="ct-lead">Pick what happened. The court only hears what the game recorded in the last {data?.lookback_hours ?? s.lookback_hours} hours.</p>
          {err && <p className="error-text">{err}</p>}
          {!data && !err && <div className="ct-skel"><span /><span /></div>}
          {data?.blocked && <p className="ct-warn">{data.blocked}</p>}
          {data && !data.events.length && <EmptyState icon="info" title="Nothing to sue over" body="No recorded event is waiting. A theft, an unfair eviction, rent owed or a Market overcharge appears here as soon as the game records it." />}
          {data?.events.map((e) => (
            <button key={`${e.kind}-${e.ref}`} type="button" disabled={e.filed || Boolean(data.blocked)} className={`ct-card ct-card--pick${pick?.ref === e.ref && pick.kind === e.kind ? ' is-on' : ''}`}
              onClick={() => setPick(e)} aria-pressed={pick?.ref === e.ref && pick.kind === e.kind}>
              <span className="ct-card__top"><span className="ct-label">{KIND_LABEL[e.kind]} · {timeAgo(e.at)}</span>{e.filed && <span className="ct-badge ct-badge--grey">Already filed</span>}</span>
              <span className="ct-main"><span aria-hidden>{KIND_ICON[e.kind]}</span> {e.title}</span>
              <span className="ct-meta">{e.sub}</span>
              <span className="ct-divider" />
              <span className="ct-card__foot"><span className="ct-meta">Against @{e.defendant_name ?? 'unknown'} · {e.tier === 'customary' ? 'Customary Court' : 'High Court'}</span><b>{naira(e.claim)}</b></span>
            </button>
          ))}
          <Button variant="green" block disabled={!pick} onClick={() => setStep(2)}>Next: pick a lawyer</Button>
        </>
      )}

      {step === 2 && pick && (
        <>
          <p className="ct-lead">A lawyer is a real player. They accept or decline, and the fee is held until the verdict. No lawyer? You speak for yourself.</p>
          <button type="button" className={`ct-card ct-card--pick${!lawyer ? ' is-on' : ''}`} onClick={() => setLawyer(null)} aria-pressed={!lawyer}>
            <span className="ct-main">🧑🏾 Speak for myself</span>
            <span className="ct-meta">No fee. You post your own statements at the hearing.</span>
          </button>
          <LawyerList skipMe picked={lawyer?.user_id ?? null} onPick={(l) => setLawyer(l.user_id === lawyer?.user_id ? null : l)} />
          <Button variant="green" block onClick={() => setStep(3)}>Next: confirm</Button>
        </>
      )}

      {step === 3 && pick && (
        <>
          <section className="ct-panel">
            <span className="ct-label">{pick.tier === 'customary' ? 'Customary Court, Benin' : 'High Court, Benin'}</span>
            <span className="ct-main"><span aria-hidden>{KIND_ICON[pick.kind]}</span> {pick.title}</span>
            <span className="ct-meta">{KIND_HELP[pick.kind]}</span>
            <span className="ct-divider" />
            <dl className="ct-dl">
              <div><dt>Against</dt><dd>@{pick.defendant_name}</dd></div>
              <div><dt>You are asking for</dt><dd>{naira(pick.claim)}</dd></div>
              <div><dt>Hearing</dt><dd>about {s.hearing_delay_minutes} minutes after you file</dd></div>
              <div><dt>Filing fee</dt><dd>{naira(pick.fee)}</dd></div>
              <div><dt>Lawyer</dt><dd>{lawyer ? `@${lawyer.username}` : 'none (you speak)'}</dd></div>
              {lawyer && <div><dt>Lawyer fee (held)</dt><dd>{naira(lawyer.fee)}</dd></div>}
            </dl>
          </section>
          {lawyer && <LawyerCard l={lawyer} compact />}
          <p className="ct-meta">If the court finds them guilty you get your filing fee back and they pay you back, plus a fine. If not guilty, the filing fee is lost. The lawyer fee goes to the lawyer either way (minus a {s.cut_pct}% court cut). If the lawyer says no, it comes back to you.</p>
          <Button variant="gold" block size="lg" loading={busy} onClick={() => void file()}>Confirm and pay {naira(total)}</Button>
        </>
      )}
    </div>
  );
}
