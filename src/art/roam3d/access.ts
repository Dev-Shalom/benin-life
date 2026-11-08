// Free roam: who may see the entry buttons (no three.js; used by the game chunk). The server decides for real (roam_start / roam_enter);
// this only hides buttons that could not work: master switch off, area off, or (when the whole city is not open) the place is outside the box.
import { AREA } from './area';

export interface RoamCfg {
  enabled: boolean;
  /** roam.area.all: every active place is open (phase 2). Off: only the box. */
  all: boolean;
  box: { x0: number; y0: number; x1: number; y1: number };
}

export function roamCfg(cfg: <T>(key: string, fallback: T) => T): RoamCfg {
  return {
    enabled: Boolean(cfg('roam.enabled', true)) && Boolean(cfg('roam.area.enabled', true)),
    all: Boolean(cfg('roam.area.all', true)),
    // the legacy box (phase 1 round King's Square), used only when roam.area.all is off
    box: {
      x0: Number(cfg('roam.area.x0', 395)),
      y0: Number(cfg('roam.area.y0', 392)),
      x1: Number(cfg('roam.area.x1', 610)),
      y1: Number(cfg('roam.area.y1', 645)),
    },
  };
}

export function placeInRoam(loc: { x: number; y: number; active?: boolean } | null | undefined, c: RoamCfg): boolean {
  if (!c.enabled || !loc || loc.active === false) return false;
  const x = Number(loc.x), y = Number(loc.y);
  if (c.all) return x >= AREA.x0 && x <= AREA.x1 && y >= AREA.y0 && y <= AREA.y1;
  return x >= c.box.x0 && x <= c.box.x1 && y >= c.box.y0 && y <= c.box.y1;
}

/** Where "Go to King's Square to walk" sends you (only offered when the whole city is not open and you are outside the box). */
export const ROAM_HUB = 'national_museum';
