// D2 Link-ups (docs/LINKUPS.md): dating NPCs only (adults 21–40), never another player; the server rolls every yes / no
// and every morning-after risk. Everything intimate is fade-to-black.
import { rpc } from '../lib/api';

export type LinkupWant = 'men' | 'women' | 'anyone';

export interface LinkupNpc {
  id: string;
  name: string;
  gender: 'man' | 'woman';
  age: number;
  vibe: string;
  likes: string;
  hates: string;
  avatar: Record<string, unknown>;
}

export interface LinkupOdds { pct: number; base: number; npc: number; charm: number; rank: number; cred: number; looks: number; spark: number }

export interface LinkupHere extends LinkupNpc {
  yes_pct: LinkupOdds;
  spark: number;
  met: boolean;
  yes_until: string | null;
  no_until: string | null;
  cold_until: string | null;
  partner: boolean;
}

export interface LinkupPerson extends LinkupNpc {
  spark: number;
  drinks: number;
  yeses: number;
  dinners: number;
  nights: number;
  met_at: string;
  last_at: string;
  partner: boolean;
  ended_at: string | null;
  yes_until: string | null;
  cold_until: string | null;
}

export interface LinkupAction {
  id: string;
  name: string;
  icon: string;
  blurb: string;
  kind: 'drinks' | 'date' | 'hotel';
  price: number;
  seconds: number;
  effects: Record<string, number>;
  spark: number;
  needs_yes: boolean;
  scenes: string[];
  morning: boolean;
  min_rank: string | null;
  rank_name: string | null;
  rank_ok: boolean;
  /** Can be done where I am now (right kind of place, open). */
  here: boolean;
  places: { id: string; name: string }[];
}

export interface LinkupRun {
  id: number;
  action_id: string;
  npc_id: string;
  name: string;
  icon: string;
  kind: LinkupAction['kind'];
  npc_name: string;
  started_at: string;
  resolve_at: string;
  status: 'running' | 'yes' | 'no' | 'done';
  price: number;
  yes_pct: number | null;
  line: string;
  place: string | null;
}

export interface LinkupMorning {
  run_id?: number;
  npc: LinkupNpc;
  action: string;
  action_id: string;
  line: string;
  robbed: boolean;
  robbed_amount: number;
  caught: boolean;
  ex: { id: string; name: string } | null;
  breakup: Record<string, number> | null;
  effects: Record<string, number>;
  with_partner: boolean;
}

export interface LinkupResult {
  status: 'yes' | 'no' | 'done' | 'none' | string;
  run_id?: number;
  action_id?: string;
  kind?: LinkupAction['kind'];
  name?: string;
  icon?: string;
  npc?: LinkupNpc;
  line?: string;
  effects?: Record<string, number>;
  spark?: number;
  new_partner?: boolean;
  morning?: LinkupMorning | null;
  yes_until?: string | null;
  already?: boolean;
}

export interface LinkupCurrent extends LinkupNpc { spark: number; partner: boolean; yes_until: string | null }

export interface LinkupStatus {
  enabled: boolean;
  want: LinkupWant;
  stats: { linkups: number; nights: number; breakups: number; lost: number };
  cash: number;
  bank: number;
  rank: string;
  attraction: number | null;
  place: { id: string; name: string; scene: string; open: boolean } | null;
  actions: LinkupAction[];
  here: LinkupHere[] | null;
  current: LinkupCurrent | null;
  partner: (LinkupNpc & { spark: number; since: string | null }) | null;
  steady: { dinners: number; spark: number };
  people: LinkupPerson[];
  run: LinkupRun | null;
  resolved: LinkupResult | null;
  morning: LinkupMorning | null;
  history: LinkupRun[];
}

export interface LinkupStarted {
  run_id: number;
  busy_until: string;
  resolve_at: string;
  seconds: number;
  action_id: string;
  name: string;
  icon: string;
  kind: LinkupAction['kind'];
  npc: LinkupNpc;
  price: number;
  yes_pct: number | null;
  line: string;
  message: string;
}

export const LINKUP_LABEL_PREFIX = 'Link-up: ';

export const linkupStatus = () => rpc<LinkupStatus>('linkup_status');
export const linkupSetPref = (want: LinkupWant) => rpc<{ want: LinkupWant; message: string }>('linkup_set_pref', { p_want: want });
export const linkupStart = (action: string, npc?: string | null) => rpc<LinkupStarted>('linkup_start', { p_action: action, p_npc: npc ?? null });
export const linkupFinish = () => rpc<LinkupResult>('linkup_finish');
export const linkupMorningSeen = (run: number) => rpc<{ seen: boolean }>('linkup_morning_seen', { p_run: run });

export const WANT_LABEL: Record<LinkupWant, string> = { women: 'Women', men: 'Men', anyone: 'Anyone' };
