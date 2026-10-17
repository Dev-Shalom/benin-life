// deno test supabase/functions/_shared/playerPush.test.ts   (no network: a fake database and a fake push service)
import { drainPlayerPush, outcome, payloadOf, type OutboxRow } from './playerPush.ts';
import type { SendResult } from './push.ts';

const keys = { publicKey: 'p', privateKey: 'k', subject: 'mailto:a@b.c' };
const row = (id: number, user: string, attempts = 1): OutboxRow => ({
  id, user_id: user, category: 'messages', kind: 'dm', title: '@x', body: 'hi', url: '/play?go=dm:1', tag: 'dm:1', count: 1, attempts,
});

function assert(c: unknown, m: string) { if (!c) throw new Error('FAILED: ' + m); }

// A tiny stand-in for the Supabase client: just the calls drainPlayerPush makes.
function fakeDb(rows: OutboxRow[], subs: { id: number; user_id: string; endpoint: string; p256dh: string; auth: string; fail_count: number }[]) {
  const updates: Record<number, Record<string, unknown>> = {};
  const deletedSubs: number[] = [];
  let claimed = false;
  const db = {
    rpc: (fn: string) => Promise.resolve(fn === 'bl_push_claim'
      ? { data: claimed ? [] : (claimed = true, rows), error: null } : { data: { ok: true }, error: null }),
    from: (t: string) => ({
      select: () => ({ in: () => Promise.resolve({ data: t === 'push_subscriptions' ? subs : [] }) }),
      update: (patch: Record<string, unknown>) => ({
        eq: (_c: string, id: number) => { updates[id] = patch; return Promise.resolve({}); },
        in: () => Promise.resolve({}),
      }),
      delete: () => ({ in: (_c: string, ids: number[]) => { deletedSubs.push(...ids); return Promise.resolve({}); } }),
    }),
  };
  // deno-lint-ignore no-explicit-any
  return { db: db as any, updates, deletedSubs };
}

Deno.test('payload carries the category and the deep link, nothing else private', () => {
  const p = payloadOf(row(1, 'u'));
  assert(p.cat === 'messages' && p.url === '/play?go=dm:1' && p.tag === 'dm:1' && p.title === '@x', 'payload');
});

Deno.test('outcome table', () => {
  assert(outcome(1, true, true, false).status === 'sent', 'ok');
  assert(outcome(1, false, false, false).status === 'skipped', 'no device');
  assert(outcome(1, false, true, true).status === 'failed', 'all devices gone');
  assert(outcome(1, false, true, false).status === 'pending', 'retry');
  assert(outcome(3, false, true, false).status === 'failed', 'gives up after 3');
});

Deno.test('sent, dead device removed (404/410), retry, no device', async () => {
  const sub = (id: number, user: string) => ({ id, user_id: user, endpoint: `https://x/${id}`, p256dh: 'a', auth: 'b', fail_count: 0 });
  const { db, updates, deletedSubs } = fakeDb(
    [row(1, 'ok'), row(2, 'dead'), row(3, 'flaky'), row(4, 'none'), row(5, 'mixed')],
    [sub(10, 'ok'), sub(11, 'dead'), sub(12, 'flaky'), sub(13, 'mixed'), sub(14, 'mixed')]);
  const send = (s: { endpoint: string }): Promise<SendResult> => {
    if (s.endpoint === 'https://x/11' || s.endpoint === 'https://x/13') return Promise.resolve({ ok: false, status: 410, gone: true, error: 'gone' });
    if (s.endpoint === 'https://x/12') return Promise.resolve({ ok: false, status: 503, gone: false, error: 'busy' });
    return Promise.resolve({ ok: true });
  };
  const r = await drainPlayerPush(db, keys, { send });
  assert(r.claimed === 5 && r.sent === 2 && r.failed === 1 && r.retried === 1 && r.skipped === 1, 'counts ' + JSON.stringify(r));
  assert(updates[1].status === 'sent' && updates[1].sent_at, 'row 1 sent');
  assert(updates[2].status === 'failed' && updates[2].error === 'device gone', 'row 2 failed: device gone');
  assert(updates[3].status === 'pending' && updates[3].send_after, 'row 3 retried later');
  assert(updates[4].status === 'skipped', 'row 4 no device');
  assert(updates[5].status === 'sent', 'row 5: one device alive is enough');
  assert(deletedSubs.sort().join() === '11,13', 'dead subscriptions deleted: ' + deletedSubs);
  assert(r.removed === 2, 'removed count');
});

Deno.test('no VAPID key: nothing is claimed, rows stay queued', async () => {
  const { db, updates } = fakeDb([row(1, 'u')], []);
  const r = await drainPlayerPush(db, null);
  assert(!r.configured && r.claimed === 0 && Object.keys(updates).length === 0, 'untouched');
});
