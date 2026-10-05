// Chat moderation: reported messages with hide / unhide and a quick mute for the author.
import { useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { adminApi, type ChatReport } from './api';
import { Badge, Btn, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

export default function Chat() {
  const { data, setData, error, loading, reload } = useLoad(() => adminApi.chatReports());
  const [showHidden, setShowHidden] = useState(false);
  const [busy, setBusy] = useState<number | null>(null);

  const act = async (r: ChatReport, fn: () => Promise<{ message: string }>, patch?: Partial<ChatReport>) => {
    setBusy(r.id);
    try {
      const res = await fn();
      toast(res.message, 'good');
      if (patch && data) setData(data.map((x) => (x.id === r.id ? { ...x, ...patch } : x)));
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };

  const list = (data ?? []).filter((r) => showHidden || !r.hidden);
  const hiddenCount = (data ?? []).filter((r) => r.hidden).length;

  return (
    <div className="adm-page">
      <PageHead title="Chat reports" sub="Messages players reported. Hidden messages disappear for everyone."
        actions={<Btn icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      <div className="adm-toolbar">
        <div className="adm-chips">
          <button type="button" className={`adm-chip${!showHidden ? ' is-on' : ''}`} onClick={() => setShowHidden(false)}>Waiting <span className="adm-chip__n">{(data ?? []).length - hiddenCount}</span></button>
          <button type="button" className={`adm-chip${showHidden ? ' is-on' : ''}`} onClick={() => setShowHidden(true)}>All <span className="adm-chip__n">{(data ?? []).length}</span></button>
        </div>
      </div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={5} />}
      {data && (
        <div className="adm-stack">
          {list.length === 0 && <div className="adm-card"><p className="adm-empty">Nothing to review. 🎉</p></div>}
          {list.map((r) => (
            <article key={r.id} className={`adm-card adm-report${r.hidden ? ' is-off' : ''}`}>
              <div className="adm-report__head">
                <b>@{r.username}</b>
                <span className="adm-sub">at {r.location_name ?? r.location_id} · {timeShort(r.created_at)}</span>
                <Badge tone={r.reports >= 3 ? 'red' : 'amber'}>{r.reports} {r.reports === 1 ? 'report' : 'reports'}</Badge>
                {r.hidden && <Badge>Hidden</Badge>}
              </div>
              <p className="adm-report__body">{r.body}</p>
              <p className="adm-sub">
                {r.reasons?.length ? `Reasons: ${r.reasons.join(', ')} · ` : ''}Reported by {r.reporters.filter(Boolean).join(', ')}
              </p>
              <div className="adm-btnrow">
                {r.hidden
                  ? <Btn small disabled={busy === r.id} onClick={() => act(r, () => adminApi.chatHide(r.id, false), { hidden: false })}>Unhide</Btn>
                  : <Btn small tone="danger" disabled={busy === r.id} onClick={() => act(r, () => adminApi.chatHide(r.id, true), { hidden: true })}>Hide message</Btn>}
                <Btn small disabled={busy === r.id} onClick={() => act(r, () => adminApi.mute(r.user_id, 60))}>Mute author 1 h</Btn>
                <Btn small tone="quiet" disabled={busy === r.id} onClick={() => act(r, () => adminApi.mute(r.user_id, 1440))}>Mute 1 day</Btn>
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
