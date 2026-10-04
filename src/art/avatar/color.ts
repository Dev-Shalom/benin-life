// Small colour helpers for the avatar renderer. Shadows are tinted toward indigo,
// highlights toward warm cream — never pure black / pure white (five-zone lighting).

export const SHADOW_TINT = '#2a1b4d';
export const DEEP_TINT = '#1a1030';
export const LIGHT_TINT = '#fff1dc';
export const REFLECT_TINT = '#ff9a5c';

function clamp(n: number, lo = 0, hi = 255) {
  return Math.max(lo, Math.min(hi, n));
}

export function isHex(s: unknown): s is string {
  return typeof s === 'string' && /^#[0-9a-fA-F]{6}$/.test(s);
}

export function hexToRgb(hex: string): [number, number, number] {
  const h = isHex(hex) ? hex.slice(1) : '808080';
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

export function rgbToHex(r: number, g: number, b: number): string {
  return '#' + [r, g, b].map((v) => Math.round(clamp(v)).toString(16).padStart(2, '0')).join('');
}

export function mix(a: string, b: string, t: number): string {
  const [r1, g1, b1] = hexToRgb(a);
  const [r2, g2, b2] = hexToRgb(b);
  return rgbToHex(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t);
}

/** Colored (indigo) shadow of a colour. */
export const shade = (c: string, t: number) => mix(c, SHADOW_TINT, t);
/** Warm highlight of a colour. */
export const light = (c: string, t: number) => mix(c, LIGHT_TINT, t);

/** Relative luminance 0..1 */
export function luma(c: string): number {
  const [r, g, b] = hexToRgb(c);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

/** A readable accent that contrasts with a fabric colour (gold on most, teal on yellows). */
export function accentFor(c: string): string {
  const [r, g, b] = hexToRgb(c);
  const yellowish = r > 170 && g > 130 && b < 110;
  if (yellowish) return '#1f6f8b';
  if (luma(c) > 0.82) return '#c8901f';
  return '#e8b13a';
}

/** Deep version of a fabric colour for prints / trims. */
export function deepOf(c: string): string {
  return luma(c) < 0.12 ? '#4a4560' : shade(c, 0.55);
}
