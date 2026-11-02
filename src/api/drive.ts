// Drive scene RPCs (server: 20261114000100_drive.sql, docs/DRIVE.md). The server rolls every road event and applies the
// result; the client only shows the card and the outcome.
import { rpc } from '../lib/api';

export type DriveKind = 'ambush' | 'police' | 'goslow' | 'beggar';

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
