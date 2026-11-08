// Page chrome for the marketing screens: the graphite and bronze look (public/mk/mk.css, docs/FRONTEND.md),
// the sticky nav with the theme toggle, and the footer. The game screens never render any of this.
import { useRef, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import '../../styles/marketing.css';
import { ThemeToggle } from './ThemeToggle';
import { useMarketingPage, useReveal, useStuckNav } from './useMk';

export function MkRoot({ children, className = '' }: { children: ReactNode; className?: string }) {
  useMarketingPage();
  const host = useRef<HTMLDivElement>(null);
  const sentinel = useRef<HTMLSpanElement>(null);
  useReveal(host);
  useStuckNav(host, sentinel);
  return (
    <div ref={host} className={`mk ${className}`.trim()}>
      <span ref={sentinel} className="mk-sentinel" aria-hidden="true" />
      <a className="mk-skip" href="#main">Skip to content</a>
      {children}
    </div>
  );
}

export function MkBrand({ beta }: { beta?: boolean }) {
  return (
    <Link to="/" className="mk-brand" aria-label="Benin Life home">
      <img src="/brand/logo-mark.svg" alt="" width="30" height="30" />
      Benin Life
      {beta && <span className="mk-beta" title="Benin Life is in beta: new features land often">Beta</span>}
    </Link>
  );
}

export interface MkLink {
  href: string;
  label: string;
  /** Plain <a> for the static pages (/about/, /faq/, /sponsor/), router link otherwise. */
  to?: string;
}

/** Sticky nav: brand, text links, theme toggle, then whatever call to action the page passes as children. */
export function MkNav({ links = [], beta, children }: { links?: MkLink[]; beta?: boolean; children?: ReactNode }) {
  return (
    <header className="mk-nav">
      <div className="mk-wrap">
        <MkBrand beta={beta} />
        <div className="mk-links">
          {links.map((l) =>
            l.to ? (
              <Link key={l.label} className="mk-text" to={l.to}>{l.label}</Link>
            ) : (
              <a key={l.label} className="mk-text" href={l.href}>{l.label}</a>
            ),
          )}
          <ThemeToggle />
          {children}
        </div>
      </div>
    </header>
  );
}

/** Footer links shared by every marketing screen. */
export function MkFooter({ note }: { note?: ReactNode }) {
  return (
    <footer className="mk-footer">
      <div className="mk-wrap">
        <span>{note ?? 'Made in Benin City by Shalom Uwagboe.'}</span>
        <nav aria-label="Footer">
          <a href="/about/">About</a>
          <a href="/faq/">FAQ</a>
          <a href="/sponsor/">Partners</a>
          <a href="https://www.tiktok.com/@beninlife_official_" target="_blank" rel="noopener">TikTok</a>
          <Link to="/terms">Terms</Link>
          <Link to="/privacy">Privacy</Link>
        </nav>
      </div>
    </footer>
  );
}
