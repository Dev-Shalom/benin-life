// B1 buy mode + arrange (supabase/migrations/20261012000200_buy_catalogue.sql).
import { rpc } from '../lib/api';

export interface FurnitureBuyResult {
  furniture_key: string;
  id: string;
  name: string;
  qty: number;
  spent: number;
  cash: number;
  bank: number;
  message: string;
}

export interface FurniturePlacement {
  furniture_key: string;
  x: number;
  z: number;
  rotation: number;
  stored: boolean;
  layout: string;
}

export const furnitureBuy = (id: string) => rpc<FurnitureBuyResult>('furniture_buy', { p_id: id });
export const furniturePlace = (key: string, x: number, z: number, rotation: number) =>
  rpc<FurniturePlacement>('furniture_place', { p_key: key, p_x: x, p_z: z, p_rotation: rotation });
export const furnitureStore = (key: string) => rpc<{ furniture_key: string; stored: boolean; layout: string }>('furniture_store', { p_key: key });

/** H2: sell one owned copy (stored or placed) for furniture.resale_pct of its price, in cash. */
export interface FurnitureSellResult {
  message: string;
  furniture_key: string;
  /** The last copy's old key, now renamed to furniture_key (null when the last copy was sold). */
  moved_from: string | null;
  id: string;
  name: string;
  earned: number;
  qty: number;
  cash: number;
}
export const furnitureSell = (key: string) => rpc<FurnitureSellResult>('furniture_sell', { p_key: key });
