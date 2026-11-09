// Sign up / Log in / Forgot password / Set a new password.
// Marketing look (docs/FRONTEND.md): a picture panel beside the form on desktop, the form alone on phones.
// Labels above inputs, helper or error text below. All the sign-in logic below is unchanged.
import { useEffect, useId, useState, type FormEvent, type ReactNode } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { passwordProblem } from '../lib/passwordPolicy';
import { storedReferral } from '../lib/referral';
import { supabase } from '../lib/supabase';
import { authErrorMessage, randomGreeting } from '../lib/pidgin';
import { captchaOption, turnstileEnabled } from '../lib/turnstile';
import { useGame } from '../state/game';
import { toast } from '../ui';
import { Turnstile } from '../ui/Turnstile';
import { Ph } from './mk/Ph';
import { MkRoot, MkBrand } from './mk/Shell';
import { ThemeToggle } from './mk/ThemeToggle';

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
    <div className="au-field">
      <label htmlFor={id}>{label}</label>
      {children}
      {error ? (
        <p className="au-msg au-msg--error" id={`${id}-msg`} role="alert">{error}</p>
      ) : helper ? (
        <p className="au-msg" id={`${id}-msg`}>{helper}</p>
      ) : null}
    </div>
  );
}

function PasswordInput({ id, value, onChange, autoComplete, invalid, minLength }: {
  id: string; value: string; onChange: (v: string) => void; autoComplete: string; invalid?: boolean; minLength?: number;
}) {
  const [show, setShow] = useState(false);
  return (
    <div className="au-pw">
      <input
        id={id}
        className="au-input"
        type={show ? 'text' : 'password'}
        autoComplete={autoComplete}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-invalid={invalid || undefined}
        aria-describedby={`${id}-msg`}
        required
        minLength={minLength}
      />
      <button
        type="button"
        className="au-pw__btn"
        onClick={() => setShow((s) => !s)}
        aria-label={show ? 'Hide password' : 'Show password'}
        aria-pressed={show}
      >
        <Ph name={show ? 'eyeSlash' : 'eye'} />
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
  // Optional Turnstile CAPTCHA (only when VITE_TURNSTILE_SITE_KEY is set): one single-use token per attempt
  const [captcha, setCaptcha] = useState<string | null>(null);
  const [captchaReset, setCaptchaReset] = useState(0);
  // If the safety check cannot load or errors, do not block the player here; the server decides.
  const [captchaFailed, setCaptchaFailed] = useState(false);

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
    if (mode === 'signin' && password.length < 1) return fail('password', 'Type your password.');
    if (mode === 'signup' || mode === 'reset') {
      const problem = passwordProblem(password);
      if (problem) return fail('password', problem);
    }
    if (mode === 'signup' && !adult) return fail('adult', 'Please confirm you are 18 or older to create an account.');
    if (turnstileEnabled && !captchaFailed && mode !== 'reset' && !captcha) return fail('form', 'Please wait for the safety check to finish, then try again.');
    setBusy(true);
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          email: em,
          password,
          options: { ...captchaOption(captcha), data: { age_confirmed: true, age_confirmed_at: new Date().toISOString(), ...(storedReferral() ? { referral_code: storedReferral() } : {}) } },
        });
        if (error) throw error;
        if (!data.session) {
          setInfo('Account created! Check your email to confirm it, then come back and log in.');
          return;
        }
        // No toast here: it would cover the creator's top bar, which already greets the player.
      } else if (mode === 'signin') {
        const { error } = await supabase.auth.signInWithPassword({ email: em, password, options: captchaOption(captcha) });
        if (error) throw error;
        toast(randomGreeting(), 'good');
      } else if (mode === 'forgot') {
        const { error } = await supabase.auth.resetPasswordForEmail(em, {
          redirectTo: `${window.location.origin}/auth?mode=reset`,
          ...captchaOption(captcha),
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
      if (turnstileEnabled && mode !== 'reset') { setCaptcha(null); setCaptchaReset((n) => n + 1); }
    }
  };

  const emailField = (helper?: string) => (
    <Field id={`${uid}-email`} label="Email" helper={helper} error={err?.field === 'email' ? err.msg : null}>
      <input
        id={`${uid}-email`}
        className="au-input"
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
        invalid={err?.field === 'password'} minLength={mode === 'signup' || mode === 'reset' ? 8 : undefined} />
    </Field>
  );

  const formError = err?.field === 'form' ? <p className="au-alert au-alert--error" role="alert">{err.msg}</p> : null;
  const formInfo = info ? <p className="au-alert au-alert--info" role="status">{info}</p> : null;

  let body: ReactNode;
  if (mode === 'signup' || mode === 'signin') {
    const signup = mode === 'signup';
    body = (
      <>
        <div className="au-tabs" role="tablist" aria-label="Account">
          {(['signup', 'signin'] as const).map((m) => (
            <button key={m} type="button" role="tab" aria-selected={mode === m} className={mode === m ? 'is-on' : ''} onClick={() => setMode(m)}>
              {m === 'signup' ? 'Create account' : 'Log in'}
            </button>
          ))}
        </div>
        <form className="au-form" onSubmit={submit} noValidate>
          {emailField(signup ? "We'll use it to log you in and to reset your password." : undefined)}
          {passwordField('Password', signup ? 'At least 8 characters, and not only numbers.' : undefined, signup ? 'new-password' : 'current-password')}
          {signup ? (
            <div className="au-field">
              <label className={`au-check${err?.field === 'adult' ? ' is-invalid' : ''}`}>
                <input type="checkbox" checked={adult} onChange={(e) => setAdult(e.target.checked)}
                  aria-describedby={err?.field === 'adult' ? `${uid}-adult-msg` : undefined} />
                <span className="au-check__box" aria-hidden><Ph name="check" /></span>
                <span>
                  I'm <b>18 or older</b> and I agree to the{' '}
                  <a href="/terms" target="_blank" rel="noopener" className="au-link-inline">Terms</a> and{' '}
                  <a href="/privacy" target="_blank" rel="noopener" className="au-link-inline">Privacy Policy</a>.
                </span>
              </label>
              {err?.field === 'adult' && <p className="au-msg au-msg--error" id={`${uid}-adult-msg`} role="alert">{err.msg}</p>}
            </div>
          ) : (
            <button type="button" className="au-link" onClick={() => setMode('forgot')}>Forgot password?</button>
          )}
          <Turnstile onToken={setCaptcha} onFailed={() => setCaptchaFailed(true)} resetKey={captchaReset} />
          {formError}
          {formInfo}
          <button type="submit" className="mk-btn mk-btn--primary mk-btn--block" aria-busy={busy || undefined} disabled={busy}>
            {busy ? 'One moment...' : signup ? 'Create account' : 'Log in'}
          </button>
          <p className="au-note">
            {signup ? 'Free to play. Your Sim lives in the same Benin City as every other player.' : 'Welcome back to Benin City.'}
          </p>
        </form>
      </>
    );
  } else if (mode === 'forgot') {
    body = (
      <form className="au-form" onSubmit={submit} noValidate>
        <div className="au-head">
          <h2>Reset your password</h2>
          <p>Enter the email you signed up with. We'll send you a link to choose a new password.</p>
        </div>
        {emailField()}
        <Turnstile onToken={setCaptcha} onFailed={() => setCaptchaFailed(true)} resetKey={captchaReset} />
        {formError}
        {formInfo}
        <button type="submit" className="mk-btn mk-btn--primary mk-btn--block" aria-busy={busy || undefined} disabled={busy}>{busy ? 'One moment...' : 'Send reset link'}</button>
        <button type="button" className="au-link au-link--center" onClick={() => setMode('signin')}>
          <Ph name="arrowLeft" /> Back to log in
        </button>
      </form>
    );
  } else {
    const linkDead = authReady && !session;
    body = (
      <form className="au-form" onSubmit={submit} noValidate>
        <div className="au-head">
          <h2>Choose a new password</h2>
          <p>{linkDead ? 'This reset link has expired or was already used. Request a new one.' : 'Pick something you will remember. At least 8 characters, and not only numbers.'}</p>
        </div>
        {linkDead ? (
          <button type="button" className="mk-btn mk-btn--primary mk-btn--block" onClick={() => setMode('forgot')}>Get a new link</button>
        ) : (
          <>
            {passwordField('New password', 'At least 8 characters, and not only numbers.', 'new-password')}
            {formError}
            <button type="submit" className="mk-btn mk-btn--primary mk-btn--block" aria-busy={busy || undefined} disabled={busy || !authReady}>{busy ? 'One moment...' : 'Save password'}</button>
          </>
        )}
      </form>
    );
  }

  return (
    <MkRoot className="au">
      <header className="mk-nav">
        <div className="mk-wrap">
          <MkBrand />
          <div className="mk-links">
            <Link to="/" className="mk-text au-backlink"><Ph name="arrowLeft" /> Back</Link>
            <ThemeToggle />
          </div>
        </div>
      </header>
      <main id="main" className="au-grid mk-wrap">
        <aside className="au-side" aria-hidden="true">
          <img src="/mk/hero-1300.webp" srcSet="/mk/hero-700.webp 700w, /mk/hero-1300.webp 1300w" sizes="560px" width={1300} height={813} alt="" decoding="async" />
          <p className="mk-display">A life-sim set in the real Benin City.</p>
        </aside>
        <section className="au-card" key={mode === 'signup' || mode === 'signin' ? 'account' : mode} aria-label="Account">
          <h1 className="mk-display au-title">
            {mode === 'signup' ? 'Create your account' : mode === 'signin' ? 'Welcome back' : mode === 'forgot' ? 'Reset your password' : 'Choose a new password'}
          </h1>
          <p className="au-sub">A life-sim set in the real Benin City. <span className="au-age" aria-label="18 plus">18+</span></p>
          {body}
        </section>
      </main>
    </MkRoot>
  );
}
