// R6 cash-out sheet (docs/YAHOO.md "R6"): three ways to turn the yahoo balance into cash, each with its real numbers
// (amount, fee, what lands, EFCC chance, time) shown BEFORE you confirm. All numbers come from the server (yahoo_cashout_quote).
// Abstract game mechanic: no real laundering method is described, only the trade-off (more risk = faster and no fee).
import { useEffect, useRef, useState } from 'react';
import { yahooCashoutQuote, yahooCashoutStart, type CashMode, type CashOption, type CashQuote } from '../../../api/yahoo';
import { errorMessage } from '../../../lib/api';
import { countdown, naira, nairaShort, secondsUntil } from '../../../lib/format';
import { useNow } from '../../../lib/clock';
import { useGame } from '../../../state/game';
import { useYahoo } from '../../../state/yahoo';
import { Button, Sheet, toast } from '../../../ui';

const BLURB: Record<CashMode, string> = {
  full: 'Everything at once. Fastest, and the highest EFCC risk.',
  half: 'Move half now, keep half for later. Lower risk.',
  launder: 'Pass it through the contact for a fee. Much lower risk, but e dey take longer.',
};
const ICON: Record<CashMode, string> = { full: '💸', half: '✂️', launder: '🕴️' };

function tone(p: number): string {
  return p >= 20 ? 'is-hot' : p >= 10 ? 'is-warm' : 'is-cool';
}
const pct = (p: number) => `${Math.round(p * 10) / 10}%`;

export function CashOutSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const refresh = useGame((x) => x.refresh);
  const now = useNow(1000);
  const [q, setQ] = useState<CashQuote | null>(null);
  const [mode, setMode] = useState<CashMode>('full');
  const [busy, setBusy] = useState(false);
  // the parent re-renders every second (the clock): keep the latest onClose without re-running the quote effect
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    if (!open) return;
    let live = true;
    setQ(null);
    yahooCashoutQuote().then((r) => {
      if (!live) return;
      setQ(r);
      setMode((m) => (r.options.find((o) => o.mode === m)?.ok ? m : (r.options.find((o) => o.ok)?.mode ?? 'full')));
    }).catch((e) => { if (live) { toast(errorMessage(e), 'bad'); closeRef.current(); } });
    return () => { live = false; };
  }, [open]);

  const opt: CashOption | undefined = q?.options.find((o) => o.mode === mode);
  const cd = q ? secondsUntil(q.cooldown_until, now) : 0;
  const why = !q ? null : !q.enabled ? 'Yahoo is switched off' : q.blocked ?? (cd > 0 ? `Wait ${countdown(cd)}` : null);

  const go = async () => {
    if (!opt || busy) return;
    setBusy(true);
    try {
      const r = await yahooCashoutStart(mode);
      toast(r.message, 'info');
      useYahoo.getState().started({
        id: r.run_id, job_id: r.job_id, name: `${opt.label}`, icon: ICON[mode], started_at: new Date(Date.now()).toISOString(),
        resolve_at: r.resolve_at, status: 'running', caught_pct: r.skill_caught_pct ?? r.caught_pct, amount: r.amount, mode: r.mode, fee: r.fee,
      });
      void refresh();
      onClose();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void yahooCashoutQuote().then(setQ).catch(() => undefined);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onClose={onClose} className="yh-sheet" title="Cash out" subtitle={q ? `Yahoo balance ${naira(q.dirty)}. Pick how you want to move am.` : 'Checking the odds…'}
      footer={q && (
        <div className="yh-co__foot">
          {opt && (
            <p className="yh-co__sum" data-testid="cashout-summary">
              {opt.fee > 0 ? <>You get <b>{naira(opt.net)}</b> cash after a <b>{naira(opt.fee)}</b> fee</> : <>You get <b>{naira(opt.net)}</b> cash</>}
              {' · '}EFCC <b>{pct(opt.caught_pct)}</b> · {opt.seconds >= 60 ? `${Math.floor(opt.seconds / 60)}m ${opt.seconds % 60}s` : `${opt.seconds}s`}
            </p>
          )}
          <Button block variant="gold" disabled={!opt?.ok || Boolean(why)} loading={busy} onClick={() => void go()} data-testid="cashout-confirm">
            {why ?? (opt?.ok ? `Confirm · ${opt.label}` : (opt?.why ?? 'Not available'))}
          </Button>
        </div>
      )}>
      <span className="yh-sheet-host" hidden />
      {!q ? (
        <div className="yh-skel"><span /><span /><span /></div>
      ) : (
        <div className="yh-co" role="radiogroup" aria-label="Cash-out option">
          {q.options.map((o) => (
            <button key={o.mode} type="button" role="radio" aria-checked={mode === o.mode} disabled={!o.ok}
              className={`yh-co__opt${mode === o.mode ? ' is-on' : ''}`} onClick={() => setMode(o.mode)} data-testid={`cashout-${o.mode}`}>
              <span className="yh-co__icon" aria-hidden>{ICON[o.mode]}</span>
              <span className="yh-co__main">
                <b>{o.label}{o.mode === 'launder' ? ` · ${q.contact}` : ''}</b>
                <small>{BLURB[o.mode]}</small>
                <span className="yh-co__nums">
                  <span>Moves <b>{nairaShort(o.amount)}</b></span>
                  {o.fee > 0 && <span>Fee <b>{nairaShort(o.fee)}</b> ({q.fee_pct}%)</span>}
                  <span>Cash <b>{nairaShort(o.net)}</b></span>
                  <span>{o.seconds >= 60 ? `${Math.floor(o.seconds / 60)}m ${o.seconds % 60}s` : `${o.seconds}s`}</span>
                </span>
                {!o.ok && o.why && <small className="yh-co__why">{o.why}</small>}
              </span>
              <span className={`yh-odds ${tone(o.caught_pct)}`} title={o.base_caught_pct !== o.caught_pct ? `Base ${pct(o.base_caught_pct)}, cut by your Yahoo level` : undefined}>
                🚨 {pct(o.caught_pct)}{o.base_caught_pct !== o.caught_pct ? <s>{pct(o.base_caught_pct)}</s> : null}
              </span>
            </button>
          ))}
          <p className="yh-fine">Caught during a cash out = EFCC case, and part of your yahoo balance is taken. Your Yahoo level already lowers every chance shown.</p>
        </div>
      )}
    </Sheet>
  );
}
