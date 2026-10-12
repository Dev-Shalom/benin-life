// K1: per-club identity (docs/PLACES.md "K1 new clubs"). Clubs share the club scene (zones, kit, props); a
// club listed here gets its own sign colours (3D interior sign + header art neon) and its own light colour
// (room tint + party lamp). Clubs not listed keep the default club look. Pure data, no three.js.

export interface ClubStyle {
  /** Neon colour on the header art sign (src/art/scenes/club.tsx). */
  neon: string;
  /** 3D interior sign board. */
  signBg: string;
  signInk: string;
  /** Room light tint mixed into the ambient + the party lamp colour (src/art/feel/rigs.ts club rig). */
  tint: string;
  lamp: string;
  /** Light pools / beams over the dance floor, bar and VIP (they still drift with the club colour cycle). */
  pool: string;
}

export const CLUB_STYLES: Record<string, ClubStyle> = {
  // Club Raptor & Lounge, Stadium Rd: acid-green raptor neon on black, green/teal room light
  club_raptor: { neon: '#5dff7a', signBg: '#07160c', signInk: '#7dff8f', tint: '#3fbf7a', lamp: '#6cf0a8', pool: '#8dffb4' },
  // Patricia Nightlife, Etete Rd GRA: champagne gold on deep plum, warm amber/rose room light
  patricia_nightlife: { neon: '#ffc94a', signBg: '#2a0f2e', signInk: '#ffd77a', tint: '#d98a3a', lamp: '#ffb36b', pool: '#ffc46b' },
};

const BY_NAME: Record<string, ClubStyle> = {
  'club raptor': CLUB_STYLES.club_raptor,
  'patricia nightlife': CLUB_STYLES.patricia_nightlife,
};

export const clubStyle = (placeId?: string | null): ClubStyle | null => (placeId ? CLUB_STYLES[placeId] ?? null : null);

/** The header art only gets the place name. */
export const clubStyleByName = (name?: string | null): ClubStyle | null =>
  name ? BY_NAME[name.replace(/\s*\(.*\)\s*$/, '').trim().toLowerCase()] ?? null : null;
