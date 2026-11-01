// Fix it 12: Bank app -> History. Every money move in words: what it was, why, how much, the balance after, and where it came
// from or went. A summary answers "where did my money go?" (last 7 days), filters split money in / money out, and older rows load
// on request. Yahoo money (the EFCC can seize it) is shown too. Server: money_history / money_history_summary (read only, own rows).
import { useCallback, useEffect, useState } from 'react';
import { moneyHistory, moneyHistorySummary, type MoneyHistoryRow, type MoneyHistorySummary } from '../../../api/bank';
import { errorMessage } from '../../../lib/api';
import { naira, timeAgo } from '../../../lib/format';
import { Button } from '../../../ui';

type Filter = 'all' | 'in' | 'out';
const ACCOUNT_LABEL: Record<string, string> = { bank: 'Bank', cash: 'Cash', yahoo: 'Yahoo balance' };
const ACCOUNT_ICON: Record<string, string> = { bank: '🏦', cash: '💵', yahoo: '💻' };

function dayLabel(iso: string): string {
  const d = new Date(iso);
  const today = new Date();
  const y = new Date(Date.now() - 86_400_000);
  if (d.toDateString() === today.toDateString()) return 'Today';
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
}

export function MoneyHistory({ active }: { active: boolean }) {
  const [filter, setFilter] = useState<Filter>('all');
  const [rows, setRows] = useState<MoneyHistoryRow[] | null>(null);
  const [more, setMore] = useState(false);
  const [sum, setSum] = useState<MoneyHistorySummary | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback((f: Filter) => {
    setRows(null);
    moneyHistory(30, f).then((r) => { setRows(r.rows); setMore(r.more); setErr(null); }).catch((e) => setErr(errorMessage(e)));
  }, []);
  useEffect(() => {
    if (!active) return;
    load(filter);
    moneyHistorySummary(7).then(setSum).catch(() => setSum(null));
  }, [active, filter, load]);

  const older = async () => {
    const last = rows?.[rows.length - 1];
    if (!last) return;
    setBusy(true);
    try {
      const r = await moneyHistory(30, filter, last.created_at, last.key);
      setRows([...(rows ?? []), ...r.rows]);
      setMore(r.more);
    } catch (e) { setErr(errorMessage(e)); } finally { setBusy(false); }
  };

  let lastDay = '';
  return (
    <div className="mh" data-testid="money-history">
      {sum && (
        <div className="mh__sum" data-testid="money-summary">
          <div className="mh__sumrow"><span>Money in, last {sum.days} days</span><b className="is-in">+{naira(sum.money_in)}</b></div>
          <div className="mh__sumrow"><span>Money out, last {sum.days} days</span><b>−{naira(sum.money_out)}</b></div>
          {sum.top_out.length > 0 && (
            <ul className="mh__top" aria-label="Where your money went">
              {sum.top_out.slice(0, 4).map((t) => <li key={t.category}><span>{t.category}</span><b>−{naira(t.amount)}</b></li>)}
            </ul>
          )}
          {sum.yahoo_seized > 0 && <p className="mh__note">EFCC seized {naira(sum.yahoo_seized)} of your Yahoo balance.</p>}
          <p className="mh__note">Moving cash to the bank (and back) is not counted: it is still your money.</p>
        </div>
      )}
      <div className="chop__tabs" role="tablist" aria-label="Filter">
        {([['all', 'All'], ['in', 'Money in'], ['out', 'Money out']] as const).map(([id, l]) => (
          <button key={id} type="button" role="tab" aria-selected={filter === id} className={`chop__tab${filter === id ? ' is-on' : ''}`} onClick={() => setFilter(id)}>{l}</button>
        ))}
      </div>
      {err && <p className="phone-app__lead">{err}</p>}
      {!rows && !err && <div className="panel-skel"><span /><span /></div>}
      {rows && rows.length === 0 && <p className="phone-app__lead">No money moves yet.</p>}
      {rows && rows.length > 0 && (
        <ul className="bank-hist">
          {rows.map((r) => {
            const day = dayLabel(r.created_at);
            const head = day !== lastDay;
            lastDay = day;
            return (
              <li key={r.key} className="mh__li">
                {head && <div className="mh__day">{day}</div>}
                <div className="bank-hist__row">
                  <span className="bank-hist__icon" aria-hidden>{ACCOUNT_ICON[r.account] ?? '💵'}</span>
                  <span className="grow">
                    <span className="bank-hist__label">{r.label}</span>
                    <span className="bank-hist__sub">
                      {ACCOUNT_LABEL[r.account] ?? r.account} · {timeAgo(r.created_at)}{r.category && !r.own_move ? ` · ${r.category}` : ''}
                    </span>
                    {r.detail && <span className="bank-hist__sub mh__detail">"{r.detail}"</span>}
                    <span className="bank-hist__sub">Balance after {naira(r.balance_after)}</span>
                  </span>
                  <b className={`bank-hist__amt${r.delta > 0 ? ' is-in' : ''}`}>{r.delta > 0 ? '+' : '−'}{naira(Math.abs(r.delta))}</b>
                </div>
              </li>
            );
          })}
        </ul>
      )}
      {more && <Button variant="ghost" block loading={busy} onClick={() => void older()}>Show older</Button>}
    </div>
  );
}
