// G1: "Where will you park your new car?" Opens after a car purchase (any shop path) and from the home sheet's
// "Build a garage". Lists the garage types with real prices; ones the home can't take are shown but disabled.
// docs/GARAGE.md
import { useEffect, useState } from 'react';
import { garageBuild, garageHome, type GarageHome, type GarageType } from '../../api/garage';
import { errorMessage } from '../../lib/api';
import { naira, nairaShort } from '../../lib/format';
import { useGame } from '../../state/game';
import { useGarage } from '../../state/garage';
import { Button, Sheet, toast } from '../../ui';
import { Thumb } from '../../art/thumbs/Thumb';
import { SellCarButton } from './SellCar';

const KIND_LABEL: Record<string, string> = {
  hostel: 'hostel room', face_me: 'face-me-I-face-you room', self_contain: 'self-contain', mini_flat: 'mini flat', duplex: 'GRA duplex',
};
const EMOJI: Record<string, string> = { carport: '🅿️', garage_standard: '🏠', garage_luxury: '🏛️' };

function needs(t: GarageType): string {
  return t.capacity >= 2 ? 'Needs a duplex' : 'Needs a self-contain or bigger';
}

export function GarageSheet() {
  const sheet = useGarage((s) => s.sheet);
  const version = useGarage((s) => s.version);
  const close = useGarage((s) => s.close);
  const bump = useGarage((s) => s.bump);
  const refresh = useGame((s) => s.refresh);
  const [data, setData] = useState<GarageHome | null>(null);
  const [error, setError] = useState('');
  const [pick, setPick] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!sheet) return;
    let alive = true;
    setError('');
    garageHome().then((d) => {
      if (!alive) return;
      setData(d);
      const first = d.types.find((t) => t.allowed && t.id !== d.garage?.type);
      setPick(first?.id ?? null);
    }).catch((e) => alive && setError(errorMessage(e)));
    return () => { alive = false; };
  }, [sheet, version]);

  // garage.enabled off: no offer after a car purchase
  useEffect(() => { if (sheet === 'car' && data && !data.enabled) close(); }, [sheet, data, close]);

  const chosen = data?.types.find((t) => t.id === pick) ?? null;
  const build = async () => {
    if (!chosen) return;
    setBusy(true);
    try {
      const r = await garageBuild(chosen.id);
      toast(r.message, 'good');
      await refresh();
      bump();
      close();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const afterCar = sheet === 'car';
  const current = data?.garage ?? null;
  const offline = data && !data.enabled;
  return (
    <Sheet open={sheet !== null} onClose={close} className="garage-sheet"
      title={afterCar ? 'Where will you park your new car?' : current ? 'Your garage' : 'Build a garage'}
      subtitle={afterCar ? 'Build a garage at home, or leave it parked outside.'
        : current ? `${current.name} · fits ${current.capacity} car${current.capacity > 1 ? 's' : ''}. Upgrading replaces it at the full new price.`
        : 'Your cars park at home. Without a garage they stand outside.'}
      footer={
        <div className="garage-sheet__foot">
          <Button block loading={busy} disabled={!chosen || !chosen.allowed || Boolean(offline)} onClick={() => void build()}>
            {chosen ? `${current ? 'Upgrade to' : 'Build'} ${chosen.name.toLowerCase()} · ${nairaShort(chosen.price)}` : 'Build a garage'}
          </Button>
          <Button block variant="ghost" onClick={close}>{afterCar ? 'Not now (park outside)' : 'Close'}</Button>
        </div>
      }>
      {error && <p className="error-text">{error}</p>}
      {!data && !error && <div className="panel-skel"><span /><span /><span /></div>}
      {offline && <p className="muted">Garages are switched off right now. Your car parks outside.</p>}
      {data && !offline && (
        <div className="garage-opts" role="radiogroup" aria-label="Garage type">
          {data.types.map((t) => {
            const mine = current?.type === t.id;
            const disabled = !t.allowed || mine;
            return (
              <button key={t.id} type="button" role="radio" aria-checked={pick === t.id} disabled={disabled}
                className={`garage-opt${pick === t.id ? ' is-picked' : ''}`} onClick={() => setPick(t.id)}>
                <span className="garage-opt__emoji" aria-hidden>{EMOJI[t.id] ?? (t.style === 'carport' ? '🅿️' : '🏠')}</span>
                <span className="grow">
                  <span className="garage-opt__title">{t.name}</span>
                  <span className="garage-opt__sub">{t.description}</span>
                  <span className="garage-opt__meta">
                    Fits {t.capacity} car{t.capacity > 1 ? 's' : ''}
                    {mine ? ' · You have this' : !t.allowed ? ` · ${needs(t)}` : ''}
                  </span>
                </span>
                <span className="garage-opt__price" title={naira(t.price)}>{nairaShort(t.price)}</span>
              </button>
            );
          })}
          {!afterCar && data.cars.length > 0 && (
            <div className="garage-cars">
              <h4 className="garage-cars__title">Your cars</h4>
              {data.cars.map((c) => (
                <div key={c.id} className="cars-mine__row">
                  <Thumb spec={{ type: 'car', id: c.id }} fallback="🚗" className="cars-mine__thumb" />
                  <span className="grow">
                    <span className="cars-mine__name">{c.name}</span>
                    <span className="cars-mine__sub">List price {nairaShort(c.price)}</span>
                  </span>
                  <SellCarButton car={c} />
                </div>
              ))}
            </div>
          )}
          <p className="garage-note">
            Your home: {KIND_LABEL[data.kind] ?? data.kind}. Bank first, then cash. A garage stays with this home: if you move, you build again.
          </p>
        </div>
      )}
    </Sheet>
  );
}
