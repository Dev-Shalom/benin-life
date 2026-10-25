// "Real business (show on the map)": the form, the payment sheet (price, days, terms) and "My real listings" (status, views, taps, renew).
// Payment reuses the Paystack flow of the billboards: images go to the real-biz bucket, real_biz_create makes the listing (awaiting payment)
// and returns a BLRB- reference, Paystack Inline charges it, paystack-verify marks it paid; the owner then approves it in Admin.
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  realBizCancel, realBizCreate, realBizForm, realBizMine, realBizRenewStart, realImageUrl, type RealDraft, type RealForm, type RealInit, type RealMine,
} from '../../../api/company';
import { compressAdImage, koboLabel, shortDate } from '../../../lib/billboards';
import { errorMessage } from '../../../lib/api';
import { paystackCheckout, paystackReady } from '../../../lib/payments';
import { supabase } from '../../../lib/supabase';
import { useGame } from '../../../state/game';
import { Button, Modal, toast } from '../../../ui';
import './CompanyApp.css';

const EMPTY: RealDraft = { name: '', category: 'food_spot', desc: '', phone: '', whatsapp: '', instagram: '', website: '', address: '', area: 'ugbowo', slot: '', images: [], logo: '🏪', company: null, terms: false };
const PIN_LOGOS = ['🏪', '🍲', '🥖', '✂️', '👗', '📱', '💊', '🚗', '🛵', '💻', '🎉', '📚', '🏠', '🐟', '💈', '🎧'];
const STATUS_TEXT: Record<RealMine['status'], string> = {
  awaiting_payment: 'Waiting for payment', pending_review: 'In review', live: 'On the map', rejected: 'Not approved', suspended: 'Taken off the map',
  expired: 'Ended', removed: 'Removed', cancelled: 'Cancelled',
};

interface Photo { path: string; url: string }

export function RealBizFormModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [form, setForm] = useState<RealForm | null>(null);
  const [d, setD] = useState<RealDraft>(EMPTY);
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [step, setStep] = useState<'form' | 'pay'>('form');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const uid = useGame((s) => s.state?.profile.id);
  useEffect(() => { realBizForm().then((f) => { setForm(f); setD((x) => ({ ...x, area: f.areas.find((a) => a.slots.length > 0 && a.used < a.cap)?.id ?? f.areas[0]?.id ?? 'ugbowo' })); }).catch((e) => setErr(errorMessage(e))); }, []);
  const area = form?.areas.find((a) => a.id === d.area);
  useEffect(() => { if (area && !area.slots.some((s) => s.id === d.slot)) setD((x) => ({ ...x, slot: area.slots[0]?.id ?? '' })); }, [area, d.slot]);
  const set = <K extends keyof RealDraft>(k: K, v: RealDraft[K]) => setD((x) => ({ ...x, [k]: v }));

  const addPhoto = async (file: File | undefined) => {
    if (!file || !uid || !form) return;
    setBusy(true); setErr('');
    try {
      const c = await compressAdImage(file);
      const ext = c.type === 'image/webp' ? 'webp' : c.type === 'image/png' ? 'png' : 'jpg';
      const path = `${uid}/${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const up = await supabase.storage.from('real-biz').upload(path, c.blob, { contentType: c.type, cacheControl: '31536000', upsert: false });
      if (up.error) throw new Error('Upload failed. Check your connection and try again.');
      setPhotos((p) => [...p, { path, url: c.url }]);
    } catch (e) { setErr(errorMessage(e)); } finally { setBusy(false); }
  };
  const dropPhoto = (path: string) => { setPhotos((p) => p.filter((x) => x.path !== path)); void supabase.storage.from('real-biz').remove([path]); };

  const problems = useMemo(() => {
    const p: string[] = [];
    if (d.name.trim().length < 3) p.push('business name');
    if (d.desc.trim().length < 15) p.push('a short description');
    if (d.address.trim().length < 5) p.push('address');
    if (!d.phone.trim() && !d.whatsapp.trim() && !d.instagram.trim() && !d.website.trim()) p.push('one way to contact you');
    if (photos.length < 1) p.push('at least one photo');
    if (!d.slot) p.push('a map spot');
    if (!d.terms) p.push('accept the terms');
    return p;
  }, [d, photos]);

  const pay = async () => {
    setBusy(true); setErr('');
    let init: RealInit | null = null;
    try {
      init = await realBizCreate({ ...d, images: photos.map((p) => p.path) });
      const r = await paystackCheckout(init, { purpose: 'real_business', biz_id: init.biz_id, days: init.days });
      if (r === 'cancelled') { await realBizCancel(init.biz_id).catch(() => {}); setStep('form'); return; }
      if ('error' in r) { await realBizCancel(init.biz_id).catch(() => {}); setErr(r.error); setStep('form'); return; }
      toast(r.ok ? 'Paid! Your pin goes on the map as soon as the Benin Life team checks it.' : 'Payment received. It shows in My real listings once Paystack confirms it.', 'good');
      onDone();
    } catch (e) { setErr(errorMessage(e)); setStep('form'); } finally { setBusy(false); }
  };

  const canBuy = Boolean(form?.buy_enabled) && paystackReady();
  return (
    <Modal open onClose={() => !busy && onClose()} title={step === 'pay' ? 'Pay and list' : '📍 Real business on the map'}
      actions={step === 'pay'
        ? <><Button variant="ghost" disabled={busy} onClick={() => setStep('form')}>Back</Button>
            <Button variant="gold" loading={busy} disabled={!canBuy} onClick={() => void pay()} data-testid="real-pay">{canBuy ? `Pay ${koboLabel(form?.price_kobo ?? 0)}` : 'Payments paused'}</Button></>
        : <><Button variant="ghost" onClick={onClose}>Close</Button>
            <Button variant="gold" disabled={problems.length > 0 || busy} onClick={() => setStep('pay')} data-testid="real-next">{problems.length ? 'Fill the form' : 'Next: pay'}</Button></>}>
      {!form && !err && <div className="panel-skel"><span /><span /></div>}
      {err && <p className="bz-err" role="alert">{err}</p>}
      {form && step === 'pay' && (
        <div className="co-form" data-testid="real-pay-sheet">
          <div className="bz-rows">
            <div><span>Business</span><b>{d.logo} {d.name}</b></div>
            <div><span>Area</span><b>{area?.name}</b></div>
            <div><span>Photos</span><b>{photos.length}</b></div>
            <div><span>On the map for</span><b>{form.days} days</b></div>
            <div><span>Price (real money)</span><b>{koboLabel(form.price_kobo)}</b></div>
          </div>
          <p className="bz-hint">Pay securely with Paystack. The Benin Life team checks your photos and details first (usually within a few hours). If we do not approve it, you are refunded automatically. This is an advert only: no payments between players and your business happen in the game.</p>
          <p className="co-terms">{form.terms} Questions: {form.contact_email}</p>
        </div>
      )}
      {form && step === 'form' && (
        <div className="co-form" data-testid="real-form">
          {!canBuy && <p className="bz-note">Listing payments are paused right now. You can fill the form, but cannot pay yet.</p>}
          <label className="bz-field"><span>Business name</span><input value={d.name} maxLength={40} onChange={(e) => set('name', e.target.value)} placeholder="e.g. Ada's Bakery" enterKeyHint="next" /></label>
          <div className="co-two">
            <label className="bz-field"><span>Category</span><select value={d.category} onChange={(e) => set('category', e.target.value)}>{form.categories.map((c) => <option key={c.id} value={c.id}>{c.icon} {c.name}</option>)}</select></label>
            <div className="bz-field"><span>Pin logo</span><div className="co-emoji">{PIN_LOGOS.map((l) => <button key={l} type="button" className={d.logo === l ? 'is-on' : ''} onClick={() => set('logo', l)} aria-label={`Logo ${l}`}>{l}</button>)}</div></div>
          </div>
          <label className="bz-field"><span>What you sell (short description)</span><textarea value={d.desc} maxLength={400} rows={3} onChange={(e) => set('desc', e.target.value)} placeholder="Fresh bread, cakes and small chops, delivery in GRA." /></label>
          <div className="bz-field"><span>Photos of your products or shop ({photos.length}/{form.max_images})</span>
            <div className="co-thumbs">
              {photos.map((p) => <span key={p.path} className="co-thumb"><img src={p.url} alt="" /><button type="button" aria-label="Remove photo" onClick={() => dropPhoto(p.path)}>×</button></span>)}
              {photos.length < form.max_images && <label className="co-thumb co-thumb--add">+<input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => { void addPhoto(e.target.files?.[0]); e.target.value = ''; }} /></label>}
            </div>
          </div>
          <div className="co-two">
            <label className="bz-field"><span>Phone</span><input value={d.phone} inputMode="tel" onChange={(e) => set('phone', e.target.value)} placeholder="08012345678" /></label>
            <label className="bz-field"><span>WhatsApp</span><input value={d.whatsapp} inputMode="tel" onChange={(e) => set('whatsapp', e.target.value)} placeholder="2348012345678" /></label>
          </div>
          <div className="co-two">
            <label className="bz-field"><span>Instagram</span><input value={d.instagram} onChange={(e) => set('instagram', e.target.value)} placeholder="@adabakes" autoCapitalize="none" /></label>
            <label className="bz-field"><span>Website</span><input value={d.website} inputMode="url" onChange={(e) => set('website', e.target.value)} placeholder="https://…" autoCapitalize="none" /></label>
          </div>
          <label className="bz-field"><span>Address</span><input value={d.address} maxLength={120} onChange={(e) => set('address', e.target.value)} placeholder="12 Airport Rd, GRA" enterKeyHint="done" /></label>
          <label className="bz-field"><span>Area on the map</span>
            <select value={d.area} onChange={(e) => set('area', e.target.value)}>{form.areas.map((a) => <option key={a.id} value={a.id} disabled={a.used >= a.cap || a.slots.length === 0}>{'₦'.repeat(a.tier)} {a.name} ({a.used >= a.cap || a.slots.length === 0 ? 'full' : `${a.cap - a.used} spots left`})</option>)}</select>
          </label>
          {area && area.slots.length > 0 && (
            <div className="bz-field"><span>Pick your spot</span><div className="co-spots">{area.slots.map((s, i) => <button key={s.id} type="button" className={d.slot === s.id ? 'is-on' : ''} onClick={() => set('slot', s.id)}>Spot {i + 1}</button>)}</div></div>
          )}
          {form.companies.length > 0 && (
            <label className="bz-field"><span>Link your in-game company (optional, adds "Visit in game")</span>
              <select value={d.company ?? ''} onChange={(e) => set('company', e.target.value ? Number(e.target.value) : null)}><option value="">No link</option>{form.companies.map((c) => <option key={c.id} value={c.id}>{c.logo} {c.name}</option>)}</select></label>
          )}
          <p className="co-terms">{form.terms}</p>
          <label className="co-check"><input type="checkbox" checked={d.terms} onChange={(e) => set('terms', e.target.checked)} /> <span>I accept the terms. My business is real and legal.</span></label>
          {problems.length > 0 && <p className="bz-hint">Still needed: {problems.join(', ')}.</p>}
          <p className="bz-hint">{koboLabel(form.price_kobo)} for {form.days} days, checked by the Benin Life team first. Contact: {form.contact_email}</p>
        </div>
      )}
    </Modal>
  );
}

export function RealListings({ onNew }: { onNew: () => void }) {
  const [rows, setRows] = useState<RealMine[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [info, setInfo] = useState<RealForm | null>(null);
  useEffect(() => { realBizForm().then(setInfo).catch(() => {}); }, []);
  const load = useCallback(() => { realBizMine().then(setRows).catch(() => setRows([])); }, []);
  useEffect(() => { load(); }, [load]);
  const renew = async (r: RealMine) => {
    setBusy(r.id);
    try {
      const init = await realBizRenewStart(r.id);
      const res = await paystackCheckout(init, { purpose: 'real_business', biz_id: init.biz_id, days: init.days, renewal: true });
      if (res === 'cancelled') return;
      if ('error' in res) { toast(res.error, 'bad'); return; }
      toast(res.ok ? 'Renewed! Your pin stays on the map.' : 'Payment received. It updates once Paystack confirms it.', 'good');
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); load(); }
  };
  return (
    <section className="co-real" data-testid="real-listings">
      <div className="co-hero co-hero--real">
        <span className="co-hero__emoji" aria-hidden>🏪</span>
        <h3>Put your real business on the map</h3>
        <p>{info ? `${koboLabel(info.price_kobo)} for ${info.days} days.` : 'Photos, contacts and a Verified pin.'} Players find you on the map and in Discover.</p>
        <ul className="co-hero__list">
          <li>Up to {info?.max_images ?? 3} photos, phone, WhatsApp, Instagram</li>
          <li>Checked by the Benin Life team, refunded if not approved</li>
        </ul>
        <button type="button" className="co-pill co-pill--green" onClick={onNew} data-testid="real-new" data-tour="business-real">List my real business</button>
      </div>
      {rows?.map((r) => (
        <article key={r.id} className="co-reallisting">
          <span className="co-reallisting__logo" aria-hidden>{r.logo}</span>
          <span className="grow">
            <b>{r.name}</b>
            <small>{r.area} · {STATUS_TEXT[r.status]}{r.status === 'live' && r.ends_at ? ` until ${shortDate(r.ends_at)}` : ''}</small>
            {r.reject_reason && ['rejected', 'suspended', 'removed'].includes(r.status) && <small className="is-bad">{r.reject_reason}</small>}
            {r.refund_status !== 'none' && <small>Refund: {r.refund_status.replace('_', ' ')}</small>}
            {(r.status === 'live' || r.views > 0) && <small>{r.views} views · {r.taps} taps</small>}
          </span>
          {r.can_renew && <Button size="sm" variant="gold" loading={busy === r.id} onClick={() => void renew(r)}>Renew · {koboLabel(r.renew_price_kobo)}</Button>}
          {r.images[0] && <img className="co-reallisting__img" src={realImageUrl(r.images[0])} alt="" />}
        </article>
      ))}
    </section>
  );
}
