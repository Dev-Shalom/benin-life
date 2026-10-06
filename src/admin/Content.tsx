// Content tables: homes, traits, dreams, careers, items, activities, places, origins, banned words.
// Reads with admin_table_rows, writes with admin_row_upsert (server whitelists columns + types).
import { useMemo, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { adminApi, type AdminTable, type Row } from './api';
import { Badge, Btn, DetailPane, JsonControl, LoadError, PageHead, Skeleton, Toggle } from './parts';
import { useLoad } from './util';

type FieldType = 'text' | 'long' | 'int' | 'money' | 'num' | 'bool' | 'json' | 'list' | 'intnull' | 'textnull';
interface Field { key: string; label: string; type: FieldType; help?: string }
interface TableDef {
  id: string; table: AdminTable; title: string; emoji: string; blurb: string; pk: string[]; insert: boolean;
  fields: Field[]; inline?: string[]; titleOf: (r: Row) => string; subOf?: (r: Row) => string; newRow?: Row;
}

const DEFS: TableDef[] = [
  {
    id: 'homes', table: 'start_homes', title: 'Homes', emoji: '🏠', blurb: 'Starting homes in the creator: rent and start cash per origin.',
    pk: ['id'], insert: true, inline: ['weekly_rent'],
    titleOf: (r) => `${r.emoji} ${r.name}`, subOf: (r) => `${r.district} · ${r.tag} · start ${Object.entries((r.start_cash as Row) ?? {}).map(([k, v]) => `${k} ${naira(v as number)}`).join(', ')}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'emoji', label: 'Emoji', type: 'text' },
      { key: 'weekly_rent', label: 'Weekly rent', type: 'money' },
      { key: 'start_cash', label: 'Start cash per origin', type: 'json', help: '{"lapo": 8000, "nepo": 80000}' },
      { key: 'allowed_origins', label: 'Only for origins', type: 'list', help: 'Comma-separated, empty = everyone (e.g. nepo)' },
      { key: 'locked_quip', label: 'Locked message', type: 'text' },
      { key: 'location_id', label: 'Map place id', type: 'text' }, { key: 'housing_id', label: 'Housing id (3D layout)', type: 'text' },
      { key: 'district', label: 'District', type: 'text' }, { key: 'tag', label: 'Tag', type: 'text' },
      { key: 'description', label: 'Description', type: 'long' }, { key: 'sort', label: 'Sort order', type: 'int' },
      { key: 'active', label: 'Active (shown in the creator)', type: 'bool' },
    ],
    newRow: { emoji: '🏠', weekly_rent: 0, start_cash: { lapo: 5000, nepo: 50000 }, allowed_origins: [], sort: 100, active: true, location_id: 'ekenwan_room', housing_id: 'face_me_ekenwan' },
  },
  {
    id: 'traits', table: 'traits', title: 'Traits', emoji: '✨', blurb: 'Personality traits. Effects tweak needs, pay and skills.',
    pk: ['id'], insert: true, titleOf: (r) => `${r.emoji} ${r.name}`, subOf: (r) => String(r.description),
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'emoji', label: 'Emoji', type: 'text' },
      { key: 'description', label: 'Description', type: 'long' },
      { key: 'effects', label: 'Effects', type: 'json', help: 'e.g. {"decay": {"hunger": 1.15}, "work_pay": 1.05}' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { emoji: '✨', effects: {}, sort: 100, active: true },
  },
  {
    id: 'dreams', table: 'dreams', title: 'Dreams', emoji: '🌟', blurb: 'Life goals players pick in the creator.',
    pk: ['id'], insert: true, titleOf: (r) => `${r.emoji} ${r.name}`, subOf: (r) => String(r.description),
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'emoji', label: 'Emoji', type: 'text' },
      { key: 'description', label: 'Description', type: 'long' },
      { key: 'goal', label: 'Goal', type: 'json', help: 'e.g. {"type": "net_worth", "amount": 5000000}' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { emoji: '🌟', goal: {}, sort: 100, active: true },
  },
  {
    id: 'items', table: 'items', title: 'Items', emoji: '🛍️', blurb: 'Shop items: price, where they are sold and what they do.',
    pk: ['id'], insert: true, inline: ['price'],
    titleOf: (r) => `${r.icon ? `${r.icon} ` : ''}${r.name}`, subOf: (r) => `${r.category} · sold at ${(r.sold_at as string[]).length} places${r.sellable ? ` · resale ${r.resale_pct}%` : ''}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'category', label: 'Category', type: 'text' },
      { key: 'price', label: 'Price', type: 'money' },
      { key: 'sold_at', label: 'Sold at (place ids)', type: 'list', help: 'Comma-separated place ids; empty = not for sale' },
      { key: 'effects', label: 'Effects', type: 'json', help: 'Need changes when used, e.g. {"hunger": 20, "fun": 3}' },
      { key: 'sellable', label: 'Can be sold back', type: 'bool' }, { key: 'resale_pct', label: 'Resale %', type: 'num' },
      { key: 'description', label: 'Description', type: 'long' }, { key: 'icon', label: 'Icon (emoji)', type: 'textnull' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { category: 'food', price: 500, sold_at: [], effects: {}, sellable: false, resale_pct: 0, sort: 100 },
  },
  {
    id: 'activities', table: 'activities', title: 'Activities', emoji: '🎯', blurb: 'Things to do at places: cost, real seconds and effects.',
    pk: ['id'], insert: false, inline: ['cost', 'max_seconds'],
    titleOf: (r) => String(r.name), subOf: (r) => `${(r.scenes as string[]).join(', ')}${r.home_only ? ' · home only' : ''}${r.night_only ? ' · night only' : ''}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'cost', label: 'Cost', type: 'money' },
      { key: 'max_seconds', label: 'Longest (real seconds)', type: 'num', help: 'When the need it fills is empty (sleep at 0 energy)' },
      { key: 'min_seconds', label: 'Shortest (real seconds)', type: 'num', help: 'When the need is nearly full' },
      { key: 'scale_by_need', label: 'Shorter when the need is fuller', type: 'bool' },
      { key: 'game_minutes', label: 'Duration (game minutes, old timing only)', type: 'int' },
      { key: 'effects', label: 'Effects', type: 'json', help: 'e.g. {"energy": 90, "stress": -10}' },
      { key: 'scenes', label: 'Scenes', type: 'list' }, { key: 'home_only', label: 'Home only', type: 'bool' },
      { key: 'night_only', label: 'Night only', type: 'bool' }, { key: 'sort', label: 'Sort order', type: 'int' },
    ],
  },
  {
    id: 'places', table: 'locations', title: 'Places', emoji: '📍', blurb: 'Map places: robbery risk, CCTV, keke, traffic and actions.',
    pk: ['id'], insert: false, inline: ['risk'],
    titleOf: (r) => String(r.name), subOf: (r) => `${r.district} · night ×${r.night_risk_mult}${r.cctv ? ' · CCTV' : ''}${r.keke_ok ? ' · keke' : ''}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' },
      { key: 'risk', label: 'Robbery risk (0–1)', type: 'num', help: 'Multiplies the street robbery chance here' },
      { key: 'night_risk_mult', label: 'Night risk ×', type: 'num' }, { key: 'cctv', label: 'CCTV', type: 'bool' },
      { key: 'keke_ok', label: 'Keke allowed', type: 'bool' }, { key: 'congestion', label: 'Traffic congestion ×', type: 'num' },
      { key: 'remote_km', label: 'Extra km (outskirts)', type: 'num' },
      { key: 'actions', label: 'Actions', type: 'list', help: 'e.g. shop, bank, pos, chat' },
      { key: 'blurb', label: 'Blurb', type: 'long' }, { key: 'sort', label: 'Sort order', type: 'int' },
    ],
  },
  {
    id: 'origins', table: 'origin_tiers', title: 'Origins', emoji: '👶', blurb: 'LAPO / Nepo copy and perks. Chances and start money live in Settings → Origin.',
    pk: ['id'], insert: false, titleOf: (r) => String(r.name), subOf: (r) => String(r.tagline),
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'tagline', label: 'Tagline', type: 'long' },
      { key: 'welcome', label: 'Welcome message', type: 'long', help: 'Placeholders: {name} {home} {cash} {bank}' },
      { key: 'perks', label: 'Perks', type: 'json' }, { key: 'sort', label: 'Sort order', type: 'int' },
    ],
  },
  {
    id: 'words', table: 'chat_banned_words', title: 'Banned words', emoji: '🤐', blurb: 'Chat profanity filter. Lowercase letters, digits and spaces.',
    pk: ['word'], insert: true, titleOf: (r) => String(r.word),
    fields: [{ key: 'active', label: 'Active', type: 'bool' }],
    newRow: { active: true },
  },
];

const SHORT: Record<string, string> = {
  price: 'Price', weekly_rent: 'Rent / week', cost: 'Cost', game_minutes: 'Minutes', max_seconds: 'Max sec', risk: 'Risk 0–1',
  pay_per_shift: 'Pay', shift_game_minutes: 'Minutes', xp_per_shift: 'XP', xp_to_next: 'XP to next',
};
const rowKey = (def: TableDef, r: Row) => def.pk.map((k) => String(r[k])).join('|');
const fmtField = (f: Field, v: unknown): string => (v === null || v === undefined ? '' : f.type === 'list' ? (v as string[]).join(', ') : f.type === 'json' ? JSON.stringify(v, null, 2) : String(v));

/** Convert a form string into the value we send; returns [value, error]. */
function parseField(f: Field, raw: unknown): [unknown, string | null] {
  switch (f.type) {
    case 'bool': return [raw === true, null];
    case 'text': case 'long': return [String(raw ?? ''), null];
    case 'textnull': return [String(raw ?? '').trim() === '' ? null : String(raw), null];
    case 'list': return [String(raw ?? '').split(',').map((s) => s.trim()).filter(Boolean), null];
    case 'json':
      try {
        const p = JSON.parse(String(raw));
        if (p === null || typeof p !== 'object' || Array.isArray(p)) return [null, 'Must be a JSON object { … }'];
        return [p, null];
      } catch { return [null, 'Invalid JSON']; }
    default: {
      const s = String(raw ?? '').trim();
      if (s === '' && f.type === 'intnull') return [null, null];
      const n = Number(s);
      if (s === '' || !Number.isFinite(n)) return [null, 'Enter a number'];
      if (f.type !== 'num' && !Number.isInteger(n)) return [null, 'Whole number'];
      if (n < 0 && f.key !== 'sort') return [null, 'Can’t be negative'];
      return [n, null];
    }
  }
}

function FieldInput({ f, value, onChange }: { f: Field; value: unknown; onChange: (v: unknown) => void }) {
  if (f.type === 'bool') return <Toggle checked={value === true} onChange={onChange} label={f.label} />;
  if (f.type === 'json') return <JsonControl rows={5} value={String(value ?? '')} onChange={(t) => onChange(t)} />;
  if (f.type === 'long') return <textarea className="adm-input" rows={3} value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />;
  const numeric = ['int', 'money', 'num', 'intnull'].includes(f.type);
  return (
    <label className="adm-numbox adm-numbox--wide">
      {f.type === 'money' && <span className="adm-numbox__affix">₦</span>}
      <input type={numeric ? 'number' : 'text'} inputMode={numeric ? 'decimal' : undefined} step="any"
        value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}

/** Edit / create one row in the side pane. */
function RowForm({ def, row, isNew, onSaved, onClose }: {
  def: TableDef; row: Row; isNew: boolean; onSaved: (r: Row) => void; onClose: () => void;
}) {
  const initial = useMemo(() => {
    const o: Record<string, unknown> = {};
    def.fields.forEach((f) => { o[f.key] = f.type === 'bool' ? row[f.key] === true : fmtField(f, row[f.key]); });
    def.pk.forEach((k) => { o[k] = row[k] ?? ''; });
    return o;
  }, [def, row]);
  const [form, setForm] = useState(initial);
  const [busy, setBusy] = useState(false);
  const errors: Record<string, string> = {};
  const payload: Row = {};
  def.pk.forEach((k) => {
    const v = form[k];
    payload[k] = k === 'level' ? Number(v) : String(v ?? '').trim();
    if (String(v ?? '').trim() === '') errors[k] = 'Required';
  });
  def.fields.forEach((f) => {
    if (!isNew && form[f.key] === initial[f.key]) return;
    const [v, err] = parseField(f, form[f.key]);
    if (err) errors[f.key] = err; else payload[f.key] = v;
  });
  const changed = Object.keys(payload).length > def.pk.length;
  const save = async () => {
    setBusy(true);
    try {
      const r = await adminApi.rowUpsert(def.table, payload);
      toast(`${r.message} ${def.titleOf(r.row)}`, 'good');
      onSaved(r.row);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <DetailPane open title={isNew ? `New ${def.title.replace(/s$/, '').toLowerCase()}` : def.titleOf(row)} onClose={onClose}
      footer={<><Btn tone="quiet" onClick={onClose}>Cancel</Btn>
        <Btn tone="primary" disabled={busy || !changed || Object.keys(errors).length > 0} onClick={save}>{busy ? 'Saving…' : isNew ? 'Add' : 'Save'}</Btn></>}>
      <div className="adm-form">
        {def.pk.map((k) => (
          <label key={k} className="adm-field">
            <span className="adm-field__label">{k === 'id' || k === 'word' ? (k === 'word' ? 'Word' : 'Id (lowercase, no spaces)') : k}</span>
            {isNew ? <input className="adm-input" value={String(form[k] ?? '')} onChange={(e) => setForm({ ...form, [k]: e.target.value })} />
              : <code className="adm-cfg__key">{String(row[k])}</code>}
          </label>
        ))}
        {def.fields.map((f) => (
          <div key={f.key} className={`adm-field${f.type === 'bool' ? ' adm-field--row' : ''}${!isNew && form[f.key] !== initial[f.key] ? ' is-dirty' : ''}`}>
            <span className="adm-field__label">{f.label}</span>
            <FieldInput f={f} value={form[f.key]} onChange={(v) => setForm({ ...form, [f.key]: v })} />
            {f.help && <span className="adm-field__help">{f.help}</span>}
            {errors[f.key] && f.type !== 'json' && <span className="adm-field__err">{errors[f.key]}</span>}
          </div>
        ))}
      </div>
    </DetailPane>
  );
}

function TableEditor({ def, rows, setRows, filter, extraNew }: {
  def: TableDef; rows: Row[]; setRows: (r: Row[]) => void; filter?: (r: Row) => boolean; extraNew?: Row;
}) {
  const [open, setOpen] = useState<{ row: Row; isNew: boolean } | null>(null);
  const [inline, setInline] = useState<Record<string, Record<string, string>>>({});
  const [q, setQ] = useState('');
  const fieldsByKey = new Map(def.fields.map((f) => [f.key, f]));
  const needle = q.trim().toLowerCase();
  const shown = rows.filter((r) => (!filter || filter(r))
    && (!needle || JSON.stringify(r).toLowerCase().includes(needle)));

  const merge = (saved: Row) => {
    const k = rowKey(def, saved);
    const exists = rows.some((r) => rowKey(def, r) === k);
    setRows(exists ? rows.map((r) => (rowKey(def, r) === k ? saved : r)) : [...rows, saved]);
  };
  const saveInline = async (r: Row) => {
    const k = rowKey(def, r);
    const payload: Row = {};
    def.pk.forEach((p) => { payload[p] = r[p]; });
    for (const [field, raw] of Object.entries(inline[k] ?? {})) {
      const [v, err] = parseField(fieldsByKey.get(field)!, raw);
      if (err) { toast(`${fieldsByKey.get(field)!.label}: ${err}`, 'bad'); return; }
      payload[field] = v;
    }
    try {
      const res = await adminApi.rowUpsert(def.table, payload);
      toast(`${res.message} ${def.titleOf(res.row)}`, 'good');
      merge(res.row);
      setInline((s) => { const n = { ...s }; delete n[k]; return n; });
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  return (
    <div className={`adm-split${open ? ' has-detail' : ''}`}>
      <div className="adm-split__main">
        <div className="adm-toolbar">
          <label className="adm-search">
            <span aria-hidden>🔎</span>
            <input type="search" placeholder={`Search ${def.title.toLowerCase()}…`} value={q} onChange={(e) => setQ(e.target.value)} />
          </label>
          {def.insert && <Btn tone="primary" icon="plus" onClick={() => setOpen({ row: { ...(def.newRow ?? {}), ...(extraNew ?? {}) }, isNew: true })}>Add</Btn>}
        </div>
        <div className="adm-card adm-rows">
          {shown.length === 0 && <p className="adm-empty">Nothing here.</p>}
          {shown.map((r) => {
            const k = rowKey(def, r);
            const edits = inline[k];
            const selected = open && !open.isNew && rowKey(def, open.row) === k;
            return (
              <div key={k} className={`adm-row${selected ? ' is-selected' : ''}${r.active === false ? ' is-off' : ''}`}>
                <button type="button" className="adm-row__main" onClick={() => setOpen({ row: r, isNew: false })}>
                  <span className="adm-row__title">{def.titleOf(r)} {r.active === false && <Badge>Off</Badge>}</span>
                  {def.subOf && <span className="adm-row__sub">{def.subOf(r)}</span>}
                </button>
                {def.inline && (
                  <div className="adm-row__inline">
                    {def.inline.map((field) => {
                      const f = fieldsByKey.get(field)!;
                      const val = edits?.[field] ?? String(r[field] ?? '');
                      return (
                        <label key={field} className="adm-inline" title={f.label}>
                          <span className="adm-inline__cap">{SHORT[field] ?? f.label}</span>
                          <span className={`adm-numbox adm-numbox--sm${f.type === 'money' ? ' adm-numbox--money' : ''}${edits?.[field] !== undefined ? ' is-dirty' : ''}`}>
                          {f.type === 'money' && <span className="adm-numbox__affix">₦</span>}
                          <input type="number" inputMode="decimal" step="any" aria-label={`${f.label} for ${def.titleOf(r)}`} value={val}
                            onChange={(e) => setInline((s) => {
                              const cur = { ...(s[k] ?? {}) };
                              if (e.target.value === String(r[field] ?? '')) delete cur[field]; else cur[field] = e.target.value;
                              const n = { ...s, [k]: cur };
                              if (Object.keys(cur).length === 0) delete n[k];
                              return n;
                            })} />
                          </span>
                        </label>
                      );
                    })}
                    {edits && <Btn small tone="primary" onClick={() => saveInline(r)}>Save</Btn>}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
      {open && (
        <RowForm key={open.isNew ? 'new' : rowKey(def, open.row)} def={def} row={open.row} isNew={open.isNew}
          onClose={() => setOpen(null)} onSaved={(saved) => { merge(saved); setOpen({ row: saved, isNew: false }); }} />
      )}
    </div>
  );
}

function GenericSection({ def }: { def: TableDef }) {
  const { data, setData, error, loading, reload } = useLoad(() => adminApi.tableRows(def.table), [def.table]);
  if (error) return <LoadError error={error} onRetry={reload} />;
  if (!data || loading && !data) return <Skeleton rows={6} />;
  return <TableEditor def={def} rows={data} setRows={setData} />;
}

const TRACK_DEF: TableDef = {
  id: 'tracks', table: 'career_tracks', title: 'Career tracks', emoji: '💼', blurb: '', pk: ['id'], insert: false,
  titleOf: (r) => `${r.emoji} ${r.name}`,
  fields: [
    { key: 'name', label: 'Name', type: 'text' }, { key: 'emoji', label: 'Emoji', type: 'text' },
    { key: 'description', label: 'Description', type: 'long' },
    { key: 'location_ids', label: 'Work places (place ids)', type: 'list' }, { key: 'skill', label: 'Skill', type: 'textnull' },
    { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active (hiring)', type: 'bool' },
  ],
};
const LEVEL_DEF: TableDef = {
  id: 'levels', table: 'career_levels', title: 'Levels', emoji: '📈', blurb: '', pk: ['track_id', 'level'], insert: true,
  inline: ['pay_per_shift', 'shift_game_minutes', 'xp_per_shift', 'xp_to_next'],
  titleOf: (r) => `L${r.level} · ${r.title}`,
  subOf: (r) => `${naira(r.pay_per_shift as number)} / shift · ${r.shift_game_minutes} min · ${r.xp_per_shift} XP${r.xp_to_next ? ` · ${r.xp_to_next} XP to next` : ' · top level'}`,
  fields: [
    { key: 'title', label: 'Title', type: 'text' }, { key: 'pay_per_shift', label: 'Pay per shift', type: 'money' },
    { key: 'shift_game_minutes', label: 'Shift length (game minutes, old timing only)', type: 'int', help: 'Short timing uses Settings → Action timing → Work shift seconds' },
    { key: 'xp_per_shift', label: 'XP per shift', type: 'int' },
    { key: 'xp_to_next', label: 'XP to next level (empty = top)', type: 'intnull' },
    { key: 'energy_cost', label: 'Energy cost', type: 'int' },
    { key: 'requirements', label: 'Requirements', type: 'json', help: 'e.g. {"item": "laptop", "min_shifts_in_level": 3, "degree": true}' },
    { key: 'effects', label: 'Need effects per shift', type: 'json' }, { key: 'perks', label: 'Perks', type: 'json' },
  ],
};

function CareersSection() {
  const tracks = useLoad(() => adminApi.tableRows('career_tracks'));
  const levels = useLoad(() => adminApi.tableRows('career_levels'));
  const [track, setTrack] = useState<string | null>(null);
  const [editTrack, setEditTrack] = useState(false);
  if (tracks.error || levels.error) return <LoadError error={(tracks.error || levels.error)!} onRetry={() => { void tracks.reload(); void levels.reload(); }} />;
  if (!tracks.data || !levels.data) return <Skeleton rows={6} />;
  const cur = track ?? String(tracks.data[0]?.id ?? '');
  const t = tracks.data.find((x) => x.id === cur);
  const lv = levels.data.filter((l) => l.track_id === cur);
  const last = lv[lv.length - 1];
  return (
    <div>
      <div className="adm-chips adm-chips--scroll">
        {tracks.data.map((x) => (
          <button key={String(x.id)} type="button" className={`adm-chip${x.id === cur ? ' is-on' : ''}`} onClick={() => { setTrack(String(x.id)); setEditTrack(false); }}>
            {String(x.emoji)} {String(x.name)} {x.active === false && <Badge>Off</Badge>}
          </button>
        ))}
      </div>
      {t && (
        <div className="adm-card adm-trackhead">
          <div>
            <div className="adm-row__title">{String(t.emoji)} {String(t.name)}</div>
            <div className="adm-row__sub">{String(t.description)}</div>
          </div>
          <Btn small onClick={() => setEditTrack(true)}>Edit track</Btn>
        </div>
      )}
      <p className="adm-sub adm-inline-hint">Edit pay, shift length and XP right in the list. Tap a level for its requirements.</p>
      <TableEditor def={LEVEL_DEF} rows={levels.data} setRows={levels.setData} filter={(r) => r.track_id === cur}
        extraNew={last ? { ...last, track_id: cur, level: Number(last.level) + 1, title: '' } : { track_id: cur, level: 1 }} />
      {editTrack && t && (
        <RowForm def={TRACK_DEF} row={t} isNew={false} onClose={() => setEditTrack(false)}
          onSaved={(saved) => { tracks.setData(tracks.data!.map((x) => (x.id === saved.id ? saved : x))); setEditTrack(false); }} />
      )}
    </div>
  );
}

const SECTIONS = [
  ...DEFS.slice(0, 3).map((d) => ({ id: d.id, title: d.title, emoji: d.emoji, blurb: d.blurb })),
  { id: 'careers', title: 'Careers', emoji: '💼', blurb: 'Tracks and their level ladders: titles, pay, shift length, XP and requirements.' },
  ...DEFS.slice(3).map((d) => ({ id: d.id, title: d.title, emoji: d.emoji, blurb: d.blurb })),
];

export default function Content() {
  const [sec, setSec] = useState('homes');
  const meta = SECTIONS.find((s) => s.id === sec)!;
  const def = DEFS.find((d) => d.id === sec);
  return (
    <div className="adm-page">
      <PageHead title="Content" sub={meta.blurb} />
      <nav className="adm-catnav" aria-label="Tables">
        {SECTIONS.map((s) => (
          <button key={s.id} type="button" className={`adm-chip${sec === s.id ? ' is-on' : ''}`} onClick={() => setSec(s.id)}>{s.emoji} {s.title}</button>
        ))}
      </nav>
      {sec === 'careers' ? <CareersSection /> : def && <GenericSection key={def.id} def={def} />}
    </div>
  );
}
