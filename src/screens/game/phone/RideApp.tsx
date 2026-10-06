// Phone "Ride" app (S1): book what you ride, ride-hailing style.
// Step 1: where to (search + places by distance, or pick on the map). Step 2: the ride options from
// `travel_quote` (keke, ECTS bus, drop, your car, walk) with price, trip time and risk; Book -> `travel_start`.
// The quote/book logic is shared with the location sheet's TravelPicker (useTravel).
import { useEffect, useMemo, useState } from 'react';
import { districtName } from '../../../lib/format';
import { useLiveNow } from '../../../lib/live';
import type { GameState, Location } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, EmptyState, Icon, Spinner } from '../../../ui';
import { deriveStatus } from '../status';
import { ModeCard } from '../TravelPicker';
import { bookLabel, useTravel } from '../travel';

function useKm(state: GameState, locations: Location[]) {
  return useMemo(() => {
    const here = locations.find((l) => l.id === state.location.id) ?? state.location;
    return locations
      .filter((l) => l.id !== here.id)
      .map((l) => ({ l, km: (Math.hypot(l.x - here.x, l.y - here.y) / 1000) * 18 + (l.remote_km || 0) }))
      .sort((a, b) => a.km - b.km);
  }, [state.location, locations]);
}

const kmLabel = (km: number) => (km < 1 ? `${Math.round(km * 1000)} m` : `${km.toFixed(1)} km`);

function Options({ dest, state, onBooked, onBack }: { dest: Location; state: GameState; onBooked: () => void; onBack: () => void }) {
  const cash = state.profile.cash;
  const { quote, loading, err, mode, setMode, going, load, go, selected } = useTravel(dest, cash, onBooked);
  const now = useLiveNow(true, 1000);
  const blocked = deriveStatus(state, now).blockedReason;
  // eslint-disable-next-line react-hooks/exhaustive-deps -- quote once per destination
  useEffect(() => { void load(); }, [dest.id]);
  const isHome = dest.id === state.profile.home_location_id;
  // Rides first (keke, bus, drop, car), walking last.
  const opts = quote ? [...quote.options].sort((a, b) => Number(a.mode === 'walk') - Number(b.mode === 'walk')) : [];
  return (
    <div className="phone-app__body ride-app">
      <button type="button" className="ride-dest" onClick={onBack} aria-label="Change destination">
        <span className="ride-dest__dots" aria-hidden><span /><span /></span>
        <span className="grow">
          <span className="ride-dest__from">{state.location.name}</span>
          <span className="ride-dest__to">{isHome ? 'Home' : dest.name}<span className="muted"> · {districtName(dest.district)}</span></span>
        </span>
        <span className="ride-dest__edit">Change</span>
      </button>
      <div className="ride-app__head">
        <h4>Choose a ride</h4>
        {quote && <span className="chip"><Icon name="road" size={12} /> {quote.km.toFixed(1)} km</span>}
        {loading && <Spinner size={14} />}
      </div>
      {err && <p className="error-text">{err} <button type="button" className="ride-retry" onClick={() => void load()}>Try again</button></p>}
      {!quote && !err && <div className="panel-skel"><span /><span /><span /></div>}
      {quote && (opts.length === 0
        ? <EmptyState icon="road" title="No route" body="There is no way to get there right now." />
        : <div className="mode-grid">{opts.map((o) => <ModeCard key={o.mode} o={o} cash={cash} active={o.mode === mode} onPick={() => setMode(o.mode)} />)}</div>)}
      {blocked && <p className="travel-blocked"><Icon name="info" size={16} /> {blocked}</p>}
      {quote && (
        <div className="ride-app__book">
          <Button size="lg" block variant="green" loading={going}
            disabled={Boolean(blocked) || !selected || !selected.allowed || selected.cost > cash} onClick={() => void go()}>
            {bookLabel(selected, 'Book')}
          </Button>
        </div>
      )}
    </div>
  );
}

export default function RideApp({ state, onPickOnMap, onBooked }: { state: GameState; onPickOnMap: () => void; onBooked: () => void }) {
  const locations = useGame((s) => s.locations);
  const rows = useKm(state, locations);
  const homeId = state.profile.home_location_id;
  const [dest, setDest] = useState<Location | null>(null);
  const [q, setQ] = useState('');

  if (dest) return <Options dest={dest} state={state} onBooked={onBooked} onBack={() => setDest(null)} />;

  const needle = q.trim().toLowerCase();
  const list = needle
    ? rows.filter(({ l }) => `${l.name} ${districtName(l.district)} ${l.id === homeId ? 'home' : ''}`.toLowerCase().includes(needle))
    : [...rows.filter(({ l }) => l.id === homeId), ...rows.filter(({ l }) => l.id !== homeId)];
  return (
    <div className="phone-app__body ride-app">
      <label className="ride-search">
        <Icon name="pin" size={16} />
        <input className="ride-search__input" type="search" placeholder="Where to?" value={q} onChange={(e) => setQ(e.target.value)}
          aria-label="Search places" />
      </label>
      <button type="button" className="ride-row ride-row--map" onClick={onPickOnMap}>
        <span className="ride-row__pin" aria-hidden>🗺️</span>
        <span className="grow">
          <span className="ride-row__name">Pick on the map</span>
          <span className="ride-row__sub">Tap a place, then choose how to go</span>
        </span>
        <Icon name="chevronRight" size={16} />
      </button>
      <ul className="ride-list">
        {list.map(({ l, km }) => (
          <li key={l.id}>
            <button type="button" className="ride-row" onClick={() => setDest(l)}>
              <span className="ride-row__pin" aria-hidden>{l.id === homeId ? '🏠' : '📍'}</span>
              <span className="grow">
                <span className="ride-row__name">{l.id === homeId ? 'Home' : l.name}</span>
                <span className="ride-row__sub">{districtName(l.district)}</span>
              </span>
              <span className="ride-row__km">{kmLabel(km)}</span>
            </button>
          </li>
        ))}
        {list.length === 0 && <li className="phone-app__lead">No place called “{q}”.</li>}
      </ul>
    </div>
  );
}
