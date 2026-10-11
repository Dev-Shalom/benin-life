// S1-D Feedback app: send a Suggestion / Bug / Review to the Benin Life team and see their replies.
import { useEffect, useState } from 'react';
import { FEEDBACK_KINDS, FEEDBACK_STATUS, feedbackMine, feedbackSubmit, type FeedbackKind, type FeedbackMine } from '../../../api/feedback';
import { errorMessage } from '../../../lib/api';
import { useGame } from '../../../state/game';
import { Button, EmptyState, toast } from '../../../ui';

const MAX = 1000;

function Stars({ value, onChange }: { value: number; onChange?: (n: number) => void }) {
  return (
    <span className={`fb-stars${onChange ? ' is-input' : ''}`} role={onChange ? 'radiogroup' : undefined} aria-label={onChange ? 'Rating' : `${value} of 5 stars`}>
      {[1, 2, 3, 4, 5].map((n) => onChange ? (
        <button key={n} type="button" role="radio" aria-checked={value === n} aria-label={`${n} star${n > 1 ? 's' : ''}`}
          className={n <= value ? 'is-on' : ''} onClick={() => onChange(n)}>★</button>
      ) : <span key={n} className={n <= value ? 'is-on' : ''} aria-hidden>★</span>)}
    </span>
  );
}

export default function FeedbackApp() {
  const [data, setData] = useState<FeedbackMine | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [kind, setKind] = useState<FeedbackKind>('suggestion');
  const [rating, setRating] = useState(0);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  // a reply arrives as an in-game alert (events channel): reload the list when one lands
  const replies = useGame((s) => s.events.filter((e) => e.kind === 'feedback_reply').length);

  const load = () => feedbackMine().then((d) => { setData(d); setErr(null); }).catch((e) => setErr(errorMessage(e)));
  useEffect(() => { void load(); }, [replies]);

  const trimmed = text.trim();
  const canSend = !busy && trimmed.length >= 3 && trimmed.length <= MAX && (kind !== 'review' || rating > 0)
    && (data?.enabled ?? true) && (data?.left_today ?? 1) > 0;
  const send = async () => {
    if (!canSend) return;
    setBusy(true);
    try {
      const r = await feedbackSubmit(kind, trimmed, kind === 'review' ? rating : null);
      toast(r.message, 'good');
      setText('');
      setRating(0);
      await load();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const meta = FEEDBACK_KINDS.find((k) => k.id === kind)!;

  return (
    <div className="phone-app__body fb-app">
      <p className="phone-app__lead">Tell the Benin Life team wetin you think. We read everything, and we fit reply you here.</p>
      {data && !data.enabled && <p className="error-text">The feedback box is closed for now. Try again later.</p>}
      <section className="fb-form" aria-label="Send feedback">
        <div className="seg fb-kinds" role="radiogroup" aria-label="Type">
          {FEEDBACK_KINDS.map((k) => (
            <button key={k.id} type="button" role="radio" aria-checked={kind === k.id}
              className={`seg__btn${kind === k.id ? ' is-on' : ''}`} onClick={() => setKind(k.id)}>
              <span aria-hidden>{k.emoji}</span> {k.label}
            </button>
          ))}
        </div>
        {kind === 'review' && <div className="fb-rate"><span>Your rating</span><Stars value={rating} onChange={setRating} /></div>}
        <label className="fb-text">
          <span className="sr-only">Your message</span>
          <textarea value={text} maxLength={MAX} rows={5} placeholder={meta.hint} onChange={(e) => setText(e.target.value)} />
          <span className={`fb-count${text.length > MAX - 50 ? ' is-near' : ''}`}>{text.length}/{MAX}</span>
        </label>
        <Button variant="green" block loading={busy} disabled={!canSend} onClick={() => void send()}>Send {meta.label.toLowerCase()}</Button>
        {data && <p className="hint fb-left">{data.left_today > 0 ? `You fit send ${data.left_today} more today.` : 'You don reach today’s limit. Thank you! Try again tomorrow.'}</p>}
      </section>

      <section className="fb-mine">
        <h3>Your messages</h3>
        {err && <p className="error-text">{err}</p>}
        {!data && !err && <div className="panel-skel"><span /><span /></div>}
        {data && data.rows.length === 0 && <EmptyState icon="info" title="Nothing yet" body="Your suggestions, bug reports and reviews show here, with our replies." />}
        {data?.rows.map((f) => {
          const k = FEEDBACK_KINDS.find((x) => x.id === f.kind);
          return (
            <article key={f.id} className="fb-item">
              <header>
                <b><span aria-hidden>{k?.emoji}</span> {k?.label}</b>
                {f.rating ? <Stars value={f.rating} /> : null}
                <span className={`fb-status fb-status--${f.status}`}>{FEEDBACK_STATUS[f.status]}</span>
                {f.reply && <span className="fb-status fb-status--replied">Replied</span>}
              </header>
              <p>{f.body}</p>
              <small className="muted">{new Date(f.created_at).toLocaleString()}</small>
              {f.reply && (
                <div className="fb-reply">
                  <b>Benin Life team</b>
                  <p>{f.reply}</p>
                </div>
              )}
            </article>
          );
        })}
      </section>
    </div>
  );
}
