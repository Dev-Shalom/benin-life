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
