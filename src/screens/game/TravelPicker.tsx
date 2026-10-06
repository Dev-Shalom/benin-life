import { naira } from '../../lib/format';
import { secondsLabel } from '../../lib/live';
import { MODE_META } from '../../lib/pidgin';
import type { Location, TravelOption } from '../../lib/types';
import { Button, EmptyState, Icon, Spinner } from '../../ui';
import { bookLabel, riskTone, useTravel } from './travel';

const MODE_ICON: Record<string, string> = { walk: 'walk', keke: 'keke', bus: 'bus', drop: 'drop', car: 'car' };


export function TravelPicker({ dest, cash, blockedReason, onStarted }: {
  dest: Location; cash: number; blockedReason: string | null; onStarted: () => void;
}) {
  const { quote, loading, err, mode, setMode, going, load, go, selected } = useTravel(dest, cash, onStarted);

  if (blockedReason) {
    return <p className="travel-blocked"><Icon name="info" size={16} /> {blockedReason}</p>;
  }

  if (!quote) {
    return (
      <div className="travel-cta">
        {err && <p className="error-text">{err}</p>}
        <Button size="lg" block icon="pin" loading={loading} onClick={() => void load()}>
          Go there
        </Button>
      </div>
    );
  }

  return (
    <div className="travel">
      <div className="travel__head">
        <h4>How do you want to go?</h4>
        <span className="chip"><Icon name="road" size={12} /> {quote.km.toFixed(1)} km</span>
        {loading && <Spinner size={14} />}
      </div>
      {quote.options.length === 0 ? (
        <EmptyState icon="road" title="No route" body="There is no way to get there right now." />
      ) : (
        <div className="mode-grid">
          {quote.options.map((o) => (
            <ModeCard key={o.mode} o={o} cash={cash} active={o.mode === mode} onPick={() => setMode(o.mode)} />
          ))}
        </div>
      )}
      <Button size="lg" block variant="green" loading={going} disabled={!selected || !selected.allowed || selected.cost > cash}
        onClick={() => void go()}>
        {bookLabel(selected)}
      </Button>
    </div>
  );
}

export function ModeCard({ o, cash, active, onPick }: { o: TravelOption; cash: number; active: boolean; onPick: () => void }) {
  const broke = o.allowed && o.cost > cash;
  const disabled = !o.allowed || broke;
  const reason = !o.allowed ? (o.reason ?? 'Not available right now') : broke ? 'Not enough cash' : null;
  const risk = Number(o.risk_pct) || 0;
  return (
    <button type="button" className={`mode-card${active ? ' is-active' : ''}${disabled ? ' is-disabled' : ''}`}
      onClick={onPick} disabled={disabled} aria-pressed={active}>
      <span className="mode-card__icon"><Icon name={MODE_ICON[o.mode] ?? 'road'} size={22} /></span>
      <span className="mode-card__main">
        <span className="mode-card__name">{o.label || MODE_META[o.mode]?.label || o.mode}</span>
        {reason ? (
          <span className="mode-card__reason">{reason}</span>
        ) : (
          <span className="mode-card__meta">
            {secondsLabel(o.real_seconds)} <span className="muted">trip</span>
          </span>
        )}
      </span>
      <span className="mode-card__side">
        <span className="mode-card__cost">{o.cost ? naira(o.cost) : 'Free'}</span>
        <span className={`chip ${riskTone(risk)}`}>{risk <= 0 ? 'No risk' : `${risk.toFixed(risk < 10 ? 1 : 0)}% risk`}</span>
      </span>
    </button>
  );
}
