// L1: app errors players hit (client_error_log), grouped by message, newest first. Shown on Overview.
import { useState } from 'react';
import { rpc } from '../lib/api';
import { Badge, Btn, LoadError, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

interface ErrorSample { at: string; user: string | null; username: string | null; url: string | null; build: string | null; ua: string | null; stack: string | null }
interface ErrorGroup { message: string; kind: string; count: number; players: number; first: string; last: string; builds: string[] | null; samples: ErrorSample[] | null }
interface ErrorsData { since: string; total: number; players: number; groups: ErrorGroup[] }

const KIND: Record<string, string> = { boundary: 'Crash screen', error: 'Error', rejection: 'Unhandled', chunk: 'Old build' };

export default function ErrorsSection() {
  const [hours, setHours] = useState(72);
  const { data, error, loading, reload } = useLoad(() => rpc<ErrorsData>('admin_client_errors', { p_hours: hours }), [hours]);
  const [open, setOpen] = useState<string | null>(null);
  return (
    <section className="adm-card adm-errors">
      <div className="adm-errors__head">
        <h2 className="adm-h2">App errors</h2>
        <div className="adm-chips">
          {[24, 72, 168].map((h) => (
            <button key={h} type="button" className={`adm-chip${hours === h ? ' is-on' : ''}`} onClick={() => setHours(h)}>
              {h === 24 ? '24 h' : h === 72 ? '3 days' : '7 days'}
            </button>
          ))}
          <Btn small icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>
        </div>
      </div>
      <p className="adm-sub">Crashes and errors players hit in their browser, grouped by message. Tap one for details.</p>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={3} />}
      {data && (
        <>
          <p className="adm-sub"><b>{data.total}</b> reports from <b>{data.players}</b> signed-in players.</p>
          {data.groups.length === 0 && <p className="adm-empty">No errors. Nice.</p>}
          <div className="adm-rows">
            {data.groups.map((g) => (
              <div key={g.message} className="adm-cerr">
                <button type="button" className="adm-cerr__row" onClick={() => setOpen(open === g.message ? null : g.message)} aria-expanded={open === g.message}>
                  <span className="adm-cerr__count">{g.count}×</span>
                  <span className="adm-cerr__msg">{g.message}</span>
                  <span className="adm-cerr__meta">
                    <Badge tone={g.kind === 'boundary' ? 'red' : g.kind === 'chunk' ? 'grey' : 'amber'}>{KIND[g.kind] ?? g.kind}</Badge>
                    <small>{g.players} {g.players === 1 ? 'player' : 'players'} · last {timeShort(g.last)}</small>
                  </span>
                </button>
                {open === g.message && (
                  <div className="adm-cerr__detail">
                    <p className="adm-sub">First seen {timeShort(g.first)}{g.builds?.length ? ` · builds ${g.builds.join(', ')}` : ''}</p>
                    {(g.samples ?? []).map((s, i) => (
                      <div key={i} className="adm-cerr__sample">
                        <div className="adm-sub">{timeShort(s.at)} · {s.username ? `@${s.username}` : 'logged out'} · {s.url ?? ''}</div>
                        {s.ua && <div className="adm-sub adm-cerr__ua">{s.ua}</div>}
                        {s.stack && <pre className="adm-cerr__stack">{s.stack}</pre>}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </>
      )}
    </section>
  );
}
