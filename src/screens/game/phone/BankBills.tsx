// E4: Bank app "Bills" tab: income tax (this week, bands, owed, receipts) and the weekly bills with due dates (docs/ECONOMY_SINKS.md).
import { useCallback, useEffect, useState } from 'react';
import { bankSinks, billsPay, billsPayAll, taxPay, type Bill, type BankSinks } from '../../../api/economy';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { Button, toast } from '../../../ui';

const KIND_ICON: Record<string, string> = { house: '🏠', car: '🚗', business: '🏪', land: '🌍' };

const dueText = (iso: string) =>
  new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'Africa/Lagos' });

function billState(b: Bill): { label: string; tone: 'ok' | 'warn' | 'bad' | 'paid' } {
  if (b.status === 'paid') return { label: 'Paid', tone: 'paid' };
  if (b.blocked) return { label: 'Overdue, asset stopped', tone: 'bad' };
  if (b.overdue) return { label: 'Overdue, late fee added', tone: 'warn' };
  return { label: `Due ${dueText(b.due_at)}`, tone: 'ok' };
}

export function BillsTab({ active }: { active: boolean }) {
  const refresh = useGame((s) => s.refresh);
  const [d, setD] = useState<BankSinks | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    try { setD(await bankSinks()); setErr(null); } catch (e) { setErr(errorMessage(e)); }
  }, []);
  useEffect(() => { if (active) void load(); }, [active, load]);

  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try { const r = await fn(); toast(`🧾 ${r.message}`, 'good'); await refresh(); await load(); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  if (err && !d) return <p className="phone-app__lead">{err}</p>;
  if (!d) return <div className="panel-skel"><span /><span /></div>;
  const t = d.tax;
  const open = d.bills.filter((b) => b.status === 'open');
  const paid = d.bills.filter((b) => b.status === 'paid');
  const graceOn = Date.parse(d.grace_until) > Date.now();
  return (
    <div className="stack bills" data-testid="bank-bills">
      <section className="bills__card" aria-label="Income tax">
        <h4 className="bills__h">🏛️ Edo State Internal Revenue</h4>
        {!t.enabled ? <p className="bankx__fine">Income tax is switched off for now.</p> : (
          <>
            <p className="bankx__fine">
              Tax is on what you <b>earn</b> in a week (jobs, hustles, business, interest), settled on Monday. {t.exempt_now ? `You are exempt until ${dueText(t.exempt_until)}: new players pay no tax for the first days.` : ''}
            </p>
            <div className="bankx__fee">
              <div><span>Earned this week</span><b>{naira(t.week.earned)}</b></div>
              <div><span>Tax if the week ended now</span><b>{t.exempt_now ? naira(0) : naira(t.week.est_tax)}</b></div>
              {t.holiday && <div><span>🎉 {t.holiday.name}</span><b>rates −{t.holiday.cut_pct}%</b></div>}
            </div>
            <ul className="bills__bands">
              {t.bands.map((b, i) => (
                <li key={i}>
                  <span>{b.to == null ? `Above ${nairaShort(b.from)}` : `${nairaShort(b.from)} to ${nairaShort(b.to)}`}</span>
                  <b>{b.pct === 0 ? 'free' : t.holiday ? `${b.eff_pct}%` : `${b.pct}%`}</b>
                </li>
              ))}
            </ul>
            {d.owed > 0 && (
              <div className="bills__owed" data-testid="tax-owed">
                <span><b>Tax owed {naira(d.owed)}</b><small>Your next earnings pay it first. Never makes you negative.</small></span>
                <Button size="sm" variant="gold" loading={busy === 'tax'} onClick={() => void run('tax', () => taxPay())}>Pay now</Button>
              </div>
            )}
            {t.last.length > 0 && (
              <ul className="bills__recs">
                {t.last.slice(0, 4).map((r) => (
                  <li key={r.week}>
                    <span>Week of {dueText(r.week)}{r.exempt ? ' · exempt' : r.holiday ? ' · tax holiday' : ''}<small>earned {naira(r.earned)}</small></span>
                    <b>{r.tax > 0 ? `−${naira(r.paid)}` : naira(0)}</b>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </section>

      <section className="bills__card" aria-label="Bills">
        <h4 className="bills__h">🧾 Bills</h4>
        {!d.enabled ? <p className="bankx__fine">Bills are switched off for now.</p> : (
          <>
            <p className="bankx__fine">
              Every Monday your house, cars, businesses and land send a bill. {d.autopay ? 'On the due date it is paid from your bank, then cash, if the money is there. ' : ''}
              Late? A {d.late_fee_pct}% late fee. A car or business stops working only after {d.block_days} days overdue, and nothing is ever taken from you.
              {graceOn ? ` New player grace: no bills until ${dueText(d.grace_until)}.` : ''}
            </p>
            {open.length === 0 ? <p className="bills__empty">No open bills. Nice one.</p> : (
              <>
                <ul className="bills__list">
                  {open.map((b) => {
                    const st = billState(b);
                    return (
                      <li key={b.id} className={`bills__row is-${st.tone}`}>
                        <span className="bills__icon" aria-hidden>{KIND_ICON[b.kind] ?? '🧾'}</span>
                        <span className="grow">
                          <span className="bills__title">{b.title}</span>
                          <span className="bills__sub">{b.detail ? `${b.detail} · ` : ''}{st.label}{b.late_fee > 0 ? ` · +${naira(b.late_fee)} late fee` : ''}</span>
                        </span>
                        <span className="bills__pay">
                          <b>{naira(b.total)}</b>
                          <Button size="sm" variant="green" loading={busy === `b${b.id}`} onClick={() => void run(`b${b.id}`, () => billsPay(b.id))}>Pay</Button>
                        </span>
                      </li>
                    );
                  })}
                </ul>
                {open.length > 1 && (
                  <Button block variant="gold" loading={busy === 'all'} onClick={() => void run('all', () => billsPayAll())}>
                    Pay all ({naira(d.open_total)})
                  </Button>
                )}
              </>
            )}
            {paid.length > 0 && (
              <details className="bills__paid">
                <summary>Paid recently ({paid.length})</summary>
                <ul className="bills__list">
                  {paid.slice(0, 10).map((b) => (
                    <li key={b.id} className="bills__row is-paid">
                      <span className="bills__icon" aria-hidden>{KIND_ICON[b.kind] ?? '🧾'}</span>
                      <span className="grow"><span className="bills__title">{b.title}</span><span className="bills__sub">{b.detail}</span></span>
                      <b>{naira(b.total)}</b>
                    </li>
                  ))}
                </ul>
              </details>
            )}
          </>
        )}
      </section>
    </div>
  );
}
