// Shared vehicle library: which generic model the showroom / garage uses for each luxury slot. The keys are internal ids (kept
// stable for the database); the models are original designs, and the names the player sees are generic (see CAR_NAMES in place3d).
import type { VehicleModel } from './models';

export const LUX_MODEL: Record<string, { model: VehicleModel; paint: string }> = {
  gle63: { model: 'suvlux', paint: '#e9ecef' },
  g63: { model: 'suvbox', paint: '#5d6268' },
  urus: { model: 'suvsport', paint: '#f2c200' },
  cybertruck: { model: 'wedge', paint: '#b9bec4' },
  escalade: { model: 'suvfull', paint: '#2a2c32' },
  c300: { model: 'sedan2', paint: '#1f3a5f' },
  camry: { model: 'sedan', paint: '#8e1b1b' },
};
