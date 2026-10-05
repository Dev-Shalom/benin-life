// Sign up / Log in / Forgot password / Set a new password.
// One white card on the sky: logo + tagline above, a segmented switch, filled pill inputs with helper text.
import { useEffect, useId, useState, type FormEvent, type ReactNode } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { authErrorMessage, randomGreeting } from '../lib/pidgin';
import { useGame } from '../state/game';
import { Button, Icon, Segmented, toast } from '../ui';
import { Logo } from './Brand';

type Mode = 'signup' | 'signin' | 'forgot' | 'reset';

const EMAIL_RE = /^\S+@\S+\.\S+$/;

function readMode(raw: string | null): Mode {
  return raw === 'signin' || raw === 'forgot' || raw === 'reset' ? raw : 'signup';
}

/** Label above, helper text below, error replaces the helper. */
function Field({ id, label, helper, error, children }: {
  id: string; label: string; helper?: ReactNode; error?: string | null; children: ReactNode;
}) {
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {children}
      {error ? (
        <p className="field__msg field__msg--error" id={`${id}-msg`} role="alert">{error}</p>
      ) : helper ? (
        <p className="field__msg hint" id={`${id}-msg`}>{helper}</p>
      ) : null}
    </div>
  );
}

function PasswordInput({ id, value, onChange, autoComplete, invalid }: {
  id: string; value: string; onChange: (v: string) => void; autoComplete: string; invalid?: boolean;
}) {
  const [show, setShow] = useState(false);
  return (
    <div className="input-wrap">
      <input
        id={id}
        className="input"
        type={show ? 'text' : 'password'}
        autoComplete={autoComplete}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-invalid={invalid || undefined}
        aria-describedby={`${id}-msg`}
        required
        minLength={6}
      />
      <button
        type="button"
        className="input-wrap__btn"
        onClick={() => setShow((s) => !s)}
        aria-label={show ? 'Hide password' : 'Show password'}
        aria-pressed={show}
      >
        <Icon name={show ? 'eyeOff' : 'eye'} size={20} />
      </button>
    </div>
  );
}

export default function Auth() {
  const [params, setParams] = useSearchParams();
  const mode = readMode(params.get('mode'));
  const next = params.get('next') || '/play';
  const nav = useNavigate();
  const session = useGame((s) => s.session);
  const authReady = useGame((s) => s.authReady);
  const uid = useId();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [adult, setAdult] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<{ field: 'email' | 'password' | 'adult' | 'form'; msg: string } | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  // Logged in already? Go play. (Not while choosing a new password: the recovery link signs you in.)
  useEffect(() => {
    if (session && mode !== 'reset') nav(next.startsWith('/') ? next : '/play', { replace: true });
  }, [session, mode, next, nav]);

  const setMode = (m: Mode) => {
    setErr(null);
    setInfo(null);
    const p = new URLSearchParams(params);
    p.set('mode', m);
    setParams(p, { replace: true });
  };

  const fail = (field: 'email' | 'password' | 'adult' | 'form', msg: string) => setErr({ field, msg });

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setErr(null);
    setInfo(null);
    const em = email.trim();
    if (mode !== 'reset' && !EMAIL_RE.test(em)) return fail('email', "That email doesn't look right. Check it and try again.");
    if (mode !== 'forgot' && password.length < 6) return fail('password', 'Your password needs at least 6 characters.');
    if (mode === 'signup' && !adult) return fail('adult', 'Please confirm you are 18 or older to create an account.');
    setBusy(true);
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          email: em,
          password,
          options: { data: { age_confirmed: true, age_confirmed_at: new Date().toISOString() } },
        });
        if (error) throw error;
        if (!data.session) {
          setInfo('Account created! Check your email to confirm it, then come back and log in.');
          return;
        }
        toast("Welcome to Benin City! Let's create your Sim.", 'good');
      } else if (mode === 'signin') {
        const { error } = await supabase.auth.signInWithPassword({ email: em, password });
        if (error) throw error;
        toast(randomGreeting(), 'good');
      } else if (mode === 'forgot') {
        const { error } = await supabase.auth.resetPasswordForEmail(em, {
          redirectTo: `${window.location.origin}/auth?mode=reset`,
        });
        if (error) throw error;
        setInfo(`If there is an account for ${em}, a reset link is on its way. Check your inbox and spam folder.`);
      } else {
        const { error } = await supabase.auth.updateUser({ password });
        if (error) throw error;
        toast('Password updated. Welcome back!', 'good');
        nav('/play', { replace: true });
      }
    } catch (e) {
      fail('form', authErrorMessage(e instanceof Error ? e.message : String(e)));
    } finally {
      setBusy(false);
    }
  };

  const emailField = (helper?: string) => (
    <Field id={`${uid}-email`} label="Email" helper={helper} error={err?.field === 'email' ? err.msg : null}>
      <input
        id={`${uid}-email`}
        className="input"
        type="email"
        inputMode="email"
        autoComplete="email"
        autoCapitalize="off"
        spellCheck={false}
        placeholder="you@email.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        aria-invalid={err?.field === 'email' || undefined}
        aria-describedby={`${uid}-email-msg`}
        required
      />
    </Field>
  );

  const passwordField = (label: string, helper: string | undefined, autoComplete: string) => (
    <Field id={`${uid}-pass`} label={label} helper={helper} error={err?.field === 'password' ? err.msg : null}>
      <PasswordInput id={`${uid}-pass`} value={password} onChange={setPassword} autoComplete={autoComplete}
        invalid={err?.field === 'password'} />
    </Field>
  );

  const formError = err?.field === 'form' ? <p className="auth-alert auth-alert--error" role="alert">{err.msg}</p> : null;
  const formInfo = info ? <p className="auth-alert auth-alert--info" role="status">{info}</p> : null;

  let body: ReactNode;
  if (mode === 'signup' || mode === 'signin') {
    const signup = mode === 'signup';
    body = (
      <>
        <Segmented
          label="Account"
          value={mode}
          onChange={(m) => setMode(m)}
          options={[
            { id: 'signup', label: 'Create account' },
            { id: 'signin', label: 'Log in' },
          ]}
        />
        <form className="auth-form" onSubmit={submit} noValidate>
          {emailField(signup ? "We'll use it to log you in and to reset your password." : undefined)}
          {passwordField('Password', signup ? 'At least 6 characters.' : undefined, signup ? 'new-password' : 'current-password')}
          {signup ? (
            <div className="field">
              <label className={`auth-check${err?.field === 'adult' ? ' is-invalid' : ''}`}>
                <input type="checkbox" checked={adult} onChange={(e) => setAdult(e.target.checked)}
                  aria-describedby={err?.field === 'adult' ? `${uid}-adult-msg` : undefined} />
                <span className="auth-check__box" aria-hidden><Icon name="check" size={14} stroke={3} /></span>
                <span>
                  I'm <b>18 or older</b> and I agree to the <b>Terms</b> and <b>Privacy Policy</b>.
                </span>
              </label>
              {err?.field === 'adult' && <p className="field__msg field__msg--error" id={`${uid}-adult-msg`} role="alert">{err.msg}</p>}
            </div>
          ) : (
            <button type="button" className="auth-link" onClick={() => setMode('forgot')}>Forgot password?</button>
          )}
          {formError}
          {formInfo}
          <Button type="submit" size="lg" block loading={busy}>
            {signup ? 'Create account' : 'Log in'}
          </Button>
          <p className="auth-note">
            {signup ? 'Free to play. Your Sim lives in the same Benin City as every other player.' : 'Welcome back to Benin City.'}
          </p>
        </form>
      </>
    );
  } else if (mode === 'forgot') {
    body = (
      <form className="auth-form" onSubmit={submit} noValidate>
        <div className="auth-card__head">
          <h2>Reset your password</h2>
          <p>Enter the email you signed up with. We'll send you a link to choose a new password.</p>
        </div>
        {emailField()}
        {formError}
        {formInfo}
        <Button type="submit" size="lg" block loading={busy}>Send reset link</Button>
        <button type="button" className="auth-link auth-link--center" onClick={() => setMode('signin')}>
          <Icon name="back" size={16} /> Back to log in
        </button>
      </form>
    );
  } else {
    const linkDead = authReady && !session;
    body = (
      <form className="auth-form" onSubmit={submit} noValidate>
        <div className="auth-card__head">
          <h2>Choose a new password</h2>
          <p>{linkDead ? 'This reset link has expired or was already used. Request a new one.' : 'Pick something you will remember. At least 6 characters.'}</p>
        </div>
        {linkDead ? (
          <Button size="lg" block onClick={() => setMode('forgot')}>Get a new link</Button>
        ) : (
          <>
            {passwordField('New password', 'At least 6 characters.', 'new-password')}
            {formError}
            <Button type="submit" size="lg" block loading={busy} disabled={!authReady}>Save password</Button>
          </>
        )}
      </form>
    );
  }

  return (
    <div className="auth">
      <Link to="/" className="auth__back"><Icon name="back" size={16} /> Back</Link>
      <div className="auth__inner">
        <header className="auth__brand">
          <Logo size={60} />
          <h1 className="auth__title">
            Benin Life <span className="age-badge" aria-label="18 plus">18+</span>
          </h1>
          <p className="auth__tagline">A life-sim set in the real Benin City.</p>
        </header>
        <main className="auth-card" key={mode === 'signup' || mode === 'signin' ? 'account' : mode}>
          {body}
        </main>
      </div>
    </div>
  );
}
