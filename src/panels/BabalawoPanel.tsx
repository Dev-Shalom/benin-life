// B2 "Babalawo" tab at Baba's Shrine (docs/BABALAWO.md): Baba's greeting, My charms (time left), and the 10 services with
// their cash price, the offerings they consume from the Bag (have / need), what they do, how long, the fail chance and
// a note. "Ask Baba" needs a second tap (the prices are big), then queues the service like any other action: the Sim
// walks to Baba's hut or the charm altar, the timer runs on the server and the result popup shows Baba's line.
import { useEffect, useMemo, useRef, useState } from 'react';
import { shrineInfo, timeLeft, type ShrineInfo, type ShrineService } from '../api/shrine';
import { errorMessage } from '../lib/api';
import { useNow } from '../lib/clock';
import { naira, nairaShort } from '../lib/format';
import type { PanelProps } from '../lib/types';
import { useShrine } from '../state/shrine';
import { CharmChips } from '../screens/game/Shrine';
import { queueTask } from '../screens/game/TaskRunner';
import { Button, EmptyState, toast } from '../ui';

const GREETINGS = [
  '"Sit down, my child. Remove your shoe. Wetin dey worry you?"',
  '"The ancestors don see you before you enter. Talk your mind."',
  '"Wetin you bring for Baba? Kola first, then we talk."',
  '"Everything get price. Even the spirits no dey work for free."',
];

/** Baba's hut for readings and cleansing; the charm altar for the rest. */
const zoneFor = (id: string) => (id === 'consultation' || id === 'cleansing' ? { zone: 'hut', walkTo: "Baba's hut" } : { zone: 'altar', walkTo: 'the charm altar' });

function ServiceCard({ s, cash, here, busy, focus, locId, onQueued }: { s: ShrineService; cash: number; here: boolean; busy: boolean; focus: boolean; locId: string; onQueued: () => void }) {
  const [armed, setArmed] = useState(false);
  const ref = useRef<HTMLElement>(null);
  const now = useNow(30_000);
  useEffect(() => {
    if (!armed) return;
    const t = window.setTimeout(() => setArmed(false), 4000);
    return () => window.clearTimeout(t);
  }, [armed]);
  useEffect(() => {
    if (focus) ref.current?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }, [focus]);
  const missing = s.offerings.filter((o) => o.have < o.need);
  const owned = s.active && s.kind !== 'cleansing';
  const lock = !here ? "Go to Baba's Shrine first"
    : owned ? (s.kind === 'money_charm' ? 'You already carry one' : `Still working${s.active?.expires_at ? ` · ${timeLeft(s.active.expires_at, now)} left` : ''}`)
      : missing.length ? `Missing ${missing.map((o) => `${o.need - o.have} ${o.name.toLowerCase()}`).join(', ')}`
        : s.price > cash ? `Not enough cash (${nairaShort(s.price)})`
          : busy ? 'Finish what you are doing first' : null;
  const ask = () => {
    if (lock) { toast(lock, 'info'); return; }
    if (!armed) { setArmed(true); return; }
    setArmed(false);
    if (queueTask({ id: s.id, name: s.name }, locId, { kind: 'shrine', icon: s.icon, ...zoneFor(s.id) }) !== 'full') {
      toast(`${s.icon} Going to Baba for the ${s.name.toLowerCase()}…`, 'info');
      onQueued();
    }
  };
  return (
    <article ref={ref} className={`shrine-svc${focus ? ' is-focus' : ''}${owned ? ' is-owned' : ''}`} data-testid={`svc-${s.id}`}>
      <header className="shrine-svc__head">
        <span className="shrine-svc__icon" aria-hidden>{s.icon}</span>
        <span className="shrine-svc__title">
          <b>{s.name}</b>
          <small>{s.effect}</small>
        </span>
        <span className="shrine-svc__price">{s.price >= 100000 ? nairaShort(s.price) : naira(s.price)}</span>
      </header>
      <p className="shrine-svc__blurb">{s.blurb}</p>
      <div className="shrine-svc__offer" aria-label="Offerings">
        {s.offerings.map((o) => (
          <span key={o.item} className={`shrine-offer${o.have < o.need ? ' is-missing' : ''}`} title={`${o.name}: you have ${o.have}`}>
            <span aria-hidden>{o.icon}</span> {o.need} × {o.name} <small>{o.have}/{o.need}</small>
          </span>
        ))}
      </div>
      <div className="shrine-svc__meta">
        <span>⏳ {s.duration}</span>
        <span>🕐 {s.seconds}s</span>
        {s.fail_pct > 0 ? <span className="is-risk">{Math.round(s.fail_pct)}% may fail</span> : <span>Never fails</span>}
      </div>
      {s.note && <p className="shrine-svc__note">{s.note}</p>}
      <Button size="sm" block variant={armed ? 'gold' : lock ? 'ghost' : 'primary'} onClick={ask} data-testid={`ask-${s.id}`}
        aria-disabled={Boolean(lock)}>
        {lock ?? (armed ? `Tap again · pay ${nairaShort(s.price)} + offerings` : `Ask Baba · ${nairaShort(s.price)}`)}
      </Button>
    </article>
  );
}

export default function BabalawoPanel({ state, location, close }: PanelProps) {
  const [info, setInfo] = useState<ShrineInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const version = useShrine((s) => s.version);
  const focus = useShrine((s) => s.focus);
  const charms = useShrine((s) => s.charms);
  const [line] = useState(() => GREETINGS[Math.floor(Math.random() * GREETINGS.length)]);
  const p = state.profile;
  const busyNow = Boolean(p.busy_until && Date.parse(p.busy_until) > Date.now());
  const invKey = (state.inventory ?? []).map((i) => `${i.id}:${i.qty}`).join(',');

  useEffect(() => {
    let alive = true;
    shrineInfo()
      .then((d) => { if (alive) { setInfo(d); setErr(null); } })
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => { alive = false; };
  }, [version, p.cash, invKey, p.busy_until]);
  useEffect(() => {
    if (!focus) return;
    const t = window.setTimeout(() => useShrine.getState().setFocus(null), 2500);
    return () => window.clearTimeout(t);
  }, [focus]);

  const here = Boolean(info?.here) && state.location.id === location.id && !state.travel;
  const list = useMemo(() => info?.services ?? [], [info]);
  if (!info && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (!info) return <EmptyState icon="info" title="Baba is not receiving visitors" body={err ?? ''} />;
  const shown = charms.length ? charms : info.charms;
  return (
    <div className="shrine stack">
      <div className="shrine__baba">
        <span className="shrine__face" aria-hidden>👴🏿</span>
        <p>{line}</p>
      </div>
      {!info.enabled && <p className="shrine__warn">Baba is resting today. Services are closed for now.</p>}
      <section className="shrine__charms" id="my-charms">
        <h4>My charms</h4>
        <CharmChips charms={shown} empty={<p className="muted shrine__none">No charm on you yet. Baba can fix that.</p>} />
      </section>
      <section className="shrine__list" aria-label="Baba's services">
        <h4>Services <small className="muted">Cash + offerings from your Bag · offerings sold at Oba Market</small></h4>
        {list.map((s) => (
          <ServiceCard key={s.id} s={s} cash={p.cash} here={here && info.enabled} busy={busyNow || Boolean(info.visit)} focus={focus === s.id} locId={location.id} onQueued={close} />
        ))}
      </section>
      <p className="bankx__fine">About {Math.round(info.fail_pct)}% of charms fail: the money and offerings are gone. Baba is fictional; this is a game.</p>
    </div>
  );
}
