// V1-7 admin RPC wrappers. Every RPC is guarded server-side by bl_is_admin() (supabase/migrations/20261005001100_admin.sql).
import { GameError, rpc } from '../lib/api';
import { supabase } from '../lib/supabase';
import type { EconomyOverview } from '../api/economy';

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
  | 'place_zones' | 'zone_actions' | 'place_moods' | 'npc_roster' | 'crowd_profiles' | 'hype_templates' | 'place_events' | 'topup_packs'
  | 'daily_reward_steps' | 'gem_finds' | 'wardrobe_brands' | 'wardrobe_items' | 'garage_types' | 'car_dealers' | 'interaction_types' | 'billboards' | 'shrine_services' | 'laptop_specs' | 'yahoo_jobs' | 'group_missions' | 'yahoo_ranks' | 'invest_products' | 'invest_markets' | 'hustles' | 'hustle_car_classes' | 'hustle_fish' | 'skills' | 'skill_curve' | 'skill_sources' | 'courses' | 'certificates' | 'challenge_templates' | 'challenge_template_stats' | 'lounge_tiers' | 'love_flirts' | 'love_dates' | 'kids_stages' | 'kids_auto_names' | 'life_moments' | 'kids_illnesses' | 'kids_schools' | 'kids_subjects' | 'kids_items' | 'shop_price_rules' | 'house_upgrades' | 'market_settings' | 'business_types' | 'business_plots' | 'company_industries' | 'company_areas' | 'company_formats' | 'company_marketing' | 'real_biz_slots' | 'crew_jobs' | 'crew_levels' | 'offices' | 'gov_policies' | 'parties' | 'wards';

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
  profile: Row & PlayerRow & { job_title: string | null; traits: string[]; dream: string | null; street_cred: number; transfer_trusted?: boolean };
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

export interface PaymentRow {
  id: number; reference: string; user_id: string | null; username: string | null; pack_id: string | null; pack_label: string | null;
  amount_kobo: number; game_naira: number; status: 'pending' | 'success' | 'failed'; provider: string;
  created_at: string; paid_at: string | null; note: string | null;
}
export interface PaymentsData {
  rows: PaymentRow[];
  totals: { today_kobo: number; today_count: number; d7_kobo: number; d7_count: number; all_kobo: number; all_count: number;
            payers: number; pending: number; failed: number; naira_sold: number };
  enabled: boolean;
}

type Msg = { message: string };

export type GistKind = 'post' | 'comment' | 'group' | 'message';
export interface GistOverview {
  posts: number; posts_24h: number; comments_24h: number; hidden_posts: number; groups: number; public_groups: number; messages_24h: number;
  open_reports: number; bans: number; photos: number;
}
export interface GistReportRow {
  kind: GistKind; target_id: number; reports: number; last_report: string; status: 'open' | 'done'; reasons: string[] | null; reporters: (string | null)[];
  content: { text: string | null; photo_path?: string | null; author_id: string | null; author: string | null; hidden: boolean; at: string; group?: string; group_id?: number; post_id?: number; members?: number } | null;
}
export interface GistBanRow { user_id: string; username: string | null; until_at: string | null; reason: string | null; created_at: string }
export interface GistGroupRow {
  id: number; name: string; emoji: string; description: string; is_public: boolean; system: boolean; hidden: boolean; members: number;
  member_cap: number | null; owner: string | null; last_msg_at: string | null; created_at: string;
}

/** B2: a player's charm (Admin → Players → Charms). */
export interface PlayerSkillRow { skill: string; name: string; icon: string; xp: number; level: number; next_xp: number | null }

/** R4: a player's certificates (Admin → Players → Certificates). */
export interface PlayerCertRow { id: string; name: string; icon: string; earned_at: string; source: 'course' | 'admin'; course_id: string | null }
export interface PlayerCerts {
  rows: PlayerCertRow[];
  catalog: { id: string; name: string; icon: string; has: boolean }[];
  courses: { course_id: string; name: string; status: string; done: number; classes: number }[];
}

export interface CharmRow {
  id: number; kind: string; name: string; icon: string; status: string; expires_at: string | null; uses_left: number | null;
  created_at: string; ended_at: string | null; effect: string | null; debuff: boolean; live: boolean;
}

export interface JailCaseRow {
  id: number; user_id: string; username: string; status: string; decided: boolean; reason: string; bail_amount: number;
  escape_attempts: number; jail_seconds: number; jail_until: string; created_at: string; place: string | null;
}

export interface EarnOverview {
  referrals: { total: number; pending: number; rewarded: number; rejected: number; paid: number;
    rows: { id: number; inviter: string; inviter_id: string; new_player: string; new_id: string; code: string; status: string; reason: string | null;
            play_minutes: number; bonus_referrer: number; bonus_referred: number; created_at: string; rewarded_at: string | null }[] };
  weeks: { week_start: string; settled_at: string; skipped: boolean; players: number; earned: number;
           winners: { rank: number; username: string; total: number; prize: number }[] }[];
  tips: { total: number; amount: number; rows: { id: number; from: string; to: string; amount: number; note: string | null; created_at: string }[] };
}

export interface ClubRow {
  id: string; name: string; district: string; on: boolean; open_hour: number | null; close_hour: number | null;
  open_now: boolean; inside: number; events: number;
}

export interface PushStats {
  pending: number; sent_24h: number; failed_24h: number; skipped_24h: number; sent_total: number; failed_total: number;
  oldest_pending_s: number; players: number; devices: number; by_category: Record<string, number>; last_error: string | null; keep_days: number;
}

export const adminApi = {
  /** P1: player push outbox counts (docs/NOTIFICATIONS.md). */
  pushStats: () => rpc<PushStats>('admin_push_stats'),
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
  /** S1: edge function admin-delete-user (admin check + audit happen in the database first). */
  deleteUser: async (id: string, confirm: string, reason: string): Promise<Msg> => {
    const { data, error } = await supabase.functions.invoke('admin-delete-user', { body: { user_id: id, confirm, reason } });
    if (!error && data?.ok) return { message: String(data.message ?? 'Account deleted.') };
    let msg = 'Delete failed. Check your connection and try again.';
    try {
      const ctx = (error as { context?: Response } | null)?.context;
      const body = ctx ? await ctx.json() : data;
      if (body?.message) msg = String(body.message);
    } catch { /* keep the generic text */ }
    throw new GameError(msg);
  },
  ban: (id: string, banned: boolean, reason = '') => rpc<Msg>('admin_ban', { p_id: id, p_banned: banned, p_reason: reason }),
  mute: (id: string, minutes: number) => rpc<Msg>('admin_mute', { p_id: id, p_minutes: minutes }),
  setAdmin: (id: string, isAdmin: boolean) => rpc<Msg>('admin_set_admin', { p_id: id, p_is_admin: isAdmin }),
  /** R2: the club list and its on/off switch (docs/CLUBS.md). */
  clubList: () => rpc<ClubRow[]>('admin_club_list'),
  clubSet: (id: string, on: boolean) => rpc<Msg & { on: boolean; moved: number; changed: boolean }>('admin_club_set', { p_id: id, p_on: on }),
  setTransferTrusted: (id: string, on: boolean) => rpc<Msg>('admin_set_transfer_trusted', { p_id: id, p_on: on }),
  setOrigin: (id: string, origin: string, applyPerks: boolean) =>
    rpc<Msg>('admin_set_origin', { p_user: id, p_origin: origin, p_apply_perks: applyPerks }),
  stats: () => rpc<Stats>('admin_stats'),
  /** E2: referrals, weekly winners and tips (docs/HUSTLES.md). */
  /** E4: the Economy dashboard (docs/ECONOMY_SINKS.md). */
  economyOverview: (days = 14) => rpc<EconomyOverview>('admin_economy_overview', { p_days: days }),
  earnOverview: (limit = 100) => rpc<EarnOverview>('admin_earn_overview', { p_limit: limit }),
  audit: (limit = 150) => rpc<AuditEntry[]>('admin_audit_list', { p_limit: limit }),
  payments: (status: string | null, search: string | null) => rpc<PaymentsData>('admin_payments', { p_status: status, p_search: search, p_limit: 200 }),
  chatReports: () => rpc<ChatReport[]>('admin_chat_reports', { p_include_hidden: true }),
  chatHide: (id: number, hidden: boolean) => rpc<Msg>('admin_chat_hide', { p_message_id: id, p_hidden: hidden }),
  /** Benin Gist (docs/GIST.md): reports, hide / delete, bans, groups, photo clean-up. All audited. */
  gistOverview: () => rpc<GistOverview>('admin_gist_overview'),
  gistReports: (status: 'open' | 'all' = 'open') => rpc<GistReportRow[]>('admin_gist_reports', { p_status: status }),
  gistHide: (kind: GistKind, id: number, hidden: boolean) => rpc<Msg & { hidden: boolean }>('admin_gist_hide', { p_kind: kind, p_id: id, p_hidden: hidden }),
  gistDelete: (kind: GistKind, id: number) => rpc<Msg & { photo_path: string | null }>('admin_gist_delete', { p_kind: kind, p_id: id }),
  gistDismiss: (kind: GistKind, id: number) => rpc<Msg>('admin_gist_dismiss', { p_kind: kind, p_id: id }),
  gistBan: (user: string, banned: boolean, hours: number | null = null, reason: string | null = null, hide = false) =>
    rpc<Msg>('admin_gist_ban', { p_user: user, p_banned: banned, p_hours: hours, p_reason: reason, p_hide: hide }),
  gistBans: () => rpc<GistBanRow[]>('admin_gist_bans'),
  gistGroups: (query: string | null) => rpc<GistGroupRow[]>('admin_gist_groups', { p_query: query, p_limit: 80 }),
  gistGroupSet: (id: number, p: { name?: string; emoji?: string; description?: string; cap?: number; hidden?: boolean; isPublic?: boolean }) =>
    rpc<Msg>('admin_gist_group_set', { p_id: id, p_name: p.name ?? null, p_emoji: p.emoji ?? null, p_description: p.description ?? null, p_cap: p.cap ?? null, p_hidden: p.hidden ?? null, p_public: p.isPublic ?? null }),
  gistOrphanPhotos: () => rpc<{ name: string; bytes: number | null; created_at: string }[]>('admin_gist_orphan_photos', { p_limit: 200 }),
  claim: () => rpc<Msg & { is_admin: boolean }>('admin_claim'),
  /** C1: jail cases (open by default) and admin release (audited). */
  jailCases: (status = 'open') => rpc<{ rows: JailCaseRow[] }>('admin_jail_cases', { p_status: status, p_limit: 100 }),
  jailRelease: (caseId: number, reason: string) => rpc<Msg>('admin_jail_release', { p_case_id: caseId, p_reason: reason }),
  /** B2: a player's charms; clear one (id) or all active ones (null). Audited. */
  playerCharms: (userId: string) => rpc<{ rows: CharmRow[] }>('admin_player_charms', { p_user: userId }),
  /** R3: a player's skills; set a level (jumps to its XP) or exact XP. Audited (set_skill). */
  playerSkills: (userId: string) => rpc<{ max_level: number; rows: PlayerSkillRow[] }>('admin_player_skills', { p_user: userId }),
  setPlayerSkill: (userId: string, skill: string, level: number | null, xp: number | null) =>
    rpc<Msg & { skill: string; xp: number; level: number }>('admin_set_player_skill', { p_user: userId, p_skill: skill, p_level: level, p_xp: xp }),
  /** R4: a player's certificates; grant or revoke one. Audited (grant_cert / revoke_cert). */
  playerCerts: (userId: string) => rpc<PlayerCerts>('admin_player_certs', { p_user: userId }),
  grantCert: (userId: string, cert: string, note: string | null) => rpc<Msg & { cert: string }>('admin_grant_cert', { p_user: userId, p_cert: cert, p_note: note }),
  revokeCert: (userId: string, cert: string, note: string | null) => rpc<Msg & { cert: string }>('admin_revoke_cert', { p_user: userId, p_cert: cert, p_note: note }),
  /** R7: a player's Members' Lounge membership; grant a tier (hours = override, empty = the tier's length) or revoke. Audited (lounge_grant / lounge_revoke). */
  loungeGet: (userId: string) => rpc<{
    member: { tier_id: string; tier_name: string; started_at: string; expires_at: string; active: boolean; vouchers_left: number; source: string; paid_total: number } | null;
    guest_passes: { host: string; expires_at: string }[];
    tiers: { id: string; name: string; hours: number }[];
  }>('admin_lounge_get', { p_user: userId }),
  loungeGrant: (userId: string, tier: string, hours: number | null) => rpc<Msg & { tier: string; expires_at: string }>('admin_lounge_grant', { p_user: userId, p_tier: tier, p_hours: hours }),
  loungeRevoke: (userId: string) => rpc<Msg>('admin_lounge_revoke', { p_user: userId }),
  /** R8: a player's house upgrades (built / building) and the ones that could be granted; grant is free, instant and audited (house_upgrade_grant). */
  houseUpgradeGet: (userId: string) => rpc<{
    kind: string; start_home: string | null;
    rows: { id: string; name: string; emoji: string; state: 'done' | 'building'; paid: number; ready_at: string; done_at: string | null; source: string }[];
    options: { id: string; name: string; emoji: string }[];
  }>('admin_house_upgrade_get', { p_user: userId }),
  houseUpgradeGrant: (userId: string, upgrade: string) => rpc<Msg & { upgrade: string }>('admin_house_upgrade_grant', { p_user: userId, p_upgrade: upgrade }),
  charmClear: (userId: string, charmId: number | null) => rpc<Msg & { cleared: number }>('admin_charm_clear', { p_user: userId, p_charm: charmId }),
};
