// "PoS" tab in the location sheet (action id `pos`, V1-5 — docs/BANK.md): cash-out from the bank or
// deposit cash into it, any hour, for a charge (pos.fee_pct, at least pos.fee_min, rounded up to ₦10).
import { useState } from 'react';
import { posCashout, posDeposit, posFee } from '../api/bank';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import type { PanelProps } from '../lib/types';
import { Button, EmptyState, Segmented, toast } from '../ui';
import { AmountBox, Balances } from './bank/BankUI';
import { useBankInfo } from './bank/bankHooks';

type Mode = 'cashout' | 'deposit';

const BANTER = [
  '"Oga, you wan withdraw or transfer? Network dey today."',
  '"Customer, come! Cash dey, no long story."',
  '"Count am well before you leave o."',
  '"Small charge only. Na so everybody dey do am."',
];

export default function PosPanel({ state, refresh }: PanelProps) {
  const { info, err, reload } = useBankInfo();
  const [mode, setMode] = useState<Mode>('cashout');
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const [line] = useState(() => BANTER[Math.floor(Math.random() * BANTER.length)]);
  const p = state.profile;

  if (!info && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (!info) return <EmptyState icon="info" title="The PoS network is down" body={err ?? ''} />;

  const min = info.min_amount;
  const cap = info.pos.max_amount;
  const max = mode === 'cashout' ? info.pos.max_cashout : info.pos.max_deposit;
  const n = Number(amount) || 0;
  const fee = n > 0 ? posFee(n, info.pos.fee_pct, info.pos.fee_min) : 0;
  const from = mode === 'cashout' ? p.bank : p.cash;
  const blocked = n < min ? `At least ${naira(min)}` : n > cap ? `At most ${naira(cap)} per go`
    : n + fee > from ? (mode === 'cashout' ? 'Not enough in the bank' : 'Not enough cash') : null;

  const go = async () => {
    setBusy(true);
    try {
      const r = mode === 'cashout' ? await posCashout(n) : await posDeposit(n);
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

  return (
    <div className="bankx stack">
      <p className="shop__greet">{line}</p>
      <Balances state={state} />
      <Segmented<Mode> label="Cash out or deposit" value={mode} onChange={(m) => { setMode(m); setAmount(''); }}
        options={[{ id: 'cashout', label: 'Cash out' }, { id: 'deposit', label: 'Deposit' }]} />
      <AmountBox value={amount} onChange={setAmount} max={max} min={min}
        label={mode === 'cashout' ? 'Cash you want in hand' : 'Cash to send to your bank'} />
      <div className="bankx__fee">
        <div><span>Charge ({info.pos.fee_pct}%, at least {naira(info.pos.fee_min)})</span><b>{naira(fee)}</b></div>
        <div>
          <span>{mode === 'cashout' ? 'Taken from your bank' : 'You hand over in cash'}</span>
          <b>{naira(n + fee)}</b>
        </div>
      </div>
      <Button variant="gold" block loading={busy} disabled={Boolean(blocked)} onClick={() => void go()} icon={mode === 'cashout' ? 'cash' : 'bank'}>
        {blocked ?? (mode === 'cashout' ? `Cash out ${naira(n)}` : `Deposit ${naira(n)}`)}
      </Button>
      <p className="bankx__fine">Works any hour. The Bronze Bank counter is free but keeps banking hours.</p>
    </div>
  );
}
