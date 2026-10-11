// H3 phone app "Billboards" (docs/BILLBOARDS.md): every digital board (what's on air, price from) and
// My ads (status, days left, views and taps). Tapping a board opens the board sheet on the map.
import { useEffect, useState } from 'react';
import {
  adImageUrl, adIndexNow, daysLeft, houseAdUrl, HOUSE_ADS, koboLabel, loadMyAds, shortDate, useBillboards, type MyAd,
} from '../../../lib/billboards';
import { errorMessage } from '../../../lib/api';
import { EmptyState, Segmented } from '../../../ui';
import '../../../styles/billboards.css';

const STATUS: Record<MyAd['status'], [string, string]> = {
  awaiting_payment: ['Waiting for payment', 'wait'],
  pending_review: ['In review', 'review'],
  live: ['On air', 'live'],
  rejected: ['Not approved', 'bad'],
  removed: ['Taken down', 'bad'],
  expired: ['Ended', 'ended'],
  cancelled: ['Cancelled', 'ended'],
};
const REFUND: Record<MyAd['refund_status'], string | null> = {
  none: null, pending: 'Refund on the way', processing: 'Refund on the way', refunded: 'Refunded', refund_failed: 'Refund delayed: the team is on it',
};

export default function BillboardsApp({ onOpenBoard, initialTab = 'boards' }: { onOpenBoard: (id: string) => void; initialTab?: 'boards' | 'mine' }) {
  const [tab, setTab] = useState<'boards' | 'mine'>(initialTab);
  return (
    <div className="phone-app__body bb-app">
      <Segmented label="Billboards" value={tab} onChange={setTab} options={[{ id: 'boards', label: 'Boards' }, { id: 'mine', label: 'My ads' }]} />
      {tab === 'boards' ? <Boards onOpenBoard={onOpenBoard} /> : <MyAds onOpenBoard={onOpenBoard} />}
    </div>
  );
}

function Boards({ onOpenBoard }: { onOpenBoard: (id: string) => void }) {
  const data = useBillboards((s) => s.data);
  const error = useBillboards((s) => s.error);
  const load = useBillboards((s) => s.load);
  useEffect(() => { void load(); }, [load]);
  if (!data) return error ? <p className="phone-app__lead">{error}</p> : <div className="panel-skel"><span /><span /><span /></div>;
  if (!data.enabled || !data.boards.length) return <EmptyState icon="info" title="No billboards right now" body="Check back soon." />;
  return (
    <>
      <p className="bb-app__lead">Digital screens at the busiest spots in Benin. Ads take turns every {data.rotate_seconds} s, and everybody sees the same one.</p>
      <ul className="bb-list">
        {data.boards.map((b) => {
          const n = b.ads.length;
          const cur = n ? b.ads[adIndexNow(n, data.rotate_seconds)] : null;
          const from = Math.min(b.prices['1'], b.prices['3'] / 3, b.prices['7'] / 7);
          return (
            <li key={b.id}>
              <button type="button" className="bb-row" onClick={() => onOpenBoard(b.id)}>
                <span className="bb-thumb"><img src={cur ? adImageUrl(cur.image) : houseAdUrl(HOUSE_ADS[3].id, 240)} alt="" loading="lazy" /></span>
                <span className="grow">
                  <span className="bb-row__name">{b.name}</span>
                  <span className="bb-row__sub">{b.area}</span>
                  <span className="bb-row__meta">
                    {n > 0 ? <span className="bb-live-dot">● {n} on air</span> : <span>Free to book</span>}
                    <span>· {koboLabel(b.prices['7'])} / 7 days · from {koboLabel(Math.round(from / 100) * 100)}/day</span>
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function MyAds({ onOpenBoard }: { onOpenBoard: (id: string) => void }) {
  const [ads, setAds] = useState<MyAd[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    loadMyAds().then((r) => alive && setAds(r)).catch((e) => alive && setErr(errorMessage(e)));
    return () => { alive = false; };
  }, []);
  if (err) return <p className="phone-app__lead">{err}</p>;
  if (!ads) return <div className="panel-skel"><span /><span /></div>;
  if (!ads.length) return <EmptyState icon="star" title="No ads yet" body="Pick a board in the Boards tab and book your first ad. It shows to every player who passes." />;
  return (
    <ul className="bb-list">
      {ads.map((a) => {
        const [label, tone] = STATUS[a.status];
        const left = a.status === 'live' ? daysLeft(a.ends_at) : 0;
        const refund = REFUND[a.refund_status];
        return (
          <li key={a.id} className="bb-my">
            <div className="bb-my__top">
              <span className="bb-thumb"><img src={adImageUrl(a.image)} alt="" loading="lazy" /></span>
              <span className="grow">
                <button type="button" className="bb-row__name" style={{ border: 0, background: 'none', padding: 0, font: 'inherit', fontWeight: 700, cursor: 'pointer', textAlign: 'left' }}
                  onClick={() => onOpenBoard(a.board_id)}>{a.board}</button>
                <span className="bb-row__sub">{a.days} {a.days === 1 ? 'day' : 'days'} · {koboLabel(a.paid_kobo ?? a.price_kobo)}</span>
                <span className={`bb-status bb-status--${tone}`}>{label}{a.status === 'live' ? ` · ${left} ${left === 1 ? 'day' : 'days'} left` : ''}</span>
              </span>
            </div>
            <div className="bb-my__stats">
              <span className="bb-stat"><b>{a.views.toLocaleString('en-NG')}</b><small>views</small></span>
              <span className="bb-stat"><b>{a.taps.toLocaleString('en-NG')}</b><small>taps</small></span>
              <span className="bb-stat"><b>{a.views ? ((a.taps / a.views) * 100).toFixed(1) + '%' : '–'}</b><small>tap rate</small></span>
            </div>
            <p className="bb-my__note">
              {a.status === 'live' && a.starts_at && a.ends_at && `${shortDate(a.starts_at)} → ${shortDate(a.ends_at)}`}
              {a.status === 'pending_review' && 'Paid. The Benin Life team checks every ad, usually within a few hours.'}
              {a.status === 'awaiting_payment' && 'Not paid yet. If you paid, it updates as soon as Paystack confirms.'}
              {(a.status === 'rejected' || a.status === 'removed') && a.reject_reason && `Reason: ${a.reject_reason}`}
              {a.status === 'expired' && a.ends_at && `Ended ${shortDate(a.ends_at)}.`}
              {refund && <><br />{refund}</>}
            </p>
          </li>
        );
      })}
    </ul>
  );
}
