// H3 Admin → Ads (docs/BILLBOARDS.md): the approval queue for billboard ads.
// Approve (live now for the paid days), Reject with a reason (automatic Paystack refund through the
// billboard-refund Edge Function; a failed refund shows here as "Refund failed" with Retry), Remove a live ad
// (no refund unless ticked), place a free Sponsor ad on any board for any dates. Every action is audited by the
// database. The "Notify me" card turns on Web Push for this device; without push the nav badge + sound still work.
import { useEffect, useMemo, useState } from 'react';
import { adImageUrl, compressAdImage, domainOf, koboLabel } from '../lib/billboards';
import { errorMessage, rpc } from '../lib/api';
import { currentSubscription, disablePush, enablePush, flushAdminPush, pushSupport, testPush } from '../lib/push';
import { supabase } from '../lib/supabase';
import { useGame } from '../state/game';
import { Icon, toast } from '../ui';
import { Badge, Btn, ConfirmButton, DetailPane, LoadError, PageHead, Skeleton, Toggle } from './parts';
import { timeShort, useLoad } from './util';

type Filter = 'review' | 'live' | 'reported' | 'refunds' | 'ended' | 'all';
const FILTERS: { id: Filter; label: string }[] = [
  { id: 'review', label: 'In review' }, { id: 'live', label: 'Live' }, { id: 'reported', label: 'Reported' },
  { id: 'refunds', label: 'Refunds' }, { id: 'ended', label: 'Ended' }, { id: 'all', label: 'All' },
];

interface AdRow {
  id: string; board_id: string; board: string; kind: 'paid' | 'sponsor'; status: string; image: string; link: string | null; title: string;
  days: number; price_kobo: number; paid_kobo: number | null; paid_at: string | null; created_at: string; starts_at: string | null;
  ends_at: string | null; reviewed_at: string | null; reviewer: string | null; reject_reason: string | null; refund_status: string;
  refund_kobo: number | null; refund_error: string | null; reference: string | null; user_id: string | null; username: string | null;
  email: string | null; views: number; taps: number; reports: number; report_reasons: string[];
}
interface Queue {
  counts: Record<Exclude<Filter, 'all'>, number>;
  payments_enabled: boolean;
  boards: { id: string; name: string; area: string; live: number }[];
  rows: AdRow[];
}
interface Inbox { unread: number; last_id: number; seen_id: number; subscriptions: number; rows: { id: number; kind: string; title: string; body: string; created_at: string; unread: boolean }[] }

const STATUS_TONE: Record<string, 'green' | 'amber' | 'red' | 'grey' | 'blue'> = {
  pending_review: 'amber', live: 'green', rejected: 'red', removed: 'red', expired: 'grey', awaiting_payment: 'blue', cancelled: 'grey',
};
const STATUS_LABEL: Record<string, string> = {
  pending_review: 'In review', live: 'Live', rejected: 'Rejected', removed: 'Removed', expired: 'Ended', awaiting_payment: 'Unpaid', cancelled: 'Cancelled',
};
const REFUND_LABEL: Record<string, [string, 'amber' | 'green' | 'red']> = {
  pending: ['Refund pending', 'amber'], processing: ['Refunding…', 'amber'], refunded: ['Refunded', 'green'], refund_failed: ['Refund failed', 'red'],
};

/** Call billboard-refund and show what happened. */
async function runRefund(adId: string): Promise<boolean> {
  const { data, error } = await supabase.functions.invoke('billboard-refund', { body: { ad_id: adId } });
  if (!error && data?.ok) {
    toast('Refund sent through Paystack.', 'good');
    return true;
  }
  let msg = 'Refund failed.';
  try {
    const ctx = (error as { context?: Response } | null)?.context;
    const body = ctx ? await ctx.json() : data;
    if (body?.message) msg = `Refund failed: ${body.message}`;
  } catch { /* keep the generic text */ }
  toast(msg + ' It is listed under Refunds; retry or refund in the Paystack dashboard.', 'bad');
  return false;
}

export default function Ads() {
  const [filter, setFilter] = useState<Filter>('review');
  const { data, error, loading, reload } = useLoad(() => rpc<Queue>('admin_billboard_queue', { p_filter: filter, p_limit: 150 }), [filter]);
  const [sponsor, setSponsor] = useState(false);
  return (
    <div className="adm-page">
      <PageHead title="Ads" sub="Billboard ads. Approve to put them on air now; rejecting refunds the player automatically."
        actions={<>
          <Btn icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>
          <Btn tone="primary" icon="plus" onClick={() => setSponsor(true)}>Sponsor ad</Btn>
        </>} />
      <NotifyCard />
      {data && !data.payments_enabled && (
        <div className="adm-card adm-pay-off"><Icon name="lock" size={16} /> Players can't book ads while <b>payments.enabled</b> is off (Settings). Sponsor ads still work.</div>
      )}
      <div className="adm-toolbar">
        <div className="adm-chips">
          {FILTERS.map((f) => {
            const n = f.id === 'all' ? null : data?.counts[f.id];
            return (
              <button key={f.id} type="button" className={`adm-chip${filter === f.id ? ' is-on' : ''}`} onClick={() => setFilter(f.id)}>
                {f.label}{n ? ` · ${n}` : ''}
              </button>
            );
          })}
        </div>
      </div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={4} />}
      {data && (
        <div className="adm-ads">
          {data.rows.length === 0 && <div className="adm-card"><p className="adm-empty">{filter === 'review' ? 'Nothing to review. 🎉' : 'Nothing here.'}</p></div>}
          {data.rows.map((r) => <AdCard key={r.id} r={r} onChanged={reload} />)}
        </div>
      )}
      {sponsor && data && <SponsorPane boards={data.boards} onClose={() => setSponsor(false)} onSaved={() => { setSponsor(false); reload(); }} />}
    </div>
  );
}

function AdCard({ r, onChanged }: { r: AdRow; onChanged: () => void }) {
  const [mode, setMode] = useState<null | 'reject' | 'remove'>(null);
  const [reason, setReason] = useState('');
  const [refund, setRefund] = useState(true);
  const [busy, setBusy] = useState(false);
  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try {
      await fn();
      flushAdminPush();
      onChanged();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const approve = () => act(async () => {
    const res = await rpc<{ message: string }>('admin_billboard_approve', { p_ad: r.id });
    toast(res.message, 'good');
  });
  const decide = () => act(async () => {
    const fn = mode === 'reject' ? 'admin_billboard_reject' : 'admin_billboard_remove';
    const res = await rpc<{ message: string; refund: boolean }>(fn, { p_ad: r.id, p_reason: reason.trim(), p_refund: refund });
    toast(res.message, 'good');
    setMode(null);
    if (res.refund) await runRefund(r.id);
  });
  const refundDue = ['pending', 'refund_failed', 'processing'].includes(r.refund_status);
  const rl = REFUND_LABEL[r.refund_status];
  return (
    <article className="adm-card adm-ad">
      <div className="adm-ad__img"><img src={adImageUrl(r.image)} alt="" loading="lazy" /></div>
      <div className="adm-ad__main">
        <div className="adm-ad__top">
          <b>{r.board}</b>
          <Badge tone={STATUS_TONE[r.status] ?? 'grey'}>{STATUS_LABEL[r.status] ?? r.status}</Badge>
          {r.kind === 'sponsor' && <Badge tone="violet">Sponsor</Badge>}
          {rl && <Badge tone={rl[1]}>{rl[0]}</Badge>}
          {r.reports > 0 && <Badge tone="red">{r.reports} report{r.reports === 1 ? '' : 's'}</Badge>}
        </div>
        <span className="adm-sub">
          {r.kind === 'sponsor' ? (r.title || 'Sponsor ad') : <>{r.username ? `@${r.username}` : 'Deleted account'}{r.email ? ` · ${r.email}` : ''}</>}
        </span>
        <span className="adm-sub">
          {r.kind === 'paid' ? <>Paid <b>{r.paid_kobo != null ? koboLabel(r.paid_kobo) : '–'}</b>{r.paid_kobo != null && r.paid_kobo !== r.price_kobo ? ` (price ${koboLabel(r.price_kobo)})` : ''} · {r.days} {r.days === 1 ? 'day' : 'days'} · {timeShort(r.paid_at ?? r.created_at)}</> : <>Free · {r.days} days</>}
          {r.starts_at && r.ends_at && ` · on air ${timeShort(r.starts_at)} → ${timeShort(r.ends_at)}`}
        </span>
        {r.link
          ? <a className="adm-ad__link" href={r.link} target="_blank" rel="noopener noreferrer"><Icon name="eye" size={14} /> {domainOf(r.link)} <span className="adm-mono">{r.link}</span></a>
          : <span className="adm-sub">No link</span>}
        {(r.views > 0 || r.taps > 0) && <span className="adm-sub">{r.views.toLocaleString()} views · {r.taps.toLocaleString()} taps</span>}
        {r.report_reasons.length > 0 && <span className="adm-sub adm-ad__reports">Reports: {r.report_reasons.join(' · ')}</span>}
        {r.reject_reason && <span className="adm-sub">Reason: {r.reject_reason}{r.reviewer ? ` (by @${r.reviewer})` : ''}</span>}
        {r.refund_error && <span className="adm-sub adm-ad__err">Paystack: {r.refund_error}</span>}
        {r.reference && <span className="adm-sub adm-mono">{r.reference}</span>}

        {mode && (
          <div className="adm-ad__decide">
            <input className="adm-input" placeholder={mode === 'reject' ? 'Reason the player sees (required)' : 'Reason (optional, the player sees it)'}
              value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} autoFocus />
            {r.kind === 'paid' && (r.paid_kobo ?? 0) > 0 && (
              <Toggle checked={refund} onChange={setRefund} label={`Refund ${koboLabel(r.paid_kobo ?? 0)} through Paystack`} />
            )}
            <div className="adm-ad__actions">
              <Btn onClick={() => setMode(null)} disabled={busy}>Cancel</Btn>
              <Btn tone="danger" disabled={busy || (mode === 'reject' && !reason.trim())} onClick={() => void decide()}>
                {busy ? 'Working…' : mode === 'reject' ? 'Reject' : 'Remove now'}
              </Btn>
            </div>
          </div>
        )}
        {!mode && (
          <div className="adm-ad__actions">
            {r.status === 'pending_review' && <>
              <Btn tone="primary" icon="check" disabled={busy} onClick={() => void approve()}>Approve · goes live now</Btn>
              <Btn tone="danger" disabled={busy} onClick={() => { setMode('reject'); setRefund(true); setReason(''); }}>Reject</Btn>
            </>}
            {r.status === 'live' && <Btn tone="danger" disabled={busy} onClick={() => { setMode('remove'); setRefund(false); setReason(''); }}>Remove</Btn>}
            {refundDue && r.refund_status !== 'processing' && (
              <ConfirmButton tone="primary" confirmText={`Refund ${koboLabel(r.refund_kobo ?? r.paid_kobo ?? 0)}?`}
                onConfirm={() => act(() => runRefund(r.id))}>{r.refund_status === 'refund_failed' ? 'Retry refund' : 'Send refund'}</ConfirmButton>
            )}
          </div>
        )}
      </div>
    </article>
  );
}

/* ------------------------------------------------------------------ */
function NotifyCard() {
  const me = useGame((s) => s.state?.profile.id);
  const support = useMemo(() => pushSupport(), []);
  const [on, setOn] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const { data: inbox, reload } = useLoad(() => rpc<Inbox>('admin_notifications', { p_limit: 8 }), []);
  useEffect(() => {
    void currentSubscription().then((s) => setOn(Boolean(s))).catch(() => setOn(false));
  }, []);
  const run = async (fn: () => Promise<string>) => {
    setBusy(true);
    try {
      toast(await fn(), 'good');
      setOn(Boolean(await currentSubscription()));
      reload();
    } catch (e) {
      toast(e instanceof Error ? e.message : errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const test = () => run(async () => {
    const r = await testPush();
    if (!r.configured) return 'Push is not set up on the server yet (VAPID_PRIVATE_KEY secret). See docs/BILLBOARDS.md.';
    return r.sent ? 'Test sent. Check your phone.' : 'No device got it. Tap "Notify me" on your phone first.';
  });
  const markRead = async () => {
    await rpc('admin_notifications_seen', { p_last_id: inbox?.last_id ?? null }).catch(() => {});
    reload();
    window.dispatchEvent(new Event('bl-admin-seen'));
  };
  return (
    <div className="adm-card adm-notify">
      <div className="adm-notify__head">
        <span className="adm-notify__icon" aria-hidden>🔔</span>
        <span className="grow">
          <b>Phone notifications</b>
          <span className="adm-sub">
            {support === 'ok' ? (on ? 'On for this device. You hear about paid ads, reports, ended ads and failed refunds.' : 'Get a notification when an ad is paid and needs approval, goes live, is reported, ends, or a refund fails.')
              : support === 'ios_install' ? 'iPhone: add Benin Life to your Home Screen (Share → Add to Home Screen), open it from there, then tap Notify me. Until then this page shows a red badge and plays a sound.'
                : support === 'denied' ? 'Notifications are blocked for this site in your browser settings. This page still shows a red badge and plays a sound.'
                  : 'This browser cannot show notifications. This page still shows a red badge and plays a sound while it is open.'}
          </span>
        </span>
      </div>
      <div className="adm-ad__actions">
        {support === 'ok' && !on && <Btn tone="primary" icon="bell" disabled={busy || !me} onClick={() => void run(enablePush)}>Notify me</Btn>}
        {support === 'ok' && on && <Btn disabled={busy} onClick={() => void run(disablePush)}>Turn off on this device</Btn>}
        {support === 'ok' && on && <Btn disabled={busy} onClick={() => void test()}>Send a test</Btn>}
        {inbox && <span className="adm-sub">{inbox.subscriptions} device{inbox.subscriptions === 1 ? '' : 's'} subscribed</span>}
      </div>
      {inbox && inbox.rows.length > 0 && (
        <div className="adm-inbox">
          <div className="adm-inbox__head">
            <b>Recent alerts</b>{inbox.unread > 0 && <Badge tone="red">{inbox.unread} new</Badge>}
            {inbox.unread > 0 && <Btn small tone="quiet" onClick={() => void markRead()}>Mark all read</Btn>}
          </div>
          {inbox.rows.map((n) => (
            <div key={n.id} className={`adm-inbox__row${n.unread ? ' is-unread' : ''}`}>
              <span className="grow"><b>{n.title}</b><span className="adm-sub">{n.body}</span></span>
              <span className="adm-sub">{timeShort(n.created_at)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
const pad = (n: number) => String(n).padStart(2, '0');
const localInput = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;

function SponsorPane({ boards, onClose, onSaved }: { boards: Queue['boards']; onClose: () => void; onSaved: () => void }) {
  const me = useGame((s) => s.state?.profile.id);
  const [board, setBoard] = useState(boards[0]?.id ?? '');
  const [title, setTitle] = useState('');
  const [image, setImage] = useState('');
  const [preview, setPreview] = useState<string | null>(null);
  const [link, setLink] = useState('');
  const [start, setStart] = useState(() => localInput(new Date()));
  const [end, setEnd] = useState(() => localInput(new Date(Date.now() + 7 * 86_400_000)));
  const [busy, setBusy] = useState(false);
  const upload = async (f: File | undefined) => {
    if (!f || !me) return;
    setBusy(true);
    try {
      const img = await compressAdImage(f);
      const path = `${me}/sponsor-${Date.now().toString(36)}.${img.type === 'image/webp' ? 'webp' : 'jpg'}`;
      const up = await supabase.storage.from('billboard-ads').upload(path, img.blob, { contentType: img.type, cacheControl: '31536000' });
      if (up.error) throw new Error('Upload failed: ' + up.error.message);
      setImage(path);
      setPreview(img.url);
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Upload failed', 'bad');
    } finally {
      setBusy(false);
    }
  };
  const save = async () => {
    setBusy(true);
    try {
      const r = await rpc<{ message: string }>('admin_billboard_sponsor', {
        p_board: board, p_image: image.trim(), p_link: link.trim() || null,
        p_starts: new Date(start).toISOString(), p_ends: new Date(end).toISOString(), p_title: title.trim(),
      });
      toast(r.message, 'good');
      onSaved();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <DetailPane open title="Free sponsor ad" onClose={onClose}
      footer={<><Btn onClick={onClose}>Cancel</Btn><Btn tone="primary" disabled={busy || !board || !image.trim()} onClick={() => void save()}>{busy ? 'Saving…' : 'Place ad'}</Btn></>}>
      <p className="adm-sub">For real-life sponsors: free, goes on air at the start time, audited. It takes turns with the players' ads on that board.</p>
      <div className="adm-field"><label className="adm-field__label">Board</label>
        <select className="adm-input" value={board} onChange={(e) => setBoard(e.target.value)}>
          {boards.map((b) => <option key={b.id} value={b.id}>{b.name} · {b.live} live</option>)}
        </select>
      </div>
      <div className="adm-field"><label className="adm-field__label">Sponsor name (only admins see it)</label>
        <input className="adm-input" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={80} placeholder="e.g. Bronze Bank" />
      </div>
      <div className="adm-field"><label className="adm-field__label">Image (2:1 looks best)</label>
        <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => void upload(e.target.files?.[0])} />
        {preview && <div className="adm-ad__img" style={{ marginTop: 8 }}><img src={preview} alt="" /></div>}
        <input className="adm-input" style={{ marginTop: 8 }} value={image} onChange={(e) => { setImage(e.target.value); setPreview(null); }}
          placeholder="…or paste an https:// image link" />
      </div>
      <div className="adm-field"><label className="adm-field__label">Link (optional, https)</label>
        <input className="adm-input" value={link} onChange={(e) => setLink(e.target.value)} placeholder="https://" />
      </div>
      <div className="adm-field"><label className="adm-field__label">Starts</label>
        <input className="adm-input" type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
      </div>
      <div className="adm-field"><label className="adm-field__label">Ends</label>
        <input className="adm-input" type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
      </div>
    </DetailPane>
  );
}
