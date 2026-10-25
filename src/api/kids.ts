// Family & Love, stage 2: kids (docs/LOVE.md). ONE read, kids_status(), feeds the Family tab and the red dot on the Family icon.
// Every number and rule lives on the server (Settings -> Kids); this file only types the answers.
import { rpc } from '../lib/api';
import type { AvatarConfig } from '../lib/types';

export type KidNeed = 'hunger' | 'sleep' | 'clean' | 'fun' | 'health' | 'love';
export type KidAction = 'feed' | 'change' | 'sleep' | 'play' | 'medicine' | 'cuddle';
export type KidStatus = 'expecting' | 'home' | 'with_relatives' | 'university';
export type KidTier = 'graduate' | 'gold' | 'silver' | 'bronze' | 'none';

export interface KidPerson { id: string; username: string; avatar: AvatarConfig | null }

/** A place that sells a supply (Oba Market: cheaper, moves a little each day, open in the day; the supermarket: fixed, dearer, always open). */
export interface KidBuyPlace { id: string; name: string; open: boolean; price: number; kind: 'market' | 'supermarket' }

export interface KidActionInfo {
  ok: boolean; code: string; msg: string; wait: number; cost: number;
  /** Care that uses a supply: which item, its name and how many uses are left (feeds, changes, doses). */
  item?: string; item_name?: string; left?: number;
  /** code 'no_item': where to buy it. */
  buy?: KidBuyPlace[];
}

export interface KidSupply { role: 'formula' | 'cereal' | 'diaper' | 'paracetamol' | 'illness_med'; item: string; name: string; icon: string | null; left: number; unit: 'feeds' | 'changes' | 'doses' }
export interface KidIllness { id: string; name: string; emoji: string; blurb: string; med_item: string | null }


// ---- School and university (docs/KIDS_SCHOOL.md). The school block comes with each child in kids_status; schools and report cards are separate reads.
export type SchoolState = 'none' | 'waiting' | 'need_school' | 'learning' | 'finished' | 'deciding' | 'university' | 'done';
export type SchoolLevel = 'nursery' | 'primary' | 'secondary' | 'university';
export interface SchoolGrade { name: string; g: number; last: number | null }
export interface SchoolBuy { id: string; name: string; open: boolean; price: number; kind: 'market' | 'supermarket' }
export interface SchoolGear { kind: 'books' | 'uniform'; item: string; name: string; icon: string | null; have: boolean; applied: boolean; pts: number; buy: SchoolBuy[] }
export interface WaecPaper { id: string; name: string; score: number; letter: string; credit: boolean }
export interface Waec { papers: WaecPaper[]; credits: number; pass: boolean; text: string; need: number }
export interface SchoolResult { class_name: string; avg: number; promoted: boolean; attended: boolean; attempt: number; level?: SchoolLevel; at?: string }
export interface KidSchool {
  enabled: boolean;
  state: SchoolState;
  level: SchoolLevel | null;
  can_enrol?: boolean;
  starts_at?: string | null;
  pass_mark: number;
  cards: number;
  attempt?: number;
  missed?: number;
  class?: { seq: number; code: string; name: string; level: SchoolLevel; stage: string } | null;
  school?: { id: string; name: string; icon: string; tier: string; quality: number; fee: number } | null;
  started_at?: string | null;
  ends_at?: string | null;
  fee?: { amount: number; paid: boolean; paid_at: string | null; paid_by_me: boolean; on_time: boolean; can_pay: boolean } | null;
  grades?: SchoolGrade[];
  avg_now?: number | null;
  homework?: { count: number; mine_done: boolean; wait: number; max: number; pts: number; can: boolean } | null;
  lessons?: { bought: boolean; cost: number; can: boolean } | null;
  gear?: SchoolGear[];
  request?: { type: string; status: 'open' | 'paid' | 'ignored' } | null;
  last?: SchoolResult | null;
  history?: SchoolResult[];
  waec?: Waec | null;
  uni?: { state: 'deciding' | 'studying' | 'graduated' | 'dropped' | 'working'; level: number; level_name: string | null; course: string | null; repeats: number; max_repeats: number; degree: string | null; avg: number | null; deadline: string | null; ends_at: string | null } | null;
  can_switch?: boolean;
}
export interface SchoolOption { id: string; name: string; icon: string; tier: string; levels: SchoolLevel[]; area: string; fee: number; quality: number; blurb: string; current: boolean }
export interface ReportCard {
  id: number; stage: 'nursery' | 'primary' | 'jss' | 'sss' | 'university'; title: string; school: string; grades: { name: string; g: number }[]; avg: number;
  position: 'Excellent' | 'Very good' | 'Good' | 'Needs help'; remark: string; teacher: string; promoted: boolean; extra: string | null; at: string;
}

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
  stage: { id: string; name: string; emoji: string; needs: KidNeed[] } | null;
  needs: Partial<Record<KidNeed, number>>;
  needy: KidNeed[];
  sick: boolean;
  sick_med: boolean;
  sick_cuddle: boolean;
  illness: KidIllness | null;
  /** My open doctor card for this child (the "See the doctor" button opens it). */
  doctor_moment: number | null;
  supplies: KidSupply[];
  /** The best toy I own for this stage (it boosts Play). */
  toy: { item: string; name: string; boost: number } | null;
  actions: Partial<Record<KidAction, KidActionInfo>>;
  removal_at: string | null;
  partner: KidPerson | null;
  log: { id: number; action: KidAction; mine: boolean; who: string; created_at: string }[];
  relatives: {
    since: string; removals: number; wait_seconds: number; used: boolean;
    /** Naira EACH parent pays (the child comes home when every parent has paid; a lone parent pays only theirs). */
    cost_each: number; window_days: number; lone: boolean;
    mine_paid: boolean; mine_at: string | null;
    partner: { id: string; username: string; paid: boolean; at: string | null } | null;
    can_pay: boolean;
    /** When a lone paid share goes back to its payer. */
    refund_at: string | null;
  } | null;
  proposed_by_me?: boolean;
  /** School and university (null when school is switched off or the child is with relatives and not enrolled). */
  school?: KidSchool | null;
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
  name_grace_hours: number; removal_days: number; neglect_hours: number; reclaim_cost_each: number; reclaim_wait_hours: number; reclaim_window_days: number;
  feed_cost: number; max_per_couple: number; max_per_player: number;
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
  grown: { id: number; name: string | null; gender: 'boy' | 'girl' | null; grown_at: string; tier: KidTier | null; score: number | null; gift: number | null; outcome: string | null; cards: number }[];
  /** Children who passed away (a small candle on the Family tab). */
  memorials: { id: number; name: string | null; gender: 'boy' | 'girl' | null; born_at: string | null; passed_at: string; days_lived: number }[];
  proud: number;
  rules?: KidsRules;
}

interface Msg { message: string }
export interface CareResult extends Msg { spent: number; cured: boolean; child: number; need: KidNeed; value: number; item: string | null; item_left: number | null }

export const kidsStatus = () => rpc<KidsStatus>('kids_status');
export const kidsTry = (rel: number | null = null) => rpc<Msg & { invite_id: number }>('kids_try', { p_rel: rel });
export const kidsAccept = (invite: number, accept = true) => rpc<Msg & { accepted: boolean; expired?: boolean; child?: number }>('kids_accept', { p_invite: invite, p_accept: accept });
export const kidsWithdraw = (invite: number) => rpc<Msg>('kids_withdraw', { p_invite: invite });
export const kidsName = (child: number, name: string, gender: 'boy' | 'girl') => rpc<Msg & { name: string }>('kids_name', { p_child: child, p_name: name, p_gender: gender });
export const kidsCare = (child: number, action: KidAction) => rpc<CareResult>('kids_care', { p_child: child, p_action: action });
export const kidsReclaim = (child: number) => rpc<Msg & { home: boolean }>('kids_reclaim', { p_child: child });
export const kidsSchoolSchools = (child: number) => rpc<{ level: SchoolLevel | null; schools: SchoolOption[] }>('kids_school_schools', { p_child: child });
export const kidsSchoolEnrol = (child: number, school: string) => rpc<Msg & { school: string }>('kids_school_enrol', { p_child: child, p_school: school });
export const kidsSchoolPay = (child: number) => rpc<Msg & { spent: number }>('kids_school_pay', { p_child: child });
export const kidsSchoolHomework = (child: number) => rpc<Msg & { helps: number }>('kids_school_homework', { p_child: child });
export const kidsSchoolLessons = (child: number) => rpc<Msg & { spent: number }>('kids_school_lessons', { p_child: child });
export const kidsSchoolGear = (child: number, kind: 'books' | 'uniform') => rpc<Msg>('kids_school_gear', { p_child: child, p_kind: kind });
export const kidsReportCards = (child: number) => rpc<{ child: { id: number; name: string | null; gender: 'boy' | 'girl' | null }; cards: ReportCard[] }>('kids_report_cards', { p_child: child });
/** "See the doctor" when no doctor card is open: Dr. Osagie sends a new one. Returns the card's id. */
export const kidsCallDoctor = (child: number) => rpc<{ moment: number }>('kids_call_doctor', { p_child: child });

// admin
export interface AdminKidsOverview {
  enabled: boolean; expecting: number; home: number; with_relatives: number; needs_attention: number; sick: number; grown: number; gone: number; passed: number; passing_enabled: boolean; due_now: number;
  university: number; at_school: number; waec_passed: number; graduated: number; dropped_uni: number; school_enabled: boolean;
  children: { id: number; name: string | null; status: string; born_at: string | null; due_at: string; sick: boolean; illness: string | null; removals: number; a: string | null; b: string | null }[];
  passed_list: { id: number; name: string | null; born_at: string | null; passed_at: string; days_lived: number; warnings: number; a: string | null; b: string | null }[];
}
export const adminKidsOverview = () => rpc<AdminKidsOverview>('admin_kids_overview');
export const adminKidsRemove = (child: number, reason = '') => rpc<Msg>('admin_kids_remove', { p_child: child, p_reason: reason });
