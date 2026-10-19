// W1: Benin Boutique / Wardrobe (docs/WARDROBE.md). Lazy-loaded overlay with ONE live turntable: full-height on
// phones, a centred panel over a dimmed backdrop from 768 px (UI1), with the standard sheet header and × close.
// Brands -> categories -> items. Tap to try on, pick a colour, buy with a confirm, save per "Wear for" slot.
import { grossPrice, noteFor } from '../../lib/tax';
import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { AvatarStage } from '../../art/avatar3d';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { applyPatch, defaultLook, lookPatch, outfitFor, OUTFIT_SLOTS, type LookItem, type OutfitSlot, type WardrobeCategory } from '../../lib/outfit';
import type { GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { useWardrobe, wardrobeBuy, wardrobeClearSlot, wardrobeSetOutfit, type WardrobeItem } from '../../state/wardrobe';
import { Button, IconButton, Modal, toast } from '../../ui';
import { useEscape } from '../../ui/presence';
import './Boutique.css';

const SLOT_META: Record<OutfitSlot, { label: string; emoji: string; note: string; def: string }> = {
  everyday: { label: 'Everyday', emoji: '☀️', note: 'Your main look. It shows on your profile, in chat and around Benin City.', def: '' },
  home: { label: 'Home', emoji: '🛋️', note: 'What your Sim changes into when relaxing at home.', def: 'The default: your everyday clothes with slippers, bag and shades off.' },
  sleep: { label: 'Sleep', emoji: '😴', note: 'What your Sim wears to bed and for naps.', def: 'The default: soft cotton pyjamas and slippers.' },
  date: { label: 'Date night', emoji: '💕', note: 'What your Sim wears on a night out with someone special.', def: 'The default: your everyday look.' },
  party: { label: 'Party', emoji: '🎉', note: 'What your Sim wears in clubs and at owambe events.', def: 'The default: your everyday look.' },
  work: { label: 'Work', emoji: '💼', note: 'What your Sim wears during work shifts.', def: 'The default: your everyday look.' },
  gym: { label: 'Gym', emoji: '🏋🏾', note: 'What your Sim wears for jogging and workouts.', def: 'The default: a vest or tee, shorts and trainers.' },
};

const CAT_LABEL: Record<WardrobeCategory, string> = {
  top: 'Shirts & tops', outfit: 'Sets & outfits', bottom: 'Bottoms', shoes: 'Shoes', bag: 'Bags', hat_hair: 'Caps & hats',
};
const CAT_ORDER: WardrobeCategory[] = ['top', 'outfit', 'bottom', 'shoes', 'bag', 'hat_hair'];
const ALL = '__all';

type Sel = Partial<Record<WardrobeCategory, { item: string; colour: string | null }>>;

function selFrom(items: { item: string; colour: string | null }[] | null | undefined, byId: Map<string, WardrobeItem>): Sel {
  const out: Sel = {};
  for (const x of items ?? []) {
    const it = byId.get(x.item);
    if (it) out[it.category] = { item: x.item, colour: x.colour };
  }
  return out;
}
const selKey = (s: Sel) => JSON.stringify(CAT_ORDER.map((c) => s[c] ?? null));

export default function Boutique({ state }: { state: GameState }) {
  const setOverlay = useUi((s) => s.setOverlay);
  const refreshGame = useGame((s) => s.refresh);
  const data = useWardrobe((s) => s.data);
  const load = useWardrobe((s) => s.load);
  const uid = state.profile.id;
  const close = () => setOverlay(null);
  useEscape(true, close);

  useEffect(() => { void load(uid, true); }, [load, uid]);

  const [slot, setSlot] = useState<OutfitSlot>('everyday');
  const [brand, setBrand] = useState<string>('benin_basics');
  const [cat, setCat] = useState<WardrobeCategory>('top');
  const [sel, setSel] = useState<Sel>({});
  const [focus, setFocus] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<WardrobeItem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const items = useMemo(() => data?.items ?? [], [data]);
  const byId = useMemo(() => new Map(items.map((i) => [i.id, i])), [items]);
  const brandsOn = data?.brands_enabled !== false;
  const brands = useMemo(() => (data?.brands ?? []).filter((b) => items.some((i) => i.brand_id === b.id)), [data, items]);
  const brandById = useMemo(() => new Map((data?.brands ?? []).map((b) => [b.id, b])), [data]);
  const curBrand = brandsOn && brands.some((b) => b.id === brand) ? brand : brandsOn && brands[0] ? brands[0].id : ALL;
  const inBrand = useMemo(() => items.filter((i) => curBrand === ALL || i.brand_id === curBrand), [items, curBrand]);
  const cats = CAT_ORDER.filter((c) => inBrand.some((i) => i.category === c));
  const curCat = cats.includes(cat) ? cat : cats[0] ?? 'top';
  const grid = inBrand.filter((i) => i.category === curCat);

  const saved = data?.outfits?.[slot];
  const savedSel = useMemo(() => selFrom(saved?.items, byId), [saved, byId]);
  // A new slot (or fresh data): start from what is saved for it.
  const [selFor, setSelFor] = useState<string>('');
  const selSeed = `${slot}:${JSON.stringify(saved ?? null)}:${items.length}`;
  if (selSeed !== selFor) {
    setSelFor(selSeed);
    setSel(savedSel);
    setFocus(null);
  }

  const base = state.profile.avatar;
  const slotBase = useMemo(() => (saved && saved.patch === null ? defaultLook(base, slot) : base), [saved, base, slot]);
  const selItems: LookItem[] = CAT_ORDER.flatMap((c) => {
    const s = sel[c];
    const it = s && byId.get(s.item);
    return it ? [{ category: it.category, patch: it.patch, colour: s.colour }] : [];
  });
  const preview = useMemo(
    () => (selItems.length ? applyPatch(slotBase, lookPatch(selItems)) : outfitFor(base, data?.outfits, slot)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [selKey(sel), slotBase, base, data?.outfits, slot, byId],
  );

  const dirty = selKey(sel) !== selKey(savedSel);
  const unowned = CAT_ORDER.map((c) => sel[c] && byId.get(sel[c]!.item)).filter((it): it is WardrobeItem => Boolean(it && it.price > 0 && !it.owned));
  const focusItem = focus ? byId.get(focus) ?? null : null;
  const focusSel = focusItem ? sel[focusItem.category] : undefined;
  const wearingIds = new Set(Object.values(savedSel).map((s) => s!.item));
  const money = (data?.cash ?? state.profile.cash) + (data?.bank ?? state.profile.bank);

  const tap = (it: WardrobeItem) => {
    setFocus(it.id);
    setSel((cur) => {
      const next: Sel = { ...cur };
      if (cur[it.category]?.item === it.id) {
        if (focus === it.id) delete next[it.category]; // second tap on the focused piece takes it off
        return next;
      }
      if (it.category === 'outfit') { delete next.top; delete next.bottom; }
      if (it.category === 'top' || it.category === 'bottom') delete next.outfit;
      next[it.category] = { item: it.id, colour: it.owned_colour ?? it.colours[0] ?? null };
      return next;
    });
  };
  const pickColour = (c: string) => {
    if (!focusItem) return;
    setSel((cur) => ({ ...cur, [focusItem.category]: { item: focusItem.id, colour: c } }));
  };

  const reload = async (avatarChanged = false) => {
    await load(uid, true);
    if (avatarChanged) await refreshGame();
  };

  const buy = async (it: WardrobeItem) => {
    setBusy('buy');
    try {
      const r = await wardrobeBuy(it.id, sel[it.category]?.item === it.id ? sel[it.category]!.colour : it.colours[0] ?? null);
      toast(r.message, 'good');
      setConfirm(null);
      await reload(true);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  const save = async () => {
    setBusy('save');
    try {
      const list = CAT_ORDER.flatMap((c) => (sel[c] ? [sel[c]!] : []));
      const r = await wardrobeSetOutfit(slot, list);
      toast(r.message, 'good');
      await reload(slot === 'everyday');
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };
  const keepEveryday = async () => {
    setBusy('keep');
    try { toast((await wardrobeClearSlot(slot)).message, 'good'); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  const useDefault = async () => {
    setBusy('default');
    try { toast((await wardrobeSetOutfit(slot, null)).message, 'good'); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };

  const meta = SLOT_META[slot];
  const slotState = slot === 'everyday' ? null : !saved ? 'everyday' : saved.patch === null ? 'default' : 'custom';
  const closed = data && !data.enabled;

  const primary = focusItem && focusItem.price > 0 && !focusItem.owned
    ? { label: `Buy · ${naira(grossPrice('wardrobe', focusItem.price))}`, run: () => setConfirm(focusItem), disabled: false, busy: busy === 'buy' }
    : unowned.length
      ? { label: `Buy the ${unowned[0].name} first`, run: () => { setFocus(unowned[0].id); setConfirm(unowned[0]); }, disabled: false, busy: false }
      : { label: dirty ? `Wear for ${meta.label}` : `Wearing for ${meta.label}`, run: () => void save(), disabled: !dirty, busy: busy === 'save' };

  return createPortal(
    <div className="btq-root">
    <div className="btq-backdrop" onClick={close} />
    <div className="btq" role="dialog" aria-modal="true" aria-labelledby="btq-title">
      <header className="btq__head">
        <h3 className="bl-sheet__title" id="btq-title">Benin Boutique</h3>
        <IconButton icon="close" label="Close" variant="plain" size={38} className="btq__close" onClick={close} />
      </header>
      <div className="btq__body">
      <section className="btq__stage">
        <AvatarStage config={preview} className="btq__canvas" />
        <span className="btq__pill btq__look">{meta.emoji} {slot === 'everyday' ? 'Your look today' : `${meta.label} look`}{dirty ? ' · trying on' : ''}</span>
      </section>

      <section className="btq__panel">
        <div className="btq__scroll">
          {!data && <div className="panel-skel"><span /><span /><span /></div>}
          {closed && <p className="btq__closed">The boutique is closed right now. Your Sim keeps the everyday look everywhere.</p>}
          {data && !closed && (
            <>
              <div className="btq__row btq__row--head">
                {brandsOn && brands.length > 0 ? (
                  <div className="btq__brands" role="tablist" aria-label="Brands">
                    {brands.map((b) => (
                      <button key={b.id} type="button" role="tab" aria-selected={curBrand === b.id}
                        className={`btq__brand${curBrand === b.id ? ' is-on' : ''}`} style={{ ['--brand' as string]: b.colour }}
                        onClick={() => setBrand(b.id)}>
                        <span className="btq__brand-dot" aria-hidden />{b.name}
                      </button>
                    ))}
                  </div>
                ) : <span className="btq__label">All pieces</span>}
                <span className="btq__money" title="Bank + cash">{naira(money)}</span>
              </div>
              {brandsOn && curBrand !== ALL && <p className="btq__tagline">{brandById.get(curBrand)?.tagline}</p>}

              <div className="btq__slots" role="tablist" aria-label="Wear for">
                <span className="btq__label">Wear for</span>
                {OUTFIT_SLOTS.map((s) => (
                  <button key={s} type="button" role="tab" aria-selected={slot === s} className={`btq__slot${slot === s ? ' is-on' : ''}`} onClick={() => setSlot(s)}>
                    <span aria-hidden>{SLOT_META[s].emoji}</span> {SLOT_META[s].label}
                  </button>
                ))}
              </div>

              <div className="btq__note">
                <p><b>{meta.label}:</b> {meta.note}{slotState && <> <span className="btq__now">{slotState === 'everyday' ? 'Now: your everyday look.' : slotState === 'default' ? `Now: ${meta.def.replace(/^The default: /, 'the default, ')}` : 'Now: a look you saved.'}</span></>}</p>
                {slot !== 'everyday' && (
                  <div className="btq__note-actions">
                    <Button size="sm" variant={slotState === 'everyday' ? 'dark' : 'ghost'} aria-pressed={slotState === 'everyday'} loading={busy === 'keep'} disabled={Boolean(busy)} onClick={() => { if (slotState !== 'everyday') void keepEveryday(); }}>Keep my everyday look</Button>
                    <Button size="sm" variant={slotState === 'default' ? 'dark' : 'ghost'} aria-pressed={slotState === 'default'} loading={busy === 'default'} disabled={Boolean(busy)} onClick={() => { if (slotState !== 'default') void useDefault(); }}>Use the default</Button>
                  </div>
                )}
              </div>

              <div className="btq__cats" role="tablist" aria-label="Categories">
                {cats.map((c) => (
                  <button key={c} type="button" role="tab" aria-selected={curCat === c} className={`btq__cat${curCat === c ? ' is-on' : ''}`} onClick={() => setCat(c)}>{CAT_LABEL[c]}</button>
                ))}
              </div>

              <div className="btq__grid">
                {grid.map((it) => {
                  const on = sel[it.category]?.item === it.id;
                  const colour = (on ? sel[it.category]?.colour : null) ?? it.owned_colour ?? it.colours[0] ?? '#d9d4ca';
                  const b = it.brand_id ? brandById.get(it.brand_id) : null;
                  return (
                    <button key={it.id} type="button" className={`btq-card${on ? ' is-on' : ''}${focus === it.id ? ' is-focus' : ''}`} onClick={() => tap(it)}
                      aria-pressed={on} aria-label={`${it.name}${b ? ` by ${b.name}` : ''}, ${it.price ? naira(it.price) : 'free'}${it.owned ? ', owned' : ''}`}>
                      <span className="btq-card__art" style={{ ['--swatch' as string]: colour }}>
                        <span className="btq-card__badges">
                          {wearingIds.has(it.id) && <span className="btq-badge btq-badge--wear">Wearing</span>}
                          {!wearingIds.has(it.id) && it.owned && it.price > 0 && <span className="btq-badge btq-badge--own">Owned</span>}
                          {it.tag === 'designer' && <span className="btq-badge btq-badge--designer">Designer</span>}
                          {it.tag === 'owambe' && <span className="btq-badge btq-badge--owambe">Owambe</span>}
                        </span>
                        <span className="btq-card__icon" aria-hidden>{it.icon}</span>
                        {it.colours.length > 0 && (
                          <span className="btq-card__dots" aria-hidden>
                            {it.colours.slice(0, 5).map((c) => <span key={c} style={{ background: c }} className={c === colour ? 'is-on' : undefined} />)}
                          </span>
                        )}
                      </span>
                      <span className="btq-card__body">
                        {b && <span className="btq-card__brand">{b.name}</span>}
                        <span className="btq-card__name">{it.name}</span>
                        <span className="btq-card__meta">
                          <span className={`btq-card__price${it.owned || it.price === 0 ? ' is-free' : ''}`}>{it.owned && it.price > 0 ? 'Yours' : it.price === 0 ? 'Free' : naira(grossPrice('wardrobe', it.price))}</span>
                          {!it.owned && it.price > 0 && noteFor('wardrobe', it.price) && <span className="btq-card__tax">{noteFor('wardrobe', it.price)}</span>}
                          {it.colours.length > 1 && <span className="btq-card__count">{it.colours.length} colours</span>}
                        </span>
                      </span>
                    </button>
                  );
                })}
              </div>
              <p className="btq__foot">Tap a piece to try it on, tap again to take it off. Clothes are just for style: they never change your stats or jobs.</p>
            </>
          )}
        </div>

        {data && !closed && (
          <div className="btq__bar">
            {focusItem && focusItem.colours.length > 0 && (
              <div className="btq__colours" role="radiogroup" aria-label={`${focusItem.name} colour`}>
                <span className="btq__colours-name">{focusItem.name}</span>
                {focusItem.colours.map((c) => (
                  <button key={c} type="button" role="radio" aria-checked={focusSel?.colour === c} aria-label={c}
                    className={`btq__swatch${focusSel?.colour === c ? ' is-on' : ''}`} style={{ background: c }} onClick={() => pickColour(c)} />
                ))}
              </div>
            )}
            <div className="btq__bar-row">
              {dirty && <Button variant="ghost" onClick={() => { setSel(savedSel); setFocus(null); }}>Reset</Button>}
              <Button variant="green" block loading={primary.busy} disabled={primary.disabled || Boolean(busy && !primary.busy)} onClick={primary.run}>{primary.label}</Button>
            </div>
          </div>
        )}
      </section>
      </div>

      <Modal open={Boolean(confirm)} onClose={() => setConfirm(null)} title={confirm ? `Buy the ${confirm.name}?` : ''}
        art={<span className="btq__confirm-art" aria-hidden>{confirm?.icon}</span>}
        actions={
          <>
            <Button variant="ghost" onClick={() => setConfirm(null)}>Not now</Button>
            <Button variant="green" loading={busy === 'buy'} disabled={!confirm || money < grossPrice('wardrobe', confirm?.price ?? 0)} onClick={() => confirm && void buy(confirm)}>
              {confirm && money < grossPrice('wardrobe', confirm.price) ? 'Not enough money' : `Pay ${confirm ? naira(grossPrice('wardrobe', confirm.price)) : ''}`}
            </Button>
          </>
        }>
        {confirm && (
          <p className="btq__confirm-text">
            {confirm.brand_id && brandById.get(confirm.brand_id) ? `${brandById.get(confirm.brand_id)!.name} · ` : ''}{confirm.description}
            {' '}{noteFor('wardrobe', confirm.price) ? `Price ${noteFor('wardrobe', confirm.price)}. ` : ''}Paid from your bank first, then cash. You get every colour. You have {naira(money)}.
          </p>
        )}
      </Modal>
    </div>
    </div>,
    document.body,
  );
}
