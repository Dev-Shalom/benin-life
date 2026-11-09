// Optional Cloudflare Turnstile CAPTCHA (docs/SECURITY.md). Only active when VITE_TURNSTILE_SITE_KEY is set at build time;
// without it nothing loads and sign-up / sign-in behave exactly as before. The token is passed to Supabase Auth as
// options.captchaToken (the secret key and the on/off switch live in the Supabase dashboard).

export const TURNSTILE_SITE_KEY: string = String(import.meta.env.VITE_TURNSTILE_SITE_KEY ?? '').trim();
export const turnstileEnabled = TURNSTILE_SITE_KEY.length > 0;

export interface TurnstileApi {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  reset: (id?: string) => void;
  remove: (id?: string) => void;
}

declare global {
  interface Window { turnstile?: TurnstileApi }
}

const SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
let loading: Promise<TurnstileApi> | null = null;

/** Load the Turnstile script once, only when somebody actually needs the widget. */
export function loadTurnstile(): Promise<TurnstileApi> {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (loading) return loading;
  loading = new Promise<TurnstileApi>((resolve, reject) => {
    const s = document.createElement('script');
    s.src = SRC;
    s.async = true;
    s.defer = true;
    s.onload = () => (window.turnstile ? resolve(window.turnstile) : reject(new Error('turnstile missing')));
    s.onerror = () => { loading = null; reject(new Error('turnstile failed to load')); };
    document.head.appendChild(s);
  });
  return loading;
}

/** The auth option to spread into supabase.auth calls: {} when there is no token. */
export const captchaOption = (token: string | null): { captchaToken?: string } => (token ? { captchaToken: token } : {});
