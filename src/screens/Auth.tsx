import { useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { authErrorPidgin, randomGreeting } from '../lib/pidgin';
import { useGame } from '../state/game';
import { Button, Icon, Tabs, toast } from '../ui';
import { Logo, Skyline } from './Brand';

type Mode = 'signup' | 'signin';

export default function Auth() {
  const [params, setParams] = useSearchParams();
  const mode: Mode = params.get('mode') === 'signin' ? 'signin' : 'signup';
  const next = params.get('next') || '/play';
  const nav = useNavigate();
  const session = useGame((s) => s.session);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  useEffect(() => {
    if (session) nav(next.startsWith('/') ? next : '/play', { replace: true });
  }, [session, next, nav]);

  const setMode = (m: string) => {
    setErr(null);
    setInfo(null);
    const p = new URLSearchParams(params);
    p.set('mode', m);
    setParams(p, { replace: true });
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setErr(null);
    setInfo(null);
    const em = email.trim();
    if (!/^\S+@\S+\.\S+$/.test(em)) return setErr('That email no look correct. Check am again.');
    if (password.length < 6) return setErr('Password too short, my guy. Make am reach 6 characters at least.');
    setBusy(true);
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({ email: em, password });
        if (error) throw error;
        if (!data.session) {
          setInfo('Account don create! Check your email make you confirm am, then come login.');
          return;
        }
        toast('Welcome to Benin! Make we create your Sim.', 'good');
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: em, password });
        if (error) throw error;
        toast(randomGreeting(), 'good');
      }
    } catch (e) {
      setErr(authErrorPidgin(e instanceof Error ? e.message : String(e)));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="auth-screen">
      <Skyline className="landing__skyline" />
      <div className="auth-wrap">
        <Link to="/" className="auth-back"><Icon name="back" size={18} /> Back</Link>
        <div className="auth-card">
          <div className="auth-card__brand">
            <Logo size={52} />
            <div>
              <h1>{mode === 'signup' ? 'Join Benin Life' : 'Welcome back'}</h1>
              <p className="muted">{mode === 'signup' ? 'Create account, create your Sim, start your hustle.' : 'Your Sim dey wait you for Benin.'}</p>
            </div>
          </div>
          <Tabs
            className="auth-tabs"
            value={mode}
            onChange={setMode}
            tabs={[
              { id: 'signup', label: 'New account' },
              { id: 'signin', label: 'Login' },
            ]}
          />
          <form className="stack" onSubmit={submit} noValidate>
            <div className="field">
              <label htmlFor="auth-email">Email</label>
              <input id="auth-email" className="input" type="email" inputMode="email" autoComplete="email"
                placeholder="you@example.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </div>
            <div className="field">
              <label htmlFor="auth-pass">Password</label>
              <div className="input-wrap">
                <input id="auth-pass" className="input" type={show ? 'text' : 'password'}
                  autoComplete={mode === 'signup' ? 'new-password' : 'current-password'}
                  placeholder={mode === 'signup' ? 'At least 6 characters' : 'Your password'}
                  value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} />
                <button type="button" className="input-wrap__btn" onClick={() => setShow((s) => !s)}>
                  {show ? 'Hide' : 'Show'}
                </button>
              </div>
            </div>
            {err && <p className="error-text" role="alert">{err}</p>}
            {info && <p className="auth-info" role="status">{info}</p>}
            <Button type="submit" size="lg" block loading={busy}>
              {mode === 'signup' ? 'Create my account' : 'Enter Benin'}
            </Button>
          </form>
          <p className="auth-switch">
            {mode === 'signup' ? (
              <>You don get account before? <button type="button" onClick={() => setMode('signin')}>Login</button></>
            ) : (
              <>New for here? <button type="button" onClick={() => setMode('signup')}>Create account</button></>
            )}
          </p>
          <p className="auth-age"><span className="age-badge">16+</span> By entering, you agree say you don reach 16 and you know say na game.</p>
        </div>
      </div>
    </div>
  );
}
