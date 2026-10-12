// A2: talk to every player at once (announcement popup / inbox) and gift money to a whole group with a narration.
// Server: admin_broadcast_preview / admin_broadcast_send / admin_gift_send / admin_broadcast_list / admin_broadcast_end
// (supabase/migrations/20261012001100_admin_broadcast.sql). One broadcasts row per send, never one per player.
import { useEffect, useRef, useState } from 'react';
import { toast } from '../ui';
import { rpc, errorMessage } from '../lib/api';
import { naira, nairaShort, parseNaira } from '../lib/format';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton, Toggle } from './parts';
import { timeShort, useLoad } from './util';

type Audience = 'everyone' | 'lapo' | 'nepo' | 'online' | 'joined_after';
type Style = 'info' | 'celebration' | 'warning';
interface Row {
  id: number; kind: 'message' | 'gift'; title: string; body: string; style: Style; audience: Audience; joined_after: string | null;
  popup: boolean; expires_at: string | null; cancelled_at: string | null; target_count: number; gift_account: 'cash' | 'bank' | null;
  gift_amount: number | null; gift_total: number | null; created_at: string; created_by: string | null; live: boolean;
  seen_count: number; dismissed_count: number;
}
interface Preview { count: number; total: number | null; gift_max: number; gift_total_max: number }

const AUDIENCES: { id: Audience; label: string }[] = [
  { id: 'everyone', label: 'Everyone' }, { id: 'lapo', label: 'LAPO only' }, { id: 'nepo', label: 'Nepo only' },
  { id: 'online', label: 'Online now' }, { id: 'joined_after', label: 'Joined after…' },
];
const STYLES: { id: Style; label: string }[] = [{ id: 'info', label: '📣 Info' }, { id: 'celebration', label: '🎉 Celebration' }, { id: 'warning', label: '⚠️ Warning' }];
const EXPIRY: { days: number | null; label: string }[] = [
  { days: null, label: 'No expiry' }, { days: 1, label: '1 day' }, { days: 3, label: '3 days' }, { days: 7, label: '7 days' }, { days: 30, label: '30 days' },
];
/** "in 6d" / "in 5h" for a future time, timeShort for a past one. */
function whenShort(iso: string): string {
  const s = Math.round((new Date(iso).getTime() - Date.now()) / 1000);
  if (s <= 0) return timeShort(iso);
  if (s < 3600) return `in ${Math.max(1, Math.floor(s / 60))}m`;
  if (s < 86400) return `in ${Math.floor(s / 3600)}h`;
  return `in ${Math.floor(s / 86400)}d`;
}
const STYLE_TONE: Record<Style, 'blue' | 'green' | 'amber'> = { info: 'blue', celebration: 'green', warning: 'amber' };

/** yyyy-mm-dd (Benin date) → start of that day in WAT. */
const joinedIso = (d: string) => (d ? `${d}T00:00:00+01:00` : null);
const expiryIso = (days: number | null) => (days ? new Date(Date.now() + days * 86_400_000).toISOString() : null);
const newKey = () => (globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`);
const audienceLabel = (a: Audience, after: string | null) =>
  a === 'joined_after' && after ? `Joined after ${new Date(after).toLocaleDateString()}` : AUDIENCES.find((x) => x.id === a)?.label ?? a;

function AudiencePicker({ value, onChange, after, onAfter, count }: {
  value: Audience; onChange: (a: Audience) => void; after: string; onAfter: (d: string) => void; count: number | null;
}) {
  return (
    <div className="adm-field">
      <span className="adm-field__label">Who gets it</span>
      <div className="adm-chips" role="group" aria-label="Audience">
        {AUDIENCES.map((a) => <button key={a.id} type="button" className={`adm-chip${value === a.id ? ' is-on' : ''}`} onClick={() => onChange(a.id)}>{a.label}</button>)}
      </div>
      {value === 'joined_after' && (
        <input className="adm-input adm-bc__date" type="date" aria-label="Joined after" value={after} onChange={(e) => onAfter(e.target.value)} />
      )}
      <span className="adm-field__help" aria-live="polite">
        {count == null ? '…' : `${count.toLocaleString()} player${count === 1 ? '' : 's'} right now`}
        {value === 'online' ? ' · frozen at send time' : value === 'joined_after' || value === 'everyone' ? ' · new players who fit also see it until it expires' : ''}
      </span>
    </div>
  );
}

function usePreview(audience: Audience, after: string, amount: number | null) {
  const [p, setP] = useState<Preview | null>(null);
  useEffect(() => {
    if (audience === 'joined_after' && !after) { setP(null); return; }
    let alive = true;
    const t = window.setTimeout(() => {
      rpc<Preview>('admin_broadcast_preview', { p_audience: audience, p_joined_after: joinedIso(after), p_amount: amount })
        .then((r) => { if (alive) setP(r); }).catch(() => { if (alive) setP(null); });
    }, 250);
    return () => { alive = false; window.clearTimeout(t); };
  }, [audience, after, amount]);
  return p;
}

function MessageForm({ onSent }: { onSent: () => void }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [style, setStyle] = useState<Style>('info');
  const [audience, setAudience] = useState<Audience>('everyone');
  const [after, setAfter] = useState('');
  const [popup, setPopup] = useState(true);
  const [expiry, setExpiry] = useState<number | null>(7);
  const [busy, setBusy] = useState(false);
  const preview = usePreview(audience, after, null);
  const ok = title.trim().length > 0 && body.trim().length > 0 && body.length <= 500 && (audience !== 'joined_after' || !!after);
  const send = async () => {
    setBusy(true);
    try {
      const r = await rpc<{ message: string }>('admin_broadcast_send', {
        p_title: title.trim(), p_body: body.trim(), p_style: style, p_audience: audience, p_joined_after: joinedIso(after),
        p_popup: popup, p_expires_at: expiryIso(expiry),
      });
      toast(r.message, 'good');
      setTitle(''); setBody('');
      onSent();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <section className="adm-card adm-bc__card">
      <h3 className="adm-h3">📣 Send a message</h3>
      <div className="adm-form">
        <label className="adm-field">
          <span className="adm-field__label">Title</span>
          <input className="adm-input" maxLength={80} value={title} placeholder="e.g. Benin Life don land!" onChange={(e) => setTitle(e.target.value)} />
        </label>
        <label className="adm-field">
          <span className="adm-field__label">Message</span>
          <textarea className="adm-input adm-bc__text" rows={4} maxLength={500} value={body} placeholder="What you want everybody to hear"
            onChange={(e) => setBody(e.target.value)} />
          <span className={`adm-field__help${body.length > 480 ? ' adm-bc__warn' : ''}`}>{body.length}/500</span>
        </label>
        <div className="adm-field">
          <span className="adm-field__label">Style</span>
          <div className="adm-chips" role="group" aria-label="Style">
            {STYLES.map((s) => <button key={s.id} type="button" className={`adm-chip${style === s.id ? ' is-on' : ''}`} onClick={() => setStyle(s.id)}>{s.label}</button>)}
          </div>
        </div>
        <AudiencePicker value={audience} onChange={setAudience} after={after} onAfter={setAfter} count={preview?.count ?? null} />
        <div className="adm-field adm-field--row">
          <span><span className="adm-field__label">Show as popup</span><br /><span className="adm-field__help">Off = inbox only (Phone → Alerts + a small toast)</span></span>
          <Toggle checked={popup} onChange={setPopup} label="Show as popup" />
        </div>
        <div className="adm-field">
          <span className="adm-field__label">Expires</span>
          <div className="adm-chips" role="group" aria-label="Expiry">
            {EXPIRY.map((x) => <button key={x.label} type="button" className={`adm-chip${expiry === x.days ? ' is-on' : ''}`} onClick={() => setExpiry(x.days)}>{x.label}</button>)}
          </div>
        </div>
        <div className="adm-btnrow">
          <ConfirmButton tone="primary" disabled={!ok || busy} confirmText={`Send to ${preview?.count?.toLocaleString() ?? '…'} players?`} onConfirm={() => void send()}>
            Send message
          </ConfirmButton>
        </div>
      </div>
    </section>
  );
}

function GiftForm({ onSent }: { onSent: () => void }) {
  const [amountText, setAmountText] = useState('');
  const [account, setAccount] = useState<'cash' | 'bank'>('cash');
  const [narration, setNarration] = useState('');
  const [audience, setAudience] = useState<Audience>('everyone');
  const [after, setAfter] = useState('');
  const [popup, setPopup] = useState(true);
  const [confirm, setConfirm] = useState(false);
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const key = useRef<string | null>(null);
  const amount = parseNaira(amountText);
  const preview = usePreview(audience, after, amount);
  const overMax = amount !== null && preview != null && amount > preview.gift_max;
  const overTotal = preview?.total != null && preview.total > preview.gift_total_max;
  const ok = amount !== null && !overMax && !overTotal && narration.trim().length >= 2 && (preview?.count ?? 0) > 0
    && (audience !== 'joined_after' || !!after);
  const open = () => { key.current = newKey(); setTyped(''); setConfirm(true); };
  const close = () => { setConfirm(false); key.current = null; };
  const pay = async () => {
    if (!key.current || amount === null) return;
    setBusy(true);
    try {
      const r = await rpc<{ message: string; duplicate: boolean }>('admin_gift_send', {
        p_key: key.current, p_amount: amount, p_account: account, p_narration: narration.trim(), p_audience: audience,
        p_joined_after: joinedIso(after), p_popup: popup, p_expires_at: null,
      });
      toast(r.message, r.duplicate ? 'info' : 'good');
      close();
      setAmountText(''); setNarration('');
      onSent();
    } catch (e) { toast(errorMessage(e), 'bad'); /* keep the key: a retry can never pay twice */ } finally { setBusy(false); }
  };
  return (
    <section className="adm-card adm-bc__card">
      <h3 className="adm-h3">🎁 Gift money to everyone</h3>
      <div className="adm-form">
        <div className="adm-field">
          <span className="adm-field__label">Amount per player</span>
          <div className="adm-grant__row">
            <label className={`adm-numbox${amountText && amount === null ? ' is-invalid' : ''}`}>
              <span className="adm-numbox__affix">₦</span>
              <input type="text" inputMode="decimal" autoComplete="off" spellCheck={false} placeholder="e.g. 5000, 50K" aria-label="Amount per player"
                value={amountText} onChange={(e) => setAmountText(e.target.value)} />
            </label>
            <div className="adm-chips" role="group" aria-label="Account">
              {(['cash', 'bank'] as const).map((a) => <button key={a} type="button" className={`adm-chip${account === a ? ' is-on' : ''}`} onClick={() => setAccount(a)}>{a === 'cash' ? 'Cash' : 'Bank'}</button>)}
            </div>
          </div>
          <span className={`adm-field__help${overMax ? ' adm-bc__warn' : ''}`}>
            {overMax ? `More than the per-player limit ${naira(preview!.gift_max)} (Settings → admin.gift_max).`
              : amount !== null ? `= ${naira(amount)}` : `Max ${preview ? naira(preview.gift_max) : '…'} per player`}
          </span>
        </div>
        <label className="adm-field">
          <span className="adm-field__label">Narration (shows in their Bank history and alert)</span>
          <input className="adm-input" maxLength={120} value={narration} placeholder="e.g. Launch gift from the Oba 🎉" onChange={(e) => setNarration(e.target.value)} />
        </label>
        <AudiencePicker value={audience} onChange={setAudience} after={after} onAfter={setAfter} count={preview?.count ?? null} />
        <div className="adm-field adm-field--row">
          <span><span className="adm-field__label">Show as popup</span><br /><span className="adm-field__help">Off = alert only. Shows for 14 days.</span></span>
          <Toggle checked={popup} onChange={setPopup} label="Show gift as popup" />
        </div>
        {amount !== null && preview && (
          <p className={`adm-bc__sum${overTotal ? ' is-bad' : ''}`}>
            <b>{preview.count.toLocaleString()}</b> players will get <b>{naira(amount)}</b> — total <b>{naira(preview.total ?? 0)}</b>
            {overTotal && <> · above the total cap {nairaShort(preview.gift_total_max)} (admin.gift_total_max)</>}
          </p>
        )}
        <div className="adm-btnrow">
          <Btn tone="primary" disabled={!ok || busy} onClick={open}>Review gift…</Btn>
        </div>
      </div>
      {confirm && amount !== null && preview && (
        <div className="adm-dialog" role="dialog" aria-modal="true" aria-labelledby="gift-confirm-title" onClick={close}>
          <div className="adm-dialog__card" onClick={(e) => e.stopPropagation()}>
            <h3 id="gift-confirm-title" className="adm-h3">Gift {preview.count.toLocaleString()} players?</h3>
            <p className="adm-dialog__amount">{naira(preview.total ?? 0)}</p>
            <p className="adm-sub">{preview.count.toLocaleString()} × {naira(amount)} to their {account} · {audienceLabel(audience, joinedIso(after))}</p>
            <p className="adm-sub">“{narration.trim()}”</p>
            <label className="adm-field">
              <span className="adm-field__label">Type GIFT to confirm</span>
              <input className="adm-input" autoFocus autoComplete="off" value={typed} onChange={(e) => setTyped(e.target.value)} aria-label="Type GIFT to confirm"
                onKeyDown={(e) => { if (e.key === 'Enter' && typed.trim().toUpperCase() === 'GIFT') void pay(); }} />
            </label>
            <div className="adm-btnrow">
              <Btn onClick={close} disabled={busy}>Cancel</Btn>
              <Btn tone="primary" disabled={busy || typed.trim().toUpperCase() !== 'GIFT'} onClick={() => void pay()}>{busy ? 'Paying…' : 'Pay everyone'}</Btn>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

function History({ rows, onEnd }: { rows: Row[]; onEnd: (id: number) => void }) {
  if (!rows.length) return <p className="adm-empty">Nothing sent yet.</p>;
  return (
    <div className="adm-bc__list">
      {rows.map((r) => {
        const pct = r.target_count ? Math.round((r.seen_count / r.target_count) * 100) : 0;
        return (
          <article key={r.id} className="adm-card adm-bc__item">
            <div className="adm-bc__head">
              <b>{r.kind === 'gift' ? '🎁 ' : ''}{r.title}</b>
              <span className="adm-bc__badges">
                <Badge tone={r.kind === 'gift' ? 'green' : STYLE_TONE[r.style]}>{r.kind === 'gift' ? 'gift' : r.style}</Badge>
                {r.live ? <Badge tone="blue">live</Badge> : <Badge>{r.cancelled_at ? 'ended' : 'expired'}</Badge>}
                {!r.popup && <Badge>inbox only</Badge>}
              </span>
            </div>
            {r.body && <p className="adm-bc__body">{r.body}</p>}
            {r.kind === 'gift' && r.gift_amount != null && (
              <p className="adm-sub">{naira(r.gift_amount)} × {r.target_count.toLocaleString()} to {r.gift_account} = <b>{naira(r.gift_total ?? 0)}</b></p>
            )}
            <div className="adm-bc__reach" aria-label={`Seen by ${r.seen_count} of ${r.target_count}`}>
              <span style={{ width: `${Math.min(100, pct)}%` }} />
            </div>
            <p className="adm-sub">
              Seen by <b>{r.seen_count.toLocaleString()}</b> of {r.target_count.toLocaleString()} ({pct}%) · {r.dismissed_count.toLocaleString()} closed the popup
              <br />{audienceLabel(r.audience, r.joined_after)} · {timeShort(r.created_at)}{r.created_by ? ` · @${r.created_by}` : ''}
              {r.expires_at ? ` · ${r.live ? 'expires' : 'expired'} ${whenShort(r.expires_at)}` : ''}
            </p>
            {r.live && (
              <div className="adm-btnrow">
                <ConfirmButton small confirmText="End it now?" onConfirm={() => onEnd(r.id)}>End now</ConfirmButton>
              </div>
            )}
          </article>
        );
      })}
    </div>
  );
}

export default function Broadcast() {
  const { data, error, loading, reload } = useLoad(() => rpc<{ rows: Row[] }>('admin_broadcast_list', { p_limit: 50 }), []);
  const end = async (id: number) => {
    try {
      const r = await rpc<{ message: string }>('admin_broadcast_end', { p_id: id });
      toast(r.message, 'good');
      reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  return (
    <div className="adm-page">
      <PageHead title="Broadcast" sub="Talk to every player at once, or gift money to a whole group with one narration."
        actions={<Btn small icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      <div className="adm-bc__forms">
        <MessageForm onSent={reload} />
        <GiftForm onSent={reload} />
      </div>
      <h3 className="adm-h3 adm-bc__histhead">History</h3>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={3} />}
      {data && <History rows={data.rows} onEnd={(id) => void end(id)} />}
    </div>
  );
}
