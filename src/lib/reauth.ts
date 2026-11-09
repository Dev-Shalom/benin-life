// "Please confirm with your password" (docs/SECURITY.md). Dangerous actions (a new life) need a sign-in from the last few minutes.
// Signing in again with the password gives the session a fresh token; the server (life_restart) checks the token's age.
import { supabase } from './supabase';
import { authErrorMessage } from './pidgin';
import { captchaOption } from './turnstile';
import { useGame } from '../state/game';

/** Sign in again with the current account's email and the typed password. Throws an Error with a player-facing message. */
export async function reauthWithPassword(password: string, captchaToken: string | null = null): Promise<void> {
  const email = useGame.getState().session?.user.email;
  if (!email) throw new Error('Please log in again, then try once more.');
  if (!password) throw new Error('Type your password to confirm.');
  const { error } = await supabase.auth.signInWithPassword({ email, password, options: captchaOption(captchaToken) });
  if (error) {
    const m = error.message.toLowerCase();
    if (m.includes('invalid login')) throw new Error('That password is not right. Try again.');
    throw new Error(authErrorMessage(error.message));
  }
}
