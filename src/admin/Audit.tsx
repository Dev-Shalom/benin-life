// Audit log: config changes and admin actions, newest first. Config changes can be restored.
import { useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { adminApi, type AuditEntry } from './api';
import { Badge, Btn, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const show = (v: unknown) => (v === undefined || v === null ? '—' : typeof v === 'string' ? (v === '' ? '(empty)' : v) : JSON.stringify(v));

function summary(a: AuditEntry): string {
  const d = (a.data ?? {}) as Record<string, unknown>;
  switch (a.action) {
    case 'grant_money': return `${Number(d.delta) >= 0 ? 'Gave' : 'Took'} ${naira(Math.abs(Number(d.delta)))} (${d.account})${d.note ? ` · “${d.note}”` : ''}`;
    case 'mute': return `Muted for ${d.minutes} min`;
    case 'set_origin': return `Origin ${d.old} → ${d.new}${d.apply_perks ? ' (with perks)' : ''}`;
    case 'row_update': case 'row_insert': {
      const row = (d.row ?? {}) as Record<string, unknown>;
      const id = row.id ?? row.word ?? `${row.track_id} L${row.level}`;
      const fields = Object.keys(row).filter((k) => !['id', 'word', 'track_id', 'level'].includes(k));
      return `${a.action === 'row_insert' ? 'Added' : 'Edited'} ${d.table} · ${id}${fields.length ? ` · ${fields.join(', ')}` : ''}`;
    }
    case 'chat_hide': case 'chat_unhide': return `“${String(d.body ?? '').slice(0, 80)}”`;
    case 'ban': case 'unban': return d.reason ? String(d.reason) : '';
    case 'admin_claim': return `Claimed with ${d.email}`;
    default: return '';
  }
}

export default function Audit() {
  const { data, error, loading, reload } = useLoad(() => adminApi.audit(200));
  const [filter, setFilter] = useState<'all' | 'config' | 'admin'>('all');
  const [busy, setBusy] = useState<string | null>(null);
  const list = (data ?? []).filter((a) => filter === 'all' || a.type === filter);

  return (
    <div className="adm-page">
      <PageHead title="Audit log" sub="Every change made by admins (and the game’s own automatic changes)."
        actions={<Btn icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      <div className="adm-chips adm-toolbar">
        {(['all', 'config', 'admin'] as const).map((f) => (
          <button key={f} type="button" className={`adm-chip${filter === f ? ' is-on' : ''}`} onClick={() => setFilter(f)}>
            {f === 'all' ? 'Everything' : f === 'config' ? 'Settings' : 'Players & content'}
          </button>
        ))}
      </div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={8} />}
      {data && (
        <div className="adm-card adm-rows">
          {list.length === 0 && <p className="adm-empty">No changes yet.</p>}
          {list.map((a) => (
            <div key={a.id} className="adm-audit">
              <span className={`adm-audit__dot is-${a.type}`} aria-hidden />
              <div className="adm-audit__main">
                <div className="adm-audit__line">
                  {a.type === 'config' ? (
                    <><code className="adm-cfg__key">{a.key}</code> <span className="adm-audit__change">{show(a.old_value)} → <b>{show(a.new_value)}</b></span></>
                  ) : (
                    <><Badge tone={a.action.includes('ban') ? 'red' : a.action.includes('admin') ? 'blue' : 'grey'}>{a.action.replace(/_/g, ' ')}</Badge>
                      {a.target && <b> @{a.target}</b>} <span className="adm-audit__change">{summary(a)}</span></>
                  )}
                </div>
                <div className="adm-sub">{a.admin} · {timeShort(a.created_at)} · {new Date(a.created_at).toLocaleString()}</div>
              </div>
              {a.type === 'config' && a.old_value !== null && a.old_value !== undefined && (
                <Btn small tone="quiet" disabled={busy === a.id} title="Set this setting back to the old value"
                  onClick={async () => {
                    setBusy(a.id);
                    try { const r = await adminApi.configRevert(a.audit_id); toast(r.message, 'good'); await reload(); }
                    catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
                  }}>↺ Restore old</Btn>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
