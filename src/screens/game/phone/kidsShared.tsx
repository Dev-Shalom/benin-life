// Small pieces the Kids card and its School panel share (docs/LOVE.md, docs/KIDS_SCHOOL.md).
import { naira } from '../../../lib/format';
import { useUi } from '../../../state/ui';
import { Button } from '../../../ui';

export type Run = (key: string, fn: () => Promise<{ message?: string }>) => void;

export function Bar({ pct, cls = '' }: { pct: number; cls?: string }) {
  return <div className={`fm-bar ${cls}`} aria-hidden><span className="fm-bar__fill" style={{ transform: `scaleX(${Math.max(0, Math.min(100, pct)) / 100})` }} /></div>;
}

export interface BuyRow { id: string; name: string; open: boolean; price: number; kind: 'market' | 'supermarket' }

/** Where to buy a missing supply. The shop is at the place (you buy there, Shop tab), so the button takes you to the map. */
export function BuyPanel({ msg, places, name, onClose }: { msg: string; places: BuyRow[]; name: string; onClose: () => void }) {
  const go = (p: BuyRow) => {
    const ui = useUi.getState();
    ui.closeAll();
    ui.setMapOpen(true);
    ui.select(p.id);
  };
  return (
    <div className="fm-buy" data-testid="kids-buy">
      <p className="fm-buy__msg"><b>{msg}</b></p>
      <ul className="fm-buy__list">
        {places.map((p) => (
          <li key={p.id} className="fm-buy__row">
            <span className="fm-buy__who">
              <b>{p.name}</b>
              <small>{p.kind === 'market' ? 'Cheaper. Price moves a little each day.' : 'Fixed price. Never closes.'} {p.open ? 'Open now.' : 'Closed right now.'}</small>
            </span>
            <span className="fm-buy__price">{naira(p.price)}</span>
            <Button variant={p.open ? 'green' : 'ghost'} size="sm" onClick={() => go(p)} data-testid={`kids-buy-${p.id}`}>Go there</Button>
          </li>
        ))}
      </ul>
      <p className="fm-fine">You buy it at the shop when you are there (Shop tab). Then come back and look after {name}.</p>
      <button type="button" className="fm-buy__close" onClick={onClose}>Close</button>
    </div>
  );
}
