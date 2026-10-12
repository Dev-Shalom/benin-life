// A2: announcements from the Benin Life team (Admin → Broadcast) and mass-gift alerts.
// <BroadcastHost/> follows the player's broadcasts (src/state/broadcasts.ts) and shows each "popup" one (oldest first) that
// hasn't been closed yet as a card on top of the game. Inbox-only ones arrive as a toast and wait in Phone → Alerts.
// <BroadcastList/> is the pinned "From Benin Life" block at the top of Alerts.
import { useEffect, useRef } from 'react';
import { Button, Modal, toast } from '../../ui';
import { playCue } from '../../lib/sound';
import { naira, timeAgo } from '../../lib/format';
import { startBroadcasts, useBroadcasts, type Broadcast } from '../../state/broadcasts';

const STYLE_EMOJI: Record<Broadcast['style'], string> = { info: '📣', celebration: '🎉', warning: '⚠️' };

export function BroadcastHost() {
  const rows = useBroadcasts((s) => s.rows);
  const mark = useBroadcasts((s) => s.mark);
  const toasted = useRef(new Set<number>());

  useEffect(() => startBroadcasts(), []);

  const current = rows.filter((r) => r.popup && !r.dismissed).sort((a, b) => a.id - b.id)[0] ?? null;

  // inbox-only: a short toast once per broadcast per tab (Alerts keeps it)
  useEffect(() => {
    for (const r of rows) {
      if (!r.popup && !r.seen && !toasted.current.has(r.id)) {
        toasted.current.add(r.id);
        playCue('alert');
        toast(`${STYLE_EMOJI[r.style]} ${r.title}`, r.style === 'warning' ? 'bad' : 'info');
      }
    }
  }, [rows]);

  // the popup counts as seen as soon as it shows
  const curId = current?.id;
  useEffect(() => {
    if (curId == null) return;
    const r = useBroadcasts.getState().rows.find((x) => x.id === curId);
    playCue(r?.kind === 'gift' ? 'money' : 'alert');
    mark([curId]);
  }, [curId, mark]);

  if (!current) return null;
  const gift = current.kind === 'gift' && current.gift_amount;
  return (
    <Modal open onClose={() => mark([current.id], true)} tone={current.style === 'warning' ? 'bad' : current.style === 'celebration' ? 'good' : 'default'}
      art={<div className={`bcast-art bcast-art--${current.style}`} aria-hidden>{gift ? '🎁' : STYLE_EMOJI[current.style]}</div>}
      title={<span className="bcast-title"><small className="bcast-kicker">From the Benin Life team</small>{gift ? 'You received a gift' : current.title}</span>}
      actions={<Button variant="primary" block onClick={() => mark([current.id], true)}>{gift ? 'Thank you!' : 'OK, I don hear'}</Button>}>
      {gift && <p className="bcast-amount">+{naira(current.gift_amount ?? 0)} <small>to your {current.gift_account === 'bank' ? 'bank' : 'cash'}</small></p>}
      {current.body && <p className="bcast-body">{current.body}</p>}
    </Modal>
  );
}

export function BroadcastList({ active }: { active: boolean }) {
  const rows = useBroadcasts((s) => s.rows);
  const mark = useBroadcasts((s) => s.mark);
  useEffect(() => {
    if (!active) return;
    const t = window.setTimeout(() => {
      const ids = useBroadcasts.getState().rows.filter((r) => !r.seen).map((r) => r.id);
      if (ids.length) mark(ids);
    }, 1200);
    return () => window.clearTimeout(t);
  }, [active, rows.length, mark]);
  if (!rows.length) return null;
  return (
    <ul className="alerts bcast-list" aria-label="From the Benin Life team">
      {rows.map((r) => (
        <li key={r.id} className={`alert bcast-item bcast-item--${r.style}${!r.seen ? ' is-new' : ''}`}>
          <span className="alert__icon" aria-hidden>{r.kind === 'gift' ? '🎁' : STYLE_EMOJI[r.style]}</span>
          <div className="grow">
            <div className="alert__title">{r.title}</div>
            {r.body && <div className="alert__body">{r.body}</div>}
            <div className="alert__meta">Benin Life team · {timeAgo(r.created_at)}</div>
          </div>
        </li>
      ))}
    </ul>
  );
}
