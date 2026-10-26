// H1: moving house (server: 20261012000300_move_house.sql, docs/SHOPS.md "Moving house").
import { rpc } from '../lib/api';

export interface HouseOption {
  id: string;
  name: string;
  emoji: string;
  district: string;
  tag: string;
  description: string;
  weekly_rent: number;
  /** One-off move-in fee (weekly rent x house.move_in_weeks). */
  move_in: number;
  kind: string;
  layout: string;
  w: number;
  d: number;
  /** Floor area in m². */
  area: number;
  /** current = your home, past = you moved out and can move back until past_until, available = can move in. */
  status: 'current' | 'past' | 'available';
  /** Past homes: when the slot runs out, how many upgrades wait there and what giving it up pays. */
  past_until: string | null;
  past_upgrades: number;
  past_value: number;
}

export interface HouseOptions {
  enabled: boolean;
  move_in_weeks: number;
  /** Real days a home you left stays in Past homes. */
  return_days: number;
  /** null when you live in a home you own or rent from a player. */
  current: string | null;
  /** The garage that stays behind if you move (null = none). */
  garage: { type: string; name: string } | null;
  homes: HouseOption[];
}

export interface HouseMoveResult {
  message: string;
  home: string;
  name: string;
  layout: string;
  placed: number;
  not_fit: number;
  /** Pieces waiting in My items (place them in Arrange). */
  in_items: number;
  /** H4: pieces this home came with (now yours: move, store or sell them). */
  came_with?: number;
  garage_left: string | null;
  /** True when this was a past home: furniture spots and upgrades are back. */
  returned?: boolean;
  upgrades_back?: number;
  spent: number;
  from_bank: number;
  from_cash: number;
  weekly_rent: number;
}

export const houseOptions = () => rpc<HouseOptions>('house_options');
export const houseMove = (home: string) => rpc<HouseMoveResult>('house_move', { p_home: home });
