// Admin notifications (H3): drain the admin_notifications outbox to every admin's push subscriptions.
// Rows are created by the database (ad paid / live / reported / ended, refund failed). Any server function can
// call flushAdminPush after an action; the admin-push function does it on demand (and ends finished ads first).
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { DEFAULT_VAPID_PUBLIC_KEY, sendPush, type PushKeys, type PushMessage } from './push.ts';

function env(name: string): string {
  return (Deno.env.get(name) ?? '').trim();
}

export function pushKeys(): PushKeys | null {
  const privateKey = env('VAPID_PRIVATE_KEY');
  if (!privateKey) return null;
  return {
    privateKey,
    publicKey: env('VAPID_PUBLIC_KEY') || DEFAULT_VAPID_PUBLIC_KEY,
    subject: env('VAPID_SUBJECT') || 'mailto:dev.shalom1@gmail.com',
  };
}

interface Row { id: number; kind: string; title: string; body: string; url: string }
interface Sub { id: number; user_id: string; endpoint: string; p256dh: string; auth: string; fail_count: number }

export interface FlushResult { configured: boolean; messages: number; sent: number; failed: number; removed: number }

/** Send the unsent admin notifications. Safe to call concurrently (rows are claimed once). */
export async function flushAdminPush(db: SupabaseClient, onlyUser?: string, test?: PushMessage): Promise<FlushResult> {
  const keys = pushKeys();
  const out: FlushResult = { configured: Boolean(keys), messages: 0, sent: 0, failed: 0, removed: 0 };
  if (!keys) {
    // push not set up: mark them handled (the admin page inbox still lists them) so clients stop poking
    if (!test) await db.rpc('bl_push_outbox_claim', { p_limit: 100 });
    return out;
  }

  let msgs: PushMessage[] = [];
  if (test) msgs = [test];
  else {
    const { data, error } = await db.rpc('bl_push_outbox_claim', { p_limit: 20 });
    if (error || !data?.length) return out;
    const rows = data as Row[];
    // more than 3 at once: one summary instead of a flood
    msgs = rows.length > 3
      ? [{ title: `Benin Life: ${rows.length} new alerts`, body: rows.slice(0, 3).map((r) => r.title).join(' · ') + ' …', url: '/admin/ads', tag: 'bl-admin-batch' }]
      : rows.map((r) => ({ title: r.title, body: r.body, url: r.url || '/admin/ads', tag: `bl-admin-${r.id}`, kind: r.kind }));
  }
  out.messages = msgs.length;

  const { data: admins } = await db.from('profiles').select('id').eq('is_admin', true).eq('banned', false);
  const ids = (admins ?? []).map((a: { id: string }) => a.id).filter((id: string) => !onlyUser || id === onlyUser);
  if (!ids.length) return out;
  const { data: subs } = await db.from('push_subscriptions').select('id, user_id, endpoint, p256dh, auth, fail_count').in('user_id', ids);
  for (const s of (subs ?? []) as Sub[]) {
    let dead = false;
    let okAny = false;
    for (const m of msgs) {
      const r = await sendPush(s, m, keys);
      if (r.ok) { out.sent++; okAny = true; continue; }
      out.failed++;
      if (r.gone) { dead = true; break; }
    }
    if (dead || (!okAny && s.fail_count >= 9)) {
      await db.from('push_subscriptions').delete().eq('id', s.id);
      out.removed++;
    } else if (okAny) {
      await db.from('push_subscriptions').update({ last_ok_at: new Date().toISOString(), fail_count: 0 }).eq('id', s.id);
    } else {
      await db.from('push_subscriptions').update({ fail_count: s.fail_count + 1 }).eq('id', s.id);
    }
  }
  return out;
}

/** Fire-and-forget flush that never throws (used after payments / refunds). */
export async function flushQuietly(db: SupabaseClient): Promise<void> {
  try {
    await flushAdminPush(db);
  } catch { /* the in-page inbox still shows them */ }
}
