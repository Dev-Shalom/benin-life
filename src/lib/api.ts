import { supabase } from './supabase';
import { noteReceipt } from '../state/receipts';
import { netFailed, netOk } from '../state/net';
import { POKE_RPC, pokePush } from './pushPoke';

/** Error thrown by game RPCs. `message` is already player-facing Pidgin. */
export class GameError extends Error {
  code?: string;
  /** Machine-readable hint from the server, e.g. 'no_profile', 'no_home', 'insufficient_funds'. */
  hint?: string;
  /** HTTP status (0 = the request never reached the server). */
  status?: number;
  constructor(message: string, code?: string, hint?: string, status?: number) {
    super(message);
    this.name = 'GameError';
    this.code = code;
    this.hint = hint;
    this.status = status;
  }
}

// S1 scaling: read-only RPCs (safe to repeat) are deduped while in flight and retried on network
// errors / 429 / 5xx. Writes are retried ONLY when the server certainly refused them before running
// (429 Too Many Requests, 503 Service Unavailable), so a transfer or purchase can never run twice.
const READ_RPC = new RegExp(
  '^(get_|players_|leaderboard_|world_counts$|money_drops_live$|place_people$|place_interior$|shop_list$|club_prices$|jobs_catalog$|travel_quote$|house_options$|' +
    'food_menu$|events_on_today$|club_music_for$|creator_catalog$|wardrobe_state$|storyline_current$|gem_hunt_status$|daily_reward_status$|' +
    'challenge_status$|push_state$|market_(info|quote|browse|mine)$|bank_info$|bank_history$|bank_recipient$|chat_recent$|chat_history$|chat_blocked$|police_cases_list$|garage_home$|' +
    'billboard_list$|billboard_my_ads$|company_(status|rankings|discover|public)$|real_biz_(form|mine|map|get)$|feedback_mine$|house_room_state$|friends_overview$|lounge_status$|love_(overview|candidates)$|kids_status$|moments_pending$|friend_join_check$|social_(friends|friend_requests|house_invites|house_info|friend_status|' +
    'message_history|search_players|streak)$|gist_(summary|feed|post_get|profile|user_posts|trending|comments|groups_mine|groups_discover|group_get|group_members|group_history|group_after)$|admin_(stats|push_stats|players|player_detail|lounge_get|house_upgrade_get|payments|notifications|table_rows|config_list|' +
    'client_errors|love_overview|kids_overview|market_overview|chat_reports|billboard_queue|company_overview|real_biz_queue|real_biz_revenue|audit_list|feedback_list|music_overview|gist_overview|gist_reports|gist_bans|gist_groups|gist_orphan_photos)$)',
);
const MAX_TRIES = 3;
const inflight = new Map<string, Promise<unknown>>();

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
/** Full-jitter exponential backoff: 0..min(4s, 500ms * 2^n). Spreads a crowd's retries out. */
const backoff = (n: number) => Math.random() * Math.min(4000, 500 * 2 ** n);

function retryable(status: number, read: boolean): boolean {
  if (status === 429 || status === 503) return true;
  if (!read) return false;
  return status === 0 || status === 502 || status === 504 || status >= 520;
}

/** Call a Postgres RPC. Throws GameError with the server's Pidgin message on failure. */
let lastWrite = 0;
/** When the last game action (non-read RPC) was sent. state/game.ts uses it to tell its own echoes apart. */
export const lastWriteAt = () => lastWrite;

export async function rpc<T = Record<string, unknown>>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const read = READ_RPC.test(fn);
  if (!read) {
    lastWrite = Date.now();
    return call<T>(fn, args, false);
  }
  const key = fn + JSON.stringify(args);
  const running = inflight.get(key);
  if (running) return running as Promise<T>;
  const p = call<T>(fn, args, true).finally(() => inflight.delete(key));
  inflight.set(key, p);
  return p;
}

async function call<T>(fn: string, args: Record<string, unknown>, read: boolean): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const { data, error, status } = await supabase.rpc(fn, args);
    if (!error) {
      netOk();
      noteReceipt(data); // H2: big purchases open the receipt sheet
      if (POKE_RPC.test(fn)) pokePush(); // P1: deliver the push this action queued
      return data as T;
    }
    const st = Number(status ?? 0);
    if (st === 0 || st >= 500 || st === 429) netFailed(st);
    else netOk(); // the server answered (a game refusal is not a connection problem)
    if (attempt + 1 < MAX_TRIES && retryable(st, read)) {
      await sleep(backoff(attempt) + (st === 429 ? 1000 : 0));
      continue;
    }
    const msg = error.code === 'P0001' ? error.message : friendly(error.message, st);
    throw new GameError(msg, error.code, error.code === 'P0001' ? error.hint || undefined : undefined, st);
  }
}

function friendly(raw: string, status = -1): string {
  if (status === 429) return 'Too many people dey play right now. Wait small and try again.';
  if (status >= 500 || status === 0 || /fetch|network|Failed to/i.test(raw)) return 'Network problem. Check your connection and try again.';
  if (/JWT|not logged|auth/i.test(raw)) return 'Your session has expired. Please log in again.';
  return 'Something went wrong. Please try again.';
}

/** Return a Pidgin message for any thrown value. */
export function errorMessage(e: unknown): string {
  if (e instanceof GameError) return e.message;
  if (e instanceof Error) return friendly(e.message);
  return 'Something went wrong. Please try again.';
}
