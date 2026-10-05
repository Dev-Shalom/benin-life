// Marketing landing page (English). It sells the game; it must not look like the game has started.
// No origin odds or starting amounts here: the birth lottery is a surprise at sign-up.
import { lazy, Suspense, useEffect, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import type { SceneType } from '../lib/types';
import { GoSlow, Logo } from './Brand';
import type { LandingArtProps } from './LandingArt';

// Scenes + avatars are heavy: they load only when a frame scrolls near the screen.
const LandingArt = lazy(() => import('./LandingArt'));

const SIGN_UP = '/auth?mode=signup';
const LOG_IN = '/auth?mode=signin';
const CTA_START = 'Start playing';
const CTA_LOGIN = 'Log in';

const PLACES: { scene: SceneType; night: boolean; name: string; line: string }[] = [
  { scene: 'palace', night: false, name: "Oba's Palace", line: 'The heart of the old city. Dress well and greet with respect.' },
  { scene: 'market', night: false, name: 'Oba Market', line: 'Buy, sell and haggle with the sharpest traders in town.' },
  { scene: 'motorpark', night: false, name: 'Ramat Park', line: 'Catch the ECTS bus here, if the go-slow lets you.' },
  { scene: 'campus', night: false, name: 'UNIBEN, Ugbowo', line: 'Lectures by day, hostel gist by night.' },
  { scene: 'club', night: true, name: 'Bronze Lounge', line: 'Friday night on Sapele Road. The DJ is ready.' },
];

const LADDER = ['Intern', 'Junior Dev', 'Mid-level Dev', 'Senior Dev', 'Tech Lead', 'Eng. Manager', 'CTO'];

const STEPS = [
  { title: 'Create your account', body: 'Free, with just an email. Nothing to download.' },
  { title: 'Design your Sim', body: 'Pick a look, a style and a name that feels like you.' },
  { title: 'Step into Benin', body: 'Find your feet, find work and make the city yours.' },
];

/** True once the element has come within `margin` of the viewport (then stays true). */
function useSeen<T extends Element>(margin = '0px') {
  const ref = useRef<T>(null);
  // Very old browsers without IntersectionObserver just show everything straight away.
  const [seen, setSeen] = useState(() => typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const el = ref.current;
    if (!el || seen) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setSeen(true);
          io.disconnect();
        }
      },
      { rootMargin: margin },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [margin, seen]);
  return [ref, seen] as const;
}

/** Fixed-ratio frame; mounts the lazy art only when near the viewport (no layout shift). */
function ArtFrame({ art, className, label }: { art: LandingArtProps; className?: string; label?: string }) {
  const [ref, seen] = useSeen<HTMLDivElement>('300px');
  return (
    <div ref={ref} className={`lp-art ${className ?? ''}`} role={label ? 'img' : undefined} aria-label={label || undefined}>
      {seen && (
        <Suspense fallback={null}>
          <LandingArt {...art} />
        </Suspense>
      )}
    </div>
  );
}

/** Section that rises in once, when it enters the viewport. */
function Reveal({ className, children, labelledBy }: { className?: string; children: ReactNode; labelledBy: string }) {
  const [ref, seen] = useSeen<HTMLElement>('0px 0px -10% 0px');
  return (
    <section ref={ref} className={`lp-section ${className ?? ''} lp-reveal${seen ? ' is-in' : ''}`} aria-labelledby={labelledBy}>
      {children}
    </section>
  );
}

function Ctas({ center }: { center?: boolean }) {
  return (
    <div className={`lp-cta${center ? ' lp-cta--center' : ''}`}>
      <Link to={SIGN_UP} className="bl-btn bl-btn--primary bl-btn--lg">
        <span className="bl-btn__label">{CTA_START}</span>
      </Link>
      <Link to={LOG_IN} className="bl-btn bl-btn--ghost bl-btn--lg">
        <span className="bl-btn__label">{CTA_LOGIN}</span>
      </Link>
    </div>
  );
}

function Emoji({ children }: { children: string }) {
  return (
    <span className="lp-emoji emoji" aria-hidden>
      {children}
    </span>
  );
}

export default function Landing() {
  return (
    <div className="lp">
      <header className="lp-nav">
        <Link to="/" className="lp-brand" aria-label="Benin Life home">
          <Logo size={36} />
          <span className="lp-brand__name">Benin Life</span>
        </Link>
        <nav className="lp-nav__actions" aria-label="Account">
          <Link to={LOG_IN} className="lp-nav__login">{CTA_LOGIN}</Link>
          <Link to={SIGN_UP} className="bl-btn bl-btn--primary bl-btn--sm lp-nav__start">
            <span className="bl-btn__label">{CTA_START}</span>
          </Link>
        </nav>
      </header>

      <main>
        <section className="lp-hero" aria-labelledby="lp-title">
          <div className="lp-hero__copy">
            <p className="lp-eyebrow">
              <span className="emoji" aria-hidden>📍</span> Benin City, Edo State
            </p>
            <h1 id="lp-title" className="lp-hero__title">
              Live a whole new life in <span>Benin City.</span>
            </h1>
            <p className="lp-hero__sub">
              Create your Sim, find work, make friends and get around the real city, alongside other real players.
            </p>
            <Ctas />
          </div>
          <div className="lp-hero__visual">
            <ArtFrame art={{ scene: 'campus', night: false }} className="lp-postcard lp-postcard--back" />
            <ArtFrame art={{ scene: 'market', night: false, sim: 'lapo' }} className="lp-postcard lp-postcard--front"
              label="A Benin Life Sim at Oba Market" />
          </div>
        </section>

        <Reveal className="lp-life" labelledBy="lp-life">
          <div className="lp-wrap">
            <h2 id="lp-life" className="lp-h2">Everything a real life needs.</h2>
            <p className="lp-lede">Work, rest, hustle and get around a city you can actually recognise.</p>
            <div className="bento">
              <article className="bento__cell bento__cell--work">
                <div>
                  <Emoji>💼</Emoji>
                  <h3>Start as an intern. Retire as the boss.</h3>
                  <p>Tech, health, banking, the police and more. Every job has a ladder, and every shift moves you up.</p>
                </div>
                <ol className="ladder" aria-label="Tech career ladder">
                  {LADDER.map((rung, i) => (
                    <li key={rung} className="ladder__rung" style={{ ['--i' as string]: i }}>
                      {rung}
                    </li>
                  ))}
                </ol>
              </article>
              <article className="bento__cell bento__cell--travel">
                <Emoji>🛺</Emoji>
                <h3>Get around the real city</h3>
                <p>Walk, take a keke or the ECTS bus, or book a drop. Just plan around the Ramat Park go-slow.</p>
                <GoSlow className="bento__goslow" />
              </article>
              <article className="bento__cell bento__cell--hustle">
                <Emoji>🧺</Emoji>
                <h3>Hustle on the side</h3>
                <p>Run a PoS stand, farm in Iguobazuwa or trade with other players at the market.</p>
              </article>
              <article className="bento__cell bento__cell--live">
                <Emoji>🍲</Emoji>
                <h3>Eat, sleep, enjoy</h3>
                <p>Your Sim gets hungry, tired and bored. Look after them and everything goes better.</p>
              </article>
              <article className="bento__cell bento__cell--night">
                <Emoji>🌙</Emoji>
                <h3>Stay sharp after dark</h3>
                <p>Some streets get risky at night. Keep your money in the bank and get home early.</p>
              </article>
            </div>
          </div>
        </Reveal>

        <Reveal className="lp-places" labelledBy="lp-places">
          <div className="lp-wrap">
            <h2 id="lp-places" className="lp-h2">Real places, from Ring Road to Ugbowo.</h2>
            <p className="lp-lede">Benin City's landmarks, markets and night spots, on one map that turns from day to night.</p>
          </div>
          <ul className="lp-strip" tabIndex={0} aria-label="Places on the map">
            {PLACES.map((p) => (
              <li key={p.scene} className="place">
                <ArtFrame art={{ scene: p.scene, night: p.night }} label={`${p.name} illustration`} />
                <h3 className="place__name">{p.name}</h3>
                <p className="place__line">{p.line}</p>
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal className="lp-origin" labelledBy="lp-origin">
          <div className="lp-wrap lp-origin__grid">
            <div className="lp-origin__copy">
              <h2 id="lp-origin" className="lp-h2">Born into a different life.</h2>
              <p className="lp-lede">
                Every player starts somewhere different. Some start in one room and hustle their way up. Some start
                with Dad's connections and a house in GRA. You find out the moment your Sim is born.
              </p>
            </div>
            <div className="lp-origin__cards">
              <article className="origin-card">
                <ArtFrame art={{ scene: 'home_face_me', night: false, sim: 'lapo' }} label="A LAPO baby outside a face-me-I-face-you compound" />
                <div className="origin-card__body">
                  <h3>LAPO baby</h3>
                  <p>Self-made. Start small, learn fast and build it all yourself.</p>
                </div>
              </article>
              <article className="origin-card">
                <ArtFrame art={{ scene: 'home_duplex', night: false, sim: 'nepo' }} label="A Nepo baby in front of a GRA duplex" />
                <div className="origin-card__body">
                  <h3>Nepo baby</h3>
                  <p>Born connected. Dad opens doors, but the city still tests you.</p>
                </div>
              </article>
            </div>
          </div>
        </Reveal>

        <Reveal className="lp-how" labelledBy="lp-how">
          <div className="lp-wrap">
            <h2 id="lp-how" className="lp-h2">Up and running in a minute.</h2>
            <ol className="how">
              {STEPS.map((s, i) => (
                <li key={s.title} className="how__step">
                  <span className="how__n" aria-hidden>{i + 1}</span>
                  <div>
                    <h3>{s.title}</h3>
                    <p>{s.body}</p>
                  </div>
                </li>
              ))}
            </ol>
          </div>
        </Reveal>

        <Reveal className="lp-final" labelledBy="lp-final">
          <div className="lp-wrap">
            <div className="lp-final__card">
              <Logo size={56} />
              <h2 id="lp-final" className="lp-h2 lp-h2--center">Your Benin life is waiting.</h2>
              <p className="lp-lede lp-lede--center">Free to play in your browser, on any phone.</p>
              <Ctas center />
              <p className="lp-age">
                <span className="age-badge">18+</span>
                <span>For players 18 and over. Benin Life is a game: the money is fake and nothing in it is real-world advice.</span>
              </p>
            </div>
          </div>
        </Reveal>
      </main>

      <footer className="lp-footer">
        <span className="lp-brand">
          <Logo size={26} />
          <span className="lp-brand__name">Benin Life</span>
        </span>
        <p>Game money only. It has no real cash value.</p>
        <p>Made with love for Benin City.</p>
      </footer>
    </div>
  );
}
