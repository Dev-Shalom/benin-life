// P1: "deliver it now". After a player does something that notifies somebody else (sends a DM, money, a friend
// request ...), the game pings the player-push Edge Function once, so the push goes out at once instead of waiting
// for the next minute of the server cron. Throttled, fire-and-forget, never throws, and it only makes the server send
// rows the database already queued (docs/NOTIFICATIONS.md).
import { getCfg } from './config';
import { supabase } from './supabase';

const MIN_GAP_MS = 8000;
let last = 0;

export function pokePush(): void {
  try {
    if (getCfg<boolean>('push.enabled', true) === false) return;
    const now = Date.now();
    if (now - last < MIN_GAP_MS) return;
    last = now;
    void supabase.functions.invoke('player-push', { body: {} }).catch(() => undefined);
  } catch {
    /* a push is never worth an error */
  }
}

/** RPCs whose success may notify another player. */
export const POKE_RPC = /^(social_send_message|chat_send|chat_send_voice|bank_transfer|tip_player|social_add_friend|social_respond_friend|social_send_house_invite|friend_invite_place|lounge_bring_guest|social_respond_house_invite|admin_broadcast_send|admin_gift_send)$/;
