// Free roam RPCs (server: 20261118000100_roam.sql, docs/ROAM.md). Positions in the 3D street are cosmetic: the server only
// records that you stepped out (roam_start), moves you into a place after a believable walk (roam_enter) and forgets the walk (roam_leave).
import { rpc } from '../lib/api';

export interface RoamStartResult {
  ok: boolean;
  place: string;
  max_speed_mps: number;
  ttl_s: number;
}

export interface RoamEnterResult {
  ok: boolean;
  location?: string;
  name?: string;
  message: string;
  /** 'far' (walk on), 'outside' (not in the phase 1 area), 'rate' (slow down). */
  hint?: string;
  wait_s?: number;
}

export const roamStart = (place: string) => rpc<RoamStartResult>('roam_start', { p_place: place });
export const roamEnter = (place: string) => rpc<RoamEnterResult>('roam_enter', { p_place: place });
export const roamLeave = () => rpc<{ ok: boolean }>('roam_leave');
