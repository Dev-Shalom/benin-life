import { Link } from 'react-router-dom';
import { Icon } from '../ui';
import { P } from '../lib/pidgin';
import { Logo, Skyline, BeadRow } from './Brand';

const FEATURES = [
  { icon: 'map', title: 'Waka round Benin', body: 'From Ring Road to Ugbowo, Uselu to Upper Sakponba. Take keke, ECTS bus or drop — mind Ramat Park traffic.' },
  { icon: 'cash', title: 'Hustle your way up', body: 'PoS operator, keke rider, UNIBEN student, Igun bronze apprentice, club DJ… pick your hustle.' },
  { icon: 'shield', title: 'Shine your eye', body: 'Carry too much cash for Sapele Road at night? Omo. Keep your money for bank — bank no dey rob.' },
  { icon: 'home', title: 'Build your life', body: 'Start for face-me-I-face-you for Ekenwan. Hammer am reach GRA duplex. Farm, esusu, friends, gist.' },
];

export default function Landing() {
  return (
    <div className="landing">
      <div className="landing__stage">
      <div className="landing__sky" aria-hidden>
        <span className="star" style={{ left: '12%', top: '9%' }} />
        <span className="star" style={{ left: '28%', top: '18%' }} />
        <span className="star" style={{ left: '46%', top: '6%' }} />
        <span className="star" style={{ left: '67%', top: '14%' }} />
        <span className="star" style={{ left: '84%', top: '7%' }} />
        <span className="star" style={{ left: '92%', top: '22%' }} />
      </div>
      <Skyline className="landing__skyline" />

      <header className="landing__top">
        <div className="row">
          <Logo size={40} />
          <span className="landing__wordmark">Benin Life</span>
        </div>
        <Link to="/auth?mode=signin" className="landing__login">Login</Link>
      </header>

      <main className="landing__hero">
        <span className="landing__kicker"><Icon name="pin" size={14} /> Benin City, Edo State</span>
        <h1 className="landing__title">
          Benin <span>Life</span>
        </h1>
        <p className="landing__pitch">
          Hustle, waka, chop, enjoy — <em>and shine your eye for Sapele Road.</em>
        </p>
        <p className="landing__sub">
          The city life-sim wey dey play for your phone. Build your Sim, find work, dodge agbero, make friends, buy land for GRA.
          Na your life — run am well.
        </p>
        <div className="landing__cta">
          <Link to="/auth?mode=signup" className="bl-btn bl-btn--primary bl-btn--lg">
            <Icon name="sparkle" size={20} />
            <span className="bl-btn__label">Create account — e free</span>
          </Link>
          <Link to="/auth?mode=signin" className="bl-btn bl-btn--dark bl-btn--lg">
            <span className="bl-btn__label">I get account, Login</span>
          </Link>
        </div>
        <p className="landing__age">
          <span className="age-badge">16+</span>
          {P.sixteenPlus}
        </p>
      </main>
      </div>

      <section className="landing__features">
        <BeadRow count={11} />
        <div className="landing__grid">
          {FEATURES.map((f) => (
            <article key={f.title} className="feature">
              <span className="feature__icon"><Icon name={f.icon} size={22} /></span>
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </article>
          ))}
        </div>
        <p className="landing__foot">Na game money be this — e no get real cash value. Made with love for Benin.</p>
      </section>
    </div>
  );
}
