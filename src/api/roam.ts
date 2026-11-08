// Free roam RPCs (server: 20261118000100_roam.sql + 20261119000100_roam2.sql, docs/ROAM.md). Positions in the 3D street are cosmetic:
// the server only records that you stepped out (roam_start), moves you into a place after a believable walk or drive (roam_enter),
// forgets the walk (roam_leave), and, for the player's own vehicle, validates fuel and damage checkpoints (roam_drive_report).
import { rpc } from '../lib/api';

export interface RoamStartResult {
  ok: boolean;
  place: string;
  max_speed_mps: number;
  ttl_s: number;
  /** Phase 2 hints: whole city open, driving / keke on, the drive speed, chunk size and load radius for the client. */
  all?: boolean;
  drive?: boolean;
  keke?: boolean;
  max_drive_mps?: number;
  chunk_m?: number;
  load_m?: number;
}

export interface RoamEnterResult {
  ok: boolean;
  location?: string;
  name?: string;
  message: string;
  /** 'far' (walk on), 'outside' (not in the area), 'rate' (slow down), 'inactive' (closed, e.g. the airport). */
  hint?: string;
  wait_s?: number;
}

export const roamStart = (place: string) => rpc<RoamStartResult>('roam_start', { p_place: place });
export const roamEnter = (place: string) => rpc<RoamEnterResult>('roam_enter', { p_place: place });
export const roamLeave = () => rpc<{ ok: boolean }>('roam_leave');

export interface RoamCarInfo {
  has_car: boolean;
  enabled: boolean;
  item?: string;
  name?: string;
  class?: 'car' | 'suv' | 'pickup' | 'motorcycle' | 'bicycle';
  fuel_l?: number;
  tank_l?: number;
  cond?: number;
  fuel_on?: boolean;
  wont_start?: boolean;
  car_place?: string | null;
  car_x?: number | null;
  car_y?: number | null;
  car_a?: number | null;
  ready_in_s?: number;
  rain?: boolean;
  mode?: 'walk' | 'car';
  max_drive_mps?: number;
}

export interface RoamModeResult {
  ok: boolean;
  mode: 'walk' | 'car';
  item?: string;
  class?: string;
  fuel_l?: number;
  tank_l?: number;
  cond?: number;
  max_drive_mps?: number;
}

export interface RoamDriveReport {
  ok: boolean;
  reason?: 'off' | 'not_driving' | 'too_soon' | 'rate';
  dist_m?: number;
  burned_l?: number;
  fuel_l?: number;
  tank_l?: number;
  cond?: number;
  damage?: number;
  empty?: boolean;
  wont_start?: boolean;
}

export interface RoamDryResult {
  ok: boolean;
  choice: string;
  message: string;
  cash_delta: number;
  wait_s: number;
  fuel_l: number;
}

export const roamCarInfo = () => rpc<RoamCarInfo>('roam_car_info');
export const roamSetMode = (mode: 'walk' | 'car', pose?: { x: number; y: number; a: number } | null) =>
  rpc<RoamModeResult>('roam_set_mode', {
    p_mode: mode,
    p_vehicle: null,
    p_x: pose ? Math.round(pose.x * 10) / 10 : null,
    p_y: pose ? Math.round(pose.y * 10) / 10 : null,
    p_a: pose ? Math.round(pose.a * 100) / 100 : null,
  });
export const roamDriveReport = (s: { dist_m: number; light: number; hard: number; x: number; y: number; a: number }) =>
  rpc<RoamDriveReport>('roam_drive_report', {
    p_stats: { dist_m: Math.round(s.dist_m * 10) / 10, light: s.light, hard: s.hard, x: Math.round(s.x * 10) / 10, y: Math.round(s.y * 10) / 10, a: Math.round(s.a * 100) / 100 },
  });
export const roamDryChoose = (choice: 'push' | 'mechanic') => rpc<RoamDryResult>('roam_dry_choose', { p_choice: choice });
export const roamHailKeke = (dest: string) => rpc<unknown>('roam_hail_keke', { p_dest: dest });

// ---- live players (server: 20261120000100_roam3.sql, docs/ROAM.md "Live players") ----
export const roamSetShow = (show: boolean) => rpc<{ ok: boolean; show_me: boolean; message: string }>('roam_set_show', { p_show: show });
export const roamReport = (user: string, reason: string) => rpc<{ ok: boolean; message: string }>('roam_report', { p_user: user, p_reason: reason });
