// The keyboard shortcuts help sheet and the Buy mode teaser (R4).
import { SHORTCUTS } from './shortcuts';
import { useUi } from '../../state/ui';
import { Sheet } from '../../ui';

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

const BUY_TABS = ['🎨 Design', '🛏️ Sleep', '🍳 Kitchen', '🛁 Bath', '🛋️ Comfort', '🎮 Fun', '📚 Skills', '💡 Light'];
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
  return (
    <Sheet open={overlay === 'buy'} onClose={() => setOverlay(null)}
      header={
        <div className="home-sheet__head">
          <span className="home-sheet__emoji" aria-hidden>🛋️</span>
          <div>
            <h3 className="bl-sheet__title">Buy mode</h3>
            <p className="bl-sheet__sub">Coming soon: furnish your home your way</p>
          </div>
        </div>
      }>
      <div className="buy-tabs" aria-hidden>
        {BUY_TABS.map((t) => <span key={t} className="chip">{t}</span>)}
      </div>
      <div className="buy-grid">
        {BUY_SAMPLES.map(([e, name, price]) => (
          <div key={name} className="buy-card" aria-disabled>
            <span className="buy-card__emoji" aria-hidden>{e}</span>
            <span className="buy-card__name">{name}</span>
            <span className="buy-card__price">{price}</span>
          </div>
        ))}
      </div>
      <p className="muted buy-note">Move, rotate and sell furniture, and every piece will make your Sim happier in its own way. Prices shown are a preview.</p>
    </Sheet>
  );
}
