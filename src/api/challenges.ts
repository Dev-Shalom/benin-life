// R5 Challenges (docs/CHALLENGES.md): typed wrappers for the challenge RPCs. Progress is counted by the server from real events;
// the client only reads it and taps Claim / Reroll / Open chest.
import { rpc } from '../lib/api';

export interface ChallengeReward {
  cash: number;
  xp: number;
  skill: string | null;
  skill_name: string | null;
  skill_icon: string | null;
  skill_xp: number;
  item: string | null;
  item_name: string | null;
  item_icon: string | null;
  item_qty: number;
}

export interface Challenge {
  id: number;
  slot: number;
  template: string;
  kind: 'daily' | 'weekly';
  title: string;
  blurb: string;
  icon: string;
  friends: boolean;
  goal: string;
  /** Progress is naira (earn / club spend / spray goals). */
  money: boolean;
  target: number;
  progress: number;
  done: boolean;
  claimed: boolean;
  reward: ChallengeReward;
  can_reroll: boolean;
}

export interface ChallengeChest {
  total: number;
  done: number;
  ready: boolean;
  claimed: boolean;
  cash: number;
  xp: number;
  item: string | null;
  item_name: string | null;
  item_icon: string | null;
}

export interface ChallengePeriod {
  period: string;
  ends_at: string;
  secs_left: number;
  rerolls_left: number;
  rerolls_max: number;
  items: Challenge[];
  chest: ChallengeChest;
}

export interface ChallengeStatus {
  enabled: boolean;
  now?: string;
  daily?: ChallengePeriod;
  weekly?: ChallengePeriod;
}

export interface ClaimResult { message: string; cash: number }
export interface RerollResult { message: string; item: Challenge; rerolls_left: number }

export const challengeStatus = () => rpc<ChallengeStatus>('challenge_status');
export const challengeClaim = (id: number) => rpc<ClaimResult>('challenge_claim', { p_id: id });
export const challengeClaimChest = (kind: 'daily' | 'weekly') => rpc<ClaimResult>('challenge_claim_chest', { p_kind: kind });
export const challengeReroll = (id: number) => rpc<RerollResult>('challenge_reroll', { p_id: id });
