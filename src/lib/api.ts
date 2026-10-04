import { supabase } from './supabase';

/** Error thrown by game RPCs. `message` is already player-facing Pidgin. */
export class GameError extends Error {
  code?: string;
  constructor(message: string, code?: string) {
    super(message);
    this.name = 'GameError';
    this.code = code;
  }
}

/** Call a Postgres RPC. Throws GameError with the server's Pidgin message on failure. */
export async function rpc<T = Record<string, unknown>>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    const msg = error.code === 'P0001' ? error.message : friendly(error.message);
    throw new GameError(msg, error.code);
  }
  return data as T;
}

function friendly(raw: string): string {
  if (/JWT|not logged|auth/i.test(raw)) return 'Abeg login again, your session don expire.';
  if (/fetch|network|Failed to/i.test(raw)) return 'Network don cut. Check your data and try again.';
  return 'Wahala dey somewhere. Try again small time.';
}

/** Return a Pidgin message for any thrown value. */
export function errorMessage(e: unknown): string {
  if (e instanceof GameError) return e.message;
  if (e instanceof Error) return friendly(e.message);
  return 'Wahala dey somewhere. Try again small time.';
}
