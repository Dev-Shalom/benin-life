// Life moments (docs/MOMENTS.md): the pop-up card. Same card as the Babalawo / broadcast popups (bl-modal + bcast-*): a speaker line, an icon,
// a short story and up to four choices, stacked on phones, with "Remind me later" under them. One card at a time. A small toast tells the outcome.
// The server decides what a choice costs and does; this file only shows the cards (src/state/moments.ts keeps them, polled cheaply).
import { useEffect, useRef, useState } from 'react';
import { momentsAnswer, momentsSeen, momentsSnooze, type Moment, type MomentChoice } from '../../api/moments';
import { GameError, errorMessage } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { naira } from '../../lib/format';
import { playCue } from '../../lib/sound';
import { useGame } from '../../state/game';
import { useKids } from '../../state/kids';
import { usePick } from '../../state/moneyPick';
import { startMoments, useMoments } from '../../state/moments';
import { Button, Modal, toast } from '../../ui';

/** Hold a card while something else owns the screen: another popup, the spray sheet, a money drop, a task, the road, a club floor. */
function useHeld(active: boolean): boolean {
  const scene = useGame((s) => s.state?.location?.scene);
  const busyUntil = useGame((s) => s.state?.profile?.busy_until ?? null);
  const travelling = useGame((s) => !!s.state?.travel);
  const drops = usePick((s) => s.drops.length);
  const [other, setOther] = useState(false);
  const [, setTick] = useState(0);
  useEffect(() => {
    if (!active) return;
    const check = () => {
      setOther(!!document.querySelector('.spray-sheet') || [...document.querySelectorAll('.bl-modal-root')].some((el) => !el.querySelector('[data-moment-card]')));
      setTick((n) => n + 1);
    };
    check();
    const id = window.setInterval(check, 1500);
    return () => window.clearInterval(id);
  }, [active]);
  const busy = !!busyUntil && Date.parse(busyUntil) > serverNow();
  return other || drops > 0 || busy || travelling || scene === 'club' || scene === 'lounge';
}

function ChoiceButton({ c, doc, first, busy, onPick }: { c: MomentChoice; doc: boolean; first: boolean; busy: string | null; onPick: (c: MomentChoice) => void }) {
  const off = !c.affordable;
  const cls = `mm-choice${doc && first ? ' is-main' : ''}${c.ignore ? ' is-ignore' : ''}${off ? ' is-off' : ''}`;
  return (
    <button type="button" className={cls} aria-disabled={off || busy !== null} disabled={busy !== null && busy !== c.id} onClick={() => onPick(c)}
      data-testid={`moment-choice-${c.id}`} data-choice={c.id}>
      <span className="mm-choice__label">{busy === c.id ? '...' : c.label}</span>
      {c.cost > 0 && <span className="mm-choice__cost">{off ? `Need ${naira(c.cost)}` : naira(c.cost)}</span>}
    </button>
  );
}

function Card({ m, snoozeHours }: { m: Moment; snoozeHours: number }) {
  const [busy, setBusy] = useState<string | null>(null);
  const done = useRef(false);
  const doc = m.kind === 'kids_ill';
  useEffect(() => { playCue('alert'); }, [m.id]);

  const refreshAll = () => {
    void useGame.getState().refresh();
    void useKids.getState().load();
    void useMoments.getState().load();
  };
  const fail = (e: unknown) => {
    toast(errorMessage(e), 'bad');
    const hint = e instanceof GameError ? e.hint : undefined;
    if (hint === 'no_moment' || hint === 'already_answered') useMoments.getState().drop(m.id);
  };
  const pick = async (c: MomentChoice) => {
    if (done.current || busy) return;
    if (!c.affordable) { toast(`You need ${naira(c.cost)} for that.`, 'bad'); return; }
    done.current = true;
    setBusy(c.id);
    try {
      const r = await momentsAnswer(m.id, c.id);
      const eff = r.effects.length ? `  (${r.effects.join(' · ')})` : '';
      toast(`${r.icon} ${r.outcome}${eff}`, r.tone === 'bad' ? 'bad' : r.tone === 'good' ? 'good' : 'info');
      useMoments.getState().drop(m.id);
    } catch (e) {
      fail(e);
    } finally {
      done.current = false;
      setBusy(null);
      refreshAll();
    }
  };
  const later = async () => {
    if (done.current || busy) return;
    done.current = true;
    setBusy('later');
    try {
      const r = await momentsSnooze(m.id);
      toast(r.expired ? r.outcome : `We will remind you in ${snoozeHours} hour${snoozeHours === 1 ? '' : 's'}.`, 'info');
      useMoments.getState().drop(m.id);
    } catch (e) {
      fail(e);
    } finally {
      done.current = false;
      setBusy(null);
      refreshAll();
    }
  };

  return (
    <Modal open dismissable={false} onClose={() => undefined}
      art={<div className={`bcast-art mm-art${doc ? ' mm-art--doc' : ''}`} aria-hidden>{m.icon}</div>}
      title={<span className="bcast-title"><small className="bcast-kicker">{m.speaker || 'Life'}</small>{m.title}</span>}
      actions={
        <div className="mm-actions" data-moment-card data-testid="moment-card" data-moment={m.moment}>
          <div className="mm-choices">
            {m.choices.map((c, i) => <ChoiceButton key={c.id} c={c} doc={doc} first={i === 0} busy={busy} onPick={(x) => void pick(x)} />)}
          </div>
          {m.snoozes_left > 0 && (
            <button type="button" className="mm-later" disabled={busy !== null} onClick={() => void later()} data-testid="moment-later">
              {busy === 'later' ? '...' : `Remind me later${snoozeHours ? ` (${snoozeHours} h)` : ''}`}
            </button>
          )}
        </div>
      }>
      <p className="bcast-body mm-body" data-moment-card>{m.body}</p>
    </Modal>
  );
}

/** Mounted once on the game screen. Starts the cheap poll, shows the first due card (or a "handled by your partner" note). */
export function MomentsHost() {
  const queue = useMoments((s) => s.queue);
  const handled = useMoments((s) => s.handled);
  const snoozeHours = useMoments((s) => s.snoozeHours);
  useEffect(() => startMoments(), []);
  const m = queue[0] ?? null;
  const h = !m ? handled[0] ?? null : null;
  const held = useHeld(!!m || !!h);
  if (held) return null;
  if (m) return <Card key={m.id} m={m} snoozeHours={snoozeHours} />;
  if (h) {
    const close = () => {
      useMoments.getState().dropHandled(h.id);
      void momentsSeen(h.id).catch(() => undefined);
    };
    return (
      <Modal open onClose={close} tone="good"
        art={<div className="bcast-art mm-art mm-art--doc" aria-hidden>{h.icon}</div>}
        title={<span className="bcast-title"><small className="bcast-kicker">{h.speaker}</small>{h.title}</span>}
        actions={<div className="mm-actions" data-moment-card><Button variant="green" block onClick={close} data-testid="moment-handled-ok">OK</Button></div>}>
        <p className="bcast-body mm-body" data-moment-card data-testid="moment-handled">{h.outcome}</p>
      </Modal>
    );
  }
  return null;
}
