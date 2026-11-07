// Drive scene RPCs (server: 20261114000100_drive.sql, docs/DRIVE.md). The server rolls every road event and applies the
// result; the client only shows the card and the outcome.
import { rpc } from '../lib/api';

export type DriveKind = 'ambush' | 'police' | 'goslow' | 'beggar' | 'dry';

export interface DriveChoice {
  id: string;
  label: string;
  hint?: string;
}

export interface DriveEvent {
  kind: DriveKind;
  title: string;
  body: string;
  choices: DriveChoice[];
}

export interface DriveOutcome {
  message: string;
  tone: 'good' | 'warn' | 'bad' | 'neutral';
  kind: DriveKind;
  choice: string;
  cash_delta: number;
  delay_s: number;
  arrives_at: string;
}

export const driveEventRoll = () => rpc<{ event: DriveEvent | null; reason?: string; resumed?: boolean }>('drive_event_roll');
export const driveEventChoose = (choice: string) => rpc<DriveOutcome>('drive_event_choose', { p_choice: choice });
export const driveTurnBack = () => rpc<{ message: string; location: string }>('drive_turn_back');

// ---- drive 3 (server: 20261117000100_drive_steer.sql): steering report, fuel, condition, repair, weather ----
export interface DriveWeather {
  enabled: boolean;
  rain: boolean;
  forced?: boolean;
  rain_today?: boolean;
  start_hour?: number | null;
  end_hour?: number | null;
  hour?: number;
}

export interface VehicleInfo {
  id: string;
  name: string;
  class: 'car' | 'suv' | 'pickup' | 'motorcycle' | 'bicycle';
  driving: boolean;
  fuel_l: number;
  tank_l: number;
  cond: number;
  /** litres per map km at the current condition */
  lpk: number;
  repair_cost: number;
  callout_cost: number;
}

export interface FuelStation {
  id: string;
  name: string;
  dry: boolean;
  price: number;
}

export interface VehicleStatus {
  fuel_on: boolean;
  damage_on: boolean;
  steer_on: boolean;
  callout_on: boolean;
  driving: string | null;
  cars: VehicleInfo[];
  at_mechanic: boolean;
  station: FuelStation | null;
  bag_l: number;
  cash: number;
  bank: number;
  traveling: boolean;
  trip: { item: string | null; fuel_before: number; need_l: number; dry_prog: number | null; dry_done: boolean; rain: boolean; saved_s: number; lost_s: number } | null;
  weather: DriveWeather;
}

export interface TripCheck {
  applies: boolean;
  item?: string;
  class?: string;
  fuel_l?: number;
  tank_l?: number;
  need_l?: number;
  short_l?: number;
  enough?: boolean;
  cond?: number;
  wont_start?: boolean;
  bag_l?: number;
  km?: number;
  station?: FuelStation | null;
}

export interface DriveReportStats {
  passes: number;
  gaps: number;
  hits: number;
  offroad: number;
}

export interface DriveReportResult {
  ok: boolean;
  reason?: string;
  saved_s?: number;
  lost_s?: number;
  damage?: number;
  cond?: number;
  arrives_at?: string;
  skid?: boolean;
  message?: string | null;
}

export const driveWeather = () => rpc<DriveWeather>('drive_weather');
export const vehicleStatus = () => rpc<VehicleStatus>('vehicle_status');
export const vehicleTripCheck = (dest: string) => rpc<TripCheck>('vehicle_trip_check', { p_dest: dest });
export const vehicleRefuel = (source: string, qty: number) =>
  rpc<{ message: string; litres: number; cost: number; fuel_l: number; tank_l: number; bad_batch: boolean }>('vehicle_refuel', { p_source: source, p_qty: qty });
export const vehicleRepair = (item?: string | null, callout = false) =>
  rpc<{ message: string; cost: number; cond: number; callout: boolean }>('vehicle_repair', { p_item: item ?? null, p_callout: callout });
/** The steering report: counts only. The server clamps everything and answers with what it granted. */
export const driveReport = (trip: string, stats: DriveReportStats) => rpc<DriveReportResult>('drive_report', { p_trip: trip, p_stats: stats });
