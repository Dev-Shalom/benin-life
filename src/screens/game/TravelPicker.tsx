import { useEffect, useState } from 'react';
import { rpc, errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { secondsLabel } from '../../lib/live';
import { MODE_META } from '../../lib/pidgin';
import type { Location, TravelOption, TravelQuote } from '../../lib/types';
import { useGame } from '../../state/game';
import { Button, EmptyState, Icon, Spinner, toast } from '../../ui';

const MODE_ICON: Record<string, string> = { walk: 'walk', keke: 'keke', bus: 'bus', drop: 'drop', car: 'car' };

function riskTone(pct: number): 'good' | 'warn' | 'bad' {
  if (pct < 3) return 'good';
  if (pct < 10) return 'warn';
  return 'bad';
}

export function TravelPicker({ dest, cash, blockedReason, onStarted }: {
  dest: Location; cash: number; blockedReason: string | null; onStarted: () => void;
}) {
  const refresh = useGame((s) => s.refresh);
  const [quote, setQuote] = useState<TravelQuote | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [mode, setMode] = useState<string | null>(null);
  const [going, setGoing] = useState(false);

  // New destination → reset.
  const [forDest, setForDest] = useState(dest.id);
  if (forDest !== dest.id) {
    setForDest(dest.id);
    setQuote(null);
    setMode(null);
    setErr(null);
  }

  const load = async () => {
    setLoading(true);
    setErr(null);
    try {
      const q = await rpc<TravelQuote>('travel_quote', { p_dest: dest.id });
      setQuote(q);
      const best = q.options.find((o) => o.allowed && o.cost <= cash && o.mode === 'bus') ?? q.options.find((o) => o.allowed && o.cost <= cash);
      setMode(best?.mode ?? null);
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  // Re-quote if the sheet stays open a while (traffic changes with the clock).
  useEffect(() => {
    if (!quote) return;
    const id = window.setInterval(() => void load(), 45_000);
    return () => window.clearInterval(id);
  }, [quote?.dest]);

  const go = async () => {
    if (!mode) return;
    setGoing(true);
    try {
      const res = await rpc<{ message?: string }>('travel_start', { p_dest: dest.id, p_mode: mode });
      toast(res?.message ?? `You're on your way to ${dest.name}.`, 'good');
      await refresh();
      onStarted();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setGoing(false);
    }
  };

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

  const selected = quote.options.find((o) => o.mode === mode);

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
        {selected ? `${selected.mode === 'walk' ? 'Walk there' : `Go by ${MODE_META[selected.mode]?.label ?? selected.label}`} · ${selected.cost ? naira(selected.cost) : 'Free'}` : 'Pick a way to travel'}
      </Button>
    </div>
  );
}

function ModeCard({ o, cash, active, onPick }: { o: TravelOption; cash: number; active: boolean; onPick: () => void }) {
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
