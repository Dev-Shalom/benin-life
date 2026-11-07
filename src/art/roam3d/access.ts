// Free roam: who may see the entry buttons (no three.js; used by the game chunk). The server decides for real (roam_start / roam_enter);
// this only hides buttons that could not work: master switch off, area off, or the place is not inside the phase 1 box.
import { AREA } from './area';

export interface RoamCfg {
  enabled: boolean;
  box: { x0: number; y0: number; x1: number; y1: number };
}

export function roamCfg(cfg: <T>(key: string, fallback: T) => T): RoamCfg {
  return {
    enabled: Boolean(cfg('roam.enabled', true)) && Boolean(cfg('roam.area.enabled', true)),
    box: {
      x0: Number(cfg('roam.area.x0', AREA.x0)),
      y0: Number(cfg('roam.area.y0', AREA.y0)),
      x1: Number(cfg('roam.area.x1', AREA.x1)),
      y1: Number(cfg('roam.area.y1', AREA.y1)),
    },
  };
}

export function placeInRoam(loc: { x: number; y: number; active?: boolean } | null | undefined, c: RoamCfg): boolean {
  if (!c.enabled || !loc || loc.active === false) return false;
  const x = Number(loc.x), y = Number(loc.y);
  return x >= c.box.x0 && x <= c.box.x1 && y >= c.box.y0 && y <= c.box.y1;
}

/** Where "Go to King's Square to walk" sends you. */
export const ROAM_HUB = 'national_museum';
