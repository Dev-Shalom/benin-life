// Terms of Service (/terms) and Privacy Policy (/privacy) — public pages, plain English, NDPR-aware.
// Same light look as the auth pages. Keep the contact email and the 48 h chat retention in sync with docs/CHAT.md.
import type { ReactNode } from 'react';
import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { Icon } from '../ui';
import { Logo } from './Brand';

const CONTACT = 'dev.shalom1@gmail.com';
const UPDATED = '6 October 2026';

function Mail() {
  return <a href={`mailto:${CONTACT}`}>{CONTACT}</a>;
}

function LegalPage({ title, children }: { title: string; children: ReactNode }) {
  useEffect(() => {
    const prev = document.title;
    document.title = `${title} · Benin Life`;
    window.scrollTo(0, 0);
    return () => { document.title = prev; };
  }, [title]);
  return (
    <div className="auth legal">
      <Link to="/" className="auth__back"><Icon name="back" size={16} /> Back</Link>
      <div className="legal__inner">
        <header className="legal__brand">
          <Logo size={44} />
          <div>
            <p className="legal__eyebrow">Benin Life <span className="beta-badge">Beta</span></p>
            <h1 className="legal__title">{title}</h1>
            <p className="legal__updated">Last updated {UPDATED}</p>
          </div>
        </header>
        <main className="auth-card legal__card">{children}</main>
        <nav className="legal__nav" aria-label="Legal">
          <Link to="/terms">Terms of Service</Link>
          <span aria-hidden>·</span>
          <Link to="/privacy">Privacy Policy</Link>
          <span aria-hidden>·</span>
          <Mail />
        </nav>
      </div>
    </div>
  );
}

export function Terms() {
  return (
    <LegalPage title="Terms of Service">
      <p className="legal__lead">
        Benin Life is a free browser game that is still in <b>beta</b>. By creating an account or playing, you agree to these terms.
        If you don't agree, please don't use the game.
      </p>

      <h2>1. Who can play</h2>
      <p>You must be <b>18 years or older</b>. The game has adult themes (nightlife, betting with game money, crime and police).
        If we learn an account belongs to someone under 18, we will close it.</p>

      <h2>2. Game money is not real money</h2>
      <ul>
        <li>The naira (₦), items, houses, cars and anything else in the game are <b>virtual</b>. They have <b>no cash value</b>.</li>
        <li>You <b>cannot withdraw</b>, sell, cash out or exchange game money or items for real money, goods or services.</li>
        <li>Nothing in the game is financial, legal, medical or other real-world advice.</li>
        <li>Buying or selling accounts, game money or items for real money is not allowed.</li>
      </ul>

      <h2>3. Your account</h2>
      <ul>
        <li>Keep your password safe. You are responsible for what happens on your account.</li>
        <li>One person, one Sim. Don't use extra accounts to farm money or get around a ban.</li>
        <li>You can ask us to delete your account at any time (see the Privacy Policy).</li>
      </ul>

      <h2>4. Play fair and be decent</h2>
      <p>Don't cheat, use bots or scripts, exploit bugs, or attack the service. In chat, don't harass, threaten, scam or share
        hate speech, sexual content involving minors, or other people's personal details. Don't share your own phone number,
        address or bank details either.</p>
      <p>We may hide messages, mute, reset progress, or suspend or close accounts that break these rules.</p>

      <h2>5. Beta: things change</h2>
      <p>The game is being built in the open. Features, prices and balances change, bugs happen, and progress may sometimes be
        reset or lost. The game is provided "as is", without any warranty. As far as the law allows, we are not liable for lost
        progress or any indirect loss from using the game.</p>

      <h2>6. Real places and names</h2>
      <p>Benin Life is set in the real Benin City and mentions real places and some real brand names to feel familiar. The game is
        not endorsed by, sponsored by or connected to any of them. Characters and events in the game are fictional.</p>

      <h2>7. Changes to these terms</h2>
      <p>We may update these terms. We'll change the date at the top and, for big changes, tell players in the game.
        If you keep playing after a change, the new terms apply.</p>

      <h2>8. Law and contact</h2>
      <p>These terms are governed by the laws of the Federal Republic of Nigeria. Questions? Email <Mail />.</p>
    </LegalPage>
  );
}

export function Privacy() {
  return (
    <LegalPage title="Privacy Policy">
      <p className="legal__lead">
        This explains what Benin Life collects, why, how long we keep it and how to delete it. We follow the Nigeria Data
        Protection Regulation (NDPR) and the Nigeria Data Protection Act 2023. We don't sell your data and we don't show ads.
      </p>

      <h2>1. What we store</h2>
      <ul>
        <li><b>Account:</b> your email address and a password (stored only as a secure hash by our login provider).</li>
        <li><b>Your Sim:</b> username, look, origin, money, home, job, items and the rest of your game progress.</li>
        <li><b>Activity:</b> when you were last online and a log of in-game actions and money movements (for the game and to stop cheating).</li>
        <li><b>Chat messages:</b> what you post in place chats. Messages (and any reports about them) are <b>deleted after
          48 hours</b>.</li>
        <li><b>Technical data:</b> our hosting providers keep standard server logs (such as IP address and browser type) for security.</li>
      </ul>
      <p>We don't collect your real name, phone number, location or payment details.</p>

      <h2>2. Why we use it</h2>
      <ul>
        <li>To run your account and save your game (this is the service you asked for).</li>
        <li>To keep the game safe and fair: moderation, stopping spam, cheating and alt-account farming.</li>
        <li>To email you only about your account (for example, a password reset).</li>
      </ul>

      <h2>3. How long we keep it</h2>
      <p>Account and game data are kept while your account exists. Chat messages are deleted after 48 hours.
        When you delete your account, your account and game data are removed within 30 days, except small records we must keep
        for security or by law.</p>

      <h2>4. Delete your account or get your data</h2>
      <p>Email <Mail /> from the address you signed up with and ask us to delete your account, or to send you a copy of
        your data, or to correct it. We'll reply within 30 days. You can also complain to the Nigeria Data Protection Commission.</p>

      <h2>5. Cookies and local storage</h2>
      <p>We don't use advertising or tracking cookies. The game uses your browser's local storage to keep you logged in and to
        remember your settings (sound, music, mute, lite map). Clearing your browser data logs you out and resets those settings.</p>

      <h2>6. Who else handles your data</h2>
      <ul>
        <li><b>Supabase</b> — database, login and live chat (stores your account and game data).</li>
        <li><b>Vercel</b> — hosts the website.</li>
      </ul>
      <p>These providers may store data outside Nigeria, with safeguards in their own data-protection terms.
        We share data with authorities only when the law requires it.</p>

      <h2>7. Age</h2>
      <p>Benin Life is for adults 18 and over. We don't knowingly collect data from anyone under 18; if we find such an account,
        we delete it.</p>

      <h2>8. Changes</h2>
      <p>If this policy changes, we'll update the date at the top and tell players in the game about big changes.</p>

      <h2>9. Contact</h2>
      <p>Questions about your data: <Mail />.</p>
    </LegalPage>
  );
}
