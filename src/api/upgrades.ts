// R8: house upgrades (server: 20261018000500_house_upgrades.sql, docs/HOUSE_UPGRADES.md).
import { rpc } from '../lib/api';

export type UpgradeCategory = 'extension' | 'quarters' | 'garage' | 'power' | 'water' | 'security' | 'finish' | 'tier';

export interface UpgradeCard {
  id: string;
  name: string;
  emoji: string;
  category: UpgradeCategory;
  description: string;
  /** What you will see in your home when it is done. */
  preview: string;
  /** Build minutes (after the admin's speed dial). 0 = instant. */
  minutes: number;
  /** Bonus on home activities: { sleep: { energy: 2 } }. */
  bonus: Record<string, Record<string, number>>;
  finish?: number | null;
  security?: number | null;
}

export interface UpgradeAvailable extends UpgradeCard {
  price: number;
  /** Tier upgrades: the rent difference x move-in weeks. */
  rent_fee: number;
  landlord_fee: number;
  total: number;
  requires: string | null;
  to_home: { id: string; name: string; weekly_rent: number; area: number } | null;
  state: 'available' | 'locked' | 'owned' | 'building';
  locked: string | null;
}

export interface UpgradeBuilding extends UpgradeCard {
  started_at: string;
  ready_at: string;
  progress: number;
  seconds_left: number;
}

export interface UpgradeState {
  enabled: boolean;
  can_upgrade: boolean;
  /** Why you can't upgrade right now (hostel, visiting, rent owed ...). */
  reason: string | null;
  kind: string;
  resale_pct: number;
  landlord_fee_pct: number;
  max_builds: number;
  building_count: number;
  tier_building: boolean;
  /** What you get back if you move out now. */
  sale_value: number;
  finish: number;
  garage: { type: string; extra: number } | null;
  done: (UpgradeCard & { paid: number; done_at: string; source: string })[];
  building: UpgradeBuilding[];
  available: UpgradeAvailable[];
  /** Finished since the last read (show a toast once). */
  just_finished: { id: string; name: string; emoji: string }[];
}

export interface UpgradeBuyResult {
  message: string;
  upgrade: string;
  name: string;
  spent: number;
  landlord_fee: number;
  minutes: number;
  ready_at: string;
  instant: boolean;
}

/** The pieces the 3D home needs: finished upgrades (geometry / finish / security) and the ones being built. */
export interface UpgradeHome {
  owner: string;
  done: { id: string; effect: Record<string, unknown> }[];
  building: { id: string; effect: Record<string, unknown>; ready_at: string; started_at: string; name: string; emoji: string }[];
}

export const houseUpgradeState = () => rpc<UpgradeState>('house_upgrade_state');
export const houseUpgradeBuy = (id: string) => rpc<UpgradeBuyResult>('house_upgrade_buy', { p_id: id });
export const houseUpgradeHome = (owner?: string | null) => rpc<UpgradeHome>('house_upgrade_home', owner ? { p_owner: owner } : {});
