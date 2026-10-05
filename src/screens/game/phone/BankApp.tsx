// Phone "Bank" app (V1-5 — docs/BANK.md): balances, send money to another player by username
// (bank to bank, with a confirm step), money history, and where to deposit / withdraw in town.
import { useEffect, useState } from 'react';
import { bankHistory, bankRecipient, bankTransfer, hourText } from '../../../api/bank';
import { errorMessage } from '../../../lib/api';
import { naira, timeAgo } from '../../../lib/format';
import type { BankRecipient, GameState, LedgerRow } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, toast } from '../../../ui';
import { AmountBox } from '../../../panels/bank/BankUI';
import { realWait, useBankInfo, useGoTo } from '../../../panels/bank/bankHooks';

type Tab = 'send' | 'history' | 'where';

function History({ active }: { active: boolean }) {
  const [rows, setRows] = useState<LedgerRow[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    if (!active) return;
    let alive = true;
    bankHistory(40)
      .then((r) => alive && (setRows(r), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [active]);
  if (err) return <p className="phone-app__lead">{err}</p>;
  if (!rows) return <div className="panel-skel"><span /><span /></div>;
  if (rows.length === 0) return <p className="phone-app__lead">No money moves yet.</p>;
  return (
    <ul className="bank-hist">
      {rows.map((r) => (
        <li key={r.id} className="bank-hist__row">
          <span className="bank-hist__icon" aria-hidden>{r.account === 'bank' ? '🏦' : '💵'}</span>
          <span className="grow">
            <span className="bank-hist__label">{r.label}</span>
            <span className="bank-hist__sub">
              {r.account === 'bank' ? 'Bank' : 'Cash'} · {timeAgo(r.created_at)}{r.note ? ` · "${r.note}"` : ''}
            </span>
          </span>
          <b className={`bank-hist__amt${r.delta > 0 ? ' is-in' : ''}`}>{r.delta > 0 ? '+' : '−'}{naira(Math.abs(r.delta))}</b>
        </li>
      ))}
    </ul>
  );
}

export default function BankApp({ state }: { state: GameState }) {
  const refresh = useGame((s) => s.refresh);
  const { info, err, reload } = useBankInfo();
  const goTo = useGoTo();
  const [tab, setTab] = useState<Tab>('send');
  const [user, setUser] = useState('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [to, setTo] = useState<BankRecipient | null>(null);
  const [busy, setBusy] = useState(false);
  const p = state.profile;

  const t = info?.transfer;
  const n = Number(amount) || 0;
  const fee = t?.fee ?? 0;
  const maxSend = t ? Math.max(0, Math.min(p.bank - fee, t.left_today)) : 0;
  const blocked = !t ? 'Loading…' : !user.trim() ? 'Type a username'
    : n < t.min_amount ? `At least ${naira(t.min_amount)}` : n > t.left_today ? `Daily limit: ${naira(t.left_today)} left`
      : n + fee > p.bank ? 'Not enough in the bank' : null;

  const check = async () => {
    setBusy(true);
    try {
      setTo(await bankRecipient(user));
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const send = async () => {
    if (!to) return;
    setBusy(true);
    try {
      const r = await bankTransfer(to.username, n, note);
      toast(`💸 ${r.message}`, 'good');
      setTo(null);
      setAmount('');
      setNote('');
      await refresh();
      reload();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      setTo(null);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="phone-app__body bank-app">
      <div className="bank-card">
        <span className="bank-card__label">Bank balance</span>
        <span className="bank-card__amt">{naira(p.bank)}</span>
        <span className="bank-card__sub">Bronze Bank · safe from street thieves</span>
      </div>
      <div className="bank-row"><span>Cash in pocket</span><b>{naira(p.cash)}</b></div>
      <div className="chop__tabs" role="tablist">
        {([['send', '💸 Send'], ['history', '🧾 History'], ['where', '📍 Where']] as const).map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={tab === id} className={`chop__tab${tab === id ? ' is-on' : ''}`}
            onClick={() => setTab(id)}>{label}</button>
        ))}
      </div>
      {err && <p className="phone-app__lead">{err}</p>}

      {tab === 'send' && t && (to ? (
        <div className="bank-confirm">
          <p className="bank-confirm__q">Send <b>{naira(n)}</b> to <b>@{to.username}</b>?</p>
          <div className="bankx__fee">
            <div><span>Transfer fee</span><b>{naira(fee)}</b></div>
            <div><span>Total from your bank</span><b>{naira(n + fee)}</b></div>
            {note.trim() && <div><span>Note</span><b>"{note.trim()}"</b></div>}
          </div>
          <div className="row bank-confirm__btns">
            <Button variant="ghost" className="grow" onClick={() => setTo(null)} disabled={busy}>Cancel</Button>
            <Button variant="green" className="grow" icon="check" loading={busy} onClick={() => void send()}>Send</Button>
          </div>
        </div>
      ) : (
        <div className="bank-send stack">
          <label className="bankx__amount-field">
            <span className="bankx__amount-label">To (username)</span>
            <span className="bankx__amount-input">
              <span aria-hidden>@</span>
              <input className="input" value={user} autoCapitalize="none" autoCorrect="off" spellCheck={false} placeholder="username"
                aria-label="Username" maxLength={30} onChange={(e) => setUser(e.target.value.replace(/^@+/, ''))} />
            </span>
          </label>
          <AmountBox value={amount} onChange={setAmount} max={maxSend} min={t.min_amount} />
          <label className="bankx__amount-field">
            <span className="bankx__amount-label">Note (optional)</span>
            <input className="input" value={note} maxLength={80} placeholder="For chop, rent, thank you…" onChange={(e) => setNote(e.target.value)} />
          </label>
          <Button variant="green" block loading={busy} disabled={Boolean(blocked)} onClick={() => void check()} icon="chevronRight">
            {blocked ?? 'Continue'}
          </Button>
          <p className="bankx__fine">
            Fee {naira(fee)} per transfer. You can send {naira(t.left_today)} more today (game day), up to {t.daily_count} transfers.
            {t.new_account_wait_real_seconds > 0 && ` New accounts can send in about ${realWait(t.new_account_wait_real_seconds)}.`}
          </p>
        </div>
      ))}

      {tab === 'history' && <History active={tab === 'history'} />}

      {tab === 'where' && info && (
        <div className="stack">
          <p className="phone-app__lead">
            Transfers work from anywhere. To put cash in or take it out, go to the bank counter (free, {info.bank_hours.open_hour === info.bank_hours.close_hour ? 'any hour' : `${hourText(info.bank_hours.open_hour)} to ${hourText(info.bank_hours.close_hour)}`})
            {' '}or a PoS stand (any hour, {info.pos.fee_pct}% charge, at least {naira(info.pos.fee_min)}).
          </p>
          <ul className="ride-list">
            {info.places.map((x) => (
              <li key={x.id}>
                <button type="button" className="ride-row" onClick={() => goTo(x.id, x.kind)}>
                  <span className="ride-row__pin" aria-hidden>{x.kind === 'bank' ? '🏦' : '🏧'}</span>
                  <span className="grow">
                    <span className="ride-row__name">{x.name}</span>
                    <span className="ride-row__sub">
                      {x.kind === 'bank'
                        ? info.bank_hours.open ? 'Open now · free' : `Closed · opens in ${realWait(info.bank_hours.opens_in_real_seconds)}`
                        : 'PoS · any hour · small charge'}
                    </span>
                  </span>
                  <span className="ride-row__km">{x.id === p.location_id ? 'Here' : 'Go'}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
