import { Icon } from '../ui';
import { Logo } from './Brand';

const STEPS = [
  { title: 'Start Supabase on this machine', code: 'npx supabase start' },
  { title: 'Copy the env file', code: 'cp .env.example .env.local' },
  { title: 'Paste in the API URL and anon key this command prints', code: 'npx supabase status' },
  { title: 'Restart the dev server', code: 'npm run dev' },
];

/** Shown when VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are missing. */
export default function Setup() {
  return (
    <div className="center-screen">
      <div className="auth-card setup-card">
        <div className="setup-card__brand">
          <Logo size={48} />
          <div>
            <h1>Connect Supabase</h1>
            <p className="muted">Benin Life needs its backend before it can run. It takes four steps.</p>
          </div>
        </div>
        <div className="setup-alert">
          <Icon name="warning" size={18} />
          <span>
            <b>Copy <code>.env.example</code> to <code>.env.local</code></b> and fill in <code>VITE_SUPABASE_URL</code> and{' '}
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
        <p className="hint">Never commit <code>.env.local</code>. It is already in .gitignore.</p>
      </div>
    </div>
  );
}
