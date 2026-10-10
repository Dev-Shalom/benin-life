// G1: garage RPCs (server: 20261010000400_garage.sql, docs/GARAGE.md).
import { rpc } from '../lib/api';

export type GarageStyle = 'carport' | 'garage';

export interface GarageType {
  id: string;
  name: string;
  description: string;
  price: number;
  capacity: number;
  style: GarageStyle;
  /** Can be built at the player's current home type. */
  allowed: boolean;
}

export interface GarageHome {
  enabled: boolean;
  owner: string;
  /** Housing kind: hostel, face_me, self_contain, mini_flat, duplex. */
  kind: string;
  garage: { type: string; name: string; capacity: number; style: GarageStyle; built_at: string } | null;
  /** Owned vehicles, most expensive first. */
  cars: { id: string; name: string; price: number }[];
  /** Build menu (owner only; empty for guests). */
  types: GarageType[];
}

export const garageHome = (owner?: string | null) => rpc<GarageHome>('garage_home', owner ? { p_owner: owner } : {});
export const garageBuild = (type: string) =>
  rpc<{ message: string; garage: string; capacity: number; spent: number; replaced: string | null }>('garage_build', { p_type: type });

/** Two-wheelers never trigger the "build a garage?" offer. */
export const isCarItem = (id: string) => id !== 'bicycle' && id !== 'bajaj_boxer';
