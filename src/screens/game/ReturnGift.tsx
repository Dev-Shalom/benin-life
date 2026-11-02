// Welcome-back gift (docs/DAILY_RETURN.md): a warm card for a player who was away 3+ days.
//   ReturnGiftCard   inline card (used inside the welcome-back screen's card, above Continue)
//   ReturnGiftHost   the same card in a pop-up, only when the welcome-back screen did not show it
import { useEffect, useState } from 'react';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useReturnGift } from '../../state/returnGift';
import { Button, Modal, toast } from '../../ui';
import './ReturnGift.css';

function daysText(n: number): string {
  return n === 1 ? '1 day' : `${n} days`;
}

export function ReturnGiftCard({ compact = false }: { compact?: boolean }) {
  const gift = useReturnGift((s) => s.gift);
  const done = useReturnGift((s) => s.claimed);
  const claim = useReturnGift((s) => s.claim);
  const [busy, setBusy] = useState(false);
  const pending = Boolean(gift?.pending);
  if (!pending && !done) return null;

  const cash = done ? done.cash : gift?.cash ?? 0;
  const item = done ? done.item : gift?.item ?? null;
  const away = done ? done.away_days : gift?.away_days ?? 0;

  const take = async () => {
    setBusy(true);
    try {
      await claim();
      void useGame.getState().refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={`rg${compact ? ' rg--compact' : ''}${done ? ' is-done' : ''}`} role="group" aria-label="Welcome-back gift">
      <span className="rg__art" aria-hidden>{done ? '✅' : '🎁'}</span>
      <div className="rg__body">
        <p className="rg__title">{done ? 'Gift don land. Welcome back!' : 'Welcome back! Benin don miss you'}</p>
        <p className="rg__sub">{done ? 'Added to your cash and your bag.' : `You were away ${daysText(away)}. A small gift dey wait you.`}</p>
        <div className="rg__chips">
          {cash > 0 && <span className="rg__chip">{naira(cash)}</span>}
          {item && <span className="rg__chip">{item.icon ?? '🍽️'} {item.name}{item.qty > 1 ? ` x${item.qty}` : ''}</span>}
        </div>
      </div>
      {!done && (
        <Button size="md" variant="green" loading={busy} onClick={() => void take()} className="rg__btn">
          Collect gift
        </Button>
      )}
    </div>
  );
}

/** Loads the gift once per session and offers it in a pop-up unless the welcome-back screen already did. */
export function ReturnGiftHost() {
  const gift = useReturnGift((s) => s.gift);
  const offered = useReturnGift((s) => s.offered);
  const done = useReturnGift((s) => s.claimed);
  const load = useReturnGift((s) => s.load);
  const markOffered = useReturnGift((s) => s.markOffered);
  const [shown, setShown] = useState(false);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    if (gift?.pending && !offered && !shown) { setShown(true); markOffered(); }
  }, [gift, offered, shown, markOffered]);
  const open = shown && (Boolean(gift?.pending) || Boolean(done));
  return (
    <Modal open={open} onClose={() => setShown(false)} tone="good" title="Welcome back"
      actions={<Button variant="ghost" block onClick={() => setShown(false)}>{done ? 'Continue' : 'Later'}</Button>}>
      <ReturnGiftCard />
    </Modal>
  );
}
