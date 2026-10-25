// Family & Love, stage 2: kids (docs/LOVE.md). ONE read, kids_status(), feeds the Family tab and the red dot on the Family icon.
// Every number and rule lives on the server (Settings -> Kids); this file only types the answers.
import { rpc } from '../lib/api';
import type { AvatarConfig } from '../lib/types';

export type KidNeed = 'hunger' | 'sleep' | 'fun' | 'health' | 'love';
export type KidAction = 'feed' | 'sleep' | 'play' | 'medicine' | 'cuddle';
export type KidStatus = 'expecting' | 'home' | 'with_relatives';

export interface KidPerson { id: string; username: string; avatar: AvatarConfig | null }

export interface KidActionInfo { ok: boolean; code: string; msg: string; wait: number; cost: number }

export interface KidChild {
  id: number;
  rel_id: number | null;
  status: KidStatus;
  name: string | null;
  gender: 'boy' | 'girl' | null;
  auto_named: boolean;
  named_by_me: boolean | null;
  name_due_at: string | null;
  conceived_at: string;
  due_at: string;
  born_at: string | null;
  age_days: number | null;
  stage: { id: string; name: string; emoji: string } | null;
  needs: Partial<Record<KidNeed, number>>;
  needy: KidNeed[];
  sick: boolean;
  sick_med: boolean;
  sick_cuddle: boolean;
  actions: Partial<Record<KidAction, KidActionInfo>>;
  removal_at: string | null;
  partner: KidPerson | null;
  log: { id: number; action: KidAction; mine: boolean; who: string; created_at: string }[];
  relatives: { since: string; removals: number; can_reclaim: boolean; wait_seconds: number; used: boolean; cost: number } | null;
  proposed_by_me?: boolean;
}

export interface KidCouple {
  rel_id: number;
  partner: KidPerson;
  couple_days: number;
  min_days: number;
  can_try: boolean;
  why: { code: string; msg: string } | null;
  invite_wait_seconds: number;
}

export interface KidInvite { id: number; rel_id: number; expires_at: string; from: KidPerson }
export interface KidOutgoing { id: number; rel_id: number; expires_at: string; state: 'pending' | 'declined' | 'noreply'; to: KidPerson }

export interface KidsRules {
  try_cost_each: number; pregnancy_days: number; min_couple_days: number; invite_expire_hours: number; grow_days: number; alert_below: number;
  name_grace_hours: number; removal_days: number; neglect_hours: number; reclaim_cost: number; reclaim_wait_hours: number;
  feed_cost: number; medicine_cost: number; max_per_couple: number; max_per_player: number;
}

export interface KidsStatus {
  enabled: boolean;
  can_start?: boolean;
  poll_seconds: number;
  /** Children that need their parents right now (the red dot on the Family icon). */
  attention: number;
  children: KidChild[];
  couples: KidCouple[];
  incoming: KidInvite[];
  outgoing: KidOutgoing[];
  grown: { id: number; name: string | null; gender: 'boy' | 'girl' | null; grown_at: string }[];
  proud: number;
  rules?: KidsRules;
}

interface Msg { message: string }
export interface CareResult extends Msg { spent: number; cured: boolean; child: number; need: KidNeed; value: number }

export const kidsStatus = () => rpc<KidsStatus>('kids_status');
export const kidsTry = (rel: number | null = null) => rpc<Msg & { invite_id: number }>('kids_try', { p_rel: rel });
export const kidsAccept = (invite: number, accept = true) => rpc<Msg & { accepted: boolean; expired?: boolean; child?: number }>('kids_accept', { p_invite: invite, p_accept: accept });
export const kidsWithdraw = (invite: number) => rpc<Msg>('kids_withdraw', { p_invite: invite });
export const kidsName = (child: number, name: string, gender: 'boy' | 'girl') => rpc<Msg & { name: string }>('kids_name', { p_child: child, p_name: name, p_gender: gender });
export const kidsCare = (child: number, action: KidAction) => rpc<CareResult>('kids_care', { p_child: child, p_action: action });
export const kidsReclaim = (child: number) => rpc<Msg>('kids_reclaim', { p_child: child });

// admin
export interface AdminKidsOverview {
  enabled: boolean; expecting: number; home: number; with_relatives: number; needs_attention: number; sick: number; grown: number; gone: number; due_now: number;
  children: { id: number; name: string | null; status: string; born_at: string | null; due_at: string; sick: boolean; removals: number; a: string | null; b: string | null }[];
}
export const adminKidsOverview = () => rpc<AdminKidsOverview>('admin_kids_overview');
export const adminKidsRemove = (child: number, reason = '') => rpc<Msg>('admin_kids_remove', { p_child: child, p_reason: reason });
