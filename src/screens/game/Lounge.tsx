// R7 Members' Lounge membership sheet (docs/LOUNGE.md): your pass (time left, perks, Renew), the tiers (Day pass, Monthly
// Member, VIP) with price, perks and the requirement, and Buy / Renew / Upgrade. Everything is server-side: lounge_buy pays
// through the ledger (reason 'lounge'), bank first. The card in the place and the map sheet open this sheet.
import { useEffect, useState } from 'react';
import { durationLabel, loungeBuy, timeLeftLabel, type LoungeCard, type LoungeTier } from '../../api/lounge';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useLounge } from '../../state/lounge';
import { Button, Icon, Sheet, Spinner, toast } from '../../ui';
import './Lounge.css';

const ACTION_LABEL: Record<LoungeTier['action'], string> = {
  buy: 'Get pass', renew: 'Renew', upgrade: 'Upgrade', lower: 'You hold a better pass', max: 'Fully renewed', locked: 'Locked',
};

function perks(t: LoungeTier): string[] {
  const out = ['Full lounge: bar, sofas, pool, chat'];
  if (t.discount_pct > 0) out.push(`${t.discount_pct}% off drinks and bites`);
  if (t.gold_tag) out.push('Gold name tag');
  if (t.vouchers > 0) out.push(`${t.vouchers} free drink voucher${t.vouchers === 1 ? '' : 's'}`);
  if (t.vip) out.push('VIP cabana and mixer');
  if (t.guests > 0) out.push(`Bring ${t.guests} guest free`);
  return out;
}

export function LoungeHost() {
  const open = useLounge((s) => s.open);
  const status = useLounge((s) => s.status);
  const hide = useLounge((s) => s.hide);
  const setStatus = useLounge((s) => s.set);
  const load = useLounge((s) => s.load);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<string | null>(null);

  useEffect(() => { if (!open) setConfirm(null); }, [open]);

  const money = (status?.cash ?? 0) + (status?.bank ?? 0);
  const buy = async (t: LoungeTier) => {
    if (confirm !== t.id) { setConfirm(t.id); return; }
    setBusy(t.id);
    try {
      const r = await loungeBuy(t.id);
      setStatus(r.status);
      toast(r.message, 'good');
      setConfirm(null);
      void refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void load();
    } finally { setBusy(null); }
  };

  const me = status?.me ?? null;
  return (
    <Sheet open={open} onClose={hide} size="tall" className="lounge-sheet"
      title={<>The Lounge <span aria-hidden>🛋️</span></>} subtitle={status?.location_name ? `${status.location_name} · open all day` : 'Open all day'}>
      {!status ? <div className="lounge-load"><Spinner size={22} /></div> : (
        <div className="lounge">
          {!status.enabled && <p className="lounge-note is-bad"><Icon name="info" size={15} /> The Lounge is closed for now. Check back soon.</p>}

          {me ? (
            <section className={`lounge-pass${me.vip ? ' is-vip' : ''}`} aria-label="Your pass">
              <span className="lounge-pass__icon" aria-hidden>{me.icon}</span>
              <div className="lounge-pass__main">
                <b>{me.tier_name}</b>
                <span>{timeLeftLabel(me.seconds_left)} left{me.source === 'admin' ? ' · gift' : ''}</span>
                <small>
                  {me.vouchers_left > 0 ? `${me.vouchers_left} free drink${me.vouchers_left === 1 ? '' : 's'} left` : 'No free drink left'}
                  {me.guest_slots > 0 ? ` · guest ${me.guests_active}/${me.guest_slots}` : ''}
                </small>
              </div>
            </section>
          ) : status.guest_pass ? (
            <section className="lounge-pass is-guest"><span className="lounge-pass__icon" aria-hidden>🎟️</span>
              <div className="lounge-pass__main"><b>Guest of @{status.guest_pass.host}</b><span>Free entry for {timeLeftLabel(Math.max(0, (Date.parse(status.guest_pass.expires_at) - Date.now()) / 1000))}</span></div>
            </section>
          ) : (
            <section className="lounge-pass is-none">
              <span className="lounge-pass__icon" aria-hidden>🔒</span>
              <div className="lounge-pass__main"><b>{status.expired_tier ? `Your ${status.expired_tier} ended` : 'Members only'}</b>
                <span>{status.expired_tier ? 'Renew below to come back in.' : 'Get a pass to enter the lounge.'}</span></div>
            </section>
          )}

          <p className="lounge-wallet">You have <b>{naira(money)}</b> (bank {naira(status.bank)} · cash {naira(status.cash)}){status.bank_first ? '. Passes are paid from the bank first.' : '.'}</p>

          <ul className="lounge-tiers">
            {status.tiers.map((t) => {
              const can = status.enabled && (t.action === 'buy' || t.action === 'renew' || t.action === 'upgrade');
              const short = can && money < t.price;
              return (
                <li key={t.id} className={`lounge-tier${t.vip ? ' is-vip' : ''}${me?.tier_id === t.id ? ' is-current' : ''}`}>
                  <div className="lounge-tier__top">
                    <span className="lounge-tier__icon" aria-hidden>{t.icon}</span>
                    <div className="lounge-tier__main">
                      <b>{t.name}</b>
                      <small>{durationLabel(t.hours)}</small>
                    </div>
                    <span className="lounge-tier__price">{naira(t.price)}</span>
                  </div>
                  {t.blurb && <p className="lounge-tier__blurb">{t.blurb}</p>}
                  <ul className="lounge-perks">{perks(t).map((p) => <li key={p}>{p}</li>)}</ul>
                  {t.requirement && (
                    <p className={`lounge-req${t.requirement_ok ? ' is-ok' : ''}`}>
                      <Icon name={t.requirement_ok ? 'check' : 'info'} size={14} /> Needs {t.requirement}{t.requirement_ok ? ' (you qualify)' : ''}
                    </p>
                  )}
                  <Button block variant={can && !short ? 'green' : 'ghost'} loading={busy === t.id}
                    disabled={!can || short || busy !== null} onClick={() => void buy(t)}>
                    {short ? `Need ${naira(t.price - money)} more`
                      : confirm === t.id ? `Tap again to pay ${naira(t.price)}`
                        : t.action === 'locked' ? `Locked: ${t.requirement ?? 'requirement'}` : ACTION_LABEL[t.action]}
                  </Button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </Sheet>
  );
}

/** Slim status line for the place card inside the lounge, and the map sheet before you go. */
export function LoungeStrip({ card, compact = false }: { card: LoungeCard | null | undefined; compact?: boolean }) {
  const show = useLounge((s) => s.show);
  if (!card) return null;
  const label = card.access === 'member' && card.tier
    ? `${card.tier.icon} ${card.tier.name} · ${timeLeftLabel(card.seconds_left)} left${card.vouchers_left > 0 ? ` · ${card.vouchers_left} free drink${card.vouchers_left === 1 ? '' : 's'}` : ''}`
    : card.access === 'guest' ? `🎟️ Guest pass${card.guest_until ? ` · ${timeLeftLabel((Date.parse(card.guest_until) - Date.now()) / 1000)} left` : ''}`
      : card.expired ? '⏰ Your pass ended' : '🔒 Members only';
  const action = card.access === 'member' ? 'Renew' : card.access === 'guest' ? 'Passes' : card.expired ? 'Renew' : 'Get pass';
  return (
    <div className={`lounge-strip${compact ? ' is-compact' : ''}${card.access ? '' : ' is-locked'}`}>
      <span className="lounge-strip__text">{label}</span>
      <button type="button" className="lounge-strip__btn" onClick={show}>{action}</button>
    </div>
  );
}

/** The map sheet's pass line for the lounge (loads the status once). */
export function LoungeMapStrip() {
  const status = useLounge((s) => s.status);
  const load = useLounge((s) => s.load);
  useEffect(() => { void load(); }, [load]);
  if (!status) return null;
  const card: LoungeCard = {
    on: status.enabled, access: status.access, vip: status.vip,
    tier: status.me ? { id: status.me.tier_id, name: status.me.tier_name, icon: status.me.icon, vip: status.me.vip, gold: status.me.gold, discount_pct: status.me.discount_pct } : null,
    expires_at: status.me?.expires_at ?? null, expired: Boolean(status.expired_tier), seconds_left: status.me?.seconds_left ?? null,
    vouchers_left: status.me?.vouchers_left ?? 0, guest_until: status.guest_pass?.expires_at ?? null,
  };
  return <LoungeStrip card={card} />;
}
