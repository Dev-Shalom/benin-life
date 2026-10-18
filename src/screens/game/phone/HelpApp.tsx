// Help phone app: searchable short guides grouped by topic, each with a "Show me" button that runs the matching tour
// step(s). Articles live in src/onboarding/helpArticles.ts (data). Deep links: go=help and go=help:<article id>.
import { useEffect, useMemo, useState } from 'react';
import { HELP_TOPICS, articleById, searchArticles, type HelpArticle } from '../../../onboarding/helpArticles';
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

// The deep link of one openPhone() call is applied once, so coming back to Help later starts at the list.
let handledNonce = -1;

export default function HelpApp() {
  const phoneApp = useUi((s) => s.phoneApp);
  const nonce = useUi((s) => s.phoneNonce);
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);

  // deep link: go=help:<article id> arrives as phoneApp 'help:<id>'
  useEffect(() => {
    if (nonce === handledNonce) return;
    handledNonce = nonce;
    const m = /^help:([a-z0-9-]+)$/.exec(phoneApp ?? '');
    setOpenId(m && articleById(m[1]) ? m[1] : null);
  }, [phoneApp, nonce]);

  const results = useMemo(() => searchArticles(q.trim()), [q]);
  const open = articleById(openId);

  if (open) return <div className="phone-app__body"><ArticleView a={open} onBack={() => setOpenId(null)} /></div>;

  const searching = q.trim().length > 0;
  return (
    <div className="phone-app__body">
      <div className="help">
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
        {HELP_TOPICS.map((t) => {
          const list = results.filter((a) => a.topic === t.id);
          if (!list.length) return null;
          return (
            <section key={t.id} className="help-group" aria-label={t.label}>
              <h3 className="help-group__h"><span aria-hidden>{t.icon}</span> {t.label}</h3>
              <div className="help-list">
                {list.map((a) => (
                  <button key={a.id} type="button" className="help-row" data-article={a.id} onClick={() => setOpenId(a.id)}>
                    <span className="help-row__main">
                      <span className="help-row__t">{a.title}</span>
                      <span className="help-row__s">{a.summary}</span>
                    </span>
                    <span className="help-row__chev" aria-hidden>&rsaquo;</span>
                  </button>
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </div>
  );
}
