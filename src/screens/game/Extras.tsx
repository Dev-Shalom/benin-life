// The keyboard shortcuts help sheet and the dock's Buy sheet (R4; V1-4 adds the Bag and Chowdeck, with
// Buy mode still a teaser).
import { SHORTCUTS } from './shortcuts';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Icon, Sheet } from '../../ui';

export function ShortcutsSheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  return (
    <Sheet open={overlay === 'shortcuts'} onClose={() => setOverlay(null)}
      header={
        <div className="home-sheet__head">
          <span className="home-sheet__emoji" aria-hidden>⌨️</span>
          <div>
            <h3 className="bl-sheet__title">Keyboard shortcuts</h3>
            <p className="bl-sheet__sub">Play Benin Life without a mouse</p>
          </div>
        </div>
      }>
      <dl className="kbd-list">
        {SHORTCUTS.map(([k, label]) => (
          <div key={k} className="kbd-list__row">
            <dt><kbd>{k}</kbd></dt>
            <dd>{label}</dd>
          </div>
        ))}
      </dl>
    </Sheet>
  );
}

const BUY_SAMPLES: [string, string, string][] = [
  ['🪑', 'Plastic chair', '₦4,500'],
  ['🌀', 'Standing fan', '₦28,000'],
  ['🛏️', 'Spring mattress', '₦95,000'],
  ['📺', 'Flat-screen TV', '₦240,000'],
  ['❄️', 'Split AC', '₦585,000'],
  ['⚡', 'Inverter + battery', '₦720,000'],
];

export function BuySheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const openPanel = useUi((s) => s.openPanel);
  const openPhone = useUi((s) => s.openPhone);
  const inv = useGame((s) => s.state?.inventory);
  const count = (inv ?? []).reduce((n, i) => n + i.qty, 0);
  const preview = (inv ?? []).slice(0, 4).map((i) => i.icon || '📦').join(' ');
  return (
    <Sheet open={overlay === 'buy'} onClose={() => setOverlay(null)}
      header={
        <div className="home-sheet__head">
          <span className="home-sheet__emoji" aria-hidden>🛍️</span>
          <div>
            <h3 className="bl-sheet__title">Buy</h3>
            <p className="bl-sheet__sub">Your Bag, food delivery and shops</p>
          </div>
        </div>
      }>
      <div className="buy-choices">
        <button type="button" className="buy-choice" onClick={() => { setOverlay(null); openPanel('inventory'); }}>
          <span className="buy-choice__emoji" aria-hidden>🎒</span>
          <span className="grow">
            <span className="buy-choice__title">Bag</span>
            <span className="buy-choice__sub">{count > 0 ? `${count} ${count === 1 ? 'thing' : 'things'} · ${preview}` : 'Empty for now'} · eat, use, sell</span>
          </span>
          <Icon name="chevronRight" size={18} stroke={2.4} />
        </button>
        <button type="button" className="buy-choice" onClick={() => openPhone('food')}>
          <span className="buy-choice__emoji" aria-hidden>🛵</span>
          <span className="grow">
            <span className="buy-choice__title">Chowdeck</span>
            <span className="buy-choice__sub">Order food to wherever you are</span>
          </span>
          <Icon name="chevronRight" size={18} stroke={2.4} />
        </button>
        <p className="buy-tip"><span aria-hidden>🛒</span> Markets, bukas, motor parks and PoS stands sell food, drinks, airtime and more: open the place on the map and tap <b>Shop</b>.</p>
      </div>
      <div className="sim-section-head buy-mode-head"><h4>Buy mode</h4><span className="soon-pill">Coming soon</span></div>
      <div className="buy-grid">
        {BUY_SAMPLES.map(([e, name, price]) => (
          <div key={name} className="buy-card" aria-disabled>
            <span className="buy-card__emoji" aria-hidden>{e}</span>
            <span className="buy-card__name">{name}</span>
            <span className="buy-card__price">{price}</span>
          </div>
        ))}
      </div>
      <p className="muted buy-note">Furnish your home your way: move, rotate and sell furniture, and every piece will make your Sim happier in its own way. Prices shown are a preview.</p>
    </Sheet>
  );
}
