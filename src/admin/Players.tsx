// Players: search, list and a detail pane with money, ban, mute, origin and admin actions.
import { useEffect, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira, nairaShort, parseNaira } from '../lib/format';
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

const GRANT_CONFIRM_AT = 1_000_000_000; // ₦1B and up asks first
const GRANT_QUICK: [number, string][] = [[1e6, '+1M'], [1e9, '+1B'], [1e12, '+1T']];

/** Give or take money: shorthand input (500K, 2.5M, 5B, 1T), live preview, quick adds, confirm on ≥ ₦1B. */
function GrantMoney({ username, cash, bank, busy, onGrant }: {
  username: string; cash: number; bank: number; busy: boolean;
  onGrant: (account: 'cash' | 'bank', delta: number, note: string) => Promise<void>;
}) {
  const [account, setAccount] = useState<'cash' | 'bank'>('cash');
  const [take, setTake] = useState(false);
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState(false);
  const n = parseNaira(amount);
  const bad = amount.trim() !== '' && n === null;
  const have = account === 'cash' ? cash : bank;
  const tooMuch = take && n !== null && n > have;
  const verb = take ? 'Take' : 'Give';
  const summary = n === null ? '' : `${verb} ${naira(n)} ${take ? 'from' : 'to'} @${username}'s ${account}`;
  const quick = (add: number) => {
    const next = Math.min((n ?? 0) + add, Number.MAX_SAFE_INTEGER);
    setAmount(naira(next).replace('₦', ''));
  };
  const submit = async () => {
    if (n === null) return;
    setConfirming(false);
    await onGrant(account, take ? -n : n, note);
    setAmount('');
  };
  const go = () => {
    if (n === null) { toast('Enter an amount above zero, e.g. 500K, 2.5M, 5B or 1T.', 'bad'); return; }
    if (n >= GRANT_CONFIRM_AT) { setConfirming(true); return; }
    void submit();
  };
  return (
    <section className="adm-box">
      <h3 className="adm-h3">Give or take money</h3>
      <div className="adm-grant__row">
        <div className="adm-chips" role="group" aria-label="Give or take">
          <button type="button" className={`adm-chip${!take ? ' is-on' : ''}`} onClick={() => setTake(false)}>Give</button>
          <button type="button" className={`adm-chip adm-chip--neg${take ? ' is-on' : ''}`} onClick={() => setTake(true)}>Take</button>
        </div>
        <div className="adm-chips" role="group" aria-label="Account">
          {(['cash', 'bank'] as const).map((a) => (
            <button key={a} type="button" className={`adm-chip${account === a ? ' is-on' : ''}`} onClick={() => setAccount(a)}>{a === 'cash' ? 'Cash' : 'Bank'}</button>
          ))}
        </div>
      </div>
      <label className={`adm-numbox adm-numbox--wide${bad ? ' is-invalid' : ''}`}>
        <span className="adm-numbox__affix">{take ? '−₦' : '₦'}</span>
        <input type="text" inputMode="decimal" autoComplete="off" spellCheck={false} placeholder="e.g. 500K, 2.5M, 5B, 1T"
          aria-label="Amount" aria-invalid={bad} value={amount} onChange={(e) => setAmount(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') go(); }} />
      </label>
      <p className={`adm-grant__preview${bad || tooMuch ? ' is-bad' : ''}`} aria-live="polite">
        {bad ? 'Use digits with K, M, B, T or Q, e.g. 2.5M (whole naira only).'
          : n === null ? `They have ${naira(have)} in ${account}.`
          : <>= <b>{take ? '−' : ''}{naira(n)}</b>{nairaShort(n) !== naira(n) && <> ({nairaShort(n)})</>}
            {tooMuch && <> · they only have {naira(have)}</>}</>}
      </p>
      <div className="adm-chips">
        {GRANT_QUICK.map(([v, label]) => (
          <button key={label} type="button" className="adm-chip" onClick={() => quick(v)}>{label}</button>
        ))}
        {amount && <button type="button" className="adm-chip" onClick={() => setAmount('')}>Clear</button>}
      </div>
      <input className="adm-input" placeholder="Note (shown to the player, optional)" maxLength={200} value={note} onChange={(e) => setNote(e.target.value)} />
      <div className="adm-btnrow">
        <Btn tone={take ? 'danger' : 'primary'} disabled={busy || n === null || tooMuch} onClick={go}>
          {n === null ? verb : `${verb} ${nairaShort(n)}`}
        </Btn>
      </div>
      {confirming && n !== null && (
        <div className="adm-dialog" role="dialog" aria-modal="true" aria-labelledby="grant-confirm-title" onClick={() => setConfirming(false)}>
          <div className="adm-dialog__card" onClick={(e) => e.stopPropagation()}>
            <h3 id="grant-confirm-title" className="adm-h3">{take ? 'Take' : 'Give'} {nairaShort(n)}?</h3>
            <p className="adm-dialog__amount">{take ? '−' : ''}{naira(n)}</p>
            <p className="adm-sub">{summary}. New {account} balance: <b>{naira(have + (take ? -n : n))}</b>.</p>
            {note.trim() && <p className="adm-sub">Note: “{note.trim()}”</p>}
            <div className="adm-btnrow">
              <Btn onClick={() => setConfirming(false)}>Cancel</Btn>
              <Btn tone={take ? 'danger' : 'primary'} disabled={busy} autoFocus onClick={() => void submit()}>Yes, {verb.toLowerCase()} it</Btn>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

function Detail({ id, onClose, onChanged }: { id: string; onClose: () => void; onChanged: () => void }) {
  const { data, error, reload } = useLoad(() => adminApi.playerDetail(id), [id]);
  const { data: tiers } = useLoad(() => adminApi.tableRows('origin_tiers'));
  const me = useGame((s) => s.state?.profile.id);
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

          <GrantMoney username={p.username} cash={p.cash} bank={p.bank} busy={busy}
            onGrant={(account, delta, note) => run(() => adminApi.grantMoney(id, account, delta, note))} />

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
                    <b className="adm-money" title={naira(p.cash + p.bank)}>{nairaShort(p.cash + p.bank)}</b>
                    <small title={naira(p.cash)}>{nairaShort(p.cash)} cash</small>
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
