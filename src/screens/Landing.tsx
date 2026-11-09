// Player-facing landing page (English), the "/" route when signed out. It sells the game; it must not look like the
// game has started. No origin odds or starting amounts here: the birth lottery is a surprise at sign-up.
// Look: the graphite and bronze marketing kit (public/mk/mk.css, docs/FRONTEND.md), dark and light with a toggle.
// Every picture is a real screenshot of the 3D city (public/sponsor/img, public/mk).
import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Accordion } from './mk/Accordion';
import { Ph } from './mk/Ph';
import { MkFooter, MkNav, MkRoot } from './mk/Shell';

const SIGN_UP = '/auth?mode=signup';
const LOG_IN = '/auth?mode=signin';
const CTA_START = 'Start playing';
const CTA_LOGIN = 'Log in';
const TIKTOK = 'https://www.tiktok.com/@beninlife_official_';

const STORY = [
  { title: "Walk King's Square", body: 'Step out of your house and walk the real streets, from the National Museum to Igun Street.', img: '/sponsor/img/palace.webp', alt: "The National Museum on King's Square in Benin Life" },
  { title: 'Shop at Oba Market', body: 'Stalls, sellers and a Market Day every Wednesday that brings everyone out.', img: '/sponsor/img/market.webp', alt: 'Sellers at their stalls in Oba Market' },
  { title: 'Drive the real roads', body: 'Ugbowo-Lagos Road, Sapele Road and Ring Road, with traffic, go-slow and ECTS buses.', img: '/sponsor/img/drive.webp', alt: 'Driving down a Benin road with traffic and a yellow ECTS bus' },
  { title: 'Go out at night', body: 'Clubs, bukas and owambes after dark, with street lamps and lit windows.', img: '/sponsor/img/night.webp', alt: 'A buka lit up at night in Benin Life' },
] as const;

const START = [
  { icon: 'envelopeSimple', title: 'Create your account', body: 'Free, with just an email. Nothing to download.' },
  { icon: 'userCircle', title: 'Design your Sim', body: 'Pick a look, a style and a name that feels like you.' },
  { icon: 'mapPin', title: 'Step into Benin', body: 'Find your feet, find work and make the city yours.' },
] as const;

const QUESTIONS = [
  { q: 'Is Benin Life free?', a: 'Yes. Benin Life is free to play. There is nothing to download.' },
  { q: 'How do I play?', a: 'Open playbeninlife.app in your phone or computer browser, sign up and create your character. It works on any modern browser.' },
  { q: 'Do I need to download an app?', a: 'No. Benin Life runs in your browser. You can add it to your phone home screen from the browser menu.' },
  { q: 'Who can play?', a: 'Players must be 18 or older.' },
];

function Ctas() {
  return (
    <div className="lp-ctas">
      <Link to={SIGN_UP} className="mk-btn mk-btn--primary">
        {CTA_START}
        <Ph name="arrowRight" className="arrow" />
      </Link>
      <Link to={LOG_IN} className="mk-btn mk-btn--ghost">{CTA_LOGIN}</Link>
    </div>
  );
}

/** The step in the middle of the screen chooses the picture (observer, not a scroll listener). */
function Story() {
  const [cur, setCur] = useState(0);
  const refs = useRef<(HTMLDivElement | null)[]>([]);
  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver(
      (entries) => {
        for (const en of entries) if (en.isIntersecting) setCur(Number((en.target as HTMLElement).dataset.step));
      },
      { rootMargin: '-45% 0px -45% 0px' },
    );
    refs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, []);
  return (
    <section className="lp-story" aria-labelledby="lp-story-h">
      <div className="mk-wrap">
        <h2 id="lp-story-h" className="mk-display mk-rise">A real city, not a generic map.</h2>
        <div className="lp-story__grid">
          <div className="lp-steps">
            {STORY.map((s, i) => (
              <div key={s.title} ref={(el) => { refs.current[i] = el; }} data-step={i} className={`lp-step${cur === i ? ' on' : ''}`}>
                <h3>{s.title}</h3>
                <p>{s.body}</p>
                <img src={s.img} width={1400} height={788} loading="lazy" decoding="async" alt={s.alt} />
              </div>
            ))}
          </div>
          <div className="lp-stage" aria-hidden="true">
            <div className="lp-stage__frame">
              {STORY.map((s, i) => (
                <img key={s.img} className={cur === i ? 'on' : ''} src={s.img} width={1400} height={788} loading={i === 0 ? 'eager' : 'lazy'} decoding="async" alt="" />
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

export default function Landing() {
  return (
    <MkRoot className="lp">
      <MkNav beta links={[{ href: '#life', label: 'What you can do' }, { href: '/faq/', label: 'FAQ' }]}>
        <Link to={LOG_IN} className="mk-text lp-login">{CTA_LOGIN}</Link>
        <Link to={SIGN_UP} className="mk-btn mk-btn--primary mk-btn--sm">{CTA_START}</Link>
      </MkNav>

      <main id="main">
        <section className="lp-hero" data-hero aria-labelledby="lp-title">
          <div className="mk-wrap lp-hero__grid">
            <div className="lp-hero__copy">
              <h1 id="lp-title" className="mk-display mk-rise" style={{ ['--i' as string]: 0 }}>Live a whole new life in Benin City.</h1>
              <p className="mk-lede mk-rise" style={{ ['--i' as string]: 1 }}>
                Walk the real streets, drive the real roads and build a life next to thousands of other players.
              </p>
              <div className="mk-rise" style={{ ['--i' as string]: 2 }}><Ctas /></div>
            </div>
            <div className="lp-hero__media">
              <figure className="lp-hero__main mk-reveal-media">
                <img
                  src="/mk/hero-1300.webp"
                  srcSet="/mk/hero-700.webp 700w, /mk/hero-1300.webp 1300w"
                  sizes="(min-width: 960px) 580px, calc(100vw - 40px)"
                  width={1300}
                  height={813}
                  fetchPriority="high"
                  decoding="async"
                  alt="Aerial view of Benin City in Benin Life, with King's Square in the middle and the river beside it"
                />
              </figure>
              <figure className="lp-hero__inset mk-rise" style={{ ['--i' as string]: 4 }}>
                <img src="/sponsor/img/market.webp" width={1400} height={788} decoding="async" alt="Players at their stalls in Oba Market" />
              </figure>
            </div>
          </div>
        </section>

        <section className="lp-numbers" aria-labelledby="lp-n-h">
          <div className="mk-wrap">
            <h2 id="lp-n-h" className="mk-display mk-rise">A busy city is already waiting.</h2>
            <div className="lp-num-grid">
              <div className="lp-num mk-rise" style={{ ['--i' as string]: 0 }}><strong data-count="9600" data-suffix="+">9,600+</strong><span>players signed up in the last month, mostly from Benin and Edo</span></div>
              <div className="lp-num mk-rise" style={{ ['--i' as string]: 1 }}><strong data-count="1000" data-suffix="+">1,000+</strong><span>players in the game on a busy day</span></div>
              <div className="lp-num mk-rise" style={{ ['--i' as string]: 2 }}><strong><span className="ngn">N</span>0</strong><span>to play. It opens in any phone browser, no download</span></div>
              <div className="lp-num mk-rise" style={{ ['--i' as string]: 3 }}><strong>18+</strong><span>Benin Life is for players 18 and over</span></div>
            </div>
          </div>
        </section>

        <Story />

        <section className="lp-life" id="life" aria-labelledby="lp-life-h">
          <div className="mk-wrap">
            <p className="mk-eyebrow mk-rise">What you can do</p>
            <h2 id="lp-life-h" className="mk-display mk-rise" style={{ ['--i' as string]: 1 }}>Everything a real life needs.</h2>
            <p className="mk-lede mk-rise" style={{ ['--i' as string]: 2 }}>Work, rest, hustle and get around a city you can actually recognise.</p>
            <div className="lp-bento">
              <article className="lp-cell lp-cell--media lp-b-work mk-rise">
                <img src="/sponsor/img/igun.webp" width={1400} height={788} loading="lazy" decoding="async" alt="Igun Street with bronze work outside the door" />
                <div className="lp-cell__copy">
                  <h3>Work up the ladder or open your own business</h3>
                  <p>Start as an intern and climb, or open a shop of your own. Every shift and every sale moves you forward.</p>
                </div>
              </article>
              <article className="lp-cell lp-cell--tint lp-b-family mk-rise" style={{ ['--i' as string]: 1 }}>
                <span className="lp-cell__icon"><Ph name="usersThree" /></span>
                <div className="lp-cell__copy">
                  <h3>Start a family</h3>
                  <p>Marry, raise children and send them to school and university.</p>
                </div>
              </article>
              <article className="lp-cell lp-cell--media lp-b-club mk-rise" style={{ ['--i' as string]: 2 }}>
                <img src="/sponsor/img/night.webp" width={1400} height={788} loading="lazy" decoding="async" alt="" />
                <div className="lp-cell__copy">
                  <h3>Join a club</h3>
                  <p>Friday night on Sapele Road. Bring your friends.</p>
                </div>
              </article>
              <article className="lp-cell lp-cell--tint lp-b-vote mk-rise">
                <span className="lp-cell__icon"><Ph name="gavel" /></span>
                <div className="lp-cell__copy">
                  <h3>Vote, run and go to court</h3>
                  <p>Stand for Councillor, Chairman or Governor in the Benin Votes election. Settle a dispute before a judge.</p>
                </div>
              </article>
              <article className="lp-cell lp-cell--tint lp-b-gist mk-rise" style={{ ['--i' as string]: 1 }}>
                <span className="lp-cell__icon"><Ph name="chatCircleText" /></span>
                <div className="lp-cell__copy">
                  <h3>Gist with real players</h3>
                  <p>Post gists, join group chats and send money on Benin Gist, the in-game social app.</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="lp-born" aria-labelledby="lp-born-h">
          <div className="mk-wrap">
            <h2 id="lp-born-h" className="mk-display mk-rise">Born into a different life.</h2>
            <p className="mk-lede mk-rise" style={{ ['--i' as string]: 1 }}>
              Every player starts somewhere different. Some start in one room and hustle their way up. Some start with
              Dad's connections and a house in GRA. You find out the moment your Sim is born.
            </p>
            <div className="lp-born__cards">
              <article className="lp-sim mk-rise">
                <img src="/art/sim-lapo.webp" width={240} height={480} loading="lazy" decoding="async" alt="A self-made Sim in Benin Life" />
                <div>
                  <h3>Self-made</h3>
                  <p>Start small, learn fast and build it all yourself.</p>
                </div>
              </article>
              <article className="lp-sim mk-rise" style={{ ['--i' as string]: 1 }}>
                <img src="/art/sim-nepo.webp" width={240} height={480} loading="lazy" decoding="async" alt="A well-connected Sim in Benin Life" />
                <div>
                  <h3>Born connected</h3>
                  <p>Dad opens doors, but the city still tests you.</p>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="lp-start" aria-labelledby="lp-start-h">
          <div className="mk-wrap lp-start__grid">
            <div>
              <p className="mk-eyebrow mk-rise">How it starts</p>
              <h2 id="lp-start-h" className="mk-display mk-rise" style={{ ['--i' as string]: 1 }}>Up and running in a minute.</h2>
              <p className="mk-lede mk-rise" style={{ ['--i' as string]: 2 }}>It opens in your browser, so there is no download and no app store. Add it to your home screen for one-tap play.</p>
            </div>
            <ol className="lp-start__list">
              {START.map((s, i) => (
                <li key={s.title} className="mk-rise" style={{ ['--i' as string]: i }}>
                  <span className="lp-start__icon"><Ph name={s.icon} /></span>
                  <div>
                    <h3>{s.title}</h3>
                    <p>{s.body}</p>
                  </div>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="lp-social" aria-labelledby="lp-social-h">
          <div className="mk-wrap">
            <div className="lp-social__card mk-rise">
              <span className="lp-social__icon"><Ph name="tiktokLogo" /></span>
              <div>
                <h2 id="lp-social-h" className="mk-display">See the city before you play.</h2>
                <p>Clips and updates from Benin Life are on TikTok.</p>
              </div>
              <a className="mk-btn mk-btn--ghost" href={TIKTOK} target="_blank" rel="noopener">
                Follow on TikTok
                <Ph name="arrowUpRight" className="arrow" />
              </a>
            </div>
          </div>
        </section>

        <section className="lp-faq" aria-labelledby="lp-faq-h">
          <div className="mk-wrap">
            <h2 id="lp-faq-h" className="mk-display mk-rise">Quick answers.</h2>
            <div className="mk-rise" style={{ ['--i' as string]: 1 }}><Accordion items={QUESTIONS} /></div>
            <p className="lp-faq__more mk-rise">More in the <a href="/faq/">full FAQ</a>.</p>
          </div>
        </section>

        <section className="lp-final" aria-labelledby="lp-final-h">
          <div className="mk-wrap">
            <h2 id="lp-final-h" className="mk-display mk-rise">Your Benin life is waiting.</h2>
            <p className="mk-lede mk-rise" style={{ ['--i' as string]: 1 }}>Free to play in your browser, on any phone.</p>
            <div className="mk-rise" style={{ ['--i' as string]: 2 }}><Ctas /></div>
            <p className="lp-final__age mk-rise" style={{ ['--i' as string]: 3 }}>
              For players 18 and over. Benin Life is a game: the money is fake and nothing in it is real-world advice.
            </p>
          </div>
        </section>
      </main>

      <MkFooter note="Made in Benin City by Shalom Uwagboe. Game money only, it has no real cash value." />
    </MkRoot>
  );
}
