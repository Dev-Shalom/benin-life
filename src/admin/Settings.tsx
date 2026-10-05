// Settings: every game_config value, grouped by category, with the most-used knobs on top.
import { useEffect, useMemo, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { useConfig } from '../lib/config';
import { adminApi, type ConfigRow, type Row } from './api';
import { Btn, JsonControl, LoadError, NumberControl, PageHead, Skeleton, Toggle } from './parts';
import { fmtValue, timeShort, useLoad } from './util';

const CATEGORY_META: Record<string, { title: string; emoji: string; blurb: string }> = {
  time: { title: 'Time & speed', emoji: '⏱️', blurb: 'How fast activities, sleep, jail and hospital timers run.' },
  clock: { title: 'Game clock', emoji: '🕰️', blurb: 'Day length, night hours and the launch day.' },
  origin: { title: 'Origin (LAPO / Nepo)', emoji: '👶', blurb: 'Who is born rich, and what each origin starts with.' },
  start: { title: 'New players', emoji: '🌱', blurb: 'Starting needs and new-player protection.' },
  creator: { title: 'Sim creator', emoji: '🧑‍🎨', blurb: 'Creator steps and the arrival spot.' },
  needs: { title: 'Needs', emoji: '🍲', blurb: 'How quickly hunger, energy and the rest go down.' },
  career: { title: 'Jobs & careers', emoji: '💼', blurb: 'Pay, XP, shifts and performance.' },
  shop: { title: 'Shops', emoji: '🛍️', blurb: 'Buying, selling and ChopNow delivery.' },
  rent: { title: 'Rent', emoji: '🏠', blurb: 'Weekly rent and what happens when you owe.' },
  bank: { title: 'Bank & transfers', emoji: '🏦', blurb: 'Opening hours, limits and fees.' },
  pos: { title: 'PoS', emoji: '🏧', blurb: 'PoS cash-out charges.' },
  travel: { title: 'Travel & fares', emoji: '🛺', blurb: 'Speeds and fares for every way to move.' },
  traffic: { title: 'Traffic', emoji: '🚦', blurb: 'Rush hours and the Ramat Park go-slow.' },
  crime: { title: 'Crime & robbery', emoji: '🦹', blurb: 'Street robbery chances, losses and injuries.' },
  chat: { title: 'Chat', emoji: '💬', blurb: 'Chat switch, rate limits and moderation.' },
  admin: { title: 'Admin', emoji: '🛡️', blurb: 'Admin access. Hidden from players.' },
};

/** The knobs the owner touches most, with plain-English help. */
const QUICK: { key: string; hint: string }[] = [
  { key: 'time.real_seconds_per_game_minute', hint: 'Activity & sleep speed. 0.75 = an 8-hour sleep takes 6 real minutes. Lower is faster.' },
  { key: 'origin.nepo_pct', hint: 'Chance a new player is born a Nepo baby.' },
  { key: 'origin.force_next', hint: 'The very next new account gets this origin, then it switches itself off.' },
  { key: 'origin.lapo.start_cash', hint: 'Cash a LAPO baby starts with (the home choice can change it).' },
  { key: 'origin.nepo.start_cash', hint: 'Cash a Nepo baby starts with.' },
  { key: 'origin.nepo.start_bank', hint: 'Money already in a Nepo baby’s bank.' },
  { key: 'origin.nepo.allowance_daily', hint: 'Dad’s allowance per game day for Nepo babies.' },
  { key: 'rent.enabled', hint: 'Turn weekly rent on or off for everyone.' },
  { key: 'crime.npc_base_pct', hint: 'Base chance of being robbed on a street trip.' },
  { key: 'crime.npc_max_pct', hint: 'Robbery chance never goes above this.' },
  { key: 'career.pay_mult', hint: 'Multiplies every job’s pay. 1 = normal, 1.5 = +50%.' },
  { key: 'career.max_shifts_per_game_day', hint: 'How many shifts a player can work per game day.' },
  { key: 'pos.fee_pct', hint: 'PoS cash-out charge.' },
  { key: 'bank.transfer_daily_limit', hint: 'Most a player can send per game day.' },
  { key: 'bank.transfer_fee', hint: 'Fee for each phone transfer.' },
  { key: 'chat.enabled', hint: 'Turn location chat on or off for everyone.' },
];

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

function validate(row: ConfigRow, v: unknown): string | null {
  if (row.kind === 'bool') return typeof v === 'boolean' ? null : 'Pick on or off';
  if (row.kind === 'text') return typeof v === 'string' ? null : 'Must be text';
  if (row.kind === 'json') return v === undefined ? 'Invalid JSON' : null;
  if (v === '' || typeof v !== 'number' || !Number.isFinite(v)) return 'Enter a number';
  if (row.kind === 'naira' && !Number.isInteger(v)) return 'Whole naira only';
  if (row.min !== null && v < row.min) return `At least ${row.min}`;
  if (row.max !== null && v > row.max) return `At most ${row.max}`;
  return null;
}

function ValueControl({ row, value, onChange, tiers }: {
  row: ConfigRow; value: unknown; onChange: (v: unknown) => void; tiers: Row[];
}) {
  const [jsonText, setJsonText] = useState(() => JSON.stringify(row.value, null, 2));
  if (row.key === 'origin.force_next') {
    const opts = [{ id: '', name: 'Off (random roll)' }, ...tiers.map((t) => ({ id: String(t.id), name: String(t.name) }))];
    return (
      <div className="adm-chips" role="radiogroup" aria-label={row.label}>
        {opts.map((o) => (
          <button key={o.id || 'off'} type="button" role="radio" aria-checked={value === o.id}
            className={`adm-chip${value === o.id ? ' is-on' : ''}`} onClick={() => onChange(o.id)}>{o.name}</button>
        ))}
      </div>
    );
  }
  switch (row.kind) {
    case 'bool':
      return <Toggle checked={value === true} onChange={onChange} label={row.label} />;
    case 'text':
      return <input className="adm-input" value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />;
    case 'json':
      return <JsonControl expect="any" value={jsonText} onChange={(t, p, ok) => { setJsonText(t); onChange(ok ? p : undefined); }} />;
    default:
      return <NumberControl kind={row.kind} value={value as number | ''} min={row.min} max={row.max}
        invalid={!!validate(row, value)} onChange={onChange} />;
  }
}

function ConfigItem({ row, draft, setDraft, onSave, onRevert, tiers, hint, card }: {
  row: ConfigRow; draft: unknown; setDraft: (v: unknown | undefined) => void; onSave: () => Promise<void>;
  onRevert: () => Promise<void>; tiers: Row[]; hint?: string; card?: boolean;
}) {
  const value = draft === undefined ? row.value : draft;
  const dirty = draft !== undefined && !same(draft, row.value);
  const err = dirty ? validate(row, value) : null;
  const [busy, setBusy] = useState(false);
  const canRevert = !dirty && row.key !== 'origin.force_next' && row.prev_value !== null && row.prev_value !== undefined && !same(row.prev_value, row.value);
  return (
    <div className={`adm-cfg${card ? ' adm-cfg--card' : ''}${dirty ? ' is-dirty' : ''}`} id={`cfg-${row.key}`}>
      <div className="adm-cfg__text">
        <div className="adm-cfg__label">{row.label || row.key}</div>
        <div className="adm-cfg__desc">{hint ?? row.description}</div>
        <code className="adm-cfg__key">{row.key}</code>
      </div>
      <div className="adm-cfg__control">
        <ValueControl row={row} value={value} tiers={tiers} onChange={(v) => setDraft(same(v, row.value) ? undefined : v)} />
        {err && <div className="adm-field__err">{err}</div>}
        <div className="adm-cfg__meta">
          {dirty ? (
            <>
              <span className="adm-cfg__was">was {fmtValue(row.kind, row.value)}</span>
              <Btn small tone="quiet" onClick={() => setDraft(undefined)}>Undo</Btn>
              <Btn small tone="primary" disabled={!!err || busy}
                onClick={async () => { setBusy(true); try { await onSave(); } finally { setBusy(false); } }}>
                {busy ? 'Saving…' : 'Save'}
              </Btn>
            </>
          ) : (
            <>
              <span className="adm-cfg__stamp">
                {row.updated_by_name ? `Changed ${timeShort(row.updated_at)} by ${row.updated_by_name}` : ''}
              </span>
              {canRevert && (
                <Btn small tone="quiet" disabled={busy} title="Put back the value from before the last change"
                  onClick={async () => { setBusy(true); try { await onRevert(); } finally { setBusy(false); } }}>
                  ↺ Back to {fmtValue(row.kind, row.prev_value)}
                </Btn>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export default function Settings() {
  const { data: rows, setData: setRows, error, loading, reload } = useLoad(() => adminApi.configList());
  const { data: tiers } = useLoad(() => adminApi.tableRows('origin_tiers'));
  const [drafts, setDrafts] = useState<Record<string, unknown>>({});
  const [q, setQ] = useState('');
  const [cat, setCat] = useState<string>('quick');
  const [savingAll, setSavingAll] = useState(false);
  const { values: liveValues } = useConfig();

  // Another admin (or the game) changed something: refresh quietly, keep local drafts.
  useEffect(() => {
    if (rows) void adminApi.configList().then(setRows).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveValues]);

  const byKey = useMemo(() => new Map((rows ?? []).map((r) => [r.key, r])), [rows]);
  const categories = useMemo(() => {
    const m = new Map<string, ConfigRow[]>();
    for (const r of rows ?? []) {
      if (!m.has(r.category)) m.set(r.category, []);
      m.get(r.category)!.push(r);
    }
    const order = Object.keys(CATEGORY_META);
    return [...m.entries()].sort((a, b) => {
      const ia = order.indexOf(a[0]); const ib = order.indexOf(b[0]);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a[0].localeCompare(b[0]);
    });
  }, [rows]);

  const dirtyKeys = Object.keys(drafts).filter((k) => byKey.has(k) && !same(drafts[k], byKey.get(k)!.value));
  const invalid = dirtyKeys.some((k) => validate(byKey.get(k)!, drafts[k]));

  const setDraft = (key: string) => (v: unknown | undefined) =>
    setDrafts((d) => { const n = { ...d }; if (v === undefined) delete n[key]; else n[key] = v; return n; });

  const applySaved = async (keys: string[]) => {
    setDrafts((d) => { const n = { ...d }; keys.forEach((k) => delete n[k]); return n; });
    try { setRows(await adminApi.configList()); } catch { /* keep */ }
  };

  const saveOne = (key: string) => async () => {
    try {
      const r = await adminApi.configSet(key, drafts[key]);
      toast(r.message, 'good');
      await applySaved([key]);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const revertOne = (row: ConfigRow) => async () => {
    try {
      await adminApi.configSet(row.key, row.prev_value);
      toast(`${row.label || row.key} is back to ${fmtValue(row.kind, row.prev_value)}.`, 'good');
      await applySaved([row.key]);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const saveAll = async () => {
    setSavingAll(true);
    try {
      const changes: Record<string, unknown> = {};
      dirtyKeys.forEach((k) => { changes[k] = drafts[k]; });
      const r = await adminApi.configSetMany(changes);
      toast(r.message, 'good');
      await applySaved(dirtyKeys);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setSavingAll(false); }
  };

  const needle = q.trim().toLowerCase();
  const matches = (r: ConfigRow) => !needle || r.key.toLowerCase().includes(needle) || r.label.toLowerCase().includes(needle)
    || r.description.toLowerCase().includes(needle);

  const item = (r: ConfigRow, hint?: string, card?: boolean) => (
    <ConfigItem key={r.key} row={r} draft={drafts[r.key]} setDraft={setDraft(r.key)} onSave={saveOne(r.key)}
      onRevert={revertOne(r)} tiers={tiers ?? []} hint={hint} card={card} />
  );

  return (
    <div className="adm-page">
      <PageHead title="Settings" sub="Every number in the game. Changes reach all players instantly." />
      {error && <LoadError error={error} onRetry={reload} />}
      {!rows && loading && <Skeleton rows={6} />}
      {rows && (
        <>
          <div className="adm-toolbar">
            <label className="adm-search">
              <span aria-hidden>🔎</span>
              <input type="search" placeholder={`Search ${rows.length} settings…`} value={q} onChange={(e) => setQ(e.target.value)} />
            </label>
          </div>
          {!needle && (
            <nav className="adm-catnav" aria-label="Categories">
              <button type="button" className={`adm-chip${cat === 'quick' ? ' is-on' : ''}`} onClick={() => setCat('quick')}>⭐ Most used</button>
              {categories.map(([c, list]) => (
                <button key={c} type="button" className={`adm-chip${cat === c ? ' is-on' : ''}`} onClick={() => setCat(c)}>
                  {CATEGORY_META[c]?.emoji ?? '⚙️'} {CATEGORY_META[c]?.title ?? c}
                  <span className="adm-chip__n">{list.length}</span>
                  {list.some((r) => dirtyKeys.includes(r.key)) && <span className="adm-dot" aria-label="unsaved" />}
                </button>
              ))}
            </nav>
          )}

          {needle ? (
            <section className="adm-card adm-cfglist">
              {rows.filter(matches).length === 0 && <p className="adm-empty">No setting matches “{q}”.</p>}
              {rows.filter(matches).map((r) => item(r))}
            </section>
          ) : cat === 'quick' ? (
            <section className="adm-quick">
              {QUICK.map((qk) => byKey.get(qk.key)).filter(Boolean).map((r) => item(r!, QUICK.find((x) => x.key === r!.key)!.hint, true))}
            </section>
          ) : (
            categories.filter(([c]) => c === cat).map(([c, list]) => (
              <section key={c} className="adm-card adm-cfglist">
                <div className="adm-cfglist__head">
                  <h2 className="adm-h2">{CATEGORY_META[c]?.emoji} {CATEGORY_META[c]?.title ?? c}</h2>
                  {CATEGORY_META[c] && <p className="adm-sub">{CATEGORY_META[c].blurb}</p>}
                </div>
                {list.map((r) => item(r))}
              </section>
            ))
          )}

          {dirtyKeys.length > 0 && (
            <div className="adm-savebar" role="status">
              <span><b>{dirtyKeys.length}</b> unsaved {dirtyKeys.length === 1 ? 'change' : 'changes'}</span>
              <Btn tone="quiet" onClick={() => setDrafts({})}>Discard</Btn>
              <Btn tone="primary" disabled={invalid || savingAll} onClick={saveAll}>{savingAll ? 'Saving…' : 'Save all'}</Btn>
            </div>
          )}
        </>
      )}
    </div>
  );
}
