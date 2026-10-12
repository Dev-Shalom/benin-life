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
  /** current = your home, released = you moved out (can't go back), available = can move in. */
  status: 'current' | 'released' | 'available';
}

export interface HouseOptions {
  enabled: boolean;
  move_in_weeks: number;
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
  spent: number;
  from_bank: number;
  from_cash: number;
  weekly_rent: number;
}

export const houseOptions = () => rpc<HouseOptions>('house_options');
export const houseMove = (home: string) => rpc<HouseMoveResult>('house_move', { p_home: home });
