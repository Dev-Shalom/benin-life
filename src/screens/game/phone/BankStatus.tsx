// E4: Bank app "Status" tab: prestige sinks. Donate to the city (Benin Philanthropists), throw a city party, buy a Chief title.
// The money is destroyed (docs/ECONOMY_SINKS.md).
import { useCallback, useEffect, useState } from 'react';
import {
  chiefTitleBuy, chiefTitles, cityPartyStatus, cityPartyThrow, donateCity, donorsTop,
  type ChiefTitles, type DonorsTop, type PartyStatus,
} from '../../../api/economy';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { Button, toast } from '../../../ui';
import { AmountBox } from '../../../panels/bank/BankUI';

export function StatusTab({ active }: { active: boolean }) {
  const refresh = useGame((s) => s.refresh);
  const state = useGame((s) => s.state);
  const [donors, setDonors] = useState<DonorsTop | null>(null);
  const [party, setParty] = useState<PartyStatus | null>(null);
  const [chief, setChief] = useState<ChiefTitles | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [arm, setArm] = useState<string | null>(null);
  const [ward, setWard] = useState('');

  const load = useCallback(async () => {
    try {
      const [a, b, c] = await Promise.all([donorsTop(20), cityPartyStatus(), chiefTitles()]);
      setDonors(a); setParty(b); setChief(c); setErr(null);
      setWard((w) => w || c.wards[0]?.id || '');
    } catch (e) { setErr(errorMessage(e)); }
  }, []);
  useEffect(() => { if (active) void load(); }, [active, load]);
  useEffect(() => { if (!arm) return; const t = window.setTimeout(() => setArm(null), 4000); return () => window.clearTimeout(t); }, [arm]);

  const total = (state?.profile.bank ?? 0) + (state?.profile.cash ?? 0);
  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try { const r = await fn(); toast(r.message, 'good'); setArm(null); setAmount(''); await refresh(); await load(); }
    catch (e) { toast(errorMessage(e), 'bad'); setArm(null); }
    finally { setBusy(null); }
  };

  if (err && !donors) return <p className="phone-app__lead">{err}</p>;
  if (!donors || !party || !chief) return <div className="panel-skel"><span /><span /></div>;
  if (!chief.enabled) return <p className="phone-app__lead">These are switched off for now.</p>;
  const n = Number(amount) || 0;
  const mine = chief.mine;
  const cd = party.cooldown_left_seconds;
  return (
    <div className="stack bills" data-testid="bank-status">
      <section className="bills__card">
        <h4 className="bills__h">🤲 Donate to the city</h4>
        <p className="bankx__fine">
          Money for Benin&apos;s roads and markets. It leaves the game for good, and you climb the Benin Philanthropists board, earn a badge and Charisma XP.
          {donors.me ? ` You have given ${naira(donors.me.total)}${donors.me.badge ? ` (${donors.me.badge})` : ''}.` : ''}
        </p>
        <AmountBox value={amount} onChange={setAmount} max={total} min={donors.min} label="Donation" />
        <Button block variant="gold" loading={busy === 'donate'} disabled={n < donors.min || n > total}
          onClick={() => (arm === 'donate' ? void run('donate', () => donateCity(n)) : setArm('donate'))}>
          {n < donors.min ? `Donate (from ${naira(donors.min)})` : n > total ? 'Not enough money' : arm === 'donate' ? `Tap again · give ${naira(n)}` : `Donate ${naira(n)}`}
        </Button>
        <h5 className="bills__h2">🏅 Benin Philanthropists</h5>
        {donors.rows.length === 0 ? <p className="bills__empty">Nobody has donated yet. Be the first.</p> : (
          <ol className="bills__board" data-testid="donors-board">
            {donors.rows.slice(0, 10).map((r) => (
              <li key={r.rank} className={r.me ? 'is-me' : ''}>
                <span className="bills__rank">{r.rank}</span>
                <span className="grow">{r.title ? `${r.title} ` : ''}@{r.username}{r.badge && <small className="bills__badge">{r.badge}</small>}</span>
                <b className="bills__band">{r.band ?? (r.total != null ? nairaShort(r.total) : '')}</b>
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="bills__card">
        <h4 className="bills__h">🎉 Throw a city party</h4>
        <p className="bankx__fine">
          Everyone in Benin gets the announcement, and everybody in the venue (and who walks in for {Math.round(party.minutes)} minutes) gets Fun +{party.fun_boost}.
          Very expensive: <b>{naira(party.cost)}</b>. You are at <b>{party.here.name}</b>.
        </p>
        {party.active.length > 0 && <p className="bankx__fine">On now: {party.active.map((a) => `${a.name} (@${a.host})`).join(', ')}</p>}
        <Button block variant="primary" loading={busy === 'party'} disabled={!party.here.ok || cd > 0 || total < party.cost}
          onClick={() => (arm === 'party' ? void run('party', () => cityPartyThrow()) : setArm('party'))}>
          {!party.here.ok ? (party.here.reason ?? 'Not here') : cd > 0 ? `Rest small · ${Math.ceil(cd / 60)} min` : total < party.cost ? 'Not enough money'
            : arm === 'party' ? `Tap again · pay ${nairaShort(party.cost)}` : `Throw a party · ${nairaShort(party.cost)}`}
        </Button>
      </section>

      <section className="bills__card">
        <h4 className="bills__h">📜 Chief titles</h4>
        <p className="bankx__fine">
          A title shows next to your name for everybody. Made-up, respectful titles only: nothing from the Oba&apos;s palace.
          {mine ? ` You are ${mine.name} ${state?.profile.username ?? ''}${mine.of ? ` of ${mine.of}` : ''}.` : ''}
        </p>
        <label className="bankx__amount-field">
          <span className="bankx__amount-label">Your title is “of”…</span>
          <select className="input" value={ward} onChange={(e) => setWard(e.target.value)} aria-label="Title of">
            {chief.wards.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
        </label>
        <ul className="bills__list">
          {chief.tiers.map((t) => (
            <li key={t.tier} className={`bills__row${t.owned ? ' is-paid' : ''}`}>
              <span className="bills__icon" aria-hidden>{['', '🪶', '🦅', '👑'][t.tier] ?? '📜'}</span>
              <span className="grow"><span className="bills__title">{t.name}</span><span className="bills__sub">{t.owned ? 'Yours' : mine ? `Upgrade for ${naira(t.cost_now)}` : naira(t.price)}</span></span>
              {!t.owned && (
                <Button size="sm" variant="gold" loading={busy === `c${t.tier}`} disabled={total < t.cost_now || !ward}
                  onClick={() => (arm === `c${t.tier}` ? void run(`c${t.tier}`, () => chiefTitleBuy(t.tier, ward)) : setArm(`c${t.tier}`))}>
                  {total < t.cost_now ? 'Too small' : arm === `c${t.tier}` ? 'Confirm' : 'Buy'}
                </Button>
              )}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
