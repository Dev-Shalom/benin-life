// V1-7 admin RPC wrappers. Every RPC is guarded server-side by bl_is_admin() (supabase/migrations/20261005001100_admin.sql).
import { rpc } from '../lib/api';

export type ConfigKind = 'number' | 'percent' | 'naira' | 'minutes' | 'bool' | 'text' | 'json';

export interface ConfigRow {
  key: string;
  value: unknown;
  category: string;
  label: string;
  description: string;
  kind: ConfigKind;
  min: number | null;
  max: number | null;
  updated_at: string;
  updated_by: string | null;
  updated_by_name: string | null;
  prev_value: unknown;
  prev_at: string | null;
}

export type Row = Record<string, unknown>;

export type AdminTable =
  | 'origin_tiers' | 'traits' | 'dreams' | 'start_homes' | 'career_tracks' | 'career_levels'
  | 'items' | 'activities' | 'locations' | 'chat_banned_words' | 'furniture' | 'starter_furniture'
  | 'place_zones' | 'zone_actions' | 'place_moods' | 'npc_roster' | 'crowd_profiles' | 'hype_templates';

export interface PlayerRow {
  id: string;
  username: string;
  email: string | null;
  origin: string;
  cash: number;
  bank: number;
  job_id: string | null;
  job_level: number;
  location_id: string;
  location_name: string | null;
  created_at: string;
  last_seen: string;
  online: boolean;
  banned: boolean;
  is_admin: boolean;
  chat_muted_until: string | null;
}

export interface LedgerRow { id: number; account: 'cash' | 'bank'; delta: number; balance_after: number; reason: string; label: string; created_at: string }
export interface PlayerDetail {
  profile: Row & PlayerRow & { job_title: string | null; traits: string[]; dream: string | null; street_cred: number };
  ledger: LedgerRow[];
  inventory: { item_id: string; qty: number; name: string | null }[];
  audit: { id: number; action: string; data: Row; created_at: string; admin: string | null }[];
}

export interface Stats {
  players: number; online: number; online_minutes: number; new_today: number; banned: number; admins: number;
  cash_total: number; bank_total: number; created_today: number; destroyed_today: number;
  money_today: { reason: string; label: string; created: number; destroyed: number; count: number }[];
  jobs: { track: string; name: string; emoji: string; count: number }[];
  origins: { origin: string; name: string; count: number }[];
  richest: { id: string; username: string; cash: number; bank: number; total: number }[];
  chat_today: number; reports_pending: number;
}

export interface AuditEntry {
  id: string; audit_id: number; type: 'config' | 'admin'; action: string; admin: string; created_at: string;
  key?: string; old_value?: unknown; new_value?: unknown;
  target?: string | null; target_id?: string | null; data?: Row;
}

export interface ChatReport {
  id: number; body: string; username: string; user_id: string; location_id: string; location_name: string | null;
  created_at: string; hidden: boolean; reports: number; last_report: string; reasons: string[] | null;
  reporters: (string | null)[]; author_muted_until: string | null;
}

type Msg = { message: string };

export const adminApi = {
  configList: () => rpc<ConfigRow[]>('admin_config_list'),
  configSet: (key: string, value: unknown) => rpc<Msg & { changed: boolean }>('admin_config_set', { p_key: key, p_value: value }),
  configSetMany: (changes: Record<string, unknown>) => rpc<Msg & { changed: number }>('admin_config_set_many', { p_changes: changes }),
  configRevert: (auditId: number) => rpc<Msg>('admin_config_revert', { p_audit_id: auditId }),
  tableRows: (table: AdminTable) => rpc<Row[]>('admin_table_rows', { p_table: table }),
  rowUpsert: (table: AdminTable, row: Row) => rpc<Msg & { row: Row }>('admin_row_upsert', { p_table: table, p_row: row }),
  players: (search: string, limit = 50, offset = 0) =>
    rpc<{ total: number; rows: PlayerRow[] }>('admin_players', { p_search: search, p_limit: limit, p_offset: offset }),
  playerDetail: (id: string) => rpc<PlayerDetail>('admin_player_detail', { p_id: id }),
  grantMoney: (id: string, account: 'cash' | 'bank', delta: number, reason: string) =>
    rpc<Msg & { balance: number }>('admin_grant_money', { p_id: id, p_account: account, p_delta: delta, p_reason: reason }),
  ban: (id: string, banned: boolean, reason = '') => rpc<Msg>('admin_ban', { p_id: id, p_banned: banned, p_reason: reason }),
  mute: (id: string, minutes: number) => rpc<Msg>('admin_mute', { p_id: id, p_minutes: minutes }),
  setAdmin: (id: string, isAdmin: boolean) => rpc<Msg>('admin_set_admin', { p_id: id, p_is_admin: isAdmin }),
  setOrigin: (id: string, origin: string, applyPerks: boolean) =>
    rpc<Msg>('admin_set_origin', { p_user: id, p_origin: origin, p_apply_perks: applyPerks }),
  stats: () => rpc<Stats>('admin_stats'),
  audit: (limit = 150) => rpc<AuditEntry[]>('admin_audit_list', { p_limit: limit }),
  chatReports: () => rpc<ChatReport[]>('admin_chat_reports', { p_include_hidden: true }),
  chatHide: (id: number, hidden: boolean) => rpc<Msg>('admin_chat_hide', { p_message_id: id, p_hidden: hidden }),
  claim: () => rpc<Msg & { is_admin: boolean }>('admin_claim'),
};
