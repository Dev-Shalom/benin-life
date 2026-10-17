// Player push sender (P1, docs/NOTIFICATIONS.md): drain public.push_outbox to the players' saved devices.
// The database decides WHO gets WHAT (triggers -> bl_push_enqueue: prefs, switches, rate limits, collapsing).
// This file only sends what the database queued: claim due rows once (bl_push_claim, for update skip locked), send
// each to every device of that player, then mark the row sent / failed / retry, and delete dead devices (404/410).
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { sendPush, type PushKeys, type PushMessage, type PushSub, type SendResult } from './push.ts';

export interface OutboxRow {
  id: number; user_id: string; category: string; kind: string; title: string; body: string; url: string;
  tag: string | null; count: number; attempts: number;
}
interface Sub extends PushSub { id: number; user_id: string; fail_count: number }

export interface PlayerPushResult {
  configured: boolean; claimed: number; sent: number; failed: number; retried: number; skipped: number; removed: number;
  tick?: unknown;
}

export type Sender = (sub: PushSub, msg: PushMessage, keys: PushKeys, ttl: number) => Promise<SendResult>;

const MAX_TRIES = 3;
/** A chat ping is worthless after an hour: let the push service drop it then. */
const TTL_SECONDS = 3600;

export function payloadOf(r: OutboxRow): PushMessage {
  return { title: r.title, body: r.body, url: r.url || '/play', tag: r.tag ?? undefined, kind: r.kind, cat: r.category, count: r.count };
}

/** What to do with a row after trying its devices. */
export function outcome(attempts: number, anyOk: boolean, hadDevices: boolean, allGone: boolean):
  { status: 'sent' | 'failed' | 'pending' | 'skipped'; error?: string; retryInSeconds?: number } {
  if (anyOk) return { status: 'sent' };
  if (!hadDevices) return { status: 'skipped', error: 'no device' };
  if (allGone) return { status: 'failed', error: 'device gone' };
  if (attempts >= MAX_TRIES) return { status: 'failed', error: 'push service error' };
  return { status: 'pending', error: 'retry', retryInSeconds: 60 * attempts };
}

/** Claim and send. `budgetMs` keeps one run well inside the function time limit. */
export async function drainPlayerPush(
  db: SupabaseClient, keys: PushKeys | null, opts: { tick?: boolean; budgetMs?: number; send?: Sender } = {},
): Promise<PlayerPushResult> {
  const send = opts.send ?? sendPush;
  const out: PlayerPushResult = { configured: Boolean(keys), claimed: 0, sent: 0, failed: 0, retried: 0, skipped: 0, removed: 0 };
  if (opts.tick) {
    const { data } = await db.rpc('bl_push_tick');
    out.tick = data;
  }
  // No keys: leave the rows queued (they expire by themselves) instead of losing them.
  if (!keys) return out;
  const deadline = Date.now() + (opts.budgetMs ?? 40_000);

  for (let batch = 0; batch < 5 && Date.now() < deadline; batch++) {
    const { data, error } = await db.rpc('bl_push_claim', { p_limit: 100 });
    if (error || !data?.length) break;
    const rows = data as OutboxRow[];
    out.claimed += rows.length;
    const ids = [...new Set(rows.map((r) => r.user_id))];
    const { data: subRows } = await db.from('push_subscriptions')
      .select('id, user_id, endpoint, p256dh, auth, fail_count').in('user_id', ids);
    const subs = new Map<string, Sub[]>();
    for (const s of (subRows ?? []) as Sub[]) subs.set(s.user_id, [...(subs.get(s.user_id) ?? []), s]);
    const dead = new Set<number>();
    const okSub = new Set<number>();

    // different players in parallel (chunks of 10), one player's rows in order
    const perUser = new Map<string, OutboxRow[]>();
    for (const r of rows) perUser.set(r.user_id, [...(perUser.get(r.user_id) ?? []), r]);
    const users = [...perUser.keys()];
    for (let i = 0; i < users.length; i += 10) {
      await Promise.all(users.slice(i, i + 10).map(async (uid) => {
        for (const r of perUser.get(uid)!) {
          const mine = (subs.get(uid) ?? []).filter((s) => !dead.has(s.id));
          let anyOk = false;
          let gone = 0;
          let lastErr = '';
          for (const s of mine) {
            const res = await send(s, payloadOf(r), keys, TTL_SECONDS);
            if (res.ok) { anyOk = true; okSub.add(s.id); } else if (res.gone) { gone++; dead.add(s.id); } else lastErr = `HTTP ${res.status} ${res.error}`.slice(0, 200);
          }
          const o = outcome(r.attempts, anyOk, mine.length > 0, mine.length > 0 && gone === mine.length);
          const patch: Record<string, unknown> = { status: o.status, error: o.error ? (lastErr || o.error) : null };
          if (o.status === 'sent') patch.sent_at = new Date().toISOString();
          if (o.status === 'pending') patch.send_after = new Date(Date.now() + (o.retryInSeconds ?? 60) * 1000).toISOString();
          await db.from('push_outbox').update(patch).eq('id', r.id);
          if (o.status === 'sent') out.sent++;
          else if (o.status === 'failed') out.failed++;
          else if (o.status === 'pending') out.retried++;
          else out.skipped++;
        }
      }));
    }
    if (dead.size) {
      await db.from('push_subscriptions').delete().in('id', [...dead]);
      out.removed += dead.size;
    }
    if (okSub.size) {
      await db.from('push_subscriptions').update({ last_ok_at: new Date().toISOString(), fail_count: 0 }).in('id', [...okSub]);
    }
    if (rows.length < 100) break;
  }
  return out;
}
