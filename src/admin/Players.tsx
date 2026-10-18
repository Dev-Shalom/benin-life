// Players: search, list and a detail pane with money, ban, mute, origin and admin actions.
import { useEffect, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira, nairaShort, parseNaira } from '../lib/format';
import { useGame } from '../state/game';
import { adminApi, type CharmRow, type JailCaseRow, type PlayerDetail, type PlayerRow, type PlayerSkillRow } from './api';
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

          <section className="adm-box">
            <h3 className="adm-h3">Sending money</h3>
            <p className="adm-sub">
              {p.transfer_trusted
                ? 'Allowed: this player can send money now, even as a new account.'
                : 'New accounts wait before they can send money. Allow this player to skip the wait.'}
            </p>
            <div className="adm-btnrow">
              {p.transfer_trusted
                ? <ConfirmButton tone="ghost" confirmText="Tap again: remove" disabled={busy} onConfirm={() => run(() => adminApi.setTransferTrusted(id, false))}>Remove permission</ConfirmButton>
                : <ConfirmButton tone="primary" confirmText="Tap again: allow sending" disabled={busy} onConfirm={() => run(() => adminApi.setTransferTrusted(id, true))}>Allow to send money now</ConfirmButton>}
            </div>
          </section>

          <PlayerSkills id={id} />

          <PlayerLounge id={id} />

          <PlayerHouseUpgrades id={id} />

          <PlayerCertificates id={id} />

          <PlayerCharms id={id} />

          {!p.is_admin && p.id !== me && (
            <DeleteAccount id={id} username={p.username} onDeleted={() => { onChanged(); onClose(); }} />
          )}

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
          <JailCases onOpen={setSel} />
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

/** S1: permanently delete a player's account (edge function admin-delete-user). Type the username + a reason. */
function DeleteAccount({ id, username, onDeleted }: { id: string; username: string; onDeleted: () => void }) {
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const ready = confirm.trim().toLowerCase() === username.toLowerCase() && reason.trim().length >= 3;
  const go = async () => {
    setBusy(true);
    setErr(null);
    try {
      const r = await adminApi.deleteUser(id, confirm.trim(), reason.trim());
      toast(r.message, 'good');
      onDeleted();
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };
  return (
    <section className="adm-box adm-danger-zone">
      <h3 className="adm-h3">Delete account</h3>
      {!open ? (
        <>
          <p className="adm-sub">Removes the login, the Sim, money, chats, DMs, furniture, ads and every other row for good. Payments stay in the books without a name. This cannot be undone.</p>
          <Btn tone="danger" onClick={() => setOpen(true)}>Delete account…</Btn>
        </>
      ) : (
        <div className="adm-stack">
          <label className="adm-field"><span className="adm-field__label">Type <b>{username}</b> to confirm</span>
            <input className="adm-input" autoComplete="off" value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder={username} />
          </label>
          <label className="adm-field"><span className="adm-field__label">Reason (kept in the audit log)</span>
            <input className="adm-input" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Player asked to delete their account" />
          </label>
          {err && <p className="adm-error" role="alert">{err}</p>}
          <div className="adm-btnrow">
            <Btn tone="danger" disabled={!ready || busy} onClick={() => void go()}>{busy ? 'Deleting…' : `Delete @${username} forever`}</Btn>
            <Btn disabled={busy} onClick={() => { setOpen(false); setConfirm(''); setReason(''); setErr(null); }}>Cancel</Btn>
          </div>
        </div>
      )}
    </section>
  );
}

/** C1: open jail cases (pickpocket arrests) with an audited Release. */
function JailCases({ onOpen }: { onOpen: (id: string) => void }) {
  const { data, reload } = useLoad(() => adminApi.jailCases('open'));
  const [busy, setBusy] = useState<number | null>(null);
  const rows: JailCaseRow[] = data?.rows ?? [];
  if (!rows.length) return null;
  const release = async (c: JailCaseRow) => {
    setBusy(c.id);
    try {
      const r = await adminApi.jailRelease(c.id, 'Released from Admin → Players');
      toast(r.message, 'good');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <section className="adm-box adm-jail">
      <h3 className="adm-h3">🚓 Open jail cases ({rows.length})</h3>
      <div className="adm-rows">
        {rows.map((c) => {
          const left = Math.max(0, Math.ceil((Date.parse(c.jail_until) - Date.now()) / 1000));
          return (
            <div key={c.id} className="adm-ledger__row">
              <button type="button" className="adm-ledger__label adm-linklike" onClick={() => onOpen(c.user_id)}>
                @{c.username} · {c.reason}
                <small>Bail {naira(c.bail_amount)} · {c.escape_attempts} failed escape{c.escape_attempts === 1 ? '' : 's'} · {left}s left · {c.decided ? 'serving' : 'deciding'}</small>
              </button>
              <ConfirmButton tone="ghost" confirmText="Tap again: release" disabled={busy !== null} onConfirm={() => void release(c)}>Release</ConfirmButton>
            </div>
          );
        })}
      </div>
    </section>
  );
}

/** B2: a player's charms from Baba's Shrine (and Baba's curses): see them, clear one or all (audited). */
function PlayerCharms({ id }: { id: string }) {
  const { data, reload } = useLoad(() => adminApi.playerCharms(id), [id]);
  const [busy, setBusy] = useState(false);
  const rows: CharmRow[] = data?.rows ?? [];
  const live = rows.filter((r) => r.live);
  const clear = async (charm: number | null) => {
    setBusy(true);
    try {
      const r = await adminApi.charmClear(id, charm);
      toast(r.message, 'good');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <section className="adm-box" data-testid="adm-charms">
      <h3 className="adm-h3">🪔 Charms ({live.length} active)</h3>
      {rows.length === 0 && <p className="adm-empty">No charms from Baba's Shrine.</p>}
      <div className="adm-rows">
        {rows.slice(0, 12).map((c) => (
          <div key={c.id} className="adm-ledger__row">
            <span className="adm-ledger__label">
              {c.icon} {c.name}{c.debuff ? ' (curse)' : ''}
              <small>
                {c.live ? 'active' : c.status}
                {c.expires_at ? ` · ends ${timeShort(c.expires_at)}` : ''}
                {c.uses_left != null ? ` · ${c.uses_left} uses left` : ''}
                {c.effect ? ` · ${c.effect}` : ''}
              </small>
            </span>
            {c.live && <ConfirmButton tone="ghost" small confirmText="Tap again: clear" disabled={busy} onConfirm={() => void clear(c.id)}>Clear</ConfirmButton>}
          </div>
        ))}
      </div>
      {live.length > 1 && (
        <div className="adm-btnrow">
          <ConfirmButton tone="ghost" confirmText="Tap again: clear all" disabled={busy} onConfirm={() => void clear(null)}>Clear all charms</ConfirmButton>
        </div>
      )}
    </section>
  );
}

/** R4: a player's certificates, with grant and revoke (both audited: grant_cert / revoke_cert). */
function PlayerCertificates({ id }: { id: string }) {
  const { data, reload } = useLoad(() => adminApi.playerCerts(id), [id]);
  const [busy, setBusy] = useState<string | null>(null);
  const [pick, setPick] = useState('');
  const [note, setNote] = useState('');
  const missing = (data?.catalog ?? []).filter((c) => !c.has);
  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      setPick('');
      setNote('');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <section className="adm-box" data-testid="adm-certs">
      <h3 className="adm-h3">🎓 Certificates</h3>
      {data && data.rows.length === 0 && <p className="adm-empty">No certificates yet.</p>}
      <div className="adm-rows">
        {(data?.rows ?? []).map((r) => (
          <div key={r.id} className="adm-ledger__row" data-testid={`adm-cert-${r.id}`}>
            <span className="adm-ledger__label">
              {r.icon} {r.name}
              <small>{r.source === 'admin' ? 'Granted by an admin' : `Earned in ${r.course_id ?? 'a course'}`} · {timeShort(r.earned_at)}</small>
            </span>
            <ConfirmButton tone="ghost" confirmText="Tap again: remove" disabled={busy !== null} onConfirm={() => void run(`r:${r.id}`, () => adminApi.revokeCert(id, r.id, note.trim() || null))}>Revoke</ConfirmButton>
          </div>
        ))}
      </div>
      {(data?.courses ?? []).filter((c) => c.status === 'enrolled').length > 0 && (
        <p className="adm-sub">In progress: {(data?.courses ?? []).filter((c) => c.status === 'enrolled').map((c) => `${c.name} ${c.done}/${c.classes}`).join(' · ')}</p>
      )}
      <div className="adm-btnrow">
        <select className="adm-input" aria-label="Certificate to grant" value={pick} onChange={(e) => setPick(e.target.value)} disabled={busy !== null}>
          <option value="">Grant a certificate…</option>
          {missing.map((c) => <option key={c.id} value={c.id}>{c.icon} {c.name}</option>)}
        </select>
        <input className="adm-input" placeholder="Note (audit log)" aria-label="Note" value={note} maxLength={120} onChange={(e) => setNote(e.target.value)} />
        <Btn tone="primary" small disabled={busy !== null || !pick} onClick={() => void run(`g:${pick}`, () => adminApi.grantCert(id, pick, note.trim() || null))}>Grant</Btn>
      </div>
    </section>
  );
}

/** R7: a player's Members' Lounge membership (tier, expiry, vouchers) with Grant (audited, free) and Remove. */
function PlayerLounge({ id }: { id: string }) {
  const { data, reload } = useLoad(() => adminApi.loungeGet(id), [id]);
  const [busy, setBusy] = useState(false);
  const [tier, setTier] = useState('');
  const [hours, setHours] = useState('');
  const m = data?.member ?? null;
  const pick = tier || data?.tiers?.[0]?.id || '';
  const act = async (fn: () => Promise<{ message: string }>) => {
    setBusy(true);
    try { const r = await fn(); toast(r.message, 'good'); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <section className="adm-box" data-testid="adm-lounge">
      <h3 className="adm-h3">🛋️ The Lounge</h3>
      {data && !m && <p className="adm-empty">No membership.</p>}
      {m && (
        <p className="adm-note">
          <b>{m.tier_name}</b> · {m.active ? 'active' : 'ended'} · until {timeShort(m.expires_at)} · {m.vouchers_left} free drink{m.vouchers_left === 1 ? '' : 's'} ·{' '}
          {m.source === 'admin' ? 'gift from admin' : `paid ${naira(m.paid_total)}`}
        </p>
      )}
      {(data?.guest_passes?.length ?? 0) > 0 && <p className="adm-note">Guest pass from {data!.guest_passes.map((g) => `@${g.host}`).join(', ')}</p>}
      <div className="adm-btnrow">
        <select className="adm-input" aria-label="Tier" value={pick} onChange={(e) => setTier(e.target.value)}>
          {(data?.tiers ?? []).map((t) => <option key={t.id} value={t.id}>{t.name} ({t.hours}h)</option>)}
        </select>
        <input className="adm-input" type="number" min={1} inputMode="numeric" placeholder="Hours (default)" aria-label="Hours override" style={{ width: 130 }}
          value={hours} onChange={(e) => setHours(e.target.value)} />
        <ConfirmButton tone="primary" confirmText="Tap again: grant free" disabled={busy || !pick}
          onConfirm={() => act(() => adminApi.loungeGrant(id, pick, hours.trim() === '' ? null : Math.max(1, Math.floor(Number(hours)))))}>Grant membership</ConfirmButton>
        {m && <ConfirmButton tone="ghost" confirmText="Tap again: remove" disabled={busy} onConfirm={() => act(() => adminApi.loungeRevoke(id))}>Remove</ConfirmButton>}
      </div>
    </section>
  );
}

/** R8: a player's house upgrades (done / building) with a free, instant, audited Grant (house_upgrade_grant). */
function PlayerHouseUpgrades({ id }: { id: string }) {
  const { data, reload } = useLoad(() => adminApi.houseUpgradeGet(id), [id]);
  const [busy, setBusy] = useState(false);
  const [pick, setPick] = useState('');
  const choice = pick || data?.options?.[0]?.id || '';
  const act = async () => {
    setBusy(true);
    try { const r = await adminApi.houseUpgradeGrant(id, choice); toast(r.message, 'good'); setPick(''); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <section className="adm-box" data-testid="adm-house-upgrades">
      <h3 className="adm-h3">🏗️ House upgrades</h3>
      {data && <p className="adm-note">Home type: <b>{data.kind.replace('_', ' ')}</b>{data.start_home ? ` (${data.start_home})` : ''}</p>}
      {data && data.rows.length === 0 && <p className="adm-empty">No upgrades built.</p>}
      {(data?.rows ?? []).map((r) => (
        <p key={r.id} className="adm-note">
          {r.emoji} <b>{r.name}</b> · {r.state === 'done' ? `done ${r.done_at ? timeShort(r.done_at) : ''}` : `builders working, ready ${timeShort(r.ready_at)}`} · {r.source === 'admin' ? 'gift from admin' : `paid ${naira(r.paid)}`}
        </p>
      ))}
      <div className="adm-btnrow">
        <select className="adm-input" aria-label="Upgrade to grant" value={choice} onChange={(e) => setPick(e.target.value)} disabled={!data?.options?.length}>
          {(data?.options ?? []).map((o) => <option key={o.id} value={o.id}>{o.emoji} {o.name}</option>)}
        </select>
        <ConfirmButton tone="primary" confirmText="Tap again: grant free" disabled={busy || !choice} onConfirm={act}>Grant upgrade</ConfirmButton>
      </div>
    </section>
  );
}

/** R3: a player's skills (level, XP) with a level picker and an exact-XP box per skill. Every change is audited (set_skill). */
function PlayerSkills({ id }: { id: string }) {
  const { data, reload } = useLoad(() => adminApi.playerSkills(id), [id]);
  const [busy, setBusy] = useState<string | null>(null);
  const [xpIn, setXpIn] = useState<Record<string, string>>({});
  const rows: PlayerSkillRow[] = data?.rows ?? [];
  const max = data?.max_level ?? 10;
  const set = async (skill: string, level: number | null, xp: number | null) => {
    setBusy(skill);
    try {
      const r = await adminApi.setPlayerSkill(id, skill, level, xp);
      toast(r.message, 'good');
      setXpIn((m) => ({ ...m, [skill]: '' }));
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <section className="adm-box" data-testid="adm-skills">
      <h3 className="adm-h3">🌟 Skills</h3>
      {data && rows.length === 0 && <p className="adm-empty">No skills set up.</p>}
      <div className="adm-rows">
        {rows.map((r) => (
          <div key={r.skill} className="adm-ledger__row" data-testid={`adm-skill-${r.skill}`}>
            <span className="adm-ledger__label">
              {r.icon} {r.name} · level {r.level}
              <small>{r.xp.toLocaleString('en-NG')} XP{r.next_xp != null ? ` · next level at ${r.next_xp.toLocaleString('en-NG')}` : ' · max level'}</small>
            </span>
            <select className="adm-input" aria-label={`${r.name} level`} value={r.level} disabled={busy === r.skill}
              onChange={(e) => void set(r.skill, Number(e.target.value), null)}>
              {Array.from({ length: max }, (_, i) => i + 1).map((l) => <option key={l} value={l}>Lvl {l}</option>)}
            </select>
            <input className="adm-input" type="number" min={0} inputMode="numeric" placeholder="XP" aria-label={`${r.name} exact XP`} style={{ width: 84 }}
              value={xpIn[r.skill] ?? ''} onChange={(e) => setXpIn((m) => ({ ...m, [r.skill]: e.target.value }))} />
            <Btn tone="ghost" small disabled={busy === r.skill || (xpIn[r.skill] ?? '') === ''} onClick={() => void set(r.skill, null, Math.max(0, Math.floor(Number(xpIn[r.skill]))))}>Set XP</Btn>
          </div>
        ))}
      </div>
    </section>
  );
}
