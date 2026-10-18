// Content tables: homes, furniture, starter furniture, traits, dreams, careers, items, activities, places,
// place zones / zone actions / mood lines (L2 interiors, docs/PLACES.md), origins, banned words.
// Reads with admin_table_rows, writes with admin_row_upsert (server whitelists columns + types).
import { useMemo, useState } from 'react';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { adminApi, type AdminTable, type Row } from './api';
import { Badge, Btn, DetailPane, JsonControl, LoadError, PageHead, Skeleton, Toggle } from './parts';
import { useLoad } from './util';
import { musicApi } from './musicApi';
import { PlaylistSelect } from './Music';

type FieldType = 'text' | 'long' | 'int' | 'money' | 'num' | 'bool' | 'json' | 'list' | 'intnull' | 'numnull' | 'textnull' | 'time';
interface Field { key: string; label: string; type: FieldType; help?: string }
interface TableDef {
  id: string; table: AdminTable; title: string; emoji: string; blurb: string; pk: string[]; insert: boolean;
  fields: Field[]; inline?: string[]; titleOf: (r: Row) => string; subOf?: (r: Row) => string; newRow?: Row;
  /** A bool column shown as an on/off switch on every row (saves at once). */
  toggle?: { key: string; label: string };
  /** Cross-field checks on the parsed values; returns { fieldKey: message }. */
  validate?: (get: (key: string) => unknown) => Record<string, string>;
}

/** Hours (numeric, 21.5) <-> "21:30" for <input type="time">. */
const hourToTime = (v: unknown): string => {
  if (v === null || v === undefined || v === '') return '';
  const n = Number(v);
  const h = Math.floor(n) % 24;
  const m = Math.round((n - Math.floor(n)) * 60);
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};
const hourLabel = (v: unknown): string => {
  const n = Number(v);
  const h = Math.floor(n) % 24;
  const m = Math.round((n - Math.floor(n)) * 60);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
};
const hoursText = (r: Row) => (r.open_hour === null || r.open_hour === undefined ? 'always open' : `${hourLabel(r.open_hour)} – ${hourLabel(r.close_hour)}`);

/** A timestamptz shown in Benin time ("6 Oct 2026, 20:46"). */
const watTime = (v: unknown): string => {
  const ms = Date.parse(String(v ?? ''));
  return Number.isNaN(ms) ? '?' : new Date(ms).toLocaleString('en-GB', { timeZone: 'Africa/Lagos', dateStyle: 'medium', timeStyle: 'short' });
};

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
    id: 'furniture', table: 'furniture', title: 'Furniture', emoji: '🛋️', blurb: 'Home furniture pieces: 3D look, where they stand and the home activities they host.',
    pk: ['id'], insert: true, inline: ['rest_pct'],
    titleOf: (r) => `${r.emoji} ${r.name}`, subOf: (r) => `${r.kind} · slot ${r.slot}${(r.activities as string[]).length ? ` · ${(r.activities as string[]).join(', ')}` : ''}${r.rest_pct !== 100 ? ` · rest ${r.rest_pct}%` : ''}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'emoji', label: 'Emoji', type: 'text' },
      { key: 'activities', label: 'Activities it hosts', type: 'list', help: 'Home activity ids, e.g. sleep, nap, bathe, cook_home, watch_tv, relax_sofa, cold_drink, sit_rest' },
      { key: 'rest_pct', label: 'Rest % (sleep energy)', type: 'int', help: '100 = a proper bed; the foam mat is 90' },
      { key: 'kind', label: '3D kind', type: 'text', help: 'e.g. mattress, bed_double, bed_single, sofa, tv, fridge, gas_cooker, kerosene_stove, stool, drum_bucket, wardrobe, rug, centre_table' },
      { key: 'slot', label: 'Default slot', type: 'text', help: 'bed, seat, sofa, tv, stove, fridge, bath, wardrobe, rug, ctable' },
      { key: 'color', label: 'Colour (#hex)', type: 'textnull' },
      { key: 'description', label: 'Description', type: 'long' }, { key: 'sort', label: 'Sort order', type: 'int' },
      { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { emoji: '🪑', kind: 'stool', slot: 'seat', activities: [], rest_pct: 100, description: '', sort: 200, active: true },
  },
  {
    id: 'starter_furniture', table: 'starter_furniture', title: 'Starter furniture', emoji: '📦', blurb: 'What each origin starts with at home. A row for one home replaces the all-homes row in the same slot. Given when a home is chosen.',
    pk: ['id'], insert: true,
    titleOf: (r) => `${String(r.origin).toUpperCase()} · ${r.furniture_id}`, subOf: (r) => `${r.start_home ?? 'every home'}${r.slot ? ` · slot ${r.slot}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'origin', label: 'Origin', type: 'text', help: 'lapo or nepo' },
      { key: 'furniture_id', label: 'Furniture id', type: 'text' },
      { key: 'start_home', label: 'Only for home (start home id)', type: 'textnull', help: 'Empty = every home, e.g. uniben_hostel' },
      { key: 'slot', label: 'Slot', type: 'textnull', help: "Empty = the piece's default slot" },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { origin: 'lapo', furniture_id: 'stool', start_home: null, slot: null, sort: 100, active: true },
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
      { key: 'needs_furniture', label: 'Needs furniture (home)', type: 'bool', help: 'Offered at home only when the player owns a piece that lists it (Furniture → Activities)' },
      { key: 'night_only', label: 'Night only', type: 'bool' }, { key: 'sort', label: 'Sort order', type: 'int' },
      { key: 'icon', label: 'Icon (emoji, action cards)', type: 'textnull' },
      { key: 'location_ids', label: 'Only at these places (ids)', type: 'list', help: 'Empty = every place of its scenes, e.g. mama_ebo' },
      { key: 'risky', label: 'Risky (street robbery roll here)', type: 'bool' },
      { key: 'requires_event', label: 'Needs event (kind or event id)', type: 'textnull', help: 'L4: the card only shows on a day that event is on here, and opens while it is LIVE with a ticket (or free). e.g. match, club_night, market_day' },
      { key: 'rush', label: 'Rush hour sell-out', type: 'json', help: '{} = never. {"from": 12, "to": 15, "pct": 40, "line": "Pepper rice don finish!"}' },
    ],
  },
  {
    id: 'places', table: 'locations', title: 'Places', emoji: '📍', blurb: 'Map places: robbery risk, CCTV, keke, traffic and actions.',
    pk: ['id'], insert: false, inline: ['risk'],
    titleOf: (r) => String(r.name),
    subOf: (r) => `${r.scene} · ${r.district} · ${hoursText(r)}${r.active === false ? ' · hidden from players' : ''}`,
    toggle: { key: 'active', label: 'Open to players' },
    validate: (get) => {
      const o = get('open_hour'), c = get('close_hour');
      if ((o === null) !== (c === null)) return { [o === null ? 'open_hour' : 'close_hour']: 'Set both times, or clear both for always open' };
      if (o !== null && o === c) return { close_hour: 'Closing time must differ from opening time (clear both for always open)' };
      return {};
    },
    fields: [
      { key: 'active', label: 'Active (open to players)', type: 'bool', help: 'Off = hidden: no map pin, not in Ride, nobody can travel there or act there. Players already inside can still leave.' },
      { key: 'open_hour', label: 'Opens at', type: 'time', help: 'Benin time. Clear both times = always open. Clubs: 21:00' },
      { key: 'close_hour', label: 'Closes at', type: 'time', help: 'Can be after midnight: 05:00 = 5 AM next morning' },
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
    id: 'zones', table: 'place_zones', title: 'Place zones', emoji: '🧭', blurb: 'Spots inside each place (by place type, or one place). Position in metres: x right, z towards the camera. A place zone with the same key replaces the type\'s zone; switch it off to hide it.',
    pk: ['id'], insert: true, inline: ['x', 'z'],
    titleOf: (r) => `${r.icon} ${r.label}`, subOf: (r) => `${r.scene ?? `place ${r.location_id}`} · ${r.zone_key} · ${r.prop} at ${r.x},${r.z}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'label', label: 'Label', type: 'text' }, { key: 'icon', label: 'Icon (emoji)', type: 'text' },
      { key: 'scene', label: 'Place type (scene)', type: 'textnull', help: 'e.g. club, market, hotel — or leave empty and set a place id' },
      { key: 'location_id', label: 'Only this place (id)', type: 'textnull', help: 'e.g. mama_ebo' },
      { key: 'zone_key', label: 'Zone key', type: 'text' },
      { key: 'prop', label: '3D prop', type: 'text', help: 'stall, bar, dance_floor, dj_booth, vip, counter, tables, seats, shelves, aisles, cars, pool, stands, pitch, statue, restroom… (docs/PLACES.md)' },
      { key: 'x', label: 'x (m)', type: 'num' }, { key: 'z', label: 'z (m)', type: 'num' },
      { key: 'w', label: 'Width (m)', type: 'num' }, { key: 'd', label: 'Depth (m)', type: 'num' },
      { key: 'rot', label: 'Facing (0 camera, 1 right, 2 back, 3 left)', type: 'int' },
      { key: 'note', label: 'Note strip under the cards', type: 'textnull' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { scene: 'club', location_id: null, zone_key: 'new_zone', label: 'New zone', icon: '📍', prop: 'tables', x: 5, z: 5, w: 2, d: 2, rot: 0, note: null, sort: 50, active: true },
  },
  {
    id: 'zone_actions', table: 'zone_actions', title: 'Zone actions', emoji: '🃏', blurb: 'The action cards in each zone: an activity, a job track, a shop item, or a place tab (shop, jobs, bank, pos).',
    pk: ['id'], insert: true,
    titleOf: (r) => `${r.zone_id} → ${r.kind}: ${r.ref}`, subOf: (r) => `${r.label ? `"${r.label}" · ` : ''}sort ${r.sort}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'zone_id', label: 'Zone id', type: 'text', help: 'e.g. club.bar' },
      { key: 'kind', label: 'Kind', type: 'text', help: 'activity | job | shop | panel' },
      { key: 'ref', label: 'Reference', type: 'text', help: 'activity id, career track id, item id, or tab (shop, jobs, bank, pos)' },
      { key: 'label', label: 'Card title (optional)', type: 'textnull' }, { key: 'icon', label: 'Icon (optional)', type: 'textnull' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { zone_id: 'club.bar', kind: 'activity', ref: 'lounge_chill', label: null, icon: null, sort: 50, active: true },
  },
  {
    id: 'moods', table: 'place_moods', title: 'Mood lines', emoji: '💬', blurb: 'The rotating line on the place card, per place type or place and part of the day.',
    pk: ['id'], insert: true,
    titleOf: (r) => `${r.icon} ${r.line}`, subOf: (r) => `${r.scene ?? `place ${r.location_id}`} · ${r.part}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'line', label: 'Line', type: 'text' }, { key: 'icon', label: 'Icon (emoji)', type: 'text' },
      { key: 'scene', label: 'Place type (scene)', type: 'textnull' }, { key: 'location_id', label: 'Only this place (id)', type: 'textnull' },
      { key: 'part', label: 'Part of day', type: 'text', help: 'any | morning | afternoon | evening | night' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { scene: 'club', location_id: null, part: 'night', icon: '✨', line: 'The DJ is warming up', sort: 50, active: true },
  },
  {
    id: 'npcs', table: 'npc_roster', title: 'People (NPCs)', emoji: '🧍🏾', blurb: 'Named background people inside places (L3). Who is there is picked per place and hour from this list, the same for every player; how many comes from Crowd profiles.',
    pk: ['id'], insert: true,
    titleOf: (r) => `${r.name} · ${r.role}`, subOf: (r) => `${(r.location_ids as string[])?.length ? `at ${(r.location_ids as string[]).join(', ')}` : (r.scenes as string[])?.join(', ')} · ${r.motion}${r.headliner ? ' · headliner' : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text', help: 'Shown on the white pill, e.g. Osaro, MC Lightning' },
      { key: 'role', label: 'Role', type: 'text', help: 'e.g. Trader, Keke rider, Hype man, Bouncer' },
      { key: 'motion', label: 'What they do', type: 'text', help: 'idle | dance | hype | dj | trade | serve | guard | sit | cheer | work | phone' },
      { key: 'lines', label: 'Lines (English)', type: 'long', help: 'One line per row. Shown as a speech bubble when tapped, and now and then.' },
      { key: 'pidgin', label: 'Pidgin lines', type: 'long', help: 'One per row. Only used at markets, streets, motor parks and PoS stands.' },
      { key: 'scenes', label: 'Place types', type: 'list', help: 'e.g. market, club, campus (used when no place ids are set)' },
      { key: 'location_ids', label: 'Only these places (ids)', type: 'list', help: 'e.g. club_360. Wins over place types.' },
      { key: 'zone_key', label: 'Stands at zone', type: 'textnull', help: 'e.g. dj, dance, bar, counter, foodstuff (empty = anywhere)' },
      { key: 'headliner', label: 'Headliner (always there while open)', type: 'bool' },
      { key: 'avatar', label: 'Look', type: 'json', help: '{"v":2,"gender":"male","skin":"tone4","hair":"low_cut","preset":"keke","top":{"c":"#d2342a"}}. Presets: bini, agbada, senator, owambe, boubou, yahoo, glam, corporate, student, market, keke, nurse, police, street, ankara' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { name: 'Osaro', role: 'Trader', motion: 'trade', lines: 'Come and buy!', pidgin: '', scenes: ['market'], location_ids: [], zone_key: null, headliner: false, avatar: { v: 2, gender: 'male', skin: 'tone4', hair: 'low_cut', preset: 'ankara' }, sort: 500, active: true },
  },
  {
    id: 'crowds', table: 'crowd_profiles', title: 'Crowd profiles', emoji: '👥', blurb: 'How many people are at each place type by hour and day. The most specific row wins (weekday / weekend before all, then the shortest band). Hours are Benin time, from is inclusive, to is exclusive (0–24).',
    pk: ['id'], insert: true, inline: ['npcs'],
    titleOf: (r) => `${r.scene} · ${r.days} · ${r.from_hour}:00–${r.to_hour}:00`, subOf: (r) => `${r.npcs} people${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'scene', label: 'Place type', type: 'text', help: 'e.g. market, club, campus, street' },
      { key: 'days', label: 'Days', type: 'text', help: 'all | weekday | weekend' },
      { key: 'from_hour', label: 'From hour (0–23)', type: 'int' }, { key: 'to_hour', label: 'To hour (1–24)', type: 'int' },
      { key: 'npcs', label: 'People', type: 'int' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { scene: 'market', days: 'all', from_hour: 7, to_hour: 12, npcs: 40, sort: 0, active: true },
  },
  {
    id: 'hype', table: 'hype_templates', title: 'Hype lines', emoji: '🎤', blurb: 'What the club hype man (MC Lightning) says when a player spends big (P2/P3: the full-screen takeover). One line is picked at random per kind, and a place never hears the same line again until it has heard them all. vip_arrival = the calm "VIP has arrived" line (any place). Placeholders: {name} {place} {count} {bottles} {amount} {rank}. SP1 custom spray: spray_<tier> pools by amount (Settings → club.spray_tier_*), spray_vip for VIP sprays; they also take {short} (₦2 TRILLION). SP2 pick the money: pick = a player started picking ({user}), pick_top = the top picker of a drop ({user} {amount}). The ticker line is the app-wide strip for spends at or above Settings → hype.global_min (keep it short, under 60 characters).',
    pk: ['id'], insert: true,
    titleOf: (r) => String(r.line), subOf: (r) => `${r.kind}${r.ticker ? ` · ticker: ${r.ticker}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'kind', label: 'Kind', type: 'text', help: 'vip | bottles | spray | shoutout | shutdown | vip_arrival | spray_small | spray_nice | spray_big | spray_huge | spray_oga | spray_billionaire | spray_trillionaire | spray_vip | pick | pick_top' },
      { key: 'line', label: 'Club line (banner, bubble, chat)', type: 'long', help: 'e.g. Make una hail @{name}! E don pop {bottles} — {place} na una own tonight!' },
      { key: 'ticker', label: 'App-wide ticker line', type: 'text', help: 'e.g. 🔥 @{name} is shutting down {place}' },
      { key: 'sort', label: 'Sort order', type: 'int' }, { key: 'active', label: 'Active', type: 'bool' },
    ],
    newRow: { kind: 'vip', line: 'Make una hail @{name}! {place}, shout!', ticker: '🔥 @{name} is balling at {place}', sort: 10, active: true },
  },
  {
    id: 'topup', table: 'topup_packs', title: 'Top-up packs', emoji: '💳', blurb: 'Real-money naira packs in the Wallet (PAY, docs/PAYMENTS.md). Price is in kobo (₦1 = 100 kobo, so ₦1,000 = 100000); Paystack charges exactly this and the server credits the game naira to the bank only after verifying it. Switch a pack off instead of deleting it. Top-ups only work when Settings → payments.enabled is on.',
    pk: ['id'], insert: true, inline: ['game_naira', 'price_kobo'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.label} · ${naira(Number(r.game_naira))}`,
    subOf: (r) => `₦${Math.round(Number(r.price_kobo) / 100).toLocaleString('en-NG')} real money${r.bonus_tag ? ` · ${r.bonus_tag}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'active', label: 'Active', type: 'bool' },
      { key: 'label', label: 'Name', type: 'text', help: 'e.g. Big boy pack' },
      { key: 'game_naira', label: 'Game naira given', type: 'money' },
      { key: 'price_kobo', label: 'Price in kobo (real money)', type: 'int', help: '100000 = ₦1,000. Minimum 10000 (₦100).' },
      { key: 'bonus_tag', label: 'Bonus tag', type: 'textnull', help: 'e.g. +30% bonus (empty = none)' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { label: 'New pack', game_naira: 100000, price_kobo: 100000, bonus_tag: null, sort: 60, active: false },
  },
  {
    id: 'billboards', table: 'billboards', title: 'Billboards', emoji: '📺', blurb: 'H3 digital billboards on the 3D map (docs/BILLBOARDS.md). Prices are real money in kobo (₦1 = 100 kobo, so ₦25,000 = 2500000) for 1, 3 and 7 days; busier boards cost more. x / y = map position (0–1000, King\'s Square is 500,500), yaw = small turn in radians (keep within ±0.3 so it faces the camera). kind: mega (biggest screen), standard or local. Ads to approve: Ads in the sidebar.',
    pk: ['id'], insert: true, inline: ['price_7d_kobo'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => String(r.name),
    subOf: (r) => `${String(r.kind)} · 1 day ₦${Math.round(Number(r.price_1d_kobo) / 100).toLocaleString('en-NG')} · 7 days ₦${Math.round(Number(r.price_7d_kobo) / 100).toLocaleString('en-NG')}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text', help: 'e.g. Ring Road mega screen' },
      { key: 'area', label: 'Where (subtitle)', type: 'text', help: 'e.g. King\'s Square · mega screen · digital' },
      { key: 'kind', label: 'Kind', type: 'text', help: 'mega, standard or local' },
      { key: 'price_1d_kobo', label: '1 day (kobo)', type: 'int', help: 'Minimum 10000 (₦100)' },
      { key: 'price_3d_kobo', label: '3 days (kobo)', type: 'int' },
      { key: 'price_7d_kobo', label: '7 days (kobo)', type: 'int' },
      { key: 'x', label: 'Map x', type: 'num' },
      { key: 'y', label: 'Map y', type: 'num' },
      { key: 'yaw', label: 'Turn (radians)', type: 'num' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New screen', area: '· digital', kind: 'standard', x: 500, y: 500, yaw: 0, price_1d_kobo: 1000000, price_3d_kobo: 2500000, price_7d_kobo: 5000000, sort: 200, active: false },
  },
  {
    id: 'events', table: 'place_events', title: 'Events', emoji: '🎟️', blurb: 'Events at places (L4, docs/EVENTS.md): match days, club nights, market days, owambe, premieres, pool parties. Weekly = every weekday 0 (Mon) … 6 (Sun) from start to end time, Benin time (an end before the start = past midnight). One-off = starts at … ends at, e.g. 2026-10-20 18:00+01. Events at hidden places never show. Ticket price 0 = free. Event-only action cards: Activities → "Needs event" (an event kind or id).',
    pk: ['id'], insert: true, inline: ['ticket_price'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.title}`,
    subOf: (r) => `${r.location_id} · ${r.kind} · ${r.recurrence === 'weekly' ? `${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][Number(r.weekday)] ?? '?'} ${hourLabel(r.start_time)} – ${hourLabel(r.end_time)}` : `${watTime(r.starts_at)} → ${watTime(r.ends_at)} WAT`} · ${Number(r.ticket_price) ? naira(Number(r.ticket_price)) : 'free'}${r.capacity != null ? ` · cap ${r.capacity}` : ''}${r.active ? '' : ' · off'}`,
    validate: (get) => {
      if (get('recurrence') === 'weekly') {
        const out: Record<string, string> = {};
        if (get('weekday') === null) out.weekday = 'Pick a weekday 0 (Mon) … 6 (Sun)';
        if (get('start_time') === null) out.start_time = 'Set a start time';
        if (get('end_time') === null) out.end_time = 'Set an end time';
        if (get('start_time') !== null && get('start_time') === get('end_time')) out.end_time = 'End must differ from start';
        return out;
      }
      if (get('recurrence') === 'none') {
        if (!get('starts_at')) return { starts_at: 'Set when it starts' };
        if (!get('ends_at')) return { ends_at: 'Set when it ends' };
      }
      return {};
    },
    fields: [
      { key: 'active', label: 'Active', type: 'bool' },
      { key: 'title', label: 'Title', type: 'text', help: '{variant} = a different line each week from Variants, e.g. Bendel Insurance vs {variant}' },
      { key: 'location_id', label: 'Place id', type: 'text', help: 'e.g. ogbemudia_stadium, club_360, oba_market' },
      { key: 'kind', label: 'Kind', type: 'text', help: 'match | concert | club_night | market_day | church | owambe | premiere | party | promo' },
      { key: 'icon', label: 'Icon (emoji)', type: 'text' },
      { key: 'recurrence', label: 'Repeats', type: 'text', help: 'weekly | none (one-off)' },
      { key: 'weekday', label: 'Weekday (weekly)', type: 'intnull', help: '0 Mon, 1 Tue, 2 Wed, 3 Thu, 4 Fri, 5 Sat, 6 Sun' },
      { key: 'start_time', label: 'Starts (weekly)', type: 'time' },
      { key: 'end_time', label: 'Ends (weekly)', type: 'time', help: 'Before the start = past midnight (22:00 → 04:00)' },
      { key: 'starts_at', label: 'Starts at (one-off; weekly: season start)', type: 'textnull', help: 'e.g. 2026-10-20 18:00+01' },
      { key: 'ends_at', label: 'Ends at (one-off; weekly: season end)', type: 'textnull' },
      { key: 'ticket_price', label: 'Ticket price', type: 'money', help: '0 = free entry, no ticket needed' },
      { key: 'capacity', label: 'Capacity (tickets)', type: 'intnull', help: 'Empty = no limit' },
      { key: 'perks', label: 'Perks for event-only actions', type: 'json', help: '{"effects": {"fun": 15, "social": 10}, "street_cred": 1}' },
      { key: 'description', label: 'Description', type: 'long' },
      { key: 'variants', label: 'Variants', type: 'long', help: 'One per row (opponents, film titles...), used for {variant}' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { location_id: 'oba_market', title: 'New event', kind: 'promo', icon: '🎉', recurrence: 'weekly', weekday: 5, start_time: 18, end_time: 22, starts_at: null, ends_at: null, ticket_price: 0, capacity: null, perks: {}, description: '', variants: '', sort: 100, active: true },
  },
  {
    id: 'daily', table: 'daily_reward_steps', title: 'Daily reward', emoji: '🎁', blurb: 'The 7-day daily reward ladder (D1, docs/DAILY.md). One claim per Benin calendar day; a missed day starts again at day 1; after day 7 it goes back to day 1. Cash goes to the player\'s cash (ledger "Daily reward (day N)"). Optional item id (Content → Items) is put in the Bag. Switch: Settings → Daily → daily.reward_enabled.',
    pk: ['day'], insert: false, inline: ['cash'],
    titleOf: (r) => `Day ${r.day} · ${naira(Number(r.cash))}${r.item_id ? ` + ${r.item_id}` : ''}`, subOf: (r) => String(r.label || ''),
    fields: [
      { key: 'cash', label: 'Cash', type: 'money' },
      { key: 'item_id', label: 'Item id (optional)', type: 'textnull', help: 'An id from Content → Items, e.g. malt_drink. Empty = none.' },
      { key: 'label', label: 'Label', type: 'text' },
    ],
  },
  {
    id: 'gemfinds', table: 'gem_finds', title: 'Gem finds', emoji: '💎', blurb: 'Read-only log of daily gem hunt finds (D1, docs/DAILY.md), newest day first. Gems are picked by the server each Benin day from active, always-open public places. Prizes: Settings → Daily (daily.gem_prize, daily.gem_all_bonus, daily.gems_per_day).',
    pk: ['user_id', 'hunt_date', 'location_id'], insert: false,
    titleOf: (r) => `${r.hunt_date} · ${r.location_id}`,
    subOf: (r) => `${naira(Number(r.prize))}${Number(r.bonus) ? ` + ${naira(Number(r.bonus))} bonus` : ''} · ${watTime(r.found_at)} WAT · player ${String(r.user_id).slice(0, 8)}`,
    fields: [],
  },
  {
    id: 'garages', table: 'garage_types', title: 'Garage types', emoji: '🚗', blurb: 'G1 garages (docs/GARAGE.md): offered after a car purchase and from Home → Build a garage. Prices are real Benin City build costs (2025-2026 estimates, sources in the doc). Capacity = cars parked inside. Allowed housing = home kinds that can build it: hostel, face_me, self_contain, mini_flat, duplex. Style carport or garage (how it is drawn). Upgrading replaces the old garage at the full new price. Switch: Settings → Garage → garage.enabled.',
    pk: ['id'], insert: true, inline: ['price'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => String(r.name),
    subOf: (r) => `${naira(Number(r.price))} · fits ${r.capacity} · ${(r.allowed_housing as string[] | null)?.join(', ') ?? ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'description', label: 'Description', type: 'long' },
      { key: 'price', label: 'Price', type: 'money' }, { key: 'capacity', label: 'Capacity (cars)', type: 'int', help: '1 to 4' },
      { key: 'allowed_housing', label: 'Allowed housing', type: 'list', help: 'Comma-separated: hostel, face_me, self_contain, mini_flat, duplex' },
      { key: 'style', label: 'Style', type: 'text', help: 'carport or garage' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New garage', description: '', price: 1000000, capacity: 1, allowed_housing: ['duplex'], style: 'garage', sort: 100, active: false },
  },
  {
    id: 'cardealers', table: 'car_dealers', title: 'Car dealers', emoji: '🏷️', blurb: 'H2 dealer price tiers (docs/GARAGE.md): every car costs its base price (Content → Items) × the dealer multiplier, rounded to ₦10,000. Tier budget = Tokunbo lot (cheaper, used stock), mid = normal dealer, premium = official showroom (dearer; the only place with the luxury cars — set which cars each dealer stocks in Items → sold_at). Location id must be a car_dealer place (one row per place: tokunbo_lot, ighodalo_cars, sdd_motors; add a new dealer place in Places first).',
    pk: ['location_id'], insert: true, inline: ['multiplier'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.location_id} · ${r.label || r.tier}`,
    subOf: (r) => `${String(r.tier)} · ×${Number(r.multiplier).toFixed(2)}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'tier', label: 'Tier', type: 'text', help: 'budget, mid or premium' },
      { key: 'multiplier', label: 'Price multiplier', type: 'num', help: '0.5 to 2. 0.88 = 12% below list, 1.2 = 20% above' },
      { key: 'label', label: 'Badge label', type: 'text', help: 'e.g. Tokunbo lot, Official showroom' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { location_id: '', tier: 'mid', multiplier: 1, label: 'Car dealer', blurb: '', sort: 100, active: false },
  },
  {
    id: 'shrine', table: 'shrine_services', title: 'Shrine services', emoji: '🪔', blurb: 'B2 Baba\'s Shrine (docs/BABALAWO.md): the 10 services. Price = cash; offerings = items taken from the Bag, e.g. {"kola_nut": 2, "palm_oil": 1} (item ids from Items, category offering). Effect value by kind: luck / road_opener = +% job pay; protection = pickpocket caught % (caps the base); vanishing = escape caught % (uses = how many escapes); home_guard = +% caught for thieves who target the holder (capped by shrine.guard_cap_pct); attraction = +% dates say yes; fame_bath = +% club hype; efcc_blindfold = − points EFCC caught; money_charm / cleansing ignore it (money charm numbers: Settings → Shrine). Duration in seconds (86400 = 1 day; empty = no time limit). Fail % empty = Settings → shrine.fail_pct. Changes apply to new charms only.',
    pk: ['id'], insert: true, inline: ['price'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${naira(Number(r.price))} + ${Object.entries((r.offerings as Row) ?? {}).map(([k, v]) => `${v} ${k}`).join(', ') || 'nothing'} · ${r.effect_kind} ${r.effect_value}${r.duration_seconds ? ` · ${Math.round(Number(r.duration_seconds) / 3600)} h` : ''}${r.uses ? ` · ${r.uses} uses` : ''}${r.fail_pct !== null && r.fail_pct !== undefined ? ` · fails ${r.fail_pct}%` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'price', label: 'Price (cash)', type: 'money' },
      { key: 'offerings', label: 'Offerings (from the Bag)', type: 'json', help: '{"kola_nut": 2, "palm_oil": 1}' },
      { key: 'effect_kind', label: 'Effect kind', type: 'text', help: 'luck, road_opener, protection, vanishing, home_guard, attraction, fame_bath, efcc_blindfold, money_charm, cleansing' },
      { key: 'effect_value', label: 'Effect value', type: 'num', help: 'See the note above for the unit per kind' },
      { key: 'duration_seconds', label: 'Lasts (seconds)', type: 'intnull', help: '86400 = 1 day, 604800 = 7 days; empty = until used / instant' },
      { key: 'uses', label: 'Uses', type: 'intnull', help: 'Vanishing charm: 3 escapes; empty = no limit' },
      { key: 'fail_pct', label: 'Fail chance %', type: 'numnull', help: 'Empty = Settings → shrine.fail_pct (10). Consultation and cleansing: 0' },
      { key: 'seconds', label: 'Action seconds', type: 'int' },
      { key: 'blurb', label: 'Blurb', type: 'long' }, { key: 'note', label: 'Note under the card', type: 'long' },
      { key: 'baba_line', label: 'Baba says when it works', type: 'long' }, { key: 'fail_line', label: 'Baba says when it fails', type: 'long' },
      { key: 'lines', label: 'Readings (consultation, one per line)', type: 'long' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New service', icon: '🪔', price: 100000, offerings: { kola_nut: 1 }, effect_kind: 'luck', effect_value: 5, duration_seconds: 86400, seconds: 12, blurb: '', note: '', baba_line: '', fail_line: '', lines: '', sort: 100, active: false },
  },
  {
    id: 'laptops', table: 'laptop_specs', title: 'Laptops (Yahoo)', emoji: '💻', blurb: 'Y1 Yahoo life (docs/YAHOO.md): what each laptop does for Yahoo jobs. Item id = an item in Items (price, name, where sold live there). Tier: jobs with a higher "laptop tier needed" are locked (Big job needs tier 3 = Dell XPS 13 or better). Pay bonus = + % on every job payout; EFCC = points taken off the caught chance; speed = % shorter job time (never under Settings → yahoo.min_seconds). The best laptop a player owns is the one used and the one seized when EFCC catches them.',
    pk: ['item_id'], insert: true, inline: ['pay_bonus_pct'],
    titleOf: (r) => `💻 ${r.item_id}`,
    subOf: (r) => `${r.label} · tier ${r.tier} · +${r.pay_bonus_pct}% pay · −${r.efcc_minus_pts} pts EFCC · ${r.speed_pct}% faster`,
    fields: [
      { key: 'item_id', label: 'Item id', type: 'text', help: 'e.g. macbook_pro_m4 (must exist in Items, category laptop)' },
      { key: 'label', label: 'Tier name', type: 'text', help: 'Shown on cards: Tokunbo, Mid, Chairman…' },
      { key: 'tier', label: 'Tier', type: 'int', help: '0 = weakest' },
      { key: 'pay_bonus_pct', label: 'Pay bonus %', type: 'num' },
      { key: 'efcc_minus_pts', label: 'EFCC caught − points', type: 'num' },
      { key: 'speed_pct', label: 'Faster %', type: 'num', help: '0 to 90' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { item_id: '', label: 'New', tier: 0, pay_bonus_pct: 0, efcc_minus_pts: 0, speed_pct: 0, sort: 100 },
  },
  {
    id: 'yahoo_jobs', table: 'yahoo_jobs', title: 'Yahoo jobs', emoji: '🧑‍💻', blurb: 'Y1 Yahoo jobs (satire, abstract buttons only). Seconds = action time before laptop speed; pay = random between min and max (before the laptop bonus), paid into the dirty yahoo balance; caught % = base EFCC chance (laptop points, EFCC blindfold −15 and bad luck +10 change it, floor in Settings → yahoo.caught_floor_pct). Cooldown = seconds before the same job again. Laptop tier needed: see Laptops (Yahoo). Kind cashout = turns the yahoo balance into cash (pay ignored). Caught = EFCC case (Settings → yahoo.bail_base, yahoo.escape_caught_pct), laptop seized, yahoo balance gone.',
    pk: ['id'], insert: true, inline: ['caught_pct'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${r.seconds}s · ${r.kind === 'cashout' ? 'cash out' : `${naira(Number(r.pay_min))}–${naira(Number(r.pay_max))}`} · EFCC ${r.caught_pct}% · cooldown ${r.cooldown_seconds}s${Number(r.min_tier) ? ` · laptop tier ${r.min_tier}+` : ''}${Number(r.min_skill_level) > 1 ? ` · skill lvl ${r.min_skill_level}+` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'kind', label: 'Kind', type: 'text', help: 'job or cashout' },
      { key: 'seconds', label: 'Seconds', type: 'int' },
      { key: 'pay_min', label: 'Pay min', type: 'money' }, { key: 'pay_max', label: 'Pay max', type: 'money' },
      { key: 'caught_pct', label: 'EFCC caught %', type: 'num' },
      { key: 'cooldown_seconds', label: 'Cooldown (seconds)', type: 'int' },
      { key: 'min_tier', label: 'Laptop tier needed', type: 'int' },
      { key: 'min_skill_level', label: 'Skill level needed', type: 'int', help: 'R3: 1 = open to everyone. The skill is the one with the most XP in Skill sources for this job (Big job: Yahoo).' },
      { key: 'req_cert', label: 'Certificate needed', type: 'textnull', help: 'R4: certificate id (comma = any of), empty = open. See Content → Certificates.' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New job', icon: '💻', blurb: '', kind: 'job', seconds: 20, pay_min: 5000, pay_max: 50000, caught_pct: 20, cooldown_seconds: 30, min_tier: 0, min_skill_level: 1, sort: 100, active: false },
  },
  {
    id: 'yahoo_ranks', table: 'yahoo_ranks', title: 'Yahoo ranks', emoji: '👑', blurb: 'Y1 status ladder by total successful Yahoo earnings (job payouts). Hype % = bigger club hype announcements. The VIP booth rank is Settings → yahoo.vip_rank (big_boy). Rank ids are used by code (aspirant, g_boy, big_boy, chairman): change names and numbers, keep the ids.',
    pk: ['id'], insert: true, inline: ['min_earned'],
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `from ${naira(Number(r.min_earned))} earned · +${r.hype_pct}% hype`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'min_earned', label: 'Total earned needed', type: 'money' },
      { key: 'hype_pct', label: 'Club hype bonus %', type: 'num' },
      { key: 'perks', label: 'Perks (shown in the app)', type: 'long' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New rank', icon: '💻', min_earned: 100000000, hype_pct: 0, perks: '', sort: 100 },
  },
  {
    id: 'courses', table: 'courses', title: 'Courses', emoji: '🎓', blurb: 'R4 School (docs/SCHOOL.md). A course = classes at a place that end in a certificate (Content → Certificates). Where: place ids (location_ids, e.g. uniben) and / or place types (scenes, e.g. motorpark). Class length: in-game minutes (shown to players) and real seconds (the timer). Cooldown = game days between classes (1 = one class per game day; Settings → School has a global multiplier, 0 = no wait). Each class costs energy and gives XP in the skill. Hours = Benin hour window (empty = any time; places have their own hours too). Prerequisite: a certificate id (comma = any of) and / or a minimum level in a skill. Exam: the final class rolls a pass chance = base % + per-level % for every skill level above 1 (clamped in Settings → School); a fail means retake that class. Modules: names shown on long courses (the classes are split evenly). Place cards: Content → Zone actions, kind class, ref = the course id.',
    pk: ['id'], insert: true, inline: ['fee'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${naira(Number(r.fee))} · ${r.classes} classes · ${r.class_seconds}s each · every ${r.cooldown_days} day(s)${r.exam ? ` · exam ${r.exam_base_pct}% + ${r.exam_per_level_pct}%/lvl` : ''} → ${r.cert_id ?? 'no certificate'}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' }, { key: 'where_text', label: 'Where (text)', type: 'text' },
      { key: 'location_ids', label: 'Place ids', type: 'list', help: 'e.g. uniben' }, { key: 'scenes', label: 'Place types', type: 'list', help: 'e.g. motorpark (any motor park)' },
      { key: 'fee', label: 'Fee', type: 'money' },
      { key: 'classes', label: 'Number of classes', type: 'int' },
      { key: 'class_game_minutes', label: 'Class length (game minutes, shown)', type: 'int' },
      { key: 'class_seconds', label: 'Class length (real seconds)', type: 'int' },
      { key: 'cooldown_days', label: 'Game days between classes (0 = none)', type: 'int' },
      { key: 'energy_cost', label: 'Energy cost per class', type: 'int' },
      { key: 'effects', label: 'Other need changes per class', type: 'json', help: '{"stress": 3, "hunger": -6}' },
      { key: 'hour_from', label: 'From hour', type: 'numnull' }, { key: 'hour_to', label: 'To hour', type: 'numnull' },
      { key: 'skill_id', label: 'Skill id for XP', type: 'textnull', help: 'yahoo, driving, cooking, music, teaching, fishing, mechanic, business, fitness, charisma' },
      { key: 'xp_per_class', label: 'XP per class', type: 'num' },
      { key: 'prereq_cert', label: 'Needs certificate id (comma = any of)', type: 'textnull' },
      { key: 'prereq_skill', label: 'Needs skill id', type: 'textnull' }, { key: 'prereq_skill_level', label: 'Needs skill level (1 = none)', type: 'int' },
      { key: 'cert_id', label: 'Certificate awarded', type: 'textnull' },
      { key: 'exam', label: 'Exam on the final class', type: 'bool' },
      { key: 'exam_base_pct', label: 'Exam pass chance % at skill level 1', type: 'num' }, { key: 'exam_per_level_pct', label: '+ % per skill level above 1', type: 'num' },
      { key: 'exam_text', label: 'Exam line', type: 'text' },
      { key: 'modules', label: 'Modules (names)', type: 'list', help: 'e.g. Year 1: Foundations, Year 2: Core courses' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New course', icon: '🎓', blurb: '', where_text: '', location_ids: ['uniben'], scenes: [], fee: 10000, classes: 4, class_game_minutes: 120, class_seconds: 30, cooldown_days: 1, energy_cost: 12, effects: {}, hour_from: 8, hour_to: 17, skill_id: null, xp_per_class: 6, prereq_cert: null, prereq_skill: null, prereq_skill_level: 1, cert_id: null, exam: false, exam_base_pct: 50, exam_per_level_pct: 8, exam_text: '', modules: [], sort: 200, active: false },
  },
  {
    id: 'certificates', table: 'certificates', title: 'Certificates', emoji: '📜', blurb: 'R4 (docs/SCHOOL.md): what a course awards. Pay bonus % is permanent: pay on the career tracks (ids like tech, pos, trade, transport, health, education) and the hustles (ids like dj_set, bolt_shift) listed below goes up by that much (bonuses stack). Careers, hustles and Yahoo jobs ask for a certificate with their "Certificate needed" field (comma = any of). The certificate in Settings → School (default bsc) counts as a UNIBEN degree. Grant or revoke for one player: Players → detail.',
    pk: ['id'], insert: true, inline: ['pay_bonus_pct'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `+${r.pay_bonus_pct}% pay${(r.bonus_tracks as string[]).length ? ` · careers ${(r.bonus_tracks as string[]).join(', ')}` : ''}${(r.bonus_hustles as string[]).length ? ` · hustles ${(r.bonus_hustles as string[]).join(', ')}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'pay_bonus_pct', label: 'Pay bonus %', type: 'num' },
      { key: 'bonus_tracks', label: 'Bonus on career tracks', type: 'list', help: 'e.g. tech, pos' },
      { key: 'bonus_hustles', label: 'Bonus on hustles', type: 'list', help: 'e.g. dj_set, bolt_shift' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New certificate', icon: '🎓', blurb: '', pay_bonus_pct: 0, bonus_tracks: [], bonus_hustles: [], sort: 200, active: true },
  },
  {
    id: 'skills', table: 'skills', title: 'Skills', emoji: '🌟', blurb: 'R3 skills (docs/SKILLS.md). Levels come from the XP curve (Skill XP curve tab); XP comes from the Skill sources tab. Pay % per level = hustle pay goes up by this much for every level above 1 on hustles whose main skill this is (5 = +5% per level, +45% at level 10). EFCC cut % per level = relative cut of the Yahoo EFCC caught chance per level above 1 (4 = −4% per level), never more than the cap (36 = −36%). Trait keys = traits.effects.skill_xp keys that speed this skill (e.g. hustle, coding, cooking); the best one applies. Master switch and XP multiplier: Settings → Skills.',
    pk: ['id'], insert: true, inline: ['pay_pct_per_level'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `pay +${r.pay_pct_per_level}%/lvl${Number(r.caught_pct_per_level) > 0 ? ` · EFCC −${r.caught_pct_per_level}%/lvl (cap ${r.caught_cap_pct}%)` : ''}${(r.trait_keys as string[]).length ? ` · traits ${(r.trait_keys as string[]).join(', ')}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' }, { key: 'train_text', label: 'Where to train (shown when locked and in the Skills tab)', type: 'long' },
      { key: 'trait_keys', label: 'Trait XP keys', type: 'list', help: 'e.g. hustle, coding' },
      { key: 'pay_pct_per_level', label: 'Hustle pay % per level above 1', type: 'num' },
      { key: 'caught_pct_per_level', label: 'EFCC cut % per level above 1 (relative)', type: 'num' },
      { key: 'caught_cap_pct', label: 'EFCC cut cap %', type: 'num' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New skill', icon: '⭐', blurb: '', train_text: '', trait_keys: [], pay_pct_per_level: 5, caught_pct_per_level: 0, caught_cap_pct: 0, sort: 200, active: false },
  },
  {
    id: 'skill_curve', table: 'skill_curve', title: 'Skill XP curve', emoji: '📈', blurb: 'R3: total XP a skill needs to reach each level (level 1 = 0). The highest level here is the max level. Changes apply to every player at once (levels are always worked out from XP). Keep the XP rising level by level.',
    pk: ['level'], insert: true, inline: ['xp'],
    titleOf: (r) => `Level ${r.level}`, subOf: (r) => `${Number(r.xp).toLocaleString('en-NG')} XP in total`,
    fields: [
      { key: 'level', label: 'Level', type: 'int' },
      { key: 'xp', label: 'Total XP to reach it', type: 'int' },
    ],
    newRow: { level: 11, xp: 4600 },
  },
  {
    id: 'skill_sources', table: 'skill_sources', title: 'Skill sources', emoji: '🎯', blurb: 'R3: which action gives how much XP in which skill. Kind: hustle (ref = hustle id), yahoo (Yahoo job id), career (career track id, per finished shift), activity (activity id, when started). One action can feed several skills (one row each). The skill with the most XP on a hustle / job is its main skill (that skill\'s level boosts its pay and opens its level gate). XP is multiplied by the player\'s trait multiplier and Settings → skills.xp_mult. Rows must be unique per kind + ref + skill.',
    pk: ['id'], insert: true, inline: ['xp'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.kind}: ${r.ref} → ${r.skill_id}`,
    subOf: (r) => `${r.xp} XP${r.note ? ` · ${r.note}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'id', label: 'Row id', type: 'text', help: 'e.g. activity:cook_home:cooking (anything unique)' },
      { key: 'kind', label: 'Kind', type: 'text', help: 'hustle, yahoo, career or activity' },
      { key: 'ref', label: 'Ref (id of the hustle / job / track / activity)', type: 'text' },
      { key: 'skill_id', label: 'Skill id', type: 'text', help: 'yahoo, driving, cooking, music, teaching, fishing, mechanic, business, fitness, charisma' },
      { key: 'xp', label: 'XP per action', type: 'num' },
      { key: 'note', label: 'Note', type: 'text' },
    ],
    newRow: { id: '', kind: 'activity', ref: '', skill_id: 'charisma', xp: 2, note: '', active: true },
  },
  {
    id: 'hustles', table: 'hustles', title: 'Hustles', emoji: '💪', blurb: 'E2 side hustles (docs/HUSTLES.md): Bolt, PoS, food stall, DJ / MC, tutoring, fishing, mechanic, stall rent, car service. Pay is a random amount between min and max (x car class for Bolt, x time-of-day, x "no tool" multiplier). Cost = fuel / ingredients / bait / parts per run (kind pass / service: the price). Cooldown in seconds; daily cap = runs per Benin day (0 = none). Where: place ids (location_ids) and / or place types (scenes: market, pos, club, campus), anywhere = any public place (Bolt). Hours: Benin hour window (empty = any time; places also have their own opening hours). Risk = chance of bad luck (pay x risk pay mult; 0 = no pay), loss = chance of losing money (PoS fraud), bonus = chance of a tip. Hour multipliers JSON: {"11-15": 1.5}. Effects: need changes at the start, e.g. {"energy": -10}. Kinds: bolt, pos, vending, dj, mc, tutor, fishing, mechanic, job, pass, service.',
    pk: ['id'], insert: true, inline: ['pay_max'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${r.kind} · ${r.seconds}s · ${Number(r.pay_max) > 0 ? `${naira(Number(r.pay_min))}–${naira(Number(r.pay_max))}` : r.kind === 'pass' || r.kind === 'service' ? naira(Number(r.cost)) : 'catch'} · cooldown ${r.cooldown_seconds}s · cap ${r.daily_cap || '∞'}${Number(r.min_skill_level) > 1 ? ` · skill lvl ${r.min_skill_level}+` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'kind', label: 'Kind', type: 'text' },
      { key: 'where_text', label: 'Where (text)', type: 'text' }, { key: 'req_text', label: 'Requirements (text)', type: 'text' },
      { key: 'seconds', label: 'Seconds', type: 'int' },
      { key: 'pay_min', label: 'Pay min', type: 'money' }, { key: 'pay_max', label: 'Pay max', type: 'money' },
      { key: 'cost', label: 'Cost per run / price', type: 'money' },
      { key: 'cooldown_seconds', label: 'Cooldown (seconds)', type: 'int' },
      { key: 'daily_cap', label: 'Daily cap (0 = none)', type: 'int' },
      { key: 'effects', label: 'Need changes at start', type: 'json', help: '{"energy": -10, "hunger": -4}' },
      { key: 'location_ids', label: 'Place ids', type: 'list', help: 'e.g. oba_market' }, { key: 'scenes', label: 'Place types', type: 'list', help: 'market, pos, club, campus' },
      { key: 'anywhere', label: 'Any public place', type: 'bool' },
      { key: 'hour_from', label: 'From hour', type: 'numnull' }, { key: 'hour_to', label: 'To hour', type: 'numnull' },
      { key: 'needs_car', label: 'Needs a car', type: 'bool' },
      { key: 'req_item', label: 'Needs item id', type: 'textnull' }, { key: 'no_item_pay_mult', label: 'Pay x without the item (empty = item is a must)', type: 'numnull' },
      { key: 'needs_pass', label: 'Needs pass', type: 'textnull' }, { key: 'pass_id', label: 'Sells pass', type: 'textnull' }, { key: 'pass_hours', label: 'Pass hours', type: 'intnull' },
      { key: 'wear_pct', label: 'Car wear % per run', type: 'num' },
      { key: 'risk_pct', label: 'Bad luck %', type: 'num' }, { key: 'risk_pay_mult', label: 'Bad luck pay x', type: 'num' }, { key: 'risk_text', label: 'Bad luck line', type: 'text' },
      { key: 'loss_pct', label: 'Loss %', type: 'num' }, { key: 'loss_min', label: 'Loss min', type: 'money' }, { key: 'loss_max', label: 'Loss max', type: 'money' }, { key: 'loss_text', label: 'Loss line', type: 'text' },
      { key: 'bonus_pct', label: 'Bonus %', type: 'num' }, { key: 'bonus_min', label: 'Bonus min', type: 'money' }, { key: 'bonus_max', label: 'Bonus max', type: 'money' }, { key: 'bonus_text', label: 'Bonus line', type: 'text' },
      { key: 'cred_gain', label: 'Street cred per run', type: 'int' },
      { key: 'hype_text', label: 'Club shout-out ({name})', type: 'text' },
      { key: 'hour_mult', label: 'Pay x by hour', type: 'json', help: '{"11-15": 1.5, "6-10": 0.6}' },
      { key: 'min_skill_level', label: 'Skill level needed', type: 'int', help: 'R3: 1 = open to everyone. The skill is the one with the most XP in Skill sources for this hustle (Engine job: Mechanic). Pay also grows with that skill (Content → Skills).' },
      { key: 'req_cert', label: 'Certificate needed', type: 'textnull', help: 'R4: certificate id (comma = any of), empty = open. See Content → Certificates.' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { req_cert: null, name: 'New hustle', icon: '💪', blurb: '', kind: 'job', where_text: '', req_text: '', seconds: 30, pay_min: 2000, pay_max: 5000, cost: 0, cooldown_seconds: 60, daily_cap: 5, effects: { energy: -6 }, location_ids: [], scenes: [], anywhere: false, hour_from: null, hour_to: null, needs_car: false, req_item: null, no_item_pay_mult: null, needs_pass: null, pass_id: null, pass_hours: null, wear_pct: 0, risk_pct: 0, risk_pay_mult: 0, risk_text: '', loss_pct: 0, loss_min: 0, loss_max: 0, loss_text: '', bonus_pct: 0, bonus_min: 0, bonus_max: 0, bonus_text: '', cred_gain: 0, hype_text: '', hour_mult: {}, min_skill_level: 1, sort: 100, active: false },
  },
  {
    id: 'hustle_car_classes', table: 'hustle_car_classes', title: 'Bolt car classes', emoji: '🚖', blurb: 'E2: the best car a player owns sets the Bolt class by price: pay x, fuel x and wear x. A car is in a class when its price is at least "Min car price". Bicycles and the Bajaj Boxer are below the lowest class.',
    pk: ['id'], insert: true, inline: ['pay_mult'],
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `from ${naira(Number(r.min_price))} · pay x${r.pay_mult} · fuel x${r.fuel_mult} · wear x${r.wear_mult}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'min_price', label: 'Min car price', type: 'money' },
      { key: 'pay_mult', label: 'Pay x', type: 'num' }, { key: 'fuel_mult', label: 'Fuel x', type: 'num' }, { key: 'wear_mult', label: 'Wear x', type: 'num' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New class', icon: '🚗', min_price: 1000000, pay_mult: 1, fuel_mult: 1, wear_mult: 1, sort: 100 },
  },
  {
    id: 'hustle_fish', table: 'hustle_fish', title: 'Fish (fishing)', emoji: '🐟', blurb: 'E2: what a cast can catch. Item id = a fish item (Items, category fish: the price is the catch value at the market). Weight = relative chance among active fish. "Nothing bit" is the Fishing hustle bad luck %.',
    pk: ['item_id'], insert: true, inline: ['weight'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `🐟 ${r.item_id}`,
    subOf: (r) => `weight ${r.weight}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'item_id', label: 'Item id', type: 'text' }, { key: 'weight', label: 'Weight', type: 'num' }, { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { item_id: '', weight: 10, sort: 100, active: false },
  },
  {
    id: 'invest_products', table: 'invest_products', title: 'Invest & Save products', emoji: '💰', blurb: 'I1 (docs/INVEST.md): Bronze Savings, SafeLock, money market fund, fixed deposits, T-bills, FGN bond, farms, transport, POS and rental flats. Rates are % per GAME year (Settings → invest.year_days real days); terms, cycles and daily income are in invest days (a game year / 365). Kind decides the rules (savings, safelock, mmf, fd, tbill, bond, farm, transport, pos, flat). Money kinds: min/max amount in naira. Unit kinds (farm, transport, pos, flat): min/max in UNITS, unit price in naira (flats: price follows the property index). Events (JSON): {"id": {"label": "...", "chance_pct": 10, "loss_of": "cycle|unit|income|vacancy", "loss_pct": 60, "span_days": 30}}. Farms roll cycle events at harvest; transport/POS/flat roll events once per invest day. Changes apply to NEW purchases (locked rates are fixed at purchase).',
    pk: ['id'], insert: true, inline: ['rate_pct'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${r.kind} · ${r.risk}${Number(r.rate_pct) ? ` · ${r.rate_pct}%/yr` : ''}${Number(r.term_days) ? ` · ${r.term_days} d` : ''}${Number(r.unit_price) ? ` · ${naira(Number(r.unit_price))}/unit` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'kind', label: 'Kind', type: 'text', help: 'savings, safelock, mmf, fd, tbill, bond, farm, transport, pos, flat' },
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'risk', label: 'Risk badge', type: 'text', help: 'safe, medium or high' },
      { key: 'rate_pct', label: 'Rate % per game year', type: 'num', help: 'Interest / coupon' },
      { key: 'term_days', label: 'Term (invest days)', type: 'int', help: 'Lock / maturity. 0 = none' },
      { key: 'exit_fee_pct', label: 'Early sell / sale fee %', type: 'num', help: 'T-bill early sell 2, bond sale 0.5, flat agent 3' },
      { key: 'forfeits_interest', label: 'Early exit loses interest', type: 'bool' },
      { key: 'unit_price', label: 'Price per unit', type: 'money', help: 'Farms, transport, POS, flats' },
      { key: 'market_id', label: 'Price market id', type: 'textnull', help: 'bond: fgn_bond; flats: property_index; else empty' },
      { key: 'min_amount', label: 'Minimum (naira, or units)', type: 'money' }, { key: 'max_amount', label: 'Maximum at once (naira, or units)', type: 'money' },
      { key: 'cycle_days', label: 'Farm cycle (invest days)', type: 'int' },
      { key: 'gain_min_pct', label: 'Farm payout gain min %', type: 'num' }, { key: 'gain_max_pct', label: 'Farm payout gain max %', type: 'num' },
      { key: 'income_day', label: 'Income per unit per invest day', type: 'money', help: 'Transport, POS, flats' },
      { key: 'resale_pct', label: 'Sell-back % of cost', type: 'num', help: 'Farm 80, transport 88, POS 85' },
      { key: 'depr_pct_year', label: 'Depreciation % per game year', type: 'num' },
      { key: 'resale_floor_pct', label: 'Sell-back floor %', type: 'num' },
      { key: 'events', label: 'Risk events', type: 'json', help: 'See the note above' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { kind: 'farm', name: 'New product', icon: '💰', blurb: '', risk: 'medium', rate_pct: 0, term_days: 0, exit_fee_pct: 0, forfeits_interest: false, unit_price: 100000, market_id: null, min_amount: 1, max_amount: 50, cycle_days: 120, gain_min_pct: 25, gain_max_pct: 35, income_day: 0, resale_pct: 80, depr_pct_year: 0, resale_floor_pct: 0, events: {}, sort: 300, active: false },
  },
  {
    id: 'invest_markets', table: 'invest_markets', title: 'Invest markets (stocks, crypto, land)', emoji: '📈', blurb: 'I1 (docs/INVEST.md): the simulated markets. Each has a shared deterministic price series (seeded random walk) so every player sees the same price. Drift = expected % growth per game year, volatility = % random move per step (stocks hourly, crypto 15 min, land 6 h), swing = extra smooth +/- % wobble over swing days. Price multiplier rescales the whole market instantly (plot prices, share prices). Fee % = broker fee (stocks, crypto) or agent fee (land, both buying and selling). Land: community % = settlement paid to the community / omonile on top of the plot price; levy chance % = chance they ask for an extra development levy (min to max % of the plot price) before the deal closes. Stocks: dividend chance % per hourly step and yield % of the price. Markets cannot be added here.',
    pk: ['id'], insert: false, inline: ['price_mult'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${r.kind} · drift ${r.drift_pct_year}%/yr · vol ${r.vol_pct}%/step · fee ${r.fee_pct}%${Number(r.community_pct) ? ` · community ${r.community_pct}% · levy ${r.levy_chance_pct}%` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' }, { key: 'ticker', label: 'Ticker / short name', type: 'text' },
      { key: 'blurb', label: 'Blurb', type: 'long' },
      { key: 'risk', label: 'Risk badge', type: 'text', help: 'safe, medium or high' },
      { key: 'price_mult', label: 'Price multiplier', type: 'num', help: '1 = normal; 2 = everything costs double' },
      { key: 'drift_pct_year', label: 'Drift % per game year', type: 'num', help: 'Applies to newly generated steps' },
      { key: 'vol_pct', label: 'Volatility % per step', type: 'num' },
      { key: 'swing_pct', label: 'Swing +/- %', type: 'num' }, { key: 'swing_days', label: 'Swing length (invest days)', type: 'num' },
      { key: 'fee_pct', label: 'Broker / agent fee %', type: 'num' },
      { key: 'community_pct', label: 'Land: community settlement %', type: 'num' },
      { key: 'levy_chance_pct', label: 'Land: levy chance %', type: 'num' },
      { key: 'levy_min_pct', label: 'Land: levy min %', type: 'num' }, { key: 'levy_max_pct', label: 'Land: levy max %', type: 'num' },
      { key: 'dividend_chance_pct', label: 'Stock: dividend chance % per step', type: 'num' },
      { key: 'dividend_yield_pct', label: 'Stock: dividend % of price', type: 'num' },
      { key: 'min_qty', label: 'Minimum quantity', type: 'num' }, { key: 'max_qty', label: 'Maximum at once', type: 'num' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: {},
  },
  {
    id: 'interactions', table: 'interaction_types', title: 'House interactions', emoji: '🤝', blurb: 'V2 things two players can do together in a house (docs/SOCIAL.md): tap a person, they accept, both get the effects and a busy timer. Requires = home activities the host\'s furniture must offer (any one): cook_home, watch_tv, sit_rest, relax_sofa; empty = none. Cost is paid by the one who asks. Poses come from the kind (cook_meal, movie, gist, play_game, dance, greet); a new kind just stands together. Cooldown: Settings → social.interact_cooldown_s.',
    pk: ['kind'], insert: true, inline: ['seconds'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.label}`,
    subOf: (r) => `${r.kind} · ${r.seconds}s${Number(r.cost) ? ` · ${naira(Number(r.cost))}` : ''}${(r.requires as string[] | null)?.length ? ` · needs ${(r.requires as string[]).join(' or ')}` : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'label', label: 'Label', type: 'text' }, { key: 'icon', label: 'Icon', type: 'text' },
      { key: 'description', label: 'Description', type: 'long' },
      { key: 'effects', label: 'Effects (both players)', type: 'json', help: 'Needs deltas, e.g. {"fun": 20, "social": 10}' },
      { key: 'requires', label: 'Requires furniture for', type: 'list', help: 'Comma-separated home activities, any one: cook_home, watch_tv, sit_rest, relax_sofa' },
      { key: 'cost', label: 'Cost (asker pays)', type: 'money' }, { key: 'seconds', label: 'Seconds', type: 'int', help: '1 to 3600' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { label: 'New interaction', icon: '✨', description: '', effects: { social: 5 }, requires: [], cost: 0, seconds: 20, sort: 100, active: false },
  },
  {
    id: 'wbrands', table: 'wardrobe_brands', title: 'Wardrobe brands', emoji: '🏷️', blurb: 'W1 Benin Boutique brands (docs/WARDROBE.md). Text names and an accent colour only: no logos. House brands (Benin Basics, Benin Owambe, Ring Road Atelier) are ours. Real brand names are used by the owner\'s choice for sponsorship: get each brand\'s permission before marketing. Switch the brand pills off: Settings → Wardrobe → wardrobe.brands_enabled.',
    pk: ['id'], insert: true,
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => String(r.name), subOf: (r) => `${r.colour}${r.is_house ? ' · house brand' : ''}${r.sponsor ? ' · sponsor' : ''}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'tagline', label: 'Tagline', type: 'text' },
      { key: 'colour', label: 'Accent colour (#hex)', type: 'text', help: 'e.g. #e8692a' },
      { key: 'is_house', label: 'House brand', type: 'bool' }, { key: 'sponsor', label: 'Sponsor', type: 'bool' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New brand', tagline: '', colour: '#25232b', is_house: false, sponsor: false, sort: 100, active: false },
  },
  {
    id: 'witems', table: 'wardrobe_items', title: 'Wardrobe items', emoji: '👗', blurb: 'W1 Benin Boutique items (docs/WARDROBE.md). Cosmetic only. Category: top, bottom, outfit, shoes, bag, hat_hair. Patch = the avatar parts it sets, using ids the 3D renderer knows (docs/AVATAR3D.md), e.g. {"top":{"s":"hoodie","f":"plain"}}; the colour the player picks fills top/bottom/shoes .c, or the accent for bags and hats. Price 0 = free basic. Gender empty = both. Real-brand prices are estimates: set real prices here.',
    pk: ['id'], insert: true, inline: ['price'],
    toggle: { key: 'active', label: 'On' },
    titleOf: (r) => `${r.icon} ${r.name}`,
    subOf: (r) => `${r.brand_id ?? 'no brand'} · ${r.category}${r.gender ? ` · ${r.gender}` : ''} · ${Number(r.price) ? naira(Number(r.price)) : 'free'} · ${r.tag}${r.active ? '' : ' · off'}`,
    fields: [
      { key: 'name', label: 'Name', type: 'text' }, { key: 'brand_id', label: 'Brand id', type: 'textnull', help: 'An id from Wardrobe brands, e.g. benin_basics' },
      { key: 'category', label: 'Category', type: 'text', help: 'top, bottom, outfit, shoes, bag or hat_hair' },
      { key: 'gender', label: 'Gender', type: 'textnull', help: 'male, female or empty for both' },
      { key: 'patch', label: 'Avatar patch', type: 'json' },
      { key: 'colours', label: 'Colours (#hex)', type: 'list', help: 'Comma-separated, e.g. #25232b,#f4f1ea' },
      { key: 'price', label: 'Price', type: 'money' },
      { key: 'tag', label: 'Tag', type: 'text', help: 'basic, designer or owambe' },
      { key: 'default_slots', label: 'Suggested slots', type: 'list', help: 'everyday, home, sleep, date, party, work, gym' },
      { key: 'icon', label: 'Icon (emoji)', type: 'text' }, { key: 'description', label: 'Description', type: 'long' },
      { key: 'sort', label: 'Sort order', type: 'int' },
    ],
    newRow: { name: 'New piece', brand_id: 'benin_basics', category: 'top', gender: null, patch: { top: { s: 'tee', f: 'plain' } }, colours: ['#25232b'], price: 10000, tag: 'basic', default_slots: ['everyday'], icon: '👕', description: '', sort: 100, active: false },
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
  price: 'Price', weekly_rent: 'Rent / week', rest_pct: 'Rest %', cost: 'Cost', game_minutes: 'Minutes', max_seconds: 'Max sec', risk: 'Risk 0–1',
  pay_per_shift: 'Pay', shift_game_minutes: 'Minutes', xp_per_shift: 'XP', xp_to_next: 'XP to next', x: 'x', z: 'z',
};
const rowKey = (def: TableDef, r: Row) => def.pk.map((k) => String(r[k])).join('|');
const fmtField = (f: Field, v: unknown): string => (f.type === 'time' ? hourToTime(v) : v === null || v === undefined ? '' : f.type === 'list' ? (v as string[]).join(', ') : f.type === 'json' ? JSON.stringify(v, null, 2) : String(v));

/** Convert a form string into the value we send; returns [value, error]. */
function parseField(f: Field, raw: unknown): [unknown, string | null] {
  switch (f.type) {
    case 'bool': return [raw === true, null];
    case 'text': case 'long': return [String(raw ?? ''), null];
    case 'textnull': return [String(raw ?? '').trim() === '' ? null : String(raw), null];
    case 'time': {
      const t = String(raw ?? '').trim();
      if (t === '') return [null, null];
      const m = /^(\d{1,2}):(\d{2})$/.exec(t);
      if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return [null, 'Use a time like 21:00'];
      return [Math.round((Number(m[1]) + Number(m[2]) / 60) * 100) / 100, null];
    }
    case 'list': return [String(raw ?? '').split(',').map((s) => s.trim()).filter(Boolean), null];
    case 'json':
      try {
        const p = JSON.parse(String(raw));
        if (p === null || typeof p !== 'object' || Array.isArray(p)) return [null, 'Must be a JSON object { … }'];
        return [p, null];
      } catch { return [null, 'Invalid JSON']; }
    default: {
      const s = String(raw ?? '').trim();
      if (s === '' && (f.type === 'intnull' || f.type === 'numnull')) return [null, null];
      const n = Number(s);
      if (s === '' || !Number.isFinite(n)) return [null, 'Enter a number'];
      if (f.type !== 'num' && f.type !== 'numnull' && !Number.isInteger(n)) return [null, 'Whole number'];
      if (n < 0 && f.key !== 'sort') return [null, 'Can’t be negative'];
      return [n, null];
    }
  }
}

function FieldInput({ f, value, onChange }: { f: Field; value: unknown; onChange: (v: unknown) => void }) {
  if (f.type === 'bool') return <Toggle checked={value === true} onChange={onChange} label={f.label} />;
  if (f.type === 'json') return <JsonControl rows={5} value={String(value ?? '')} onChange={(t) => onChange(t)} />;
  if (f.type === 'time') {
    return (
      <span className="adm-timebox">
        <label className="adm-numbox adm-numbox--wide">
          <input type="time" step={900} value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />
        </label>
        {String(value ?? '') !== '' && <Btn small tone="quiet" onClick={() => onChange('')}>Clear</Btn>}
      </span>
    );
  }
  if (f.type === 'long') return <textarea className="adm-input" rows={3} value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />;
  const numeric = ['int', 'money', 'num', 'intnull', 'numnull'].includes(f.type);
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
  if (def.validate) {
    const parsed = (key: string) => {
      const f = def.fields.find((x) => x.key === key);
      return f ? parseField(f, form[key])[0] : undefined;
    };
    Object.assign(errors, def.validate(parsed));
  }
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
  const [toggling, setToggling] = useState<string | null>(null);
  const saveToggle = async (r: Row, on: boolean) => {
    if (!def.toggle) return;
    const k = rowKey(def, r);
    const payload: Row = {};
    def.pk.forEach((p) => { payload[p] = r[p]; });
    payload[def.toggle.key] = on;
    setToggling(k);
    try {
      const res = await adminApi.rowUpsert(def.table, payload);
      toast(`${def.titleOf(res.row)} is now ${on ? 'open to players' : 'hidden'}`, 'good');
      merge(res.row);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setToggling(null); }
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
                {def.toggle && (
                  <label className={`adm-rowtoggle${r[def.toggle.key] === false ? '' : ' is-on'}`}>
                    <span className="adm-rowtoggle__cap">{r[def.toggle.key] === false ? 'Hidden' : 'Active'}</span>
                    <Toggle checked={r[def.toggle.key] !== false} label={`${def.toggle.label}: ${def.titleOf(r)}`}
                      onChange={(on) => { if (toggling !== k) void saveToggle(r, on); }} />
                  </label>
                )}
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
    { key: 'req_cert', label: 'Certificate needed to apply (comma = any of, empty = open)', type: 'textnull' },
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
    { key: 'req_cert', label: 'Certificate needed to reach this level (comma = any of, empty = open)', type: 'textnull', help: 'R4: certificate ids from Content → Certificates, e.g. ict,coding_bootcamp' },
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

/** R2 club switch (docs/CLUBS.md): every nightclub with an on/off switch. Off = "Closed for now". Audited. */
function ClubsSection() {
  const clubs = useLoad(() => adminApi.clubList());
  const music = useLoad(() => musicApi.overview()); // M1: the playlist picker on each club
  const [busy, setBusy] = useState<string | null>(null);
  if (clubs.error) return <LoadError error={clubs.error} onRetry={() => void clubs.reload()} />;
  if (!clubs.data) return <Skeleton rows={6} />;
  const onCount = clubs.data.filter((c) => c.on).length;
  const flip = async (id: string, on: boolean) => {
    setBusy(id);
    try {
      const r = await adminApi.clubSet(id, on);
      toast(r.message, 'good');
      await clubs.reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <div>
      <p className="adm-sub adm-inline-hint">
        {onCount} of {clubs.data.length} clubs are ON. A club that is OFF shows as "Closed for now" on the map and its place card, nobody can
        enter or spend there, and its events and banners are hidden. Players inside are sent home. Each switch is saved in the Audit log.
      </p>
      <div className="adm-card adm-rows" data-testid="club-switches">
        {clubs.data.map((c) => (
          <div key={c.id} className={`adm-row${c.on ? '' : ' is-off'}`}>
            <div className="adm-row__main adm-row__main--static">
              <span className="adm-row__title">{c.name} {!c.on && <Badge>Closed for now</Badge>}</span>
              <span className="adm-row__sub">
                {districtLabel(c.district)} · {c.open_hour === null ? 'always open' : `${hourLabel(c.open_hour)} – ${hourLabel(c.close_hour)}`}
                {' · '}{c.inside} inside · {c.events} event{c.events === 1 ? '' : 's'}
              </span>
            </div>
            {music.data && (
              <PlaylistSelect label={`Playlist for ${c.name}`} value={music.data.clubs.find((m) => m.id === c.id)?.playlist_id ?? null} playlists={music.data.playlists}
                onChange={async (pl) => {
                  try { toast((await musicApi.assign('club', c.id, pl)).message, 'good'); await music.reload(); } catch (e) { toast(errorMessage(e), 'bad'); }
                }} />
            )}
            <label className={`adm-rowtoggle${c.on ? ' is-on' : ''}`}>
              <span className="adm-rowtoggle__cap">{c.on ? 'ON' : 'OFF'}</span>
              <Toggle checked={c.on} label={`${c.name} is ${c.on ? 'on' : 'off'}`} onChange={(on) => { if (busy !== c.id) void flip(c.id, on); }} />
            </label>
          </div>
        ))}
      </div>
    </div>
  );
}
const districtLabel = (d: string) => d.replace(/_/g, ' ').replace(/^./, (x) => x.toUpperCase());

const SECTIONS = [
  { id: 'clubs', title: 'Clubs', emoji: '🪩', blurb: 'Switch each nightclub on or off. Keep one or two open while the player base is small so they feel full.' },
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
      {sec === 'clubs' ? <ClubsSection /> : sec === 'careers' ? <CareersSection /> : def && <GenericSection key={def.id} def={def} />}
    </div>
  );
}
