import { supabase } from './supabase';

/** Error thrown by game RPCs. `message` is already player-facing Pidgin. */
export class GameError extends Error {
  code?: string;
  /** Machine-readable hint from the server, e.g. 'no_profile', 'no_home', 'insufficient_funds'. */
  hint?: string;
  constructor(message: string, code?: string, hint?: string) {
    super(message);
    this.name = 'GameError';
    this.code = code;
    this.hint = hint;
  }
}

/** Call a Postgres RPC. Throws GameError with the server's Pidgin message on failure. */
export async function rpc<T = Record<string, unknown>>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    const msg = error.code === 'P0001' ? error.message : friendly(error.message);
    throw new GameError(msg, error.code, error.code === 'P0001' ? error.hint || undefined : undefined);
  }
  return data as T;
}

function friendly(raw: string): string {
  if (/JWT|not logged|auth/i.test(raw)) return 'Your session has expired. Please log in again.';
  if (/fetch|network|Failed to/i.test(raw)) return 'Network problem. Check your connection and try again.';
  return 'Something went wrong. Please try again.';
}

/** Return a Pidgin message for any thrown value. */
export function errorMessage(e: unknown): string {
  if (e instanceof GameError) return e.message;
  if (e instanceof Error) return friendly(e.message);
  return 'Something went wrong. Please try again.';
}
