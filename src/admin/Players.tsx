// Players: search, list and a detail pane with money, ban, mute, origin and admin actions.
import { useEffect, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira, nairaShort } from '../lib/format';
import { useGame } from '../state/game';
import { adminApi, type PlayerDetail, type PlayerRow } from './api';
import { Badge, Btn, ConfirmButton, DetailPane, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const MUTES = [
  { label: '15 min', minutes: 15 }, { label: '1 hour', minutes: 60 }, { label: '1 day', minutes: 1440 }, { label: '7 days', minutes: 10080 },
];

function isMuted(until: string | null | undefined) {
  return !!until && new Date(until).getTime() > Date.now();
}

function PlayerBadges({ p }: { p: Pick<PlayerRow, 'banned' | 'is_admin' | 'chat_muted_until' | 'origin'> }) {
  return (
    <>
      <Badge tone={p.origin === 'nepo' ? 'violet' : 'grey'}>{p.origin === 'nepo' ? 'Nepo' : p.origin === 'lapo' ? 'LAPO' : p.origin}</Badge>
      {p.is_admin && <Badge tone="blue">Admin</Badge>}
      {p.banned && <Badge tone="red">Banned</Badge>}
      {isMuted(p.chat_muted_until) && <Badge tone="amber">Muted</Badge>}
    </>
  );
}

function Detail({ id, onClose, onChanged }: { id: string; onClose: () => void; onChanged: () => void }) {
  const { data, error, reload } = useLoad(() => adminApi.playerDetail(id), [id]);
  const { data: tiers } = useLoad(() => adminApi.tableRows('origin_tiers'));
  const me = useGame((s) => s.state?.profile.id);
  const [account, setAccount] = useState<'cash' | 'bank'>('cash');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [origin, setOrigin] = useState('');
  const [perks, setPerks] = useState(true);
  const [busy, setBusy] = useState(false);

  const run = async (fn: () => Promise<{ message: string }>) => {
    setBusy(true);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await reload();
      onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const money = (sign: 1 | -1) => {
    const n = Math.round(Number(amount));
    if (!Number.isFinite(n) || n <= 0) { toast('Enter an amount above zero.', 'bad'); return; }
    void run(() => adminApi.grantMoney(id, account, sign * n, note)).then(() => setAmount(''));
  };

  const p = data?.profile as PlayerDetail['profile'] | undefined;
  const pick = origin || String(p?.origin ?? '');
  return (
    <DetailPane open title={p ? `@${p.username}` : 'Player'} onClose={onClose}>
      {error && <LoadError error={error} onRetry={reload} />}
      {!p && !error && <Skeleton rows={5} />}
      {p && data && (
        <div className="adm-stack">
          <div className="adm-badges"><PlayerBadges p={p} />{p.id === me && <Badge tone="green">You</Badge>}</div>
          <div className="adm-balances">
            <div><span className="adm-kicker">Cash</span><b className="adm-money">{naira(p.cash)}</b></div>
            <div><span className="adm-kicker">Bank</span><b className="adm-money">{naira(p.bank)}</b></div>
          </div>
          <dl className="adm-dl">
            <dt>Email</dt><dd>{p.email ?? '—'}</dd>
            <dt>Where</dt><dd>{p.location_name ?? p.location_id}</dd>
            <dt>Job</dt><dd>{p.job_id ? `${p.job_title ?? p.job_id} (L${p.job_level})` : 'No job'}</dd>
            <dt>Joined</dt><dd>{new Date(p.created_at).toLocaleString()}</dd>
            <dt>Last seen</dt><dd>{timeShort(p.last_seen)}</dd>
            {isMuted(p.chat_muted_until) && <><dt>Muted until</dt><dd>{new Date(p.chat_muted_until!).toLocaleString()}</dd></>}
          </dl>

          <section className="adm-box">
            <h3 className="adm-h3">Give or take money</h3>
            <div className="adm-chips">
              {(['cash', 'bank'] as const).map((a) => (
                <button key={a} type="button" className={`adm-chip${account === a ? ' is-on' : ''}`} onClick={() => setAccount(a)}>{a === 'cash' ? 'Cash' : 'Bank'}</button>
              ))}
            </div>
            <label className="adm-numbox adm-numbox--wide">
              <span className="adm-numbox__affix">₦</span>
              <input type="number" inputMode="numeric" min={1} placeholder="Amount" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </label>
            <input className="adm-input" placeholder="Note (shown to the player, optional)" maxLength={200} value={note} onChange={(e) => setNote(e.target.value)} />
            <div className="adm-btnrow">
              <Btn tone="primary" disabled={busy} onClick={() => money(1)}>Add</Btn>
              <Btn tone="danger" disabled={busy} onClick={() => money(-1)}>Take</Btn>
            </div>
          </section>

          <section className="adm-box">
            <h3 className="adm-h3">Chat mute</h3>
            <div className="adm-chips">
              {MUTES.map((m) => (
                <button key={m.minutes} type="button" className="adm-chip" disabled={busy} onClick={() => run(() => adminApi.mute(id, m.minutes))}>{m.label}</button>
              ))}
              {isMuted(p.chat_muted_until) && (
                <button type="button" className="adm-chip is-on" disabled={busy} onClick={() => run(() => adminApi.mute(id, 0))}>Unmute</button>
              )}
            </div>
          </section>

          <section className="adm-box">
            <h3 className="adm-h3">Origin</h3>
            <div className="adm-chips">
              {(tiers ?? []).map((t) => (
                <button key={String(t.id)} type="button" className={`adm-chip${pick === t.id ? ' is-on' : ''}`} onClick={() => setOrigin(String(t.id))}>{String(t.name)}</button>
              ))}
            </div>
            <label className="adm-check">
              <input type="checkbox" checked={perks} onChange={(e) => setPerks(e.target.checked)} />
              Also send the new origin’s starter money and items
            </label>
            <Btn disabled={busy || pick === p.origin} onClick={() => run(() => adminApi.setOrigin(id, pick, perks))}>Set origin</Btn>
          </section>

          <section className="adm-box">
            <h3 className="adm-h3">Access</h3>
            <div className="adm-btnrow">
              {p.banned
                ? <Btn tone="primary" disabled={busy} onClick={() => run(() => adminApi.ban(id, false))}>Unban</Btn>
                : <ConfirmButton disabled={busy || p.id === me} onConfirm={() => run(() => adminApi.ban(id, true, 'admin panel'))}>Ban player</ConfirmButton>}
              {p.is_admin
                ? <ConfirmButton tone="ghost" disabled={busy} onConfirm={() => run(() => adminApi.setAdmin(id, false))}>Remove admin</ConfirmButton>
                : <ConfirmButton tone="ghost" confirmText="Tap again: make admin" disabled={busy} onConfirm={() => run(() => adminApi.setAdmin(id, true))}>Make admin</ConfirmButton>}
            </div>
          </section>

          <section>
            <h3 className="adm-h3">Recent money</h3>
            <div className="adm-ledger">
              {data.ledger.length === 0 && <p className="adm-empty">No money moves yet.</p>}
              {data.ledger.map((l) => (
                <div key={l.id} className="adm-ledger__row">
                  <span className="adm-ledger__label">{l.label}<small>{l.account} · {timeShort(l.created_at)}</small></span>
                  <span className={`adm-money ${l.delta >= 0 ? 'is-pos' : 'is-neg'}`}>{l.delta >= 0 ? '+' : '−'}{naira(Math.abs(l.delta))}</span>
                </div>
              ))}
            </div>
          </section>
          {data.inventory.length > 0 && (
            <section>
              <h3 className="adm-h3">Bag</h3>
              <p className="adm-sub">{data.inventory.map((i) => `${i.name ?? i.item_id} ×${i.qty}`).join(' · ')}</p>
            </section>
          )}
          {data.audit.length > 0 && (
            <section>
              <h3 className="adm-h3">Admin history</h3>
              <ul className="adm-mini">
                {data.audit.map((a) => <li key={a.id}><b>{a.action.replace(/_/g, ' ')}</b> by {a.admin ?? 'system'} · {timeShort(a.created_at)}</li>)}
              </ul>
            </section>
          )}
        </div>
      )}
    </DetailPane>
  );
}

export default function Players() {
  const [q, setQ] = useState('');
  const [debounced, setDebounced] = useState('');
  const [page, setPage] = useState(0);
  const [sel, setSel] = useState<string | null>(null);
  const PAGE = 40;
  useEffect(() => { const t = window.setTimeout(() => { setDebounced(q); setPage(0); }, 250); return () => window.clearTimeout(t); }, [q]);
  const { data, error, loading, reload } = useLoad(() => adminApi.players(debounced, PAGE, page * PAGE), [debounced, page]);

  return (
    <div className="adm-page">
      <PageHead title="Players" sub={data ? `${data.total} ${data.total === 1 ? 'player' : 'players'}${debounced ? ' match' : ''}` : ' '} />
      <div className={`adm-split${sel ? ' has-detail' : ''}`}>
        <div className="adm-split__main">
          <div className="adm-toolbar">
            <label className="adm-search">
              <span aria-hidden>🔎</span>
              <input type="search" placeholder="Search name or email…" value={q} onChange={(e) => setQ(e.target.value)} />
            </label>
            <Btn icon="refresh" onClick={reload} aria-label="Refresh" />
          </div>
          {error && <LoadError error={error} onRetry={reload} />}
          {!data && loading && <Skeleton rows={8} />}
          {data && (
            <div className="adm-card adm-rows">
              {data.rows.length === 0 && <p className="adm-empty">No players found.</p>}
              {data.rows.map((p) => (
                <button key={p.id} type="button" className={`adm-row adm-row--player${sel === p.id ? ' is-selected' : ''}`} onClick={() => setSel(p.id)}>
                  <span className={`adm-avatar${p.online ? ' is-online' : ''}`} aria-hidden>{p.username.slice(0, 1).toUpperCase()}</span>
                  <span className="adm-row__main adm-row__main--static">
                    <span className="adm-row__title">{p.username} <PlayerBadges p={p} /></span>
                    <span className="adm-row__sub">{p.online ? 'Online' : timeShort(p.last_seen)} · {p.location_name ?? p.location_id}{p.job_id ? ` · ${p.job_id}` : ''}</span>
                  </span>
                  <span className="adm-row__money">
                    <b className="adm-money">{nairaShort(p.cash + p.bank)}</b>
                    <small>{nairaShort(p.cash)} cash</small>
                  </span>
                </button>
              ))}
            </div>
          )}
          {data && data.total > PAGE && (
            <div className="adm-pager">
              <Btn small disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Btn>
              <span>Page {page + 1} of {Math.ceil(data.total / PAGE)}</span>
              <Btn small disabled={(page + 1) * PAGE >= data.total} onClick={() => setPage(page + 1)}>Next</Btn>
            </div>
          )}
        </div>
        {sel && <Detail key={sel} id={sel} onClose={() => setSel(null)} onChanged={reload} />}
      </div>
    </div>
  );
}
