import { lazy, Suspense, useEffect, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { Icon } from '../ui';
import type { SceneType } from '../lib/types';
import { Logo, Skyline, BeadRow, EctsBus, Keke, GoSlow } from './Brand';
import type { LandingArtProps } from './LandingArt';

// Scenes + avatars are heavy: they load only when a card scrolls near the screen.
const LandingArt = lazy(() => import('./LandingArt'));

const SIGN_UP = '/auth?mode=signup';
const SIGN_IN = '/auth?mode=signin';
const CTA_START = 'Start your life';
const CTA_SIGNIN = 'I don get account';

const PLACES: { scene: SceneType; night: boolean; name: string; line: string }[] = [
  { scene: 'palace', night: false, name: "Oba's Palace", line: 'Greet well, dress decent. Respect dey here first.' },
  { scene: 'market', night: false, name: 'Oba Market', line: 'Buy, sell, price am. Market woman no dey dull.' },
  { scene: 'motorpark', night: false, name: 'Ramat Park', line: 'Catch ECTS bus here. If go-slow hold you, na Benin.' },
  { scene: 'club', night: true, name: 'Bronze Lounge', line: 'Friday night for Sapele Road. DJ don ready.' },
  { scene: 'police', night: true, name: 'Police Command HQ', line: 'Dem rob you? Come report. Police is your friend.' },
];

const LADDER = ['Intern', 'Junior Dev', 'Mid-level Dev', 'Senior Dev', 'Tech Lead', 'Eng. Manager', 'CTO'];

type Toss = 'idle' | 'flipping' | 'lapo' | 'nepo';

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
    <div
      ref={ref}
      className={`landing__art ${className ?? ''}`}
      role={label ? 'img' : undefined}
      aria-label={label || undefined}
    >
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
  const [ref, seen] = useSeen<HTMLElement>('0px 0px -12% 0px');
  return (
    <section ref={ref} className={`${className ?? ''} lp-reveal${seen ? ' is-in' : ''}`} aria-labelledby={labelledBy}>
      {children}
    </section>
  );
}

/** Pauses the road traffic while the hero is off-screen (saves battery on low-end phones). */
function useHeroVisible() {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(([e]) => setVisible(e.isIntersecting));
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return [ref, visible] as const;
}

function CoinToss({ result, face, spins, onToss }: {
  result: Toss; face: 'lapo' | 'nepo'; spins: number; onToss: () => void;
}) {
  const flipping = result === 'flipping';
  // Rotation only ever grows, so a CSS transition retargets smoothly and lands on the right face.
  const turn = spins * 1440 + (face === 'nepo' ? 180 : 0);
  const message =
    result === 'nepo'
      ? 'Omo! Papa don set you up. Nepo baby!'
      : result === 'lapo'
        ? 'LAPO baby. Na hustle go carry you, and e go sweet.'
        : flipping
          ? 'Coin dey for air...'
          : 'Toss am, see which one you for be.';
  return (
    <div className="landing__toss">
      <span className={`coin coin--${result}`} style={{ ['--turn' as string]: `${turn}deg` }} aria-hidden>
        <span className="coin__face coin__face--lapo">LAPO</span>
        <span className="coin__face coin__face--nepo">NEPO</span>
      </span>
      <div className="landing__toss-copy">
        <p aria-live="polite">{message}</p>
        <button type="button" className="bl-btn bl-btn--gold bl-btn--sm" onClick={onToss} disabled={flipping}>
          <Icon name="dice" size={16} />
          <span className="bl-btn__label">{result === 'idle' ? 'Toss am' : 'Toss again'}</span>
        </button>
      </div>
    </div>
  );
}

export default function Landing() {
  const [heroRef, heroVisible] = useHeroVisible();
  const [toss, setToss] = useState<Toss>('idle');
  const [face, setFace] = useState<'lapo' | 'nepo'>('lapo');
  const [spins, setSpins] = useState(0);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  function doToss() {
    // Same odds as the real roll at sign-up (origin.nepo_pct, default 10%).
    const nepo = Math.random() < 0.1;
    setSpins((s) => s + 1);
    setFace(nepo ? 'nepo' : 'lapo');
    setToss('flipping');
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToss(nepo ? 'nepo' : 'lapo'), 900);
  }

  return (
    <div className="landing">
      <div className={`landing__stage${heroVisible ? '' : ' is-paused'}`} ref={heroRef}>
        <div className="landing__sky" aria-hidden>
          <span className="star" style={{ left: '12%', top: '9%' }} />
          <span className="star" style={{ left: '28%', top: '18%' }} />
          <span className="star" style={{ left: '46%', top: '6%' }} />
          <span className="star" style={{ left: '67%', top: '14%' }} />
          <span className="star" style={{ left: '84%', top: '7%' }} />
          <span className="star" style={{ left: '92%', top: '22%' }} />
        </div>
        <div className="landing__city" aria-hidden>
          <Skyline className="landing__skyline" vehicles={false} anchor="right" />
          <div className="landing__road">
            <EctsBus className="veh veh--bus" />
            <span className="veh veh--keke">
              <Keke />
            </span>
          </div>
        </div>

        <header className="landing__top">
          <Link to="/" className="landing__brand" aria-label="Benin Life home">
            <Logo size={38} />
            <span className="landing__wordmark">Benin Life</span>
          </Link>
          <Link to={SIGN_IN} className="landing__login">{CTA_SIGNIN}</Link>
        </header>

        <main className="landing__hero">
          <div className="landing__copy">
          <span className="landing__kicker">
            <Icon name="pin" size={14} /> Benin City, Edo State
          </span>
          <h1 className="landing__title">
            Benin <span>Life</span>
          </h1>
          <p className="landing__pitch">
            Hustle, waka, chop, enjoy. The free Benin City life-sim for your phone.{' '}
            <em>Just shine your eye for Sapele Road.</em>
          </p>
          <div className="landing__cta">
            <Link to={SIGN_UP} className="bl-btn bl-btn--primary bl-btn--lg">
              <Icon name="sparkle" size={20} />
              <span className="bl-btn__label">{CTA_START}</span>
            </Link>
            <Link to={SIGN_IN} className="bl-btn bl-btn--dark bl-btn--lg">
              <span className="bl-btn__label">{CTA_SIGNIN}</span>
            </Link>
          </div>
          </div>
          {/* Desktop only (display:none on phones, so the lazy art never downloads there). */}
          <div className="landing__showcase" aria-hidden>
            <ArtFrame art={{ scene: 'buka', night: false }} className="postcard postcard--back" />
            <ArtFrame art={{ scene: 'campus', night: true }} className="postcard postcard--front" />
          </div>
        </main>
      </div>

      <div className="landing__body">
        <Reveal className="landing__places" labelledBy="lp-places">
          <div className="landing__wrap">
            <h2 id="lp-places" className="landing__h2">Tap any place. Your life start there.</h2>
            <p className="landing__lede">
              30+ real Benin spots for one illustrated map, from Ring Road to Ugbowo, Sapele Road to Ikpoba Hill. Day
              turn night, and the city change with am.
            </p>
          </div>
          <ul className="landing__strip" tabIndex={0} aria-label="Places for the map">
            {PLACES.map((p) => (
              <li key={p.scene} className="place">
                <ArtFrame art={{ scene: p.scene, night: p.night }} label={`${p.name} illustration`} />
                <h3 className="place__name">
                  <Icon name={p.night ? 'moon' : 'sun'} size={16} />
                  {p.name}
                </h3>
                <p className="place__line">{p.line}</p>
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal className="landing__origin landing__wrap" labelledBy="lp-origin">
          <h2 id="lp-origin" className="landing__h2">LAPO baby or Nepo baby?</h2>
          <p className="landing__lede">
            You no choose your family. The moment you create your Sim, the coin go decide where you start.
          </p>
          <CoinToss result={toss} face={face} spins={spins} onToss={doToss} />
          <div className="landing__duel">
            <article className={`tier tier--lapo${toss === 'lapo' ? ' is-picked' : ''}`}>
              <ArtFrame art={{ scene: 'home_face_me', night: false, sim: 'lapo' }} label="LAPO baby outside face-me-I-face-you" />
              <div className="tier__body">
                <p className="tier__odds">9 out of 10 people</p>
                <h3 className="tier__name">LAPO baby</h3>
                <ul className="tier__perks">
                  <li><Icon name="cash" size={18} /> ₦5,000 for pocket</li>
                  <li><Icon name="home" size={18} /> One room for face-me-I-face-you, Ekenwan</li>
                  <li><Icon name="bolt" size={18} /> Small loan easy to collect. Na hustle go carry you.</li>
                </ul>
              </div>
            </article>
            <article className={`tier tier--nepo${toss === 'nepo' ? ' is-picked' : ''}`}>
              <ArtFrame art={{ scene: 'home_duplex', night: false, sim: 'nepo' }} label="Nepo baby in front of a GRA duplex" />
              <div className="tier__body">
                <p className="tier__odds">1 out of 10 people</p>
                <h3 className="tier__name">Nepo baby</h3>
                <ul className="tier__perks">
                  <li><Icon name="bank" size={18} /> ₦50,000 cash plus ₦500,000 for bank</li>
                  <li><Icon name="home" size={18} /> GRA duplex, tokunbo car and laptop</li>
                  <li><Icon name="crown" size={18} /> Papa dey send allowance every day</li>
                </ul>
              </div>
            </article>
          </div>
        </Reveal>

        <Reveal className="landing__life landing__wrap" labelledBy="lp-life">
          <h2 id="lp-life" className="landing__h2">Wetin you go do for Benin?</h2>
          <div className="bento">
            <article className="bento__cell bento__cell--work">
              <div className="bento__text">
                <span className="bento__icon"><Icon name="laptop" size={22} /></span>
                <h3>Start as intern. Retire as CTO.</h3>
                <p>
                  Tech, health, police, banking: every work get ladder. Do your shift, gather XP, collect promotion,
                  collect better pay.
                </p>
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
              <span className="bento__icon"><Icon name="bus" size={22} /></span>
              <h3>Waka, keke, ECTS bus or drop</h3>
              <p>Keke no fit enter major road. Ramat Park go-slow no dey smile. Plan your movement.</p>
              <GoSlow className="bento__goslow" />
            </article>
            <article className="bento__cell bento__cell--hustle">
              <span className="bento__icon"><Icon name="bag" size={22} /></span>
              <h3>Hustle and market</h3>
              <p>PoS stand, farm for Iguobazuwa, buy for shop or sell to other players. Money must move.</p>
            </article>
            <article className="bento__cell bento__cell--eye">
              <span className="bento__icon"><Icon name="shield" size={22} /></span>
              <h3>Shine your eye</h3>
              <p>Players fit rob you for street, but police and CCTV dey watch. Keep your money for bank.</p>
            </article>
            <article className="bento__cell bento__cell--gist">
              <span className="bento__icon"><Icon name="chat" size={22} /></span>
              <h3>Chop, sleep, gist</h3>
              <p>Your Sim go hungry, tire and need enjoyment. Gist with people wey dey the same spot.</p>
            </article>
          </div>
        </Reveal>

        <Reveal className="landing__final" labelledBy="lp-final">
          <div className="landing__wrap landing__final-inner">
            <BeadRow count={11} />
            <h2 id="lp-final" className="landing__h2 landing__h2--big">Your Benin life dey wait.</h2>
            <p className="landing__lede">E free. No app to download. Create account, build your Sim, enter town.</p>
            <div className="landing__cta landing__cta--center">
              <Link to={SIGN_UP} className="bl-btn bl-btn--primary bl-btn--lg">
                <Icon name="sparkle" size={20} />
                <span className="bl-btn__label">{CTA_START}</span>
              </Link>
              <Link to={SIGN_IN} className="bl-btn bl-btn--dark bl-btn--lg">
                <span className="bl-btn__label">{CTA_SIGNIN}</span>
              </Link>
            </div>
            <p className="landing__age">
              <span className="age-badge">16+</span>
              16+ only. Na game: fake money, real wahala. Nothing for here be real crime advice.
            </p>
          </div>
        </Reveal>

        <footer className="landing__footer">
          <span className="landing__brand">
            <Logo size={28} />
            <span className="landing__wordmark">Benin Life</span>
          </span>
          <p>Na game money be this. E no get real cash value.</p>
          <p>Made with love for Benin City.</p>
        </footer>
      </div>
    </div>
  );
}
