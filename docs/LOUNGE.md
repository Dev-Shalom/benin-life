# R7: Friends tab and the Members' Lounge

Migration `supabase/migrations/20261018000400_friends_lounge.sql` · tests `supabase/tests/friends_lounge_test.sql` (14 groups) ·
client `src/api/friends.ts`, `src/api/lounge.ts`, `src/state/lounge.ts`, `src/screens/game/phone/FriendsTab.tsx` + `.css`,
`src/screens/game/Lounge.tsx` + `.css` (membership sheet, pass strip), `src/art/scenes/lounge.tsx` (header art), `pool_table` prop in
`src/art/place3d` · admin: Content -> Lounge tiers, Settings -> Lounge, Players -> detail -> The Lounge · hooks: `SocialApp.tsx` (the Friends tab),
`Overlays.tsx` ("Go there" on invite alerts), `PlaceCard.tsx`, `LocationSheet.tsx`, `Game.tsx`, `lib/sound.ts`, map pins.

Everything is server-authoritative and tunable. Copy is English with a little Pidgin.

## A. Friends tab (Phone -> Messages -> Friends)

Built on `player_friendships` and the `social_*` RPCs. Nothing is duplicated: add, accept, decline, cancel, message and house invites are the
existing RPCs.

### What the player sees
- Search box "Add a friend: @username" (`social_search_players`, `SocialPlayerButton`). 16px font, same `.msgs-input` pattern as the rest of Messages
  (docs/MOBILE_INPUT.md).
- **Requests** on top: incoming with Accept / Decline; sent ones at the bottom with Cancel.
- Friends sorted **online first**, then by last seen. Green dot = active in the last `friends.online_seconds` (120). Offline shows "last seen 3h ago".
- Where they are: the place name (green), "At home", "On the road", or "Location hidden". Offline friends show no location (it would be stale).
- Quick actions on each card:
  - **Message** opens the DM.
  - **Join them**: only when the friend is online, shares their location and is at a public, open place you may enter. Opens the map sheet of that
    place on the travel picker, so you choose how to go. At the lounge without a pass it reads **Get pass to join** and opens the membership sheet.
  - **Invite here**: only while you stand at a public open place. Sends an alert and a push.
  - **Invite home**: only when you have a home. Reuses `social_send_house_invite` (24 h invite, knock, let in).
  - **Yahoo group**: only when the friend is online with a laptop, at a valid Yahoo spot and not in a group. Opens the Yahoo app (the group flow lives there).
  - **Bring to Lounge**: only for a VIP with a free guest slot.
- Switch at the bottom: **Show my location to friends** (default on).

### One cheap RPC, polled only while open
`friends_overview()` (stable, security definer) returns everything: `me` (privacy, home chosen, whether I can invite from here), `requests`,
`friends[]` (card with online, last_seen, location, join flags and reason, yahoo_ready, house_invite, conversation id, unread). The tab polls it
through `startPoller` from `src/lib/realtime.ts` (jittered, only while the browser tab is visible, stops on unmount) every `friends.poll_seconds`
(20), and refreshes at once when a new alert arrives on the existing events channel. Closed tab = zero calls. The RPC is in the read-RPC list in
`src/lib/api.ts` (deduped and retried).

### Privacy
`profiles.share_location_friends boolean default true`, set with `friends_set_privacy(bool)`. When off, the server sends no place for that player
(no id, no name) and `can_join` is false with hint `hidden`; the online dot still shows.

### Invite to a place
`friend_invite_place(friend)`: friends only, you must stand at a public open place (not a home, not on the road; the lounge needs a pass).
Writes an alert (`events.kind = 'place_invite'`, data `{location_id, from, place}`) titled "@x wants you at 360 Signature" and a push through
`bl_push_enqueue` in the `friends` category with url `/play?go=place:<id>`. Tapping the push opens that place's map sheet with the travel picker.
In the Alerts app the invite has a **Go there** button doing the same. Cooldown `friends.invite_cooldown_seconds` (60) per friend.
Refusals (hint): `not_friend`, `travelling`, `private`, `closed`, `same`, `cooldown`, `no_membership`.

### Join
`friend_join_check(friend)` raises with the reason when the friend is offline, hides their location, is on the road, is at a private home, the
place is closed or switched off (`inactive`), you are already there (`same`) or it is the lounge and you have no pass (`no_membership`). The
travel itself is the normal `travel_start`, so every other rule (money, closed hours, lounge entry) still applies there. Arriving where a friend
stands already counts for the R5 `friend_meet` challenge goal.

## B. The Members' Lounge

**The Lounge, GRA** (`members_lounge`, scene `lounge`, map 412,688 in GRA, west of the duplex estate). **Open all day** (no hours). Pin and
3D pill carry an "Open all day" tag. Fictional name, no real brand.

### Interior (existing parts)
Zones (all admin-editable in Content -> Place zones / Place zone actions, scene `lounge`): Bar (bar), Network corner (tables), Sofas (couches),
Pool table (new `pool_table` prop, boxes and cylinders only), VIP cabana (vip booth), Restroom. Soft warm light (`lounge` rig in
`src/art/feel/rigs.ts`), dark wood kit with gold trim. Crowd: 3 to 12 named background people by hour (`crowd_profiles` rows `lounge.*`, 5 roster
people). Location chat works as at any place (the Sofas card opens it).

### Sound and music
Place sound `lounge` (the calm hotel-lounge groove) plays. The club music system covers the lounge too: Admin -> Music lists it next to the clubs
and a playlist assigned there plays as a radio (`club_music_for` resolves it; no default playlist, only clubs fall back to the default).

### Membership
Entry needs a pass. Tiers are rows of the admin table `lounge_tiers` (Content -> Lounge tiers):

| Tier | Price | Lasts | Discount | Gold tag | Free drink | Extras |
|---|---|---|---|---|---|---|
| Day pass | ₦5,000 | 24 hours | 0% | no | 0 | |
| Monthly Member | ₦150,000 | 30 days | 15% | yes | 1 | |
| VIP | ₦1,000,000 | 30 days | 30% | yes | 1 | VIP cabana and mixer, 1 free guest, needs Charisma lvl 3 OR any certificate |

- Buy, renew and upgrade in the sheet (`lounge_status()`, `lounge_buy(tier)`). Paid from the bank first (setting), then cash. Ledger `reason = 'lounge'`
  (label "The Lounge: Monthly Member"), one row per account used. Two taps: the second says "Tap again to pay".
- Same tier again = **Renew**: the time is added on top, never more than `lounge.max_stack_days` (90) from now. A higher tier **upgrades** (the new
  pass starts now, no credit for the old). A lower tier while a better one is active is refused (`have_better`).
- Expiry is by real time (`expires_at`). After it: travel, every card and the shop refuse with "members only"; the sheet and the place card show
  "Your pass ended" and a Renew button. A player already inside is not stuck (Map and Home still work).
- VIP requirement: per tier `req_charisma_level` (0 = none) OR `req_any_cert`; both off = open. `lounge.requirements_enabled` switches the check
  off for every tier. The sheet shows the requirement and "you qualify".

### Perks
- **Drinks discount**: every price in the lounge goes through `bl_club_price`, so activities, shop items, the card prices and the receipt all agree.
  Rounded to ₦10 under ₦1,000, else ₦50.
- **VIP zone**: activities in `lounge.vip_activities` (default `lounge_vip_suite`, `lounge_vip_network`) and shop items in `lounge.vip_items` refuse
  non-VIP with "VIP only"; the cards show a lock. Guests only get the VIP zone when `lounge.guest_vip` is on (default off).
- **Gold name tag**: `players_here` returns `gold`; the 3D name pill turns gold (needs `lounge.gold_tag` and the tier's tag).
- **Monthly free drink voucher**: each purchase adds `lounge_tiers.vouchers` vouchers (stack up to `lounge.max_vouchers`, 3). The first time a member
  does an activity in `lounge.voucher_activities` (default the cocktail) it costs nothing and uses one.
- **VIP guest**: `lounge_bring_guest(friend)` (Friends tab "Bring to Lounge"): a friend gets a guest pass for `lounge.guest_pass_hours` (12), one
  active guest at a time per VIP. The guest gets an alert and a friends push "@x wants you at The Lounge, GRA" and can enter and use the main lounge.

### Activities (all existing zone actions and `do_activity` / `shop_buy`)
Signature cocktail ₦6,000, small chops ₦4,500, pool ₦2,000, network ₦2,500 (trains **charisma** through `skill_sources`, 4 XP), VIP cabana + bottle
₦120,000, VIP mixer ₦15,000 (8 charisma XP), Star and champagne from the bar, restroom. All prices are rows in Content -> Activities.

### Hype
The club hype announcements are reused: a VIP cabana or a bottle bought in the lounge is announced like a club spend (`lounge.hype`). Settings ->
Hype (cooldowns, the global ticker minimum) apply.

## Admin
- Content -> **Lounge tiers**: every field, add tiers, Active switch (an inactive tier is hidden; holders keep it).
- Content -> Place zones / Place zone actions (type `lounge`), Activities, Skill sources, Crowd profiles: the lounge is ordinary data.
- Settings -> **Lounge** (`lounge.*`) and Settings -> social (`friends.*`).
- Players -> detail -> **The Lounge**: tier, expiry, vouchers, source; **Grant membership** (free, optional hours, audited `lounge_grant`) and
  **Remove** (audited `lounge_revoke`). A grant costs the player nothing and writes no ledger row.
- Admin -> Music: assign a playlist to the lounge.

## Defaults the owner should know
- Day pass ₦5,000 / 24 h, Monthly ₦150,000 / 30 d, VIP ₦1,000,000 / 30 d. Bank is charged first, so a rich-in-bank player pays without carrying cash.
- VIP is the only gated tier: Charisma level 3 OR any certificate. Players with neither can still buy Monthly.
- The gold tag goes to Monthly and VIP; the day pass has no discount and no tag.
- The VIP cabana (₦120,000, ₦84,000 for a VIP) is a big money sink and shows in the hype ticker above ₦500,000 only (hype.global_min), so it announces in the
  lounge but rarely on the city ticker.
- Upgrades do not credit the unused time of the old pass.
- Friends tab polls every 20 s while open, nothing while closed. "Online" = active in the last 2 minutes.
- Location sharing is on by default; offline friends never show a place.
- "Join them" and the invite push open the place's map sheet (pick how to travel, then Go), they do not auto-start a trip.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/friends_lounge_test.sql`: grants and RLS flags (every new RPC and private helper), `friends_overview` (online window
and its setting, last seen, hidden location, at home, privacy, pending, order), place invite (alert, push in the friends category, cooldown, refusals),
join refused (closed, inactive, private, hidden, offline, same, travelling), seeds, buy each tier (bank first, ledger kind `lounge`), entry refused
without a pass (travel, activity, shop), expiry (time travel), renew / stack cap / upgrade rules, VIP requirement (charisma, certificate, switches),
discount and voucher, VIP zone gate, guest pass, admin grant / revoke + audit + tiers editor, gold tag, interior block, open all day, hype, music.
