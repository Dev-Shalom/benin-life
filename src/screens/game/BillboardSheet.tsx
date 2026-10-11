// H3 board sheet (docs/BILLBOARDS.md): tap a billboard on the map (or Phone → Billboards).
// View: ON AIR + how many ads take turns, a swipe carousel of the live ads (Visit <domain> + until <date>,
// Report), "+ Add your ad to this board". Add: 2:1 image picker (resized/compressed in the browser), https link,
// 1 / 3 / 7 days, date range + price, Pay → Paystack → the server marks it paid → admin review.
import { useEffect, useMemo, useRef, useState } from 'react';
import { useConfig } from '../../lib/config';
import { paystackReady } from '../../lib/payments';
import {
  adImageUrl, adIndexNow, buyAd, compressAdImage, domainOf, DURATIONS, HOUSE_ADS, houseAdUrl, koboLabel, linkOk, noteAdTap,
  reportAd, shortDate, useBillboards, type Board, type BoardAd, type Duration, type HouseAd,
} from '../../lib/billboards';
import { serverNow } from '../../lib/clock';
import type { GameState } from '../../lib/types';
import { useUi } from '../../state/ui';
import { Button, Icon, Modal, Sheet, toast } from '../../ui';
import { errorMessage } from '../../lib/api';
import '../../styles/billboards.css';

const REPORT_REASONS = ['Scam or fraud', 'Adult content', 'Coins or tokens', 'Selling accounts', 'Pretending to be Benin Life', 'Something else'];

export default function BillboardSheet({ state }: { state: GameState }) {
  const sheet = useBillboards((s) => s.sheet);
  const data = useBillboards((s) => s.data);
  const close = useBillboards((s) => s.close);
  const open = useBillboards((s) => s.open);
  const board = data?.boards.find((b) => b.id === sheet?.board) ?? null;
  const [isOpen, setIsOpen] = useState(true);
  const shut = () => {
    setIsOpen(false);
    window.setTimeout(close, 260);
  };
  const mode = sheet?.mode ?? 'view';
  return (
    <Sheet open={isOpen && Boolean(sheet)} onClose={shut} className="bb-sheet"
      header={board ? <BoardHead board={board} /> : <div className="bb-head"><b>Billboard</b></div>}>
      {!data && <div className="panel-skel"><span /><span /><span /></div>}
      {data && !board && <p className="bb-note">This billboard is not available right now.</p>}
      {data && board && (mode === 'add'
        ? <AddAd key={'add:' + board.id} board={board} data={data} state={state} onBack={() => open(board.id, 'view')} onDone={shut} />
        : <BoardView key={'view:' + board.id} board={board} rotate={data.rotate_seconds} buyEnabled={data.buy_enabled && paystackReady()}
            onAdd={() => open(board.id, 'add')} onClose={shut} />)}
    </Sheet>
  );
}

function BoardHead({ board }: { board: Board }) {
  return (
    <div className="bb-head">
      <span className="bb-head__icon" aria-hidden>📣</span>
      <span className="grow">
        <b className="bb-head__name">{board.name}</b>
        <span className="bb-head__area">{board.area}</span>
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* View: the carousel                                                    */
/* ------------------------------------------------------------------ */
function BoardView({ board, rotate, buyEnabled, onAdd, onClose }: { board: Board; rotate: number; buyEnabled: boolean; onAdd: () => void; onClose: () => void }) {
  const ads = board.ads;
  const n = ads.length;
  const [onAir, setOnAir] = useState(() => adIndexNow(n || HOUSE_ADS.length, rotate));
  const [leaving, setLeaving] = useState<BoardAd | null>(null);
  const [reporting, setReporting] = useState<BoardAd | null>(null);
  const track = useRef<HTMLDivElement>(null);
  const openPanel = useUi((s) => s.openPanel);
  const setOverlay = useUi((s) => s.setOverlay);
  // follow the board: the card on air now is marked, the carousel starts there
  useEffect(() => {
    const count = n || HOUSE_ADS.length;
    let t = 0;
    const tick = () => {
      setOnAir(adIndexNow(count, rotate));
      const period = Math.max(5, rotate) * 1000;
      t = window.setTimeout(tick, period - (serverNow() % period) + 30);
    };
    tick();
    return () => window.clearTimeout(t);
  }, [n, rotate]);
  const scrolled = useRef(false);
  useEffect(() => {
    if (scrolled.current || !track.current) return;
    const el = track.current.children[onAir] as HTMLElement | undefined;
    if (el) track.current.scrollLeft = el.offsetLeft - 16;
    scrolled.current = true;
  }, [onAir]);
  const price7 = board.prices['7'];
  const house = (h: HouseAd) => {
    if (h.id === 'topup') { onClose(); openPanel('wallet'); }
    else if (h.id === 'boutique') { onClose(); setOverlay('boutique'); }
    else if (h.id === 'events') { onClose(); toast('Check "On today" on the map for tonight\'s events.', 'info'); }
    else if (buyEnabled) onAdd();
    else toast('Booking a billboard opens soon.', 'info');
  };

  return (
    <div className="bb-view">
      <div className="bb-onair">
        <span className="bb-onair__pill"><span aria-hidden /> ON AIR</span>
        <span className="bb-onair__text">{n ? `${n} ${n === 1 ? 'ad takes' : 'ads take'} turns, ${rotate} s each` : `House ads on air · be the first to book`}</span>
      </div>
      <div className="bb-track" ref={track} role="list" aria-label="Ads on this board">
        {n > 0
          ? ads.map((a, i) => (
              <div key={a.id} className={`bb-card${i === onAir ? ' is-onair' : ''}`} role="listitem">
                <div className="bb-frame">
                  <img src={adImageUrl(a.image)} alt={a.link ? `Ad for ${domainOf(a.link)}` : 'Ad'}
                    loading={Math.abs(i - onAir) <= 2 ? 'eager' : 'lazy'} />
                  {i === onAir && <span className="bb-frame__live">On screen now</span>}
                  {a.sponsor && <span className="bb-frame__tag">Sponsor</span>}
                </div>
                <div className="bb-card__row">
                  {a.link ? (
                    <button type="button" className="bb-visit" onClick={() => setLeaving(a)}>
                      <ExternalIcon /> Visit {domainOf(a.link)}
                    </button>
                  ) : <span className="bb-visit bb-visit--none">{a.sponsor ? 'Sponsor' : 'Ad'}</span>}
                  <span className="bb-until">until {shortDate(a.ends_at)}</span>
                </div>
                {!a.mine && <button type="button" className="bb-report" onClick={() => setReporting(a)}><Icon name="warning" size={13} /> Report</button>}
                {a.mine && <span className="bb-report bb-report--mine">Your ad</span>}
              </div>
            ))
          : HOUSE_ADS.map((h, i) => (
              <div key={h.id} className={`bb-card${i === onAir ? ' is-onair' : ''}`} role="listitem">
                <div className="bb-frame">
                  <img src={houseAdUrl(h.id)} alt={h.title} />
                  <span className="bb-frame__tag">Benin Life</span>
                </div>
                <div className="bb-card__row">
                  <button type="button" className="bb-visit" onClick={() => house(h)}>{h.cta}</button>
                  <span className="bb-until">house ad</span>
                </div>
              </div>
            ))}
      </div>
      <button type="button" className="bb-add" onClick={() => (buyEnabled ? onAdd() : toast('Booking a billboard opens soon. Hold on!', 'info'))}>
        <Icon name="plus" size={20} stroke={2.4} /> Add your ad to this board
      </button>
      <p className="bb-foot">
        A digital board: yours goes live after a quick check and takes turns with {n ? `the ${n} ${n === 1 ? 'ad' : 'ads'} here` : 'the other ads'} · {koboLabel(price7)} for 7 days
        {!buyEnabled && <><br />Booking opens soon.</>}
      </p>
      <LeaveModal ad={leaving} onClose={() => setLeaving(null)} />
      <ReportModal ad={reporting} onClose={() => setReporting(null)} />
    </div>
  );
}

function ExternalIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M14 4h6v6M20 4l-9 9M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4" />
    </svg>
  );
}

/** "You are leaving Benin Life" before any outside link (opened in a new tab with rel=noopener). */
function LeaveModal({ ad, onClose }: { ad: BoardAd | null; onClose: () => void }) {
  const [last, setLast] = useState<BoardAd | null>(ad);
  if (ad && ad !== last) setLast(ad);
  const a = ad ?? last;
  const url = a?.link && linkOk(a.link) ? a.link : null;
  return (
    <Modal open={Boolean(ad)} onClose={onClose} title="You are leaving Benin Life"
      art={<span className="bb-leave__art" aria-hidden>🌍</span>}
      actions={<>
        <Button variant="ghost" onClick={onClose}>Stay here</Button>
        {url && (
          <a className="bl-btn bl-btn--green bl-btn--md bb-leave__go" href={url} target="_blank" rel="noopener noreferrer"
            onClick={() => { if (a) noteAdTap(a.id); window.setTimeout(onClose, 50); }}>
            Open {domainOf(url)}
          </a>
        )}
      </>}>
      <p>This ad links to <b>{domainOf(url)}</b>, a website the Benin Life team does not run. Never share your password, and don't pay anyone you don't trust.</p>
    </Modal>
  );
}

function ReportModal({ ad, onClose }: { ad: BoardAd | null; onClose: () => void }) {
  const [reason, setReason] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const send = async () => {
    if (!ad || !reason) return;
    setBusy(true);
    try {
      toast(await reportAd(ad.id, reason), 'good');
      onClose();
      setReason(null);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <Modal open={Boolean(ad)} onClose={onClose} title="Report this ad"
      actions={<>
        <Button variant="ghost" onClick={onClose}>Cancel</Button>
        <Button variant="danger" disabled={!reason} loading={busy} onClick={() => void send()}>Report</Button>
      </>}>
      <p className="bb-report__lead">What's wrong with it? The Benin Life team checks every report.</p>
      <div className="bb-reasons">
        {REPORT_REASONS.map((r) => (
          <button key={r} type="button" className={`bb-reason${reason === r ? ' is-on' : ''}`} onClick={() => setReason(r)}>{r}</button>
        ))}
      </div>
    </Modal>
  );
}

/* ------------------------------------------------------------------ */
/* Add: the booking form                                                */
/* ------------------------------------------------------------------ */
function AddAd({ board, data, state, onBack, onDone }: {
  board: Board; data: { rotate_seconds: number; buy_enabled: boolean; max_ads: number }; state: GameState; onBack: () => void; onDone: () => void;
}) {
  const [img, setImg] = useState<{ blob: Blob; url: string; type: string; width: number; height: number } | null>(null);
  const [imgErr, setImgErr] = useState<string | null>(null);
  const [preparing, setPreparing] = useState(false);
  const [link, setLink] = useState('https://');
  const [touched, setTouched] = useState(false);
  const [days, setDays] = useState<Duration>(7);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const openPhone = useUi((s) => s.openPhone);
  const reload = useBillboards((s) => s.load);
  const maxPerPlayer = useConfig().cfg<number>('billboards.max_active_per_player', 3);
  useEffect(() => () => { if (img) URL.revokeObjectURL(img.url); }, [img]);

  const price = board.prices[String(days) as '1' | '3' | '7'];
  const end = useMemo(() => new Date(serverNow() + days * 86_400_000), [days]);
  const others = board.ads.length;
  const linkValid = linkOk(link);
  const ready = paystackReady() && data.buy_enabled;

  const pick = async (f: File | undefined) => {
    if (!f) return;
    setImgErr(null);
    setPreparing(true);
    try {
      const r = await compressAdImage(f);
      setImg((old) => {
        if (old) URL.revokeObjectURL(old.url);
        return r;
      });
    } catch (e) {
      setImgErr(e instanceof Error ? e.message : 'That image could not be used.');
    } finally {
      setPreparing(false);
      if (file.current) file.current.value = '';
    }
  };

  const pay = async () => {
    if (!img || !linkValid || busy) return;
    setBusy(true);
    const r = await buyAd({ board: board.id, days, image: img.blob, type: img.type, link, userId: state.profile.id });
    setBusy(false);
    if (r.status === 'cancelled') return;
    if (r.status === 'error') {
      toast(r.message, 'bad');
      return;
    }
    void reload(true);
    setDone(r.message);
  };

  if (done) {
    return (
      <div className="bb-done">
        <span className="bb-done__art" aria-hidden>🎉</span>
        <h3>Ad sent for review</h3>
        <p>{done}</p>
        <div className="bb-actions">
          <Button variant="ghost" onClick={onDone}>Done</Button>
          <Button variant="green" className="grow" onClick={() => { onDone(); openPhone('billboards:mine'); }}>See My ads</Button>
        </div>
      </div>
    );
  }

  const cta = !img ? 'Add an image' : !linkValid ? 'Add your link' : `Pay ${koboLabel(price)}`;
  return (
    <div className="bb-add-form">
      <button type="button" className={`bb-picker${img ? ' has-img' : ''}${preparing ? ' is-busy' : ''}`} onClick={() => file.current?.click()}
        aria-label={img ? 'Change your image' : 'Add your image'}>
        {img ? <img src={img.url} alt="Your ad" /> : (
          <span className="bb-picker__empty">
            <svg width="54" height="54" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <rect x="3" y="5" width="15" height="15" rx="2.5" /><circle cx="8.5" cy="10" r="1.6" /><path d="m3.5 18 4.5-4.5 3 3 2.5-2.5 4.5 4.5" /><path d="M19 2v6M16 5h6" />
            </svg>
            <b>{preparing ? 'Preparing your image…' : 'Add your image'}</b>
            <small>Logo or banner · wide images look best (2:1)</small>
          </span>
        )}
        {img && <span className="bb-picker__change">Change</span>}
        <span className="bb-picker__tag">AD</span>
      </button>
      <input ref={file} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => void pick(e.target.files?.[0])} />
      {imgErr && <p className="error-text">{imgErr}</p>}
      {img && <p className="bb-hint">{img.width}×{img.height} · {(img.blob.size / 1024).toFixed(0)} KB, ready to upload</p>}

      <span className="bb-label">How long</span>
      <div className="bb-days" role="radiogroup" aria-label="How long">
        {DURATIONS.map((d) => (
          <button key={d} type="button" role="radio" aria-checked={days === d} className={`bb-day${days === d ? ' is-on' : ''}`} onClick={() => setDays(d)}>
            <b>{d} {d === 1 ? 'day' : 'days'}</b>
            <small>{koboLabel(board.prices[String(d) as '1' | '3' | '7'])}</small>
          </button>
        ))}
      </div>

      <label className="bb-label" htmlFor="bb-link">Link</label>
      <input id="bb-link" className={`bb-input${touched && !linkValid ? ' is-bad' : ''}`} type="url" inputMode="url" autoComplete="url"
        spellCheck={false} value={link} onChange={(e) => setLink(e.target.value.replace(/\s/g, ''))} onBlur={() => setTouched(true)}
        placeholder="https://" maxLength={300} />
      <p className={`bb-hint${touched && !linkValid ? ' is-bad' : ''}`}>
        {touched && !linkValid ? 'Use a full https:// link, like https://wa.me/2348012345678 or https://yourshop.com.' : 'Players who tap your billboard go here.'}
      </p>

      <div className="bb-when">
        <span className="grow">
          <b>Today → {shortDate(end)}</b>
          <small>Goes live after a quick check · rotates with {others} other {others === 1 ? 'ad' : 'ads'}</small>
        </span>
        <b className="bb-when__price">{koboLabel(price)}</b>
      </div>

      <div className="bb-actions">
        <Button variant="ghost" size="lg" onClick={onBack} disabled={busy}>Back</Button>
        <Button variant="green" size="lg" className="grow" disabled={!img || !linkValid || !ready} loading={busy} onClick={() => void pay()}>
          {ready ? cta : 'Booking opens soon'}
        </Button>
      </div>
      <p className="bb-foot">
        Secure payment by Paystack. Your ad shows once the Benin Life team approves it; if it is not approved you get your money back.
        Ads that break our rules (scams, adult content, coins or tokens, selling accounts, or pretending to be Benin Life) are taken down without a refund.
        Up to {maxPerPlayer} ads at a time.
      </p>
    </div>
  );
}
