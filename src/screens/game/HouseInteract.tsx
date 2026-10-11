// V2: tap a person in the house -> a bottom sheet of things to do together (server-checked; the other
// player accepts), plus the Accept / Not now prompt and the "waiting for an answer" chip.
import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { AvatarPortrait } from '../../art/avatar3d';
import type { HomeLayout } from '../../art/home3d';
import { bankTransfer } from '../../api/bank';
import { interactRequest, interactRespond, type InteractionType, type InteractRespondResult } from '../../api/interactions';
import { socialHomeOffer } from '../../api/social';
import { naira } from '../../lib/format';
import type { AvatarConfig, InventoryItem } from '../../lib/types';
import { Icon, Sheet, toast } from '../../ui';

const NEED_LABEL: Record<string, string> = { hunger: 'hunger', fun: 'fun', social: 'social', energy: 'energy', stress: 'stress', hygiene: 'hygiene', health: 'health' };

function effectLine(t: InteractionType): string {
  const parts = Object.entries(t.effects ?? {})
    .filter(([k, v]) => NEED_LABEL[k] && Number(v) !== 0 && k !== 'stress' && k !== 'energy')
    .map(([k, v]) => `${Number(v) > 0 ? '+' : ''}${v} ${NEED_LABEL[k]}`);
  return [`${t.seconds}s`, ...parts.slice(0, 2), t.cost > 0 ? naira(t.cost) : ''].filter(Boolean).join(' · ');
}

function needText(requires: string[]): string {
  if (requires.includes('watch_tv')) return 'Needs a TV';
  if (requires.includes('cook_home')) return 'Needs a cooker';
  return 'Needs a seat';
}

export interface Waiting { id: number; label: string; icon: string; username: string; expires: number }

export function HouseInteractSheet({ person, types, layout, inventory, busy, onClose, onAsked }: {
  person: { id: string; username: string; avatar: AvatarConfig } | null;
  types: InteractionType[];
  layout: HomeLayout;
  inventory: InventoryItem[];
  busy: boolean;
  onClose: () => void;
  onAsked: (w: Waiting) => void;
}) {
  const [view, setView] = useState<'menu' | 'snack' | 'gift'>('menu');
  const [sending, setSending] = useState<string | null>(null);
  const [amount, setAmount] = useState('1000');
  const open = Boolean(person);
  useEffect(() => { if (open) setView('menu'); }, [open, person?.id]);
  const has = useMemo(() => {
    const acts = new Set(layout.furniture.flatMap((f) => f.activities ?? []));
    return (req: string[]) => !req.length || req.some((a) => acts.has(a));
  }, [layout]);
  const food = inventory.filter((item) => ['food', 'drink'].includes(item.category) && item.kind === 'use' && item.qty > 0);

  const ask = async (t: InteractionType) => {
    if (!person || sending) return;
    setSending(t.kind);
    try {
      const r = await interactRequest(person.id, t.kind);
      onAsked({ id: r.id, label: t.label, icon: t.icon, username: person.username, expires: Date.parse(r.expires_at) || Date.now() + 60_000 });
      onClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not ask right now.', 'bad');
    } finally { setSending(null); }
  };
  const offer = async (item: InventoryItem) => {
    if (!person || sending) return;
    setSending(item.id);
    try {
      const r = await socialHomeOffer(person.id, item.id);
      toast(r.message, 'good');
      onClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not share that item.', 'bad');
    } finally { setSending(null); }
  };
  const gift = async () => {
    const n = Math.round(Number(amount));
    if (!person || sending || !Number.isFinite(n) || n <= 0) return;
    setSending('gift');
    try {
      await bankTransfer(person.username, n, 'A gift from the house visit');
      toast(`Sent ${naira(n)} to @${person.username}.`, 'good');
      onClose();
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not send the gift.', 'bad');
    } finally { setSending(null); }
  };

  const header = person && (
    <div className="ix-head">
      <span className="ix-head__face">{person.avatar && <AvatarPortrait config={person.avatar} size={56} />}</span>
      <span className="ix-head__text">
        <b>@{person.username}</b>
        <small>{view === 'menu' ? 'In the house with you' : view === 'snack' ? 'Offer a drink or snack' : 'Give a gift'}</small>
      </span>
      {view !== 'menu' && <button type="button" className="ix-head__back" onClick={() => setView('menu')} aria-label="Back"><Icon name="back" size={16} /></button>}
    </div>
  );

  return (
    <Sheet open={open} onClose={onClose} header={header} className="ix-sheet">
      {view === 'menu' && (
        <div className="ix-grid">
          {types.map((t) => {
            const ok = has(t.requires);
            return (
              <button key={t.kind} type="button" className="ix-tile" disabled={!ok || busy || sending !== null} onClick={() => void ask(t)}
                data-kind={t.kind}>
                <span className="ix-tile__icon" aria-hidden>{t.icon}</span>
                <span className="ix-tile__label">{t.label}</span>
                <small className="ix-tile__meta">{!ok ? needText(t.requires) : sending === t.kind ? 'Asking…' : effectLine(t)}</small>
              </button>
            );
          })}
          <button type="button" className="ix-tile" disabled={sending !== null} onClick={() => setView('snack')}>
            <span className="ix-tile__icon" aria-hidden>🥤</span>
            <span className="ix-tile__label">Offer a drink or snack</span>
            <small className="ix-tile__meta">{food.length ? `${food.length} in your Bag` : 'Nothing in your Bag'}</small>
          </button>
          <button type="button" className="ix-tile" disabled={sending !== null} onClick={() => setView('gift')}>
            <span className="ix-tile__icon" aria-hidden>🎁</span>
            <span className="ix-tile__label">Give a gift</span>
            <small className="ix-tile__meta">Money from your bank</small>
          </button>
          {busy && <p className="ix-note">Finish what you are doing first.</p>}
        </div>
      )}
      {view === 'snack' && (
        <div className="ix-list">
          {food.length ? food.slice(0, 8).map((item) => (
            <button key={item.id} type="button" className="ix-row" disabled={sending !== null} onClick={() => void offer(item)}>
              <span>{item.icon ?? '🍽️'} {item.name}</span><small>×{item.qty}</small>
            </button>
          )) : <p className="ix-note">You have no food or drinks in your Bag.</p>}
        </div>
      )}
      {view === 'gift' && (
        <div className="ix-gift">
          <div className="ix-gift__chips">
            {[500, 1000, 5000, 20000].map((n) => (
              <button key={n} type="button" className={`ix-chip${Number(amount) === n ? ' is-on' : ''}`} onClick={() => setAmount(String(n))}>{naira(n)}</button>
            ))}
          </div>
          <label className="ix-gift__field">
            <span>Amount</span>
            <input inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^\d]/g, ''))} aria-label="Gift amount" />
          </label>
          <button type="button" className="ix-primary" disabled={sending !== null || !(Number(amount) > 0)} onClick={() => void gift()}>
            {sending === 'gift' ? 'Sending…' : `Send ${Number(amount) > 0 ? naira(Number(amount)) : ''}`}
          </button>
          <small className="ix-note">Bank transfer rules apply (fee, daily limit).</small>
        </div>
      )}
    </Sheet>
  );
}

export interface Prompt { id: number; label: string; icon: string; username: string; from: string; expires: number }

/** The other player's request: Accept / Not now with a draining countdown; plus our own waiting chip. */
export function InteractPrompts({ prompt, waiting, avatarOf, onAnswered, onDismissWaiting }: {
  prompt: Prompt | null;
  waiting: Waiting | null;
  avatarOf: (id: string) => AvatarConfig | undefined;
  onAnswered: (p: Prompt, r: InteractRespondResult | null) => void;
  onDismissWaiting: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [, tick] = useState(0);
  useEffect(() => {
    if (!prompt && !waiting) return;
    const id = window.setInterval(() => tick((n) => n + 1), 1000);
    return () => window.clearInterval(id);
  }, [prompt, waiting]);
  const answer = async (accept: boolean) => {
    if (!prompt || busy) return;
    setBusy(true);
    try {
      const r = await interactRespond(prompt.id, accept);
      if (r.status === 'expired') toast(r.message, 'info');
      else if (accept) toast(r.message, 'good');
      onAnswered(prompt, r);
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not answer.', 'bad');
      onAnswered(prompt, null);
    } finally { setBusy(false); }
  };
  const left = (until: number) => Math.max(0, Math.ceil((until - Date.now()) / 1000));
  if (!prompt && !waiting) return null;
  // portalled: above any open sheet, so the answer is always one tap away
  return createPortal(
    <div className="ix-prompts" role="region" aria-label="House requests">
      {prompt && (
        <div className="ix-prompt" key={prompt.id}>
          <span className="ix-prompt__face">{avatarOf(prompt.from) && <AvatarPortrait config={avatarOf(prompt.from)!} size={40} />}</span>
          <span className="ix-prompt__text">
            <b>@{prompt.username}</b>
            <span>{prompt.icon} {prompt.label}?</span>
          </span>
          <span className="ix-prompt__actions">
            <button type="button" className="ix-ghost" disabled={busy} onClick={() => void answer(false)}>Not now</button>
            <button type="button" className="ix-primary" disabled={busy} onClick={() => void answer(true)}>Accept</button>
          </span>
          <span className="ix-prompt__bar" style={{ animationDuration: `${Math.max(1, left(prompt.expires))}s` }} aria-hidden />
        </div>
      )}
      {waiting && (
        <button type="button" className="ix-wait" onClick={onDismissWaiting} aria-label="Hide">
          <span className="ix-wait__dot" aria-hidden />
          <span>{waiting.icon} Waiting for @{waiting.username} · {left(waiting.expires)}s</span>
        </button>
      )}
    </div>,
    document.body,
  );
}
