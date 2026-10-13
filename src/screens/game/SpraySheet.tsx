// SP1 custom spray (docs/SPRAY.md): the "Spray money" sheet, opened from the dance floor, DJ booth and VIP cards in
// any club. Amount field (numeric keypad, ₦ with commas, short preview ₦1.2M / ₦3B / ₦2T), quick chips (VIP chips start
// higher), the tier the MC will shout, and Spray. The server checks it all (open club, cash in hand, min / max,
// cooldown, VIP booking) and broadcasts the shout-out; the sprayer sees their own takeover at once.
import { useEffect, useMemo, useState } from 'react';
import { nairaWords, sprayCustom, sprayRank, sprayStatus, SPRAY_TIER_LABEL, type SprayStatus, type SprayTier } from '../../api/spray';
import { errorMessage, GameError } from '../../lib/api';
import { naira, nairaShort } from '../../lib/format';
import type { GameState } from '../../lib/types';
import { pushHype } from '../../state/hype';
import { addDrop } from '../../state/moneyPick';
import { useGame } from '../../state/game';
import { useSpray } from '../../state/spray';
import { Sheet, toast } from '../../ui';
import '../../styles/spray.css';

const MAX_DIGITS = 16;

function chipLabel(n: number): string {
  return n < 1e6 ? `₦${n >= 1000 ? `${n / 1000}k` : n}` : nairaShort(n);
}

function tierFor(n: number, s: SprayStatus | null): SprayTier {
  const tiers = s?.tiers ?? [];
  let t: SprayTier = 'small';
  for (const x of tiers) if (n >= x.min) t = x.id;
  return t;
}

export function SpraySheet({ state }: { state: GameState }) {
  const open = useSpray((s) => s.open);
  const close = useSpray((s) => s.close);
  const refresh = useGame((s) => s.refresh);
  const [st, setSt] = useState<SprayStatus | null>(null);
  const [digits, setDigits] = useState('');
  const [busy, setBusy] = useState(false);
  const [cool, setCool] = useState(0);
  const vip = open?.vip ?? false;
  const cash = state.profile.cash;

  useEffect(() => {
    if (!open) return;
    let alive = true;
    setDigits('');
    sprayStatus(open.locationId)
      .then((s) => {
        if (!alive) return;
        setSt(s);
        setCool(s.cooldown_left);
      })
      .catch((e) => alive && toast(errorMessage(e), 'bad'));
    return () => { alive = false; };
  }, [open]);

  useEffect(() => {
    if (cool <= 0) return;
    const t = window.setTimeout(() => setCool((c) => Math.max(0, c - 1)), 1000);
    return () => window.clearTimeout(t);
  }, [cool]);

  const amount = Number(digits || '0');
  const min = vip ? (st?.vip_min ?? 100_000) : (st?.min ?? 1000);
  const max = Math.min(st?.max ?? 1e13, cash);
  const chips = useMemo(() => (vip ? st?.vip_chips : st?.chips) ?? [], [st, vip]);
  const tier = tierFor(amount, st);
  const rank = sprayRank(tier);

  let problem: string | null = null;
  if (st && !st.enabled) problem = 'Spraying is paused right now.';
  else if (st && !st.open) problem = `${st.place || 'The club'} is closed right now.`;
  else if (vip && st && !st.vip_ok) problem = 'VIP spray is for VIP guests. Book a VIP table first.';
  else if (amount > 0 && amount < min) problem = `${vip ? 'VIP spray' : 'Spray'} starts from ${naira(min)}.`;
  else if (amount > (st?.max ?? Infinity)) problem = `The most you can spray at once is ${naira(st?.max ?? 0)}.`;
  else if (amount > cash) problem = `You only have ${naira(cash)} cash on you. Withdraw at the PoS first.`;
  const can = !!open && !!st && amount >= min && !problem && !busy && cool <= 0;

  const set = (n: number) => setDigits(String(Math.max(0, Math.floor(n))).slice(0, MAX_DIGITS));

  const spray = async () => {
    if (!open || !can) return;
    setBusy(true);
    try {
      const r = await sprayCustom(open.locationId, amount, vip);
      if (r.hype) pushHype(r.hype);
      if (r.drop) addDrop(r.drop);
      toast(`${r.message} +${r.points} hype`, 'good');
      setCool(r.cooldown_s);
      setDigits('');
      void refresh();
      close();
    } catch (e) {
      const hint = e instanceof GameError ? e.hint : null;
      toast(errorMessage(e), hint === 'cooldown' ? 'info' : 'bad');
      if (hint === 'cooldown') setCool(st?.cooldown_s ?? 10);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={!!open} onClose={close} className={`spray-sheet${vip ? ' is-vip' : ''}`}
      title={vip ? 'VIP spray' : 'Spray money'}
      subtitle={`${st?.place || state.location.name.replace(/\s*\(.*\)\s*$/, '')} · cash on you ${naira(cash)}`}
      footer={
        <button type="button" className={`spray-go${vip ? ' is-vip' : ''}`} disabled={!can} onClick={() => void spray()}>
          {busy ? 'Spraying…' : cool > 0 ? `Spray again in ${cool}s` : amount >= min ? `Spray ${naira(amount)}` : 'Spray'}
        </button>
      }>
      <div className="spray">
        {vip && <p className="spray__vip"><span aria-hidden>👑</span> VIP spray: gold rain on every screen, +{st?.vip_pct ?? 25}% hype, from {naira(min)}</p>}
        <label className="spray__field">
          <span className="sr-only">Amount to spray</span>
          <span className="spray__cur" aria-hidden>₦</span>
          <input className="spray__input" inputMode="numeric" pattern="[0-9]*" enterKeyHint="send" autoComplete="off"
            placeholder="0" aria-label="Amount to spray"
            value={digits ? Number(digits).toLocaleString('en-US') : ''}
            onChange={(e) => setDigits(e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, MAX_DIGITS))}
            onKeyDown={(e) => { if (e.key === 'Enter') void spray(); }} />
        </label>
        <div className="spray__preview" aria-live="polite">
          {amount > 0 ? (
            <>
              <span className="spray__short">{nairaWords(amount)}</span>
              <span className={`spray__tier t-${tier}`}>{SPRAY_TIER_LABEL[tier]} spray{rank >= 4 ? ' 👑' : ''}</span>
            </>
          ) : <span className="spray__hint">Type an amount or pick a chip · from {naira(min)}</span>}
        </div>
        {problem && <p className="spray__problem" role="alert">{problem}</p>}
        <div className="spray__chips" role="group" aria-label="Quick amounts">
          {chips.map((c) => (
            <button key={c} type="button" className={`spray__chip${amount === c ? ' is-on' : ''}`} disabled={c > cash}
              onClick={() => set(c)} title={naira(c)}>{chipLabel(c)}</button>
          ))}
          <button type="button" className={`spray__chip spray__chip--all${amount === max && max > 0 ? ' is-on' : ''}`}
            disabled={max < min} onClick={() => set(max)} title={naira(max)}>All my cash</button>
        </div>
        <p className="spray__foot">
          Cash in hand only. The MC hails every spray for everyone in the club: bigger spray, louder hype.
          {st && st.points > 0 ? ` Your hype: ${st.points.toLocaleString('en-US')} pts.` : ''}
        </p>
      </div>
    </Sheet>
  );
}
