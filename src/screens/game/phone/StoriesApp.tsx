// Stories (docs/DAILY_STORIES.md): one short story a day, with a twist. The server picks today's story, rolls what really happens, applies the
// effects, plants follow-ups and moves the hidden path. This screen only shows the scene, sends the choice, and plays the reveal.
//   Today's story card -> pick a choice -> the card turns into the reveal (tone colour, effects as chips, a seed line, a subtle path line).
//   Follow-up chapters ("Your story continues") sit above it. Below: the reading streak and "Your path so far" (words, never numbers).
import { useEffect, useMemo, useRef, useState } from 'react';
import { storyAnswer, storyToday, type PathCard, type Story, type StoryChoice, type StoryResult, type StoryStreak, type StoryTone, type StoryToday } from '../../../api/stories';
import { errorMessage } from '../../../lib/api';
import { serverNow } from '../../../lib/clock';
import { naira, nairaShort } from '../../../lib/format';
import { playCue } from '../../../lib/sound';
import { useGame } from '../../../state/game';
import { useMoments } from '../../../state/moments';
import { EmptyState, toast } from '../../../ui';
import './StoriesApp.css';

const TONE_LABEL: Record<StoryTone, string> = { good: 'That worked out', bad: 'That went wrong', twist: 'Plot twist!', funny: 'Only in Benin', info: 'Life goes on' };
const TONE_ART: Record<StoryTone, string> = { good: '🌟', bad: '💥', twist: '🌀', funny: '😂', info: '🙂' };

/** A chip is good or bad news: money out and items used are bad, and so is any need that went the wrong way (stress up, everything else down). */
function chipTone(line: string): 'up' | 'down' {
  if (/^(Paid|Used|Spent)\b/.test(line)) return 'down';
  const m = line.match(/^(.*?)\s([+-])\d/);
  if (m) return (m[2] === '+') !== /^Stress/i.test(m[1]) ? 'up' : 'down';
  return 'up';
}

/** Hours and minutes until the next Benin midnight (Africa/Lagos is UTC+1 all year). */
function untilNextStory(): string {
  const wat = serverNow() + 3_600_000;
  const left = 86_400_000 - (wat % 86_400_000);
  const h = Math.floor(left / 3_600_000);
  const m = Math.floor((left % 3_600_000) / 60_000);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

function dayLabel(iso: string): string {
  const d = new Date(`${iso}T12:00:00Z`);
  return d.toLocaleDateString('en-NG', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
}

function Reveal({ story, r, onDone }: { story: Story; r: StoryResult; onDone: () => void }) {
  const ref = useRef<HTMLElement>(null);
  useEffect(() => {
    ref.current?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    if (r.tone === 'good' && r.gain > 0) playCue('money');
    else if (r.tone === 'bad') playCue('error');
    else playCue('done');
  }, [r.tone, r.gain]);
  const chips = [
    ...(r.spent > 0 ? [`Spent ${naira(r.spent)}`] : []),
    ...r.effects,
  ];
  const paid = r.streak?.paid ?? [];
  return (
    <article ref={ref} className={`st-card st-rv st-rv--${r.tone}`} aria-live="polite" data-testid="story-reveal" data-tone={r.tone}>
      <div className="st-rv__band">
        <span className="st-rv__fx" aria-hidden>{Array.from({ length: 8 }, (_, i) => <i key={i} style={{ ['--i' as string]: i }} />)}</span>
        <span className="st-rv__art" aria-hidden>{TONE_ART[r.tone]}</span>
        <span className="st-rv__tone">{TONE_LABEL[r.tone]}</span>
      </div>
      <div className="st-rv__body">
        <p className="st-rv__chosen"><span aria-hidden>{story.icon}</span> You chose: <b>{r.choice_label}</b></p>
        <p className="st-rv__text">{r.text}</p>
        {chips.length > 0 && (
          <ul className="st-chips" aria-label="What changed">
            {chips.map((c, i) => <li key={`${c}-${i}`} className={`st-chip st-chip--${chipTone(c)}`} style={{ animationDelay: `${260 + i * 90}ms` }}>{c}</li>)}
          </ul>
        )}
        {paid.map((p) => (
          <p key={p.days} className="st-streak-win" style={{ animationDelay: `${420 + chips.length * 90}ms` }}>
            <span aria-hidden>🔥</span> {p.days}-day streak! <b>+{naira(p.cash)}</b>
          </p>
        ))}
        {r.seed && <p className="st-seed" style={{ animationDelay: `${520 + chips.length * 90}ms` }}>Something tells you this isn’t over…</p>}
        {r.whisper && <p className="st-whisper" style={{ animationDelay: `${640 + chips.length * 90}ms` }}><span aria-hidden>💭</span> {r.whisper}</p>}
        <button type="button" className="st-go" onClick={onDone} data-testid="story-continue">Continue</button>
      </div>
    </article>
  );
}

function ChoiceButton({ c, i, busy, onPick }: { c: StoryChoice; i: number; busy: string | null; onPick: (c: StoryChoice) => void }) {
  const off = !c.affordable;
  return (
    <button type="button" className={`st-choice${off ? ' is-off' : ''}`} aria-disabled={off || busy !== null} disabled={busy !== null && busy !== c.id}
      onClick={() => onPick(c)} data-testid={`story-choice-${c.id}`} data-choice={c.id}>
      <span className="st-choice__key" aria-hidden>{String.fromCharCode(65 + i)}</span>
      <span className="st-choice__label">{busy === c.id ? '…' : c.label}</span>
      {c.cost > 0 && <span className="st-choice__cost">{off ? `Need ${naira(c.cost)}` : naira(c.cost)}</span>}
    </button>
  );
}

function StoryCard({ s, busy, onPick, nextIn }: { s: Story; busy: string | null; onPick: (s: Story, c: StoryChoice) => void; nextIn: string }) {
  const chapter = s.kind === 'chapter';
  const done = s.status === 'answered' && s.result;
  return (
    <article className={`st-card st-story${chapter ? ' is-chapter' : ''}${done ? ' is-done' : ''}`} data-testid="story-card" data-story={s.story}>
      <div className="st-story__art" aria-hidden><span>{s.icon}</span></div>
      <div className="st-story__body">
        <p className="st-eyebrow">{chapter ? 'Your story continues…' : 'Today’s story'}{s.speaker ? ` · ${s.speaker}` : ''}</p>
        <h3 className="st-story__title">{s.title}</h3>
        <p className="st-story__text">{s.body}</p>
        {done && s.result ? (
          <div className={`st-done st-done--${s.result.tone}`}>
            <p className="st-done__chosen">You chose: <b>{s.result.choice_label}</b></p>
            <p className="st-done__text">{s.result.text}</p>
            {!chapter && <p className="st-done__next">A new story arrives in {nextIn}.</p>}
          </div>
        ) : (
          <div className="st-choices" role="group" aria-label="What will you do?">
            {s.choices.map((c, i) => <ChoiceButton key={c.id} c={c} i={i} busy={busy} onPick={(ch) => onPick(s, ch)} />)}
          </div>
        )}
      </div>
    </article>
  );
}

function StreakCard({ st }: { st: StoryStreak }) {
  const top = st.steps[st.steps.length - 1]?.days ?? 14;
  const pct = Math.min(100, Math.round((st.streak / top) * 100));
  return (
    <section className="st-panel st-streak" aria-label="Reading streak">
      <div className="st-panel__head">
        <span className="st-panel__icon" aria-hidden>🔥</span>
        <div>
          <b>{st.streak > 0 ? `${st.streak}-day streak` : 'Start a streak'}</b>
          <small>{st.read_today ? 'Today is counted. Come back tomorrow.' : st.streak > 0 ? 'Read today’s story to keep it going.' : 'Read a story every day for small rewards.'}</small>
        </div>
      </div>
      <div className="st-bar" role="progressbar" aria-valuemin={0} aria-valuemax={top} aria-valuenow={Math.min(st.streak, top)}><span style={{ width: `${pct}%` }} /></div>
      <ul className="st-steps">
        {st.steps.map((s) => (
          <li key={s.days} className={`st-step${s.reached ? ' is-reached' : ''}${s.claimed ? ' is-claimed' : ''}`}>
            <span className="st-step__days">{s.days} days</span>
            <span className="st-step__cash">{s.claimed ? '✓ ' : ''}{nairaShort(s.cash)}</span>
          </li>
        ))}
      </ul>
      <small className="st-fine">A missed day starts a new streak. Best so far: {st.best} {st.best === 1 ? 'day' : 'days'}.</small>
    </section>
  );
}

function PathPanel({ path }: { path: PathCard }) {
  return (
    <section className="st-panel st-path" aria-label="Your path so far">
      <p className="st-eyebrow">Your path so far</p>
      <p className="st-path__title"><span aria-hidden>🧭</span> {path.title}</p>
      {path.notes.length > 0 && (
        <ul className="st-path__notes">{path.notes.map((n) => <li key={n}>{n}</li>)}</ul>
      )}
      <small className="st-fine">Your choices shape how Benin City sees you, and now and then a small thing comes back. Nobody shows you a score.</small>
    </section>
  );
}

export default function StoriesApp() {
  const refresh = useGame((s) => s.refresh);
  const setBadge = useMoments((s) => s.setStory);
  const [data, setData] = useState<StoryToday | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [reveal, setReveal] = useState<{ story: Story; result: StoryResult } | null>(null);
  const [, setTick] = useState(0);

  const load = () => storyToday().then((d) => { setData(d); setError(''); if (d.badge) setBadge(d.badge); }).catch((e) => setError(errorMessage(e)));
  useEffect(() => { void load(); const id = window.setInterval(() => setTick((n) => n + 1), 60_000); return () => window.clearInterval(id); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const pick = async (s: Story, c: StoryChoice) => {
    if (busy || !c.affordable) { if (!c.affordable) toast(`You need ${naira(c.cost)} for that one.`, 'bad'); return; }
    setBusy(c.id);
    try {
      const r = await storyAnswer(s.id, c.id);
      setReveal({ story: r.story, result: r.reveal });
      setBadge(r.badge);
      setData((d) => d && ({
        ...d,
        today: d.today?.map((x) => (x.id === r.story.id ? r.story : x)),
        chapters: d.chapters?.map((x) => (x.id === r.story.id ? r.story : x)),
        streak: r.streak, path: r.path, badge: r.badge,
      }));
      void refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void load();
    } finally {
      setBusy(null);
    }
  };

  const nextIn = untilNextStory();
  const chapters = useMemo(() => (data?.chapters ?? []).filter((s) => s.status === 'pending' || reveal?.story.id === s.id), [data, reveal]);
  const today = data?.today ?? [];

  return (
    <div className="phone-app__body st-app" data-testid="stories-app">
      {error && <p className="error-text">{error}</p>}
      {!data && !error && <div className="panel-skel"><span /><span /></div>}
      {data && !data.enabled && <EmptyState icon="sparkle" title="Stories are paused" body="Check back soon for the next story." />}
      {data?.enabled && (
        <>
          <header className="st-hero">
            <div>
              <p className="st-hero__date">{dayLabel(data.day)}</p>
              <h2>Today in Benin City</h2>
            </div>
            {data.streak && data.streak.streak > 0 && <span className="st-flame" aria-label={`${data.streak.streak} day streak`}><span aria-hidden>🔥</span> {data.streak.streak}</span>}
          </header>
          {chapters.map((s) => (reveal?.story.id === s.id
            ? <Reveal key={`r${s.id}`} story={s} r={reveal.result} onDone={() => setReveal(null)} />
            : <StoryCard key={s.id} s={s} busy={busy} onPick={pick} nextIn={nextIn} />))}
          {today.length === 0 && <EmptyState icon="sparkle" title="No story today" body="Nothing is happening in your corner of Benin City right now. A new story arrives tomorrow." />}
          {today.map((s) => (reveal?.story.id === s.id
            ? <Reveal key={`r${s.id}`} story={s} r={reveal.result} onDone={() => setReveal(null)} />
            : <StoryCard key={s.id} s={s} busy={busy} onPick={pick} nextIn={nextIn} />))}
          {data.streak && <StreakCard st={data.streak} />}
          {data.path && <PathPanel path={data.path} />}
        </>
      )}
    </div>
  );
}
