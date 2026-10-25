// Help phone app: searchable short guides grouped by topic, each with a "Show me" button that runs the matching tour
// step(s). Articles live in src/onboarding/helpArticles.ts (data). Deep links: go=help and go=help:<article id>.
import { useEffect, useMemo, useRef, useState } from 'react';
import { HELP_ARTICLES, HELP_TOPICS, articleById, searchArticles, type HelpArticle } from '../../../onboarding/helpArticles';
import { startTour, startWhatsNew } from '../../../onboarding/tourStore';
import { useUi } from '../../../state/ui';
import './HelpApp.css';

function ArticleView({ a, onBack }: { a: HelpArticle; onBack: () => void }) {
  const topic = HELP_TOPICS.find((t) => t.id === a.topic);
  return (
    <article className="help help-article">
      <button type="button" className="help-back" onClick={onBack}>&larr; All topics</button>
      <div className="help-article__topic"><span aria-hidden>{topic?.icon}</span> {topic?.label}</div>
      <h2 className="help-article__title">{a.title}</h2>
      <p className="help-article__sum">{a.summary}</p>
      {a.steps && a.steps.length > 0 && (
        <>
          <h3 className="help-h">How to</h3>
          <ol className="help-steps">{a.steps.map((s) => <li key={s}>{s}</li>)}</ol>
        </>
      )}
      {a.where && (
        <>
          <h3 className="help-h">Where to find it</h3>
          <p className="help-where">{a.where}</p>
        </>
      )}
      {a.tips && a.tips.length > 0 && (
        <>
          <h3 className="help-h">Good to know</h3>
          <ul className="help-tips">{a.tips.map((s) => <li key={s}>{s}</li>)}</ul>
        </>
      )}
      {a.tour && a.tour.length > 0 && (
        <button type="button" className="help-show" data-help-show onClick={() => startTour(a.tour)}>
          <span aria-hidden>👀</span> Show me
        </button>
      )}
    </article>
  );
}

const topicIcon = (a: HelpArticle) => HELP_TOPICS.find((t) => t.id === a.topic)?.icon ?? '📘';

/** Question filler that would otherwise match half the articles. */
const ASK_SKIP = new Set(['how', 'what', 'where', 'when', 'why', 'who', 'can', 'get', 'the', 'and', 'for', 'you', 'your', 'are', 'does', 'did', 'with', 'this', 'that', 'want', 'make', 'dey', 'wey']);

/** "Ask Benin Life": no AI backend, so score the question against title / summary / keywords. Best 3. */
function askArticles(question: string): HelpArticle[] {
  const words = question.toLowerCase().split(/[^a-z0-9₦]+/).filter((w) => w.length > 2 && !ASK_SKIP.has(w));
  if (!words.length) return [];
  const score = (a: HelpArticle) => {
    const title = a.title.toLowerCase();
    const head = title.split(/[^a-z0-9₦]+/)[0] ?? '';
    const sum = a.summary.toLowerCase();
    const kw = (a.keywords ?? '').toLowerCase();
    let n = 0;
    for (const w of words) {
      if (title.includes(w)) n += 3;
      if (head.startsWith(w)) n += 2; // "job" -> "Jobs and careers" beats "Gangs: ... group jobs"
      if (kw.includes(w)) n += 2;
      if (sum.includes(w)) n += 1;
    }
    return n > 0 ? n + 1 / title.length : 0; // ties: the shorter, more specific title first
  };
  return HELP_ARTICLES.map((a) => ({ a, n: score(a) }))
    .filter((x) => x.n > 0)
    .sort((x, y) => y.n - x.n)
    .slice(0, 3)
    .map((x) => x.a);
}

function HelpCard({ a, expanded, onToggle, onOpen }: { a: HelpArticle; expanded: boolean; onToggle: () => void; onOpen: () => void }) {
  const panel = `help-card-${a.id}`;
  return (
    <div className={`help-card${expanded ? ' is-open' : ''}`} data-article={a.id}>
      <button type="button" className="help-card__head" aria-expanded={expanded} aria-controls={panel} onClick={onToggle}>
        <span className="help-card__icon" aria-hidden>{topicIcon(a)}</span>
        <span className="help-card__main">
          <span className="help-card__t">{a.title}</span>
          <span className="help-card__s">{a.summary}</span>
        </span>
        <svg className="help-card__chev" viewBox="0 0 24 24" width="20" height="20" aria-hidden><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
      </button>
      <div className="help-card__panel" id={panel} role="region" aria-hidden={!expanded} inert={!expanded}>
        <div className="help-card__inner">
          <div className="help-card__body">
            <p className="help-card__full">{a.summary}</p>
            {a.steps && a.steps.length > 0 && <ol className="help-steps">{a.steps.slice(0, 4).map((x) => <li key={x}>{x}</li>)}</ol>}
            <div className="help-card__acts">
              <button type="button" className="help-card__more" onClick={onOpen}>Full guide</button>
              {a.tour && a.tour.length > 0 && (
                <button type="button" className="help-card__show" data-help-show onClick={() => startTour(a.tour)}><span aria-hidden>👀</span> Show me</button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// The deep link of one openPhone() call is applied once, so coming back to Help later starts at the list.
let handledNonce = -1;

export default function HelpApp() {
  const phoneApp = useUi((s) => s.phoneApp);
  const nonce = useUi((s) => s.phoneNonce);
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [asking, setAsking] = useState(false);
  const [question, setQuestion] = useState('');
  const askRef = useRef<HTMLInputElement>(null);

  // deep link: go=help:<article id> arrives as phoneApp 'help:<id>'
  useEffect(() => {
    if (nonce === handledNonce) return;
    handledNonce = nonce;
    const m = /^help:([a-z0-9-]+)$/.exec(phoneApp ?? '');
    setOpenId(m && articleById(m[1]) ? m[1] : null);
  }, [phoneApp, nonce]);

  const results = useMemo(() => searchArticles(q.trim()), [q]);
  const matches = useMemo(() => askArticles(question), [question]);
  useEffect(() => { if (asking) askRef.current?.focus(); }, [asking]);
  const open = articleById(openId);

  if (open) return <div className="phone-app__body"><ArticleView a={open} onBack={() => setOpenId(null)} /></div>;

  const searching = q.trim().length > 0;
  return (
    <div className="phone-app__body">
      <div className="help">
        <section className={`help-ask${asking ? ' is-open' : ''}`} aria-label="Ask Benin Life">
          <div className="help-ask__row">
            <span className="help-ask__spark" aria-hidden>✨</span>
            <span className="help-ask__txt">
              <span className="help-ask__t">Ask Benin Life</span>
              <span className="help-ask__s">Any question, quick answer</span>
            </span>
            <button type="button" className="help-ask__btn" aria-expanded={asking} aria-label={asking ? 'Close' : 'Ask'} onClick={() => setAsking((v) => !v)}>
              {asking ? '✕' : 'Ask'}
            </button>
          </div>
          <div className="help-ask__panel" inert={!asking}>
            <div className="help-ask__inner">
              <div className="help-ask__box">
                <input ref={askRef} type="search" value={question} onChange={(e) => setQuestion(e.target.value)}
                  placeholder="e.g. how do I get a job?" aria-label="Ask a question" enterKeyHint="search"
                  autoComplete="off" spellCheck={false} />
                {question.trim() && matches.length === 0 && <p className="help-ask__none">No match yet. Try other words, or contact us.</p>}
                {matches.map((m) => (
                  <button key={m.id} type="button" className="help-ask__hit" onClick={() => setOpenId(m.id)}>
                    <span className="help-ask__hit-i" aria-hidden>{topicIcon(m)}</span>
                    <span className="help-ask__hit-m"><b>{m.title}</b><span>{m.summary}</span></span>
                    <span aria-hidden>&rsaquo;</span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </section>
        <label className="help-search">
          <span aria-hidden>🔎</span>
          <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search: money, clubs, jobs…"
            aria-label="Search help" enterKeyHint="search" autoComplete="off" autoCapitalize="none" spellCheck={false} />
        </label>
        {!searching && (
          <div className="help-tours">
            <button type="button" className="help-tour" data-help-replay onClick={() => startTour()}><span aria-hidden>🧭</span> Replay tour</button>
            <button type="button" className="help-tour" onClick={() => startWhatsNew()}><span aria-hidden>✨</span> What&rsquo;s new</button>
          </div>
        )}
        {results.length === 0 && (
          <div className="help-empty">
            <p>No guide for &ldquo;{q.trim()}&rdquo; yet.</p>
            <button type="button" className="help-tour" onClick={() => setOpenId('contact')}><span aria-hidden>✉️</span> Ask us</button>
          </div>
        )}
        <div className="help-cards">
          {results.map((a) => (
            <HelpCard key={a.id} a={a} expanded={expanded === a.id}
              onToggle={() => setExpanded((cur) => (cur === a.id ? null : a.id))} onOpen={() => setOpenId(a.id)} />
          ))}
        </div>
      </div>
    </div>
  );
}
