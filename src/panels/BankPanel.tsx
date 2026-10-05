// "Bank" tab in the location sheet (action id `bank`, V1-5 — docs/BANK.md): deposit / withdraw at the
// Bronze Bank counter, free, during banking hours. After hours it points at the PoS stands.
import { useState } from 'react';
import { bankDeposit, bankWithdraw, hourText } from '../api/bank';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import type { PanelProps } from '../lib/types';
import { Button, EmptyState, Segmented, toast } from '../ui';
import { AmountBox, Balances } from './bank/BankUI';
import { realWait, useBankInfo, useGoTo } from './bank/bankHooks';

type Mode = 'deposit' | 'withdraw';

export default function BankPanel({ state, refresh }: PanelProps) {
  const { info, err, reload } = useBankInfo();
  const goTo = useGoTo();
  const [mode, setMode] = useState<Mode>('deposit');
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const p = state.profile;

  if (!info && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (!info) return <EmptyState icon="info" title="Couldn't reach the bank" body={err ?? ''} />;

  const min = info.min_amount;
  const max = mode === 'deposit' ? p.cash : p.bank;
  const n = Number(amount) || 0;
  const h = info.bank_hours;
  const blocked = !h.open ? 'The bank is closed' : n < min ? `At least ${naira(min)}` : n > max
    ? mode === 'deposit' ? 'Not enough cash' : 'Not enough in the bank' : null;

  const go = async () => {
    setBusy(true);
    try {
      const r = mode === 'deposit' ? await bankDeposit(n) : await bankWithdraw(n);
      toast(r.message, 'good');
      setAmount('');
      await refresh();
      reload();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      reload();
    } finally {
      setBusy(false);
    }
  };

  const pos = info.places.filter((x) => x.kind === 'pos');
  return (
    <div className="bankx stack">
      <Balances state={state} />
      <p className="bankx__safe">🔒 Money in the bank can't be stolen on the street.</p>
      <div className={`bankx__hours${h.open ? ' is-open' : ' is-closed'}`}>
        <span className="bankx__dot" aria-hidden />
        {h.open
          ? <span>Open now · {h.open_hour === h.close_hour ? 'open 24 hours' : `${hourText(h.open_hour)} to ${hourText(h.close_hour)}`} · no charges</span>
          : <span>Closed · opens at {hourText(h.open_hour)}, in about {realWait(h.opens_in_real_seconds)} (real time)</span>}
      </div>
      {!h.open && pos.length > 0 && (
        <div className="bankx__after">
          <p>After hours, a PoS stand can do it for a small charge:</p>
          <div className="bankx__places">
            {pos.map((x) => (
              <button key={x.id} type="button" className="bankx__place" onClick={() => goTo(x.id, 'pos')}>📍 {x.name}</button>
            ))}
          </div>
        </div>
      )}
      <Segmented<Mode> label="Deposit or withdraw" value={mode} onChange={(m) => { setMode(m); setAmount(''); }}
        options={[{ id: 'deposit', label: 'Deposit' }, { id: 'withdraw', label: 'Withdraw' }]} />
      <AmountBox value={amount} onChange={setAmount} max={max} min={min}
        label={mode === 'deposit' ? 'Cash to put in the bank' : 'Cash to take out'} />
      <Button variant={mode === 'deposit' ? 'green' : 'gold'} block loading={busy} disabled={Boolean(blocked)} onClick={() => void go()}
        icon={mode === 'deposit' ? 'bank' : 'cash'}>
        {blocked ?? (mode === 'deposit' ? `Deposit ${naira(n)}` : `Withdraw ${naira(n)}`)}
      </Button>
    </div>
  );
}
