// B2 Babalawo shrine popups (docs/BABALAWO.md). Same card as the A2 broadcast / gift popup (bl-modal + bcast-*).
// <ShrineHost/>  follows my shrine state (src/state/shrine.ts) and shows, one at a time:
//   1. the result of a service (Baba's line; failed charms say why),
//   2. "Baba's blessing" (money charm payout) and "Baba's charm don backfire!" notices,
//   3. "Baba is calling you" (the money charm's weekly demand) with Pay / Ignore until it is paid, ignored or too late.
// <CharmChips/>  active charms with time left (Sim sheet, Babalawo tab).
import { useEffect, useState } from 'react';
import { charmLeft, shrineDemandIgnore, shrineDemandPay, shrineNoticeSeen, timeLeft, type Charm } from '../../api/shrine';
import { errorMessage } from '../../lib/api';
import { useNow } from '../../lib/clock';
import { naira } from '../../lib/format';
import { playCue } from '../../lib/sound';
import { startShrine, useShrine } from '../../state/shrine';
import { useGame } from '../../state/game';
import { Button, Modal, toast } from '../../ui';

export function ShrineHost() {
  const result = useShrine((s) => s.result);
  const notices = useShrine((s) => s.notices);
  const demand = useShrine((s) => s.demand);
  const [busy, setBusy] = useState<'pay' | 'ignore' | 'seen' | null>(null);
  const now = useNow(30_000);
  useEffect(() => startShrine(), []);

  const notice = notices[0] ?? null;
  // blessing popup plays the money sound once per notice
  const nid = notice?.id;
  useEffect(() => {
    if (nid == null) return;
    const n = useShrine.getState().notices.find((x) => x.id === nid);
    playCue(n?.kind === 'blessing' ? 'money' : 'error');
  }, [nid]);

  if (result) {
    const ok = result.status === 'done';
    return (
      <Modal open onClose={() => useShrine.getState().setResult(null)} tone={ok ? 'good' : 'bad'}
        art={<div className={`bcast-art shrine-art${ok ? '' : ' shrine-art--fail'}`} aria-hidden>{ok ? result.icon ?? '🪔' : '🌑'}</div>}
        title={<span className="bcast-title"><small className="bcast-kicker">Baba's Shrine</small>{ok ? `${result.name} is done` : `${result.name ?? 'The charm'} failed`}</span>}
        actions={<Button variant={ok ? 'primary' : 'ghost'} block onClick={() => useShrine.getState().setResult(null)} data-testid="shrine-result-ok">
          {ok ? 'Thank you, Baba' : 'Ehn… okay'}</Button>}>
        {result.reading && <p className="bcast-body shrine-reading">{result.reading}</p>}
        <p className="bcast-body">“{result.line}”</p>
        {!ok && <p className="crime-odds">The money and the offerings are gone. Some charms just don't take.</p>}
        {ok && result.charm?.effect && <p className="crime-odds">{result.charm.effect}{result.charm.expires_at ? ` · ${charmLeft(result.charm, now)}` : result.charm.uses_left ? ` · ${charmLeft(result.charm, now)}` : ''}</p>}
      </Modal>
    );
  }

  if (notice) {
    const good = notice.kind === 'blessing';
    const close = async () => {
      setBusy('seen');
      useShrine.setState((s) => ({ notices: s.notices.filter((n) => n.id !== notice.id) }));
      try { await shrineNoticeSeen([notice.id]); } catch { /* shows again next load */ }
      setBusy(null);
    };
    return (
      <Modal open onClose={() => void close()} tone={good ? 'good' : 'bad'}
        art={<div className={`bcast-art shrine-art${good ? ' shrine-art--gold' : ' shrine-art--fail'}`} aria-hidden>{good ? '💰' : '😵‍💫'}</div>}
        title={<span className="bcast-title"><small className="bcast-kicker">{good ? 'Money charm' : 'Money charm'}</small>{notice.title}</span>}
        actions={<Button variant={good ? 'gold' : 'ghost'} block loading={busy === 'seen'} onClick={() => void close()} data-testid="shrine-notice-ok">
          {good ? 'Baba, thank you!' : 'Wahala…'}</Button>}>
        {good && <p className="bcast-amount">+{naira(notice.amount)} <small>to your cash</small></p>}
        <p className="bcast-body">{notice.body}</p>
      </Modal>
    );
  }

  if (demand && !demand.ignored) {
    const goatsOk = demand.have_goats >= demand.goats;
    const cashOk = demand.have_cash >= demand.cash;
    const left = timeLeft(demand.deadline, now);
    const pay = async () => {
      setBusy('pay');
      try {
        const r = await shrineDemandPay();
        playCue('done');
        toast(`🐐 ${r.message}`, 'good');
      } catch (e) {
        toast(errorMessage(e), 'bad');
      } finally {
        setBusy(null);
        void useShrine.getState().load();
        void useGame.getState().refresh();
      }
    };
    const ignore = async () => {
      setBusy('ignore');
      try {
        const r = await shrineDemandIgnore();
        toast(r.message, 'info');
      } catch (e) {
        toast(errorMessage(e), 'bad');
      } finally {
        setBusy(null);
        void useShrine.getState().load();
      }
    };
    return (
      <Modal open dismissable={false} onClose={() => undefined} tone="bad"
        art={<div className="bcast-art shrine-art" aria-hidden>🥁</div>}
        title={<span className="bcast-title"><small className="bcast-kicker">Money charm · weekly offering</small>Baba is calling you</span>}
        actions={
          <div className="crime-actions">
            <Button variant="gold" block disabled={!goatsOk || !cashOk || busy !== null} loading={busy === 'pay'} onClick={() => void pay()}
              data-testid="shrine-demand-pay">
              Pay · 🐐 ×{demand.goats} + {naira(demand.cash)}
            </Button>
            {(!goatsOk || !cashOk) && (
              <small className="crime-note">
                You have {demand.have_goats} goat{demand.have_goats === 1 ? '' : 's'} and {naira(demand.have_cash)} cash.
                {!goatsOk ? ' Goats are sold at Oba Market.' : ''}
              </small>
            )}
            <Button variant="ghost" block disabled={busy !== null} loading={busy === 'ignore'} onClick={() => void ignore()} data-testid="shrine-demand-ignore">
              Ignore
            </Button>
          </div>
        }>
        <p className="bcast-body">“My child, the money wey I dey send you no be free. Bring {demand.goats === 1 ? 'one goat' : `${demand.goats} goats`} and {naira(demand.cash)}.”</p>
        {left && <p className="bcast-amount shrine-deadline">{left} <small>left to answer Baba</small></p>}
        <p className="crime-odds">Ignore Baba and the charm backfires: half your cash goes, madness stops you working for a game day, and bad luck follows you for 3 days.</p>
      </Modal>
    );
  }
  return null;
}

/** Active charms as chips with time left. */
export function CharmChips({ charms, empty }: { charms: Charm[]; empty?: React.ReactNode }) {
  const now = useNow(30_000);
  if (!charms.length) return <>{empty ?? null}</>;
  return (
    <ul className="charm-chips" aria-label="Active charms">
      {charms.map((c) => {
        const left = c.kind === 'money_charm' && c.demand?.open ? 'Baba is calling!' : charmLeft(c, now);
        return (
          <li key={c.id} className={`charm-chip${c.debuff ? ' is-bad' : ''}${c.kind === 'money_charm' && c.demand?.open ? ' is-calling' : ''}`}
            title={c.effect ?? c.name} data-testid={`charm-${c.kind}`}>
            <span className="charm-chip__icon" aria-hidden>{c.icon}</span>
            <span className="charm-chip__text">
              <b>{c.name}</b>
              {left && <small>{left}</small>}
            </span>
          </li>
        );
      })}
    </ul>
  );
}
