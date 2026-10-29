// Grant toolbox on a player's admin page (docs/ADMIN_GRANTS.md): give or set ANYTHING the game has, one collapsible section
// at a time (built for a phone). Every button needs a second tap; every call is admin-only, validated, audited and tells the
// player. Current values sit next to each control and refresh after each change.
import { createContext, Fragment, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { adminApi, type GrantCatalog, type GrantState } from './api';
import { Btn, ConfirmButton, LoadError } from './parts';
import { useLoad } from './util';
import './Grants.css';

export type SectionId = 'career' | 'skills' | 'status' | 'needs' | 'items' | 'cars' | 'furniture' | 'home' | 'business' | 'gang' | 'perks';
type Msg = { message: string };

interface Ctx {
  id: string; s: GrantState; cat: GrantCatalog; busy: boolean; ver: number;
  run: (fn: () => Promise<Msg>) => Promise<void>;
  slots: Partial<Record<SectionId, ReactNode>>;
}
const GrantCtx = createContext<Ctx | null>(null);
const useG = () => { const c = useContext(GrantCtx); if (!c) throw new Error('GrantCtx'); return c; };

// the catalogue is the same for every player: load it once per admin session
let catalogPromise: Promise<GrantCatalog> | null = null;
const loadCatalog = () => (catalogPromise ??= adminApi.grantCatalog().catch((e) => { catalogPromise = null; throw e; }));

const num = (v: string): number | null => (v.trim() === '' || Number.isNaN(Number(v)) ? null : Math.floor(Number(v)));
const left = (sec: number) => (sec >= 3600 ? `${Math.floor(sec / 3600)} h ${Math.floor((sec % 3600) / 60)} min` : sec >= 60 ? `${Math.floor(sec / 60)} min ${sec % 60} s` : `${sec} s`);
const cap = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);

function Field({ label, children, wide }: { label: string; children: ReactNode; wide?: boolean }) {
  return <label className={`ag-field${wide ? ' ag-field--wide' : ''}`}><span>{label}</span>{children}</label>;
}

/** Short note kept in the audit log and shown to the player. Required for level and money-like grants. */
function Reason({ value, onChange, required }: { value: string; onChange: (v: string) => void; required?: boolean }) {
  return (
    <Field label={required ? 'Reason (required, the player sees it)' : 'Reason (optional, the player sees it)'} wide>
      <input className={`adm-input${required && value.trim().length > 0 && value.trim().length < 3 ? ' is-invalid' : ''}`} maxLength={200} value={value}
        placeholder="e.g. Compensation for the lost shift" onChange={(e) => onChange(e.target.value)} />
    </Field>
  );
}

function Go({ children, onConfirm, tone = 'primary', disabled, reason, small, confirmText }: {
  children: ReactNode; onConfirm: () => Promise<Msg>; tone?: 'primary' | 'danger' | 'ghost'; disabled?: boolean; reason?: string | null; small?: boolean; confirmText?: string;
}) {
  const { run, busy } = useG();
  return (
    <ConfirmButton tone={tone} small={small} confirmText={confirmText ?? 'Tap again to confirm'} disabled={busy || disabled}
      onConfirm={async () => {
        if (reason !== undefined && reason !== null && reason.trim().length < 3) { toast('Add a short reason first (at least 3 letters).', 'bad'); return; }
        await run(onConfirm);
      }}>
      {children}
    </ConfirmButton>
  );
}

function Row({ title, sub, children }: { title: ReactNode; sub?: ReactNode; children?: ReactNode }) {
  return (
    <div className="ag-item">
      <span className="ag-item__main"><b>{title}</b>{sub && <small>{sub}</small>}</span>
      {children && <span className="ag-item__act">{children}</span>}
    </div>
  );
}

function Slot({ id }: { id: SectionId }) {
  const { slots, ver } = useG();
  const node = slots[id];
  return node ? <div className="ag-slot"><Fragment key={ver}>{node}</Fragment></div> : null;
}

// ---------------------------------------------------------------- Career
function CareerSection() {
  const { id, s, cat } = useG();
  const [track, setTrack] = useState('');
  const [level, setLevel] = useState('');
  const [xp, setXp] = useState('');
  const [reset, setReset] = useState(false);
  const [reason, setReason] = useState('');
  const c = s.career;
  const t = track || c.track || cat.careers[0]?.id || '';
  const tr = cat.careers.find((x) => x.id === t);
  const same = t === c.track;
  const lvl = level || String(same ? c.level : 1);
  const top = tr?.levels.length ?? 1;
  const lv = tr?.levels.find((l) => String(l.level) === lvl);
  const lowering = same && Number(lvl) < c.level;
  const apply = (L: number) => adminApi.grantCareer(id, t, L, num(xp), reset && L < c.level, reason);
  return (
    <div className="ag-body">
      <p className="ag-now">
        {c.track ? <>Now: <b>{c.title}</b> ({c.track_name}), level <b>{c.level}</b> of {c.top} · {c.xp}{c.xp_to_next ? ` / ${c.xp_to_next}` : ''} XP{c.on_shift ? ' · on a shift' : ''}</> : 'No job right now.'}
      </p>
      <div className="ag-grid">
        <Field label="Job"><select className="adm-input" value={t} onChange={(e) => { setTrack(e.target.value); setLevel(''); }}>
          {cat.careers.map((x) => <option key={x.id} value={x.id}>{x.emoji} {x.name}</option>)}</select></Field>
        <Field label={`Level (1 to ${top})`}><select className="adm-input" value={lvl} onChange={(e) => setLevel(e.target.value)}>
          {(tr?.levels ?? []).map((l) => <option key={l.level} value={l.level}>L{l.level} · {l.title}</option>)}</select></Field>
        <Field label={`XP (0 to ${lv?.xp_to_next ?? '1,000,000'})`}><input className="adm-input" type="number" min={0} inputMode="numeric" value={xp} placeholder="keep" onChange={(e) => setXp(e.target.value)} /></Field>
      </div>
      {lowering && <label className="adm-check"><input type="checkbox" checked={reset} onChange={(e) => setReset(e.target.checked)} />Also lower their best-ever level on this job</label>}
      <Reason value={reason} onChange={setReason} required />
      <div className="adm-btnrow">
        <Go reason={reason} onConfirm={() => apply(Number(lvl))}>Set job and level</Go>
        {c.track && <Go tone="ghost" reason={reason} disabled={c.level >= (c.top ?? 1)} onConfirm={() => adminApi.grantCareer(id, c.track!, c.level + 1, null, false, reason)}>Promote +1</Go>}
        {c.track && <Go tone="ghost" reason={reason} disabled={c.level <= 1} onConfirm={() => adminApi.grantCareer(id, c.track!, c.level - 1, null, false, reason)}>Demote −1</Go>}
        {c.track && <Go tone="danger" reason={reason} onConfirm={() => adminApi.careerRemove(id, reason)}>Remove job</Go>}
      </div>
      <p className="adm-sub">Skips the promotion requirements (laptop, degree, shifts). Not allowed in the middle of a shift: clear it under Needs and stuck states.</p>
    </div>
  );
}

// ---------------------------------------------------------------- Skills and courses
function SkillsSection() {
  const { id, s } = useG();
  const [reason, setReason] = useState('');
  return (
    <div className="ag-body">
      <Slot id="skills" />
      <h4 className="ag-h">Courses</h4>
      <Reason value={reason} onChange={setReason} />
      {s.courses.map((k) => (
        <Row key={k.id} title={<>{k.icon} {k.name}</>} sub={k.status === 'completed' ? 'Completed' : k.status === 'enrolled' ? `In progress ${k.done}/${k.classes}` : 'Not started'}>
          {k.status !== 'completed' && <Go small onConfirm={() => adminApi.completeCourse(id, k.id, reason)}>Mark completed</Go>}
          {k.status !== 'none' && <Go small tone="ghost" onConfirm={() => adminApi.resetCourse(id, k.id, k.status === 'completed', reason)}>Reset</Go>}
        </Row>
      ))}
      <p className="adm-sub">Completing gives the certificate through the game&rsquo;s own graduation, with the graduation alert. Reset also takes the certificate back if it was completed.</p>
    </div>
  );
}

// ---------------------------------------------------------------- Status, reputation, debts
const PATH_LABEL: Record<string, string> = { goodwill: 'Goodwill', hustle: 'Hustle', luck: 'Luck', trouble: 'Trouble', faith: 'Faith', family: 'Family' };

function StatusSection() {
  const { id, s, cat } = useG();
  const st = s.status;
  const [cred, setCred] = useState('');
  const [wanted, setWanted] = useState('');
  const [path, setPath] = useState<Record<string, string>>({});
  const [rank, setRank] = useState('');
  const [reason, setReason] = useState('');
  const pathBody = () => {
    const out: Record<string, number> = {};
    for (const k of cat.path_keys) { const v = num(path[k] ?? ''); if (v !== null) out[k] = v; }
    return Object.keys(out).length ? out : null;
  };
  const clear = () => { setCred(''); setWanted(''); setPath({}); };
  return (
    <div className="ag-body">
      <Reason value={reason} onChange={setReason} required />
      <div className="ag-grid">
        <Field label={`Street cred (now ${st.street_cred})`}><input className="adm-input" type="number" min={0} max={1000000} inputMode="numeric" placeholder="keep" value={cred} onChange={(e) => setCred(e.target.value)} /></Field>
        <Field label={`Wanted level 0 to 5 (now ${st.wanted})`}><select className="adm-input" value={wanted} onChange={(e) => setWanted(e.target.value)}>
          <option value="">keep</option>{[0, 1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>{n}</option>)}</select></Field>
        {cat.path_keys.map((k) => (
          <Field key={k} label={`${PATH_LABEL[k] ?? k} −100 to 100 (now ${st.path[k] ?? 0})`}>
            <input className="adm-input" type="number" min={-100} max={100} inputMode="numeric" placeholder="keep" value={path[k] ?? ''} onChange={(e) => setPath({ ...path, [k]: e.target.value })} /></Field>
        ))}
      </div>
      <div className="adm-btnrow">
        <Go reason={reason} disabled={cred === '' && wanted === '' && pathBody() === null}
          onConfirm={async () => { const r = await adminApi.setNumbers(id, num(cred), num(wanted), pathBody(), reason); clear(); return r; }}>Set these numbers</Go>
      </div>
      <h4 className="ag-h">Yahoo rank</h4>
      <p className="ag-now">Now: <b>{cat.yahoo_ranks.find((r) => r.id === st.yahoo_rank)?.name ?? st.yahoo_rank}</b> · {naira(st.yahoo_total)} earned the dirty way</p>
      <div className="ag-grid">
        <Field label="Rank"><select className="adm-input" value={rank || st.yahoo_rank} onChange={(e) => setRank(e.target.value)}>
          {cat.yahoo_ranks.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow"><Go reason={reason} disabled={(rank || st.yahoo_rank) === st.yahoo_rank} onConfirm={() => adminApi.setYahooRank(id, rank, reason)}>Set Yahoo rank</Go></div>
      <h4 className="ag-h">Debts</h4>
      <p className="ag-now">Rent owed <b>{naira(st.rent_owed)}</b> · tax owed <b>{naira(st.tax_owed)}</b></p>
      <div className="adm-btnrow">
        <Go tone="ghost" reason={reason} disabled={st.rent_owed === 0} onConfirm={() => adminApi.clearDebts(id, true, false, reason)}>Clear the rent</Go>
        <Go tone="ghost" reason={reason} disabled={st.tax_owed === 0} onConfirm={() => adminApi.clearDebts(id, false, true, reason)}>Clear the tax</Go>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- Needs and stuck states
function NeedsSection() {
  const { id, s, cat } = useG();
  const [reason, setReason] = useState('');
  const [secs, setSecs] = useState('30');
  const [jr, setJr] = useState('');
  const st = s.states;
  const stuck: [string, string, boolean][] = [
    ['busy', st.busy_left > 0 ? `Clear busy timer (${st.busy_label ?? 'busy'}, ${left(st.busy_left)})` : 'Clear busy timer', st.busy_left > 0],
    ['travel', st.travelling ? `Stop road trip (to ${st.travel_to})` : 'Stop road trip', st.travelling],
    ['shift', 'Cancel running shift', st.on_shift],
    ['hospital', st.hospital_left > 0 ? `Discharge from hospital (${left(st.hospital_left)} left)` : 'Discharge from hospital', st.hospital_left > 0],
  ];
  return (
    <div className="ag-body">
      <div className="ag-needs">
        {cat.needs.map((k) => {
          const v = s.needs[k] ?? 0;
          const good = k === 'stress' ? 100 - v : v;
          return <span key={k} className="ag-need"><i style={{ width: `${Math.max(0, Math.min(100, v))}%` }} className={good < 30 ? 'is-low' : ''} /><b>{cap(k)} {v}</b></span>;
        })}
      </div>
      <div className="adm-btnrow">
        <Go onConfirm={() => adminApi.refillNeeds(id, null, reason)}>Refill every need</Go>
      </div>
      <div className="adm-chips">
        {cat.needs.map((k) => (
          <Go key={k} small tone="ghost" confirmText="Tap again" onConfirm={() => adminApi.refillNeeds(id, [k], reason)}>{k === 'stress' ? 'Calm stress' : `Fill ${k}`}</Go>
        ))}
      </div>
      <Reason value={reason} onChange={setReason} />
      <h4 className="ag-h">Stuck states</h4>
      <div className="adm-btnrow">
        {stuck.map(([k, label, on]) => <Go key={k} tone="ghost" disabled={!on} onConfirm={() => adminApi.clearStates(id, [k], reason)}>{label}</Go>)}
      </div>
      <h4 className="ag-h">Jail</h4>
      <p className="ag-now">{st.jail_left > 0 ? <>In a cell, <b>{left(st.jail_left)}</b> left{st.jail_reason ? ` (${st.jail_reason})` : ''}</> : 'Not in jail.'}</p>
      <div className="ag-grid">
        <Field label="Seconds in jail (1 to 3600)"><input className="adm-input" type="number" min={1} max={3600} inputMode="numeric" value={secs} onChange={(e) => setSecs(e.target.value)} /></Field>
      </div>
      <Reason value={jr} onChange={setJr} required />
      <div className="adm-btnrow">
        <Go tone="danger" reason={jr} disabled={st.jail_left > 0 || num(secs) === null} onConfirm={() => adminApi.jailSet(id, num(secs) ?? 0, jr)}>Put in jail</Go>
        <Go tone="ghost" reason={jr} disabled={st.jail_left === 0} onConfirm={() => adminApi.jailSet(id, 0, jr)}>Release</Go>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- Items
function useFilter<T extends { name: string }>(list: T[]) {
  const [q, setQ] = useState('');
  const shown = useMemo(() => { const t = q.trim().toLowerCase(); return t ? list.filter((x) => x.name.toLowerCase().includes(t)) : list; }, [list, q]);
  return { q, setQ, shown };
}

function ItemsSection() {
  const { id, s, cat } = useG();
  const items = useMemo(() => cat.items.filter((i) => i.category !== 'vehicle'), [cat.items]);
  const { q, setQ, shown } = useFilter(items);
  const [pick, setPick] = useState('');
  const [qty, setQty] = useState('1');
  const [reason, setReason] = useState('');
  const choice = shown.some((i) => i.id === pick) ? pick : shown[0]?.id ?? '';
  const bag = s.inventory.filter((i) => i.category !== 'vehicle');
  return (
    <div className="ag-body">
      <div className="ag-grid">
        <Field label="Find an item" wide><input className="adm-input" type="search" placeholder="e.g. jollof, laptop, fuel…" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
        <Field label={`Item (${shown.length})`} wide><select className="adm-input" value={choice} onChange={(e) => setPick(e.target.value)}>
          {shown.map((i) => <option key={i.id} value={i.id}>{i.icon ?? ''} {i.name} · {i.category}</option>)}</select></Field>
        <Field label="How many (1 to 99)"><input className="adm-input" type="number" min={1} max={99} inputMode="numeric" value={qty} onChange={(e) => setQty(e.target.value)} /></Field>
      </div>
      <Reason value={reason} onChange={setReason} />
      <div className="adm-btnrow"><Go disabled={!choice || num(qty) === null} onConfirm={() => adminApi.giveItem(id, choice, num(qty) ?? 0, reason)}>Give to the bag</Go></div>
      <h4 className="ag-h">In their bag ({bag.length})</h4>
      {bag.length === 0 && <p className="adm-empty">The bag is empty.</p>}
      {bag.map((i) => (
        <Row key={i.item} title={`${i.name} × ${i.qty}`} sub={i.category}>
          <Go small tone="ghost" confirmText="Tap again" onConfirm={() => adminApi.takeItem(id, i.item, 1, reason)}>Take 1</Go>
          {i.qty > 1 && <Go small tone="danger" confirmText="Tap again" onConfirm={() => adminApi.takeItem(id, i.item, i.qty, reason)}>Take all</Go>}
        </Row>
      ))}
      <p className="adm-sub">There is no fuel item in the game (fuel is part of the car&rsquo;s running cost), so nothing to give there.</p>
    </div>
  );
}

// ---------------------------------------------------------------- Cars and garage
function CarsSection() {
  const { id, s, cat } = useG();
  const cars = useMemo(() => cat.items.filter((i) => i.category === 'vehicle'), [cat.items]);
  const owned = s.inventory.filter((i) => i.category === 'vehicle');
  const free = cars.filter((c) => !owned.some((o) => o.item === c.id));
  const [car, setCar] = useState('');
  const [gar, setGar] = useState('');
  const [reason, setReason] = useState('');
  const carChoice = free.some((c) => c.id === car) ? car : free[0]?.id ?? '';
  const garChoice = gar || cat.garages[0]?.id || '';
  return (
    <div className="ag-body">
      <Reason value={reason} onChange={setReason} />
      <div className="ag-grid">
        <Field label="Car to give" wide><select className="adm-input" value={carChoice} onChange={(e) => setCar(e.target.value)}>
          {free.map((c) => <option key={c.id} value={c.id}>{c.icon ?? '🚗'} {c.name}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow"><Go disabled={!carChoice} onConfirm={() => adminApi.giveItem(id, carChoice, 1, reason)}>Give the car</Go></div>
      <h4 className="ag-h">Their cars ({owned.length})</h4>
      {owned.length === 0 && <p className="adm-empty">No cars.</p>}
      {owned.map((c) => <Row key={c.item} title={`🚗 ${c.name}`}><Go small tone="danger" confirmText="Tap again" onConfirm={() => adminApi.takeItem(id, c.item, 1, reason)}>Take back</Go></Row>)}
      <h4 className="ag-h">Garage</h4>
      <p className="ag-now">{s.garage ? <>Has a <b>{s.garage.name}</b></> : 'No garage.'} · home type: {s.home.kind.replace('_', ' ')}</p>
      <div className="ag-grid">
        <Field label="Garage type" wide><select className="adm-input" value={garChoice} onChange={(e) => setGar(e.target.value)}>
          {cat.garages.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow">
        <Go onConfirm={() => adminApi.giveGarage(id, garChoice, reason)}>Build it free</Go>
        {s.garage && <Go tone="danger" onConfirm={() => adminApi.removeGarage(id, reason)}>Remove garage</Go>}
      </div>
      <p className="adm-sub">A garage has to fit their home (a carport fits any home; a luxury garage needs a duplex).</p>
    </div>
  );
}

// ---------------------------------------------------------------- Furniture, wardrobe, stall pass
function FurnitureSection() {
  const { id, s, cat } = useG();
  const { q, setQ, shown } = useFilter(cat.furniture);
  const [pick, setPick] = useState('');
  const [qty, setQty] = useState('1');
  const [cl, setCl] = useState('');
  const [pass, setPass] = useState('');
  const [hours, setHours] = useState('24');
  const [reason, setReason] = useState('');
  const choice = shown.some((f) => f.id === pick) ? pick : shown[0]?.id ?? '';
  const clothes = cat.wardrobe.filter((w) => (!w.gender || w.gender === s.gender) && !s.wardrobe.some((o) => o.id === w.id));
  const clChoice = clothes.some((c) => c.id === cl) ? cl : clothes[0]?.id ?? '';
  const passChoice = pass || cat.passes[0] || '';
  return (
    <div className="ag-body">
      <Reason value={reason} onChange={setReason} />
      <div className="ag-grid">
        <Field label="Find a piece" wide><input className="adm-input" type="search" placeholder="e.g. sofa, bed, TV…" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
        <Field label={`Furniture (${shown.length})`} wide><select className="adm-input" value={choice} onChange={(e) => setPick(e.target.value)}>
          {shown.map((f) => <option key={f.id} value={f.id}>{f.emoji} {f.name} (max {f.max})</option>)}</select></Field>
        <Field label="How many"><input className="adm-input" type="number" min={1} max={20} inputMode="numeric" value={qty} onChange={(e) => setQty(e.target.value)} /></Field>
      </div>
      <div className="adm-btnrow"><Go disabled={!choice || num(qty) === null} onConfirm={() => adminApi.giveFurniture(id, choice, num(qty) ?? 0, reason)}>Give to their house</Go></div>
      <h4 className="ag-h">Their furniture ({s.furniture.length})</h4>
      {s.furniture.map((f) => (
        <Row key={f.id} title={`${f.emoji} ${f.name} × ${f.qty}`} sub={`most ${f.max}${f.house_qty ? ` · ${f.house_qty} came with the house` : ''}`}>
          {f.qty - f.house_qty > 0 && <Go small tone="ghost" confirmText="Tap again" onConfirm={() => adminApi.takeFurniture(id, f.id, 1, reason)}>Take 1</Go>}
        </Row>
      ))}
      <h4 className="ag-h">Wardrobe ({s.wardrobe.length})</h4>
      <div className="ag-grid">
        <Field label="Clothes to give" wide><select className="adm-input" value={clChoice} onChange={(e) => setCl(e.target.value)}>
          {clothes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow"><Go disabled={!clChoice} onConfirm={() => adminApi.giveWardrobe(id, clChoice, reason)}>Give the clothes</Go></div>
      {s.wardrobe.map((w) => <Row key={w.id} title={w.name}><Go small tone="ghost" confirmText="Tap again" onConfirm={() => adminApi.takeWardrobe(id, w.id, reason)}>Take back</Go></Row>)}
      <h4 className="ag-h">Stall pass</h4>
      <div className="ag-grid">
        <Field label="Pass"><select className="adm-input" value={passChoice} onChange={(e) => setPass(e.target.value)}>{cat.passes.map((p) => <option key={p} value={p}>{p}</option>)}</select></Field>
        <Field label="Hours (1 to 720)"><input className="adm-input" type="number" min={1} max={720} inputMode="numeric" value={hours} onChange={(e) => setHours(e.target.value)} /></Field>
      </div>
      <div className="adm-btnrow"><Go disabled={!passChoice || num(hours) === null} onConfirm={() => adminApi.giveHustlePass(id, passChoice, num(hours) ?? 0, reason)}>Give the pass</Go></div>
      {s.passes.map((p) => <Row key={p.pass} title={`${p.pass} pass`} sub={`until ${new Date(p.until).toLocaleString()}`}><Go small tone="ghost" confirmText="Tap again" onConfirm={() => adminApi.takeHustlePass(id, p.pass, reason)}>End it</Go></Row>)}
    </div>
  );
}

// ---------------------------------------------------------------- Home, property, land
function HomeSection() {
  const { id, s, cat } = useG();
  const [home, setHome] = useState('');
  const [offer, setOffer] = useState('');
  const [mkt, setMkt] = useState('');
  const [plots, setPlots] = useState('1');
  const [reason, setReason] = useState('');
  const homeChoice = home || cat.homes.find((h) => h.id !== s.home.start_home)?.id || '';
  const offerChoice = offer || cat.offers[0]?.id || '';
  const mktChoice = mkt || cat.land[0]?.id || '';
  return (
    <div className="ag-body">
      <p className="ag-now">Lives in: <b>{s.home.name ?? s.home.start_home ?? '—'}</b> ({s.home.kind.replace('_', ' ')}){s.home.residence ? ` · ${s.home.residence.role === 'owner' ? 'own property' : 'tenant'}` : ''}</p>
      <Reason value={reason} onChange={setReason} required />
      <div className="ag-grid">
        <Field label="Home type" wide><select className="adm-input" value={homeChoice} onChange={(e) => setHome(e.target.value)}>
          {cat.homes.map((h) => <option key={h.id} value={h.id}>{h.name}{h.district ? ` · ${h.district}` : ''}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow"><Go reason={reason} disabled={!homeChoice} onConfirm={() => adminApi.setHome(id, homeChoice, null, reason)}>Move them in, free</Go></div>
      <p className="adm-sub">Same path as moving house: furniture is placed again, upgrades follow the home. They must be free (not busy, jailed, travelling or visiting).</p>
      <h4 className="ag-h">Their properties ({s.properties.length})</h4>
      {s.properties.length === 0 && <p className="adm-empty">No properties.</p>}
      {s.properties.map((p) => (
        <Row key={p.id} title={p.name} sub={[p.lives ? 'they live here' : p.occupied ? 'a tenant lives here' : 'empty', p.listed ? 'listed' : '', p.built ? 'built block unit' : ''].filter(Boolean).join(' · ')}>
          <Go small tone="ghost" reason={reason} disabled={p.occupied} onConfirm={() => adminApi.setHome(id, null, p.id, reason)}>Live there</Go>
          <Go small tone="danger" reason={reason} disabled={p.occupied || p.built} onConfirm={() => adminApi.takeProperty(id, p.id, reason)}>Take</Go>
        </Row>
      ))}
      <div className="ag-grid">
        <Field label="Give a property" wide><select className="adm-input" value={offerChoice} onChange={(e) => setOffer(e.target.value)}>
          {cat.offers.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow"><Go reason={reason} disabled={!offerChoice} onConfirm={() => adminApi.giveProperty(id, offerChoice, reason)}>Give the property</Go></div>
      <p className="adm-sub">A gift is worth ₦0 if sold back (no cash printed); living in it and upgrades work as normal.</p>
      <h4 className="ag-h">Land ({s.land.reduce((a, l) => a + l.plots, 0)} plots)</h4>
      {s.land.map((l) => (
        <Row key={l.market} title={`${l.name}: ${l.plots} plot${l.plots === 1 ? '' : 's'}`} sub={l.locked ? `${l.locked} locked under a build` : undefined}>
          <Go small tone="danger" reason={reason} disabled={l.plots - l.locked < 1} onConfirm={() => adminApi.takeLand(id, l.market, 1, reason)}>Take 1</Go>
        </Row>
      ))}
      <div className="ag-grid">
        <Field label="Land area"><select className="adm-input" value={mktChoice} onChange={(e) => setMkt(e.target.value)}>{cat.land.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select></Field>
        <Field label="Plots (1 to 100)"><input className="adm-input" type="number" min={1} max={100} inputMode="numeric" value={plots} onChange={(e) => setPlots(e.target.value)} /></Field>
      </div>
      <div className="adm-btnrow"><Go reason={reason} disabled={!mktChoice || num(plots) === null} onConfirm={() => adminApi.giveLand(id, mktChoice, num(plots) ?? 0, reason)}>Give the plots</Go></div>
      <Slot id="home" />
    </div>
  );
}

// ---------------------------------------------------------------- Business and company
type BizDraft = { level: string; staff: string; ins: string; stock: string };

function BusinessCard({ b }: { b: GrantState['businesses'][number] }) {
  const [d, setD] = useState<BizDraft>({ level: '', staff: '', ins: '', stock: '' });
  const [reason, setReason] = useState('');
  const set = (k: keyof BizDraft, v: string) => setD({ ...d, [k]: v });
  const dirty = d.level !== '' || d.staff !== '' || d.ins !== '' || d.stock !== '';
  const hoursLeft = b.stock_until ? Math.max(0, Math.round((Date.parse(b.stock_until) - Date.now()) / 3600000)) : 0;
  const insLeft = b.insured_until ? Math.max(0, Math.ceil((Date.parse(b.insured_until) - Date.now()) / 86400000)) : 0;
  return (
    <div className="ag-card">
      <b>{b.icon} {b.name}</b>
      <small>{b.type} · level {b.level}/{b.max_level} · {b.staff}/{b.staff_slots} staff · insured {insLeft} d · stock {hoursLeft} h{b.listed ? ' · ON THE MARKET' : ''}</small>
      <div className="ag-grid">
        <Field label="Level"><select className="adm-input" value={d.level} onChange={(e) => set('level', e.target.value)}>
          <option value="">keep ({b.level})</option>{Array.from({ length: b.max_level }, (_, i) => i + 1).map((n) => <option key={n} value={n}>{n}</option>)}</select></Field>
        <Field label="Staff"><select className="adm-input" value={d.staff} onChange={(e) => set('staff', e.target.value)}>
          <option value="">keep ({b.staff})</option>{Array.from({ length: b.staff_slots + 1 }, (_, i) => i).map((n) => <option key={n} value={n}>{n}</option>)}</select></Field>
        <Field label="Insured days (0 to 90)"><input className="adm-input" type="number" min={0} max={90} inputMode="numeric" placeholder="keep" value={d.ins} onChange={(e) => set('ins', e.target.value)} /></Field>
        <Field label="Stock hours"><input className="adm-input" type="number" min={0} inputMode="numeric" placeholder="keep" value={d.stock} onChange={(e) => set('stock', e.target.value)} /></Field>
      </div>
      <Reason value={reason} onChange={setReason} required />
      <div className="adm-btnrow">
        <Go reason={reason} disabled={!dirty || b.listed}
          onConfirm={async () => { const r = await adminApi.businessSet(b.id, num(d.level), num(d.staff), num(d.ins), num(d.stock), reason); setD({ level: '', staff: '', ins: '', stock: '' }); return r; }}>Apply to this business</Go>
      </div>
    </div>
  );
}

function CompanyCard({ c }: { c: GrantState['companies'][number] }) {
  const { cat } = useG();
  const [fmt, setFmt] = useState('');
  const [staff, setStaff] = useState('');
  const [mgr, setMgr] = useState<'' | 'yes' | 'no'>('');
  const [gen, setGen] = useState<'' | 'yes' | 'no'>('');
  const [reason, setReason] = useState('');
  const dirty = fmt !== '' || staff !== '' || mgr !== '' || gen !== '';
  const yn = (v: '' | 'yes' | 'no') => (v === '' ? null : v === 'yes');
  return (
    <div className="ag-card">
      <b>{c.logo} {c.name}</b>
      <small>{c.industry} · size {c.format ?? '?'} · {c.staff}/{c.slots} staff · {c.manager ? 'manager' : 'no manager'} · {c.generator ? 'generator' : 'no generator'}{c.listed ? ' · ON THE MARKET' : ''}</small>
      <div className="ag-grid">
        <Field label="Size"><select className="adm-input" value={fmt} onChange={(e) => setFmt(e.target.value)}><option value="">keep ({c.format})</option>
          {cat.company_formats.map((f) => <option key={f.id} value={f.id}>{f.name} ({f.staff_slots} staff)</option>)}</select></Field>
        <Field label="Staff"><input className="adm-input" type="number" min={0} inputMode="numeric" placeholder={`keep (${c.staff})`} value={staff} onChange={(e) => setStaff(e.target.value)} /></Field>
        <Field label="Manager"><select className="adm-input" value={mgr} onChange={(e) => setMgr(e.target.value as '' | 'yes' | 'no')}><option value="">keep</option><option value="yes">Yes</option><option value="no">No</option></select></Field>
        <Field label="Generator"><select className="adm-input" value={gen} onChange={(e) => setGen(e.target.value as '' | 'yes' | 'no')}><option value="">keep</option><option value="yes">Yes</option><option value="no">No</option></select></Field>
      </div>
      <Reason value={reason} onChange={setReason} required />
      <div className="adm-btnrow">
        <Go reason={reason} disabled={!dirty || c.listed}
          onConfirm={async () => { const r = await adminApi.companySet(c.id, fmt || null, num(staff), yn(mgr), yn(gen), reason); setFmt(''); setStaff(''); setMgr(''); setGen(''); return r; }}>Apply to this company</Go>
      </div>
    </div>
  );
}

function BusinessSection() {
  const { id, s, cat } = useG();
  const [ind, setInd] = useState('');
  const [area, setArea] = useState('');
  const [name, setName] = useState('');
  const [reason, setReason] = useState('');
  const indChoice = ind || cat.company_industries[0]?.id || '';
  const areaChoice = area || cat.company_areas[0]?.id || '';
  return (
    <div className="ag-body">
      <h4 className="ag-h">Map businesses ({s.businesses.length})</h4>
      {s.businesses.length === 0 && <p className="adm-empty">Owns no map business. Use the grant box below.</p>}
      {s.businesses.map((b) => <BusinessCard key={b.id} b={b} />)}
      <Slot id="business" />
      <h4 className="ag-h">Companies ({s.companies.length})</h4>
      {s.companies.length === 0 && <p className="adm-empty">Owns no company.</p>}
      {s.companies.map((c) => <CompanyCard key={c.id} c={c} />)}
      <div className="ag-card">
        <b>Give a company</b>
        <div className="ag-grid">
          <Field label="Kind"><select className="adm-input" value={indChoice} onChange={(e) => setInd(e.target.value)}>{cat.company_industries.map((i) => <option key={i.id} value={i.id}>{i.icon} {i.name}</option>)}</select></Field>
          <Field label="Head office area"><select className="adm-input" value={areaChoice} onChange={(e) => setArea(e.target.value)}>{cat.company_areas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></Field>
          <Field label="Name (optional)" wide><input className="adm-input" maxLength={28} value={name} onChange={(e) => setName(e.target.value)} /></Field>
        </div>
        <Reason value={reason} onChange={setReason} required />
        <div className="adm-btnrow"><Go reason={reason} disabled={!indChoice || !areaChoice} onConfirm={async () => { const r = await adminApi.companyGrant(id, indChoice, areaChoice, name.trim() || null, reason); setName(''); return r; }}>Give the company</Go></div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- Gang and titles
function GangSection() {
  const { id, s, cat } = useG();
  const [crew, setCrew] = useState('');
  const [rank, setRank] = useState('member');
  const [tier, setTier] = useState('');
  const [ward, setWard] = useState('');
  const [reason, setReason] = useState('');
  const crewChoice = crew || String(s.crew?.id ?? cat.crews[0]?.id ?? '');
  const tierChoice = tier || String(cat.chief_tiers[0]?.tier ?? '');
  const wardChoice = ward || cat.wards[0]?.id || '';
  return (
    <div className="ag-body">
      <Reason value={reason} onChange={setReason} />
      <p className="ag-now">{s.crew ? <>In <b>{s.crew.name}</b> [{s.crew.tag}] as <b>{cap(s.crew.rank)}</b></> : 'Not in a gang.'}</p>
      <div className="ag-grid">
        <Field label="Gang" wide><select className="adm-input" value={crewChoice} onChange={(e) => setCrew(e.target.value)}>
          {cat.crews.map((c) => <option key={c.id} value={c.id}>{c.name} [{c.tag}] · {c.members} members</option>)}</select></Field>
        <Field label="Rank"><select className="adm-input" value={rank} onChange={(e) => setRank(e.target.value)}>
          {['lieutenant', 'member', 'prospect'].map((r) => <option key={r} value={r}>{cap(r)}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow">
        <Go disabled={!crewChoice || (!!s.crew && String(s.crew.id) !== crewChoice)} onConfirm={() => adminApi.crewSet(id, Number(crewChoice), rank, reason)}>{s.crew ? 'Set rank' : 'Put in the gang'}</Go>
        {s.crew && <Go tone="danger" onConfirm={() => adminApi.crewRemove(id, reason)}>Remove from gang</Go>}
      </div>
      <p className="adm-sub">The Boss rank changes inside the gang itself. A player already in another gang must be removed first.</p>
      <h4 className="ag-h">Chief title</h4>
      <p className="ag-now">{s.chief ? <><b>{s.chief.name}</b> of {s.chief.ward_name ?? s.chief.ward}</> : 'No chief title.'}</p>
      <div className="ag-grid">
        <Field label="Title"><select className="adm-input" value={tierChoice} onChange={(e) => setTier(e.target.value)}>{cat.chief_tiers.map((t) => <option key={t.tier} value={t.tier}>{t.name}</option>)}</select></Field>
        <Field label="Of (part of Benin)"><select className="adm-input" value={wardChoice} onChange={(e) => setWard(e.target.value)}>{cat.wards.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}</select></Field>
      </div>
      <div className="adm-btnrow">
        <Go reason={reason} disabled={!tierChoice || !wardChoice} onConfirm={() => adminApi.setChiefTitle(id, Number(tierChoice), wardChoice, reason)}>Give the title</Go>
        {s.chief && <Go tone="danger" onConfirm={() => adminApi.removeChiefTitle(id, reason)}>Remove title</Go>}
      </div>
      <h4 className="ag-h">Office titles</h4>
      <p className="adm-sub">Mayor, councillor and industry offices are handled in <Link to="/admin/offices" className="adm-link ag-link">Admin → Offices</Link> (appoint anybody by username) and <Link to="/admin/elections" className="adm-link ag-link">Admin → Elections</Link>.</p>
    </div>
  );
}

// ---------------------------------------------------------------- Perks and bans
function PerksSection() {
  const { id, s } = useG();
  return (
    <div className="ag-body">
      <Slot id="perks" />
      <h4 className="ag-h">Benin Gist ban</h4>
      {s.gist_ban
        ? <>
            <p className="ag-now">Banned from Gist{s.gist_ban.until ? ` until ${new Date(s.gist_ban.until).toLocaleString()}` : ' for good'}{s.gist_ban.reason ? ` (${s.gist_ban.reason})` : ''}.</p>
            <div className="adm-btnrow"><Go onConfirm={() => adminApi.gistBan(id, false)}>Lift the Gist ban</Go></div>
          </>
        : <p className="ag-now">Not banned from Gist.</p>}
    </div>
  );
}

// ---------------------------------------------------------------- the toolbox
interface Sec { id: SectionId; icon: string; title: string; keys: string; summary: (s: GrantState) => string; body: ReactNode }

const SECTIONS: Sec[] = [
  { id: 'career', icon: '💼', title: 'Career', keys: 'job level xp promote demote work shift track', summary: (s) => (s.career.track ? `${s.career.title} · L${s.career.level}/${s.career.top}` : 'no job'), body: <CareerSection /> },
  { id: 'skills', icon: '🌟', title: 'Skills and courses', keys: 'skill course certificate degree school learn', summary: (s) => `${s.courses.filter((c) => c.status === 'completed').length}/${s.courses.length} courses done`, body: <SkillsSection /> },
  { id: 'status', icon: '📈', title: 'Street cred, wanted, reputation', keys: 'street cred wanted reputation path goodwill luck faith yahoo rank debt rent tax', summary: (s) => `cred ${s.status.street_cred} · wanted ${s.status.wanted}`, body: <StatusSection /> },
  { id: 'needs', icon: '❤️', title: 'Needs, jail, stuck states', keys: 'needs hunger energy hygiene fun social health stress jail hospital busy travel stuck release', summary: (s) => (s.states.jail_left ? 'in jail' : s.states.hospital_left ? 'in hospital' : s.states.busy_left ? 'busy' : s.states.travelling ? 'travelling' : 'free'), body: <NeedsSection /> },
  { id: 'items', icon: '🎒', title: 'Items and bag', keys: 'item bag food drink tool laptop phone ingredient give take inventory', summary: (s) => `${s.inventory.filter((i) => i.category !== 'vehicle').length} kinds in the bag`, body: <ItemsSection /> },
  { id: 'cars', icon: '🚗', title: 'Cars and garage', keys: 'car vehicle garage carport park', summary: (s) => `${s.inventory.filter((i) => i.category === 'vehicle').length} cars${s.garage ? ' · ' + s.garage.name : ''}`, body: <CarsSection /> },
  { id: 'furniture', icon: '🛋️', title: 'Furniture, clothes, stall pass', keys: 'furniture sofa bed tv wardrobe clothes outfit pass stall hustle', summary: (s) => `${s.furniture.length} pieces · ${s.wardrobe.length} clothes`, body: <FurnitureSection /> },
  { id: 'home', icon: '🏠', title: 'Home, property, land', keys: 'home house move property land plot estate rent upgrade', summary: (s) => `${s.home.name ?? '—'} · ${s.properties.length} props · ${s.land.reduce((a, l) => a + l.plots, 0)} plots`, body: <HomeSection /> },
  { id: 'business', icon: '🏪', title: 'Business and company', keys: 'business company level staff insurance stock manager generator shop', summary: (s) => `${s.businesses.length} businesses · ${s.companies.length} companies`, body: <BusinessSection /> },
  { id: 'gang', icon: '🎖️', title: 'Gang and titles', keys: 'gang crew rank chief title office badge', summary: (s) => (s.crew ? `${s.crew.tag} ${cap(s.crew.rank)}` : 'no gang') + (s.chief ? ` · ${s.chief.name}` : ''), body: <GangSection /> },
  { id: 'perks', icon: '🛋️', title: 'Perks and bans', keys: 'lounge membership charm gist ban shrine', summary: (s) => (s.gist_ban ? 'Gist-banned' : 'lounge, charms, Gist'), body: <PerksSection /> },
];

export default function GrantToolbox({ id, onChanged, slots }: { id: string; onChanged: () => void; slots: Partial<Record<SectionId, ReactNode>> }) {
  const { data: s, error, reload } = useLoad(() => adminApi.grantState(id), [id]);
  const { data: cat, error: catError, reload: reloadCat } = useLoad(loadCatalog, []);
  const [open, setOpen] = useState<SectionId | null>(null);
  const [q, setQ] = useState('');
  const [busy, setBusy] = useState(false);
  const [ver, setVer] = useState(0);

  const run = async (fn: () => Promise<Msg>) => {
    setBusy(true);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await reload();
      setVer((v) => v + 1);
      onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };

  const term = q.trim().toLowerCase();
  const list = SECTIONS.filter((x) => !term || `${x.title} ${x.keys}`.toLowerCase().includes(term));
  useEffect(() => { if (term && list.length === 1) setOpen(list[0].id); }, [term, list.length]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <section className="adm-box ag" data-testid="adm-grants">
      <h3 className="adm-h3">🎁 Grant toolbox</h3>
      <p className="adm-sub">Give, set or take back anything in the game. Every change needs a second tap, is audited and shows the player an alert.</p>
      {(error || catError) && <LoadError error={error ?? catError ?? ''} onRetry={() => { void reload(); void reloadCat(); }} />}
      {!s || !cat ? (!error && !catError && <p className="adm-empty" aria-busy="true">Loading the toolbox…</p>) : (
        <GrantCtx.Provider value={{ id, s, cat, busy, ver, run, slots }}>
          {s.banned && <p className="adm-error" role="alert">This account is banned. Grants are refused; taking things back still works.</p>}
          <label className="adm-search ag-search"><span aria-hidden>🔎</span>
            <input type="search" placeholder="Jump to: career, items, car, home, gang…" aria-label="Jump to a section" value={q} onChange={(e) => setQ(e.target.value)} /></label>
          <div className="ag-list">
            {list.length === 0 && <p className="adm-empty">Nothing matches “{q}”.</p>}
            {list.map((x) => {
              const isOpen = open === x.id;
              return (
                <div key={x.id} className={`ag-sec${isOpen ? ' is-open' : ''}`} data-testid={`ag-sec-${x.id}`}>
                  <button type="button" className="ag-sec__head" aria-expanded={isOpen} onClick={() => setOpen(isOpen ? null : x.id)}>
                    <span className="ag-sec__icon" aria-hidden>{x.icon}</span>
                    <span className="ag-sec__title"><b>{x.title}</b><small>{x.summary(s)}</small></span>
                    <span className="ag-sec__chev" aria-hidden>{isOpen ? '▾' : '▸'}</span>
                  </button>
                  {isOpen && <div className="ag-sec__body">{x.body}</div>}
                </div>
              );
            })}
          </div>
          <div className="adm-btnrow"><Btn small tone="quiet" icon="refresh" onClick={() => { void reload(); setVer((v) => v + 1); }}>Refresh numbers</Btn></div>
        </GrantCtx.Provider>
      )}
    </section>
  );
}
