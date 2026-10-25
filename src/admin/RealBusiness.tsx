// Real businesses queue (docs/COMPANIES.md): approve (the pin goes live on the map), reject with a reason (automatic Paystack refund through the
// billboard-refund Edge Function with biz_id), suspend / put back, remove (optionally refund). Photos are shown so you can check them before approving.
// Every action is audited by the database. New submissions reach this page as push notifications and the nav badge.
import { useState } from 'react';
import { realImageUrl } from '../api/company';
import { koboLabel } from '../lib/billboards';
import { errorMessage, rpc } from '../lib/api';
import { flushAdminPush } from '../lib/push';
import { supabase } from '../lib/supabase';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

type Filter = 'review' | 'live' | 'suspended' | 'reported' | 'refunds' | 'ended' | 'all';
const FILTERS: { id: Filter; label: string }[] = [
  { id: 'review', label: 'In review' }, { id: 'live', label: 'Live' }, { id: 'suspended', label: 'Suspended' }, { id: 'reported', label: 'Reported' },
  { id: 'refunds', label: 'Refunds' }, { id: 'ended', label: 'Ended' }, { id: 'all', label: 'All' },
];
interface BizRow {
  id: string; name: string; logo: string; category: string; descr: string; phone: string | null; whatsapp: string | null; instagram: string | null; website: string | null;
  address: string; area_id: string; area: string; slot: string | null; images: string[]; status: string; days: number; price_kobo: number; paid_kobo: number | null;
  paid_at: string | null; created_at: string; starts_at: string | null; ends_at: string | null; reviewer: string | null; reject_reason: string | null; refund_status: string;
  refund_kobo: number | null; refund_error: string | null; reference: string | null; username: string | null; email: string | null; views: number; taps: number; reports: number;
  renewals: number; report_reasons: string[]; company_id: number | null;
}
interface Queue {
  counts: Record<Exclude<Filter, 'all'>, number>; payments_enabled: boolean;
  areas: { id: string; name: string; used: number; cap: number; slots: number }[]; rows: BizRow[];
}
const TONE: Record<string, 'green' | 'amber' | 'red' | 'grey' | 'blue'> = { pending_review: 'amber', live: 'green', rejected: 'red', removed: 'red', suspended: 'red', expired: 'grey', awaiting_payment: 'blue', cancelled: 'grey' };
const LABEL: Record<string, string> = { pending_review: 'In review', live: 'Live', rejected: 'Rejected', removed: 'Removed', suspended: 'Suspended', expired: 'Ended', awaiting_payment: 'Unpaid', cancelled: 'Cancelled' };
const REFUND: Record<string, [string, 'amber' | 'green' | 'red']> = { pending: ['Refund pending', 'amber'], processing: ['Refunding…', 'amber'], refunded: ['Refunded', 'green'], refund_failed: ['Refund failed', 'red'] };

async function runRefund(bizId: string): Promise<boolean> {
  const { data, error } = await supabase.functions.invoke('billboard-refund', { body: { biz_id: bizId } });
  if (!error && data?.ok) { toast('Refund sent through Paystack.', 'good'); return true; }
  let msg = 'Refund failed.';
  try {
    const ctx = (error as { context?: Response } | null)?.context;
    const body = ctx ? await ctx.json() : data;
    if (body?.message) msg = `Refund failed: ${body.message}`;
  } catch { /* generic */ }
  toast(msg + ' It is listed under Refunds; retry or refund in the Paystack dashboard.', 'bad');
  return false;
}

export default function RealBusiness() {
  const [filter, setFilter] = useState<Filter>('review');
  const { data, error, loading, reload } = useLoad(() => rpc<Queue>('admin_real_biz_queue', { p_filter: filter, p_limit: 150 }), [filter]);
  return (
    <div className="adm-page" data-testid="admin-real-business">
      <PageHead title="Real business" sub="Real Benin businesses on the map. Approve to put the pin live; rejecting refunds the owner automatically."
        actions={<Btn icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      {data && !data.payments_enabled && <div className="adm-card adm-pay-off">Owners can't list while <b>payments.enabled</b> is off (Settings).</div>}
      {data && (
        <section className="adm-card"><p className="adm-sub">Pins per area: {data.areas.map((a) => `${a.name} ${a.used}/${a.cap}`).join(' · ')}</p></section>
      )}
      <div className="adm-toolbar"><div className="adm-chips">{FILTERS.map((f) => {
        const n = f.id === 'all' ? null : data?.counts[f.id];
        return <button key={f.id} type="button" className={`adm-chip${filter === f.id ? ' is-on' : ''}`} onClick={() => setFilter(f.id)}>{f.label}{n ? ` · ${n}` : ''}</button>;
      })}</div></div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={4} />}
      {data && (
        <div className="adm-ads">
          {data.rows.length === 0 && <div className="adm-card"><p className="adm-empty">{filter === 'review' ? 'Nothing to review.' : 'Nothing here.'}</p></div>}
          {data.rows.map((r) => <BizCard key={r.id} r={r} onChanged={reload} />)}
        </div>
      )}
    </div>
  );
}

function BizCard({ r, onChanged }: { r: BizRow; onChanged: () => void }) {
  const [mode, setMode] = useState<null | 'reject' | 'suspend' | 'remove'>(null);
  const [reason, setReason] = useState('');
  const [refund, setRefund] = useState(true);
  const [busy, setBusy] = useState(false);
  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try { await fn(); flushAdminPush(); onChanged(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const rf = REFUND[r.refund_status];
  return (
    <article className="adm-card adm-ad" data-testid="real-biz-card">
      <div className="adm-ad__body">
        <div className="adm-ad__top">
          <b>{r.logo} {r.name}</b> <Badge tone={TONE[r.status] ?? 'grey'}>{LABEL[r.status] ?? r.status}</Badge>
          {rf && <Badge tone={rf[1]}>{rf[0]}</Badge>}
        </div>
        <p className="adm-sub">@{r.username ?? 'deleted'} · {r.email ?? ''} · {r.category} · {r.area}{r.slot ? ` (${r.slot})` : ''}</p>
        <p>{r.descr}</p>
        <p className="adm-sub">📍 {r.address}</p>
        <p className="adm-sub">{[r.phone && `☎ ${r.phone}`, r.whatsapp && `WhatsApp ${r.whatsapp}`, r.instagram && `IG @${r.instagram}`, r.website].filter(Boolean).join(' · ')}</p>
        <div className="adm-ad__imgs" style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {r.images.map((p) => <a key={p} href={realImageUrl(p)} target="_blank" rel="noopener noreferrer"><img src={realImageUrl(p)} alt="" style={{ width: 120, height: 90, objectFit: 'cover', borderRadius: 10 }} /></a>)}
        </div>
        <p className="adm-sub">
          {r.paid_kobo ? `Paid ${koboLabel(r.paid_kobo)} ${r.paid_at ? timeShort(r.paid_at) : ''}` : 'Not paid'} · {r.days} days{r.ends_at ? ` · ends ${timeShort(r.ends_at)}` : ''}
          {r.renewals ? ` · renewed ${r.renewals}×` : ''} · {r.views} views · {r.taps} taps{r.reports ? ` · ${r.reports} report${r.reports > 1 ? 's' : ''}` : ''}
        </p>
        {r.report_reasons.length > 0 && <p className="adm-sub">Reports: {r.report_reasons.join(' / ')}</p>}
        {r.reject_reason && <p className="adm-sub">Reason: {r.reject_reason}</p>}
        {r.refund_error && <p className="adm-sub">Refund error: {r.refund_error}</p>}
        {r.reference && <p className="adm-sub adm-mono">{r.reference}</p>}
      </div>
      <div className="adm-ad__actions">
        {r.status === 'pending_review' && <Btn tone="primary" disabled={busy} onClick={() => act(async () => toast((await rpc<{ message: string }>('admin_real_biz_approve', { p_id: r.id })).message, 'good'))}>Approve</Btn>}
        {r.status === 'pending_review' && <Btn tone="danger" disabled={busy} onClick={() => { setMode('reject'); setRefund(true); }}>Reject</Btn>}
        {r.status === 'live' && <Btn disabled={busy} onClick={() => setMode('suspend')}>Suspend</Btn>}
        {r.status === 'suspended' && <Btn tone="primary" disabled={busy} onClick={() => act(async () => toast((await rpc<{ message: string }>('admin_real_biz_unsuspend', { p_id: r.id })).message, 'good'))}>Put back</Btn>}
        {['live', 'suspended', 'pending_review'].includes(r.status) && <Btn tone="danger" disabled={busy} onClick={() => { setMode('remove'); setRefund(false); }}>Remove</Btn>}
        {['pending', 'refund_failed', 'processing'].includes(r.refund_status) && (
          <ConfirmButton small confirmText="Tap again: refund" onConfirm={() => act(async () => { await rpc('admin_real_biz_refund_start', { p_id: r.id }).catch(() => {}); await runRefund(r.id); })}>{r.refund_status === 'refund_failed' ? 'Retry refund' : 'Refund now'}</ConfirmButton>
        )}
      </div>
      {mode && (
        <div className="adm-ad__form">
          <label className="adm-field"><span className="adm-field__label">Reason (the owner sees it)</span>
            <input className="adm-input" value={reason} maxLength={300} onChange={(e) => setReason(e.target.value)} /></label>
          {mode !== 'suspend' && <label className="adm-check"><input type="checkbox" checked={refund} onChange={(e) => setRefund(e.target.checked)} /> Refund the owner</label>}
          <Btn tone="danger" disabled={busy || (mode !== 'remove' && !reason.trim())} onClick={() => act(async () => {
            const fn = mode === 'reject' ? 'admin_real_biz_reject' : mode === 'suspend' ? 'admin_real_biz_suspend' : 'admin_real_biz_remove';
            const args = mode === 'suspend' ? { p_id: r.id, p_reason: reason } : { p_id: r.id, p_reason: reason, p_refund: refund };
            const out = await rpc<{ message: string; refund?: boolean }>(fn, args);
            toast(out.message, 'good');
            setMode(null);
            if (out.refund) await runRefund(r.id);
          })}>Confirm {mode}</Btn>
          <Btn onClick={() => setMode(null)}>Cancel</Btn>
        </div>
      )}
    </article>
  );
}
