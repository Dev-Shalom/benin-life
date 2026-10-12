// D2 Link-ups (docs/LINKUPS.md). NPC dates only (adults 21–40), never another player; nothing explicit.
// <LinkupHost/>   follows my link-up state (src/state/linkups.ts) and shows:
//                  1. the fade to black while a hotel action runs ("The night goes on… ☾"),
//                  2. the morning-after popup (same card as the other popups: bl-modal + bcast-*),
//                  3. the pick sheet opened from a place card (who to buy drinks for / who you're going out with).
// Shared bits for the Link-ups phone app: <NpcRow/>, <SparkMeter/>, <WantPicker/>, useLinkupStart().
import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { linkupMorningSeen, linkupSetPref, linkupStart, WANT_LABEL, type LinkupAction, type LinkupHere, type LinkupNpc, type LinkupWant } from '../../api/linkups';
import { AvatarPortrait } from '../../art/avatar3d';
import { npcAvatar } from '../../art/place3d/model';
import { errorMessage } from '../../lib/api';
import { useNow } from '../../lib/clock';
import { countdown, naira, secondsUntil } from '../../lib/format';
import { useGame } from '../../state/game';
import { startLinkups, useLinkups } from '../../state/linkups';
import { Button, Modal, Sheet, toast } from '../../ui';
import './Linkups.css';

export function minutesLeft(iso: string | null | undefined, now: number): string {
  const s = secondsUntil(iso ?? null, now);
  if (s <= 0) return '';
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return countdown(s);
}

export function NpcFace({ npc, size = 44 }: { npc: LinkupNpc; size?: number }) {
  const cfg = useMemo(() => npcAvatar(npc.avatar), [npc.avatar]);
  return <span className="lu-face" style={{ width: size, height: size }}><AvatarPortrait config={cfg} size={size} /></span>;
}

export function SparkMeter({ spark, small }: { spark: number; small?: boolean }) {
  const v = Math.max(0, Math.min(100, spark));
  return (
    <span className={`lu-spark${small ? ' is-small' : ''}`} aria-label={`Spark ${v} of 100`} title={`Spark ${v}/100`}>
      <span className="lu-spark__track"><span style={{ width: `${v}%` }} /></span>
      <span className="lu-spark__n">✨ {v}</span>
    </span>
  );
}

export function WantPicker({ want, onChange }: { want: LinkupWant; onChange?: (w: LinkupWant) => void }) {
  const [busy, setBusy] = useState(false);
  const set = async (w: LinkupWant) => {
    if (w === want || busy) return;
    setBusy(true);
    try {
      const r = await linkupSetPref(w);
      toast(r.message, 'good');
      await useLinkups.getState().load();
      onChange?.(w);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <div className="seg lu-want" role="radiogroup" aria-label="Link-ups with">
      {(['women', 'men', 'anyone'] as const).map((w) => (
        <button key={w} type="button" role="radio" aria-checked={want === w} disabled={busy}
          className={`seg__btn${want === w ? ' is-on' : ''}`} onClick={() => void set(w)} data-testid={`lu-want-${w}`}>
          {WANT_LABEL[w]}
        </button>
      ))}
    </div>
  );
}

/** Start an action; returns [busy id, start]. */
export function useLinkupStart(): [string | null, (action: LinkupAction, npc: string | null) => Promise<boolean>] {
  const [busy, setBusy] = useState<string | null>(null);
  const start = async (action: LinkupAction, npc: string | null) => {
    setBusy(`${action.id}:${npc ?? ''}`);
    try {
      const r = await linkupStart(action.id, npc);
      toast(r.message, 'info');
      useLinkups.getState().started(r);
      void useGame.getState().refresh();
      return true;
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void useLinkups.getState().load();
      return false;
    } finally { setBusy(null); }
  };
  return [busy, start];
}

function oddsText(h: LinkupHere): string {
  const o = h.yes_pct;
  const bits: string[] = [];
  if (o.npc) bits.push(`${o.npc > 0 ? '+' : '−'}${Math.abs(o.npc)} vibe`);
  if (o.charm) bits.push(`+${o.charm} charm`);
  if (o.rank) bits.push(`+${o.rank} rank`);
  if (o.cred) bits.push(`+${o.cred} hype`);
  if (o.looks) bits.push(`${o.looks > 0 ? '+' : '−'}${Math.abs(o.looks)} looks`);
  if (o.spark) bits.push(`+${o.spark} spark`);
  return bits.join(' · ');
}

/** One person out tonight, with Buy drinks. */
export function NpcRow({ h, drinks, now, busy, free, onBuy }: {
  h: LinkupHere; drinks: LinkupAction | undefined; now: number; busy: string | null; free: boolean; onBuy: (npc: string) => void;
}) {
  const yes = h.yes_until && Date.parse(h.yes_until) > now;
  const cold = h.cold_until && Date.parse(h.cold_until) > now;
  const wait = h.no_until && Date.parse(h.no_until) > now ? secondsUntil(h.no_until, now) : 0;
  const pct = Math.round(h.yes_pct.pct);
  const lock = h.partner ? 'Your partner 💑' : yes ? 'Said yes ✓' : cold ? 'Not talking to you' : wait > 0 ? `Try again in ${countdown(wait)}` : null;
  return (
    <div className={`lu-npc${yes ? ' is-yes' : ''}`} data-testid={`lu-npc-${h.id}`}>
      <NpcFace npc={h} />
      <div className="lu-npc__main">
        <div className="lu-npc__name"><span><b>{h.name}</b>, {h.age}</span> <span className={`lu-odds ${pct >= 60 ? 'is-hot' : pct >= 40 ? 'is-warm' : 'is-cool'}`}>{pct}% yes</span></div>
        <div className="lu-npc__vibe">{h.vibe}</div>
        <div className="lu-npc__likes">💚 {h.likes} · 🚫 {h.hates}</div>
        {oddsText(h) && <div className="lu-npc__odds">{h.yes_pct.base}% base · {oddsText(h)}</div>}
        {h.met && <SparkMeter spark={h.spark} small />}
        {drinks && (
          <Button size="sm" variant={lock ? 'ghost' : 'primary'} className="lu-npc__btn" disabled={Boolean(lock) || !free || busy !== null}
            loading={busy === `${drinks.id}:${h.id}`} onClick={() => onBuy(h.id)} data-testid={`lu-buy-${h.id}`}>
            {lock ?? `🍸 Buy drinks · ${naira(drinks.price)}`}
          </Button>
        )}
      </div>
    </div>
  );
}

/** Fade to black while a hotel action runs. */
function FadeToBlack() {
  const run = useLinkups((s) => s.run);
  const now = useNow(250);
  if (!run || run.kind !== 'hotel') return null;
  const end = Date.parse(run.resolve_at);
  const start = Date.parse(run.started_at);
  if (end <= now - 1500) return null;
  const frac = end > start ? Math.min(1, Math.max(0, (now - start) / (end - start))) : 1;
  return createPortal(
    <div className="lu-fade" role="status" aria-live="polite" data-testid="lu-fade">
      <div className="lu-fade__moon" aria-hidden>☾</div>
      <p className="lu-fade__line">The night goes on…</p>
      <p className="lu-fade__sub">{run.name} with {run.npc_name}</p>
      <div className="lu-fade__bar"><span style={{ transform: `scaleX(${frac})` }} /></div>
    </div>,
    document.body,
  );
}

function MorningAfter() {
  const m = useLinkups((s) => s.morning);
  const run = useLinkups((s) => s.run);
  const [busy, setBusy] = useState(false);
  if (!m || run) return null;
  const bad = m.robbed || m.caught;
  const close = async () => {
    setBusy(true);
    useLinkups.getState().setMorning(null);
    if (m.run_id) { try { await linkupMorningSeen(m.run_id); } catch { /* shows again next load */ } }
    setBusy(false);
  };
  return (
    <Modal open onClose={() => void close()} tone={bad ? 'bad' : 'good'}
      art={<div className={`bcast-art lu-morning-art${bad ? ' is-bad' : ''}`} aria-hidden>{m.caught ? '💔' : m.robbed ? '👛' : '☀️'}</div>}
      title={<span className="bcast-title"><small className="bcast-kicker">The morning after · {m.action}</small>
        {m.caught ? `${m.ex?.name ?? 'Your partner'} found out` : m.robbed ? 'Link-up gone wrong' : 'Morning don break'}</span>}
      actions={<Button variant={bad ? 'ghost' : 'primary'} block loading={busy} onClick={() => void close()} data-testid="lu-morning-ok">
        {m.caught ? 'E don cast…' : m.robbed ? 'Wahala…' : 'Good morning ☀️'}</Button>}>
      <div className="lu-morning-who"><NpcFace npc={m.npc} size={52} /><span><b>{m.npc.name}</b>, {m.npc.age}<small>{m.npc.vibe}</small></span></div>
      <p className="bcast-body">{m.line}</p>
      {m.robbed && <p className="bcast-amount lu-morning-lost">−{naira(m.robbed_amount)} <small>missing from your cash</small></p>}
      {m.caught && <p className="crime-odds">{m.ex?.name} saw everything. The relationship is over, and your mood took a hit.</p>}
      {!bad && <p className="crime-odds">{m.with_partner ? 'Nothing like a night with your person. ' : ''}Fun up, stress down.</p>}
    </Modal>
  );
}

/** Opened from a place card: who to buy drinks for, or who you're taking out. */
function PickSheet() {
  const sheet = useLinkups((s) => s.sheet);
  const s = useLinkups((x) => x.status);
  const run = useLinkups((x) => x.run);
  const profile = useGame((g) => g.state?.profile);
  const now = useNow(1000);
  const [busy, start] = useLinkupStart();
  const a = s?.actions.find((x) => x.id === sheet);
  const close = () => useLinkups.getState().closeSheet();
  const free = !run && !(profile?.busy_until && Date.parse(profile.busy_until) > now);
  const go = async (npc: string | null) => {
    if (!a) return;
    if (await start(a, npc)) close();
  };
  const drinks = a?.kind === 'drinks';
  return (
    <Sheet open={Boolean(sheet)} onClose={close} title={a ? `${a.icon} ${a.name}` : 'Link-ups'} subtitle={s?.place?.name} size={a?.kind === 'drinks' ? 'tall' : 'auto'}>
      {!s || !a ? <div className="panel-skel"><span /><span /></div> : (
        <div className="lu-sheet" data-testid="lu-sheet">
          <p className="lu-sheet__lead">{a.blurb}</p>
          {drinks ? (
            <>
              <div className="lu-sheet__row"><span className="muted">Link-ups with</span><WantPicker want={s.want} /></div>
              {s.attraction ? <p className="lu-chip-line">🪔 Attraction charm working: +{s.attraction} on every yes</p> : null}
              <h4 className="lu-h">Out tonight</h4>
              {(s.here ?? []).length === 0 && <p className="muted">Nobody you fancy is out here right now.</p>}
              {(s.here ?? []).map((h) => (
                <NpcRow key={h.id} h={h} drinks={a} now={now} busy={busy} free={free} onBuy={(id) => void go(id)} />
              ))}
              <p className="lu-fine">Every person here is an adult NPC. A yes lasts a couple of hours: take them to dinner or a hotel.</p>
            </>
          ) : (
            <>
              {!a.rank_ok && <p className="lu-warn">🤑 {a.rank_name ?? 'Big Boy'}+ only. Rise in the Yahoo life first.</p>}
              {s.current ? (
                <div className="lu-with">
                  <NpcFace npc={s.current} size={56} />
                  <div className="lu-with__main">
                    <b>{s.current.name}, {s.current.age}</b>
                    <small>{s.current.partner ? 'Your partner 💑' : `Said yes · ${minutesLeft(s.current.yes_until, now)} left`}</small>
                    <SparkMeter spark={s.current.spark} />
                  </div>
                </div>
              ) : (
                <p className="lu-warn">You need a link-up first. Go to a club, buy someone drinks, and get a yes.</p>
              )}
              <Button variant="primary" block disabled={!s.current || !a.rank_ok || !a.here || !free || busy !== null}
                loading={busy?.startsWith(`${a.id}:`)} onClick={() => void go(s.current?.id ?? null)} data-testid={`lu-go-${a.id}`}>
                {a.icon} {a.name} · {naira(a.price)}
              </Button>
              {a.kind === 'hotel' && <p className="lu-fine">Fade to black. You wake up the next morning. Keep an eye on your wallet.</p>}
            </>
          )}
        </div>
      )}
    </Sheet>
  );
}

export function LinkupHost() {
  useEffect(() => startLinkups(), []);
  return (
    <>
      <FadeToBlack />
      <MorningAfter />
      <PickSheet />
    </>
  );
}
