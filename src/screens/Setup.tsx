import { Icon } from '../ui';
import { Logo, Skyline } from './Brand';

const STEPS = [
  { title: 'Start Supabase for your system', code: 'npx supabase start' },
  { title: 'Copy the env file', code: 'cp .env.example .env.local' },
  { title: 'Paste the API URL + anon key wey this command show', code: 'npx supabase status' },
  { title: 'Restart the dev server', code: 'npm run dev' },
];

/** Shown when VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are missing. */
export default function Setup() {
  return (
    <div className="auth-screen">
      <Skyline className="landing__skyline" />
      <div className="auth-wrap">
        <div className="auth-card setup-card">
          <div className="auth-card__brand">
            <Logo size={52} />
            <div>
              <h1>Supabase never connect</h1>
              <p className="muted">Benin Life need im backend before e fit run. No wahala — na 4 steps.</p>
            </div>
          </div>
          <div className="setup-alert">
            <Icon name="warning" size={18} />
            <span>
              <b>Copy <code>.env.example</code> to <code>.env.local</code></b> and fill <code>VITE_SUPABASE_URL</code> and{' '}
              <code>VITE_SUPABASE_ANON_KEY</code>.
            </span>
          </div>
          <ol className="setup-steps">
            {STEPS.map((s, i) => (
              <li key={s.code}>
                <span className="setup-steps__n">{i + 1}</span>
                <div>
                  <p>{s.title}</p>
                  <code className="setup-code">{s.code}</code>
                </div>
              </li>
            ))}
          </ol>
          <p className="hint">Never commit <code>.env.local</code> — e dey for .gitignore already.</p>
        </div>
      </div>
    </div>
  );
}
