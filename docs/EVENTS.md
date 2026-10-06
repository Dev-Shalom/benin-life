# Events and the map place sheet (L4)

Places have events: Bendel Insurance home matches, club nights, market days, owambe, Nollywood premieres, pool parties.
They are data-driven and computed on the server in real Benin time (WAT). Players see them in four places: the map
place sheet ("On today"), a slim top banner, a badge on the map pin, and event-only action cards inside the place.

Migration `supabase/migrations/20261006001800_events.sql`, tests `supabase/tests/events_test.sql`.

## Server
### Tables (RLS on; clients can only `select`; writes go through admin RPCs and `event_buy_ticket`)
| Table | Columns | Notes |
|---|---|---|
| `place_events` | `id`, `location_id`, `title` (`{variant}` = a different line each week from `variants`, e.g. the opponent), `description`, `kind` (match, concert, club_night, market_day, church, owambe, premiere, party, promo), `icon`, `recurrence` (`weekly` \| `none`), `weekday` (0 = Monday … 6 = Sunday), `start_time` / `end_time` (Benin hours, 21.5 = 9:30 PM; end ≤ start = past midnight), `starts_at` / `ends_at` (a one-off's times; for weekly they optionally bound the season), `ticket_price` (0 = free, no ticket needed), `capacity` (null = no limit), `perks` (`{"effects": {...}, "street_cred": n}`, added to event-only actions), `variants`, `sort`, `active` | Checks: kind / recurrence lists, weekly needs weekday + both times, one-off needs both timestamps (ends after starts). Players can read only active events at active places. |
| `event_tickets` | `event_id`, `user_id`, `occurs_on` (the WAT date the occurrence starts), `price`, `created_at` | `unique (event_id, user_id, occurs_on)`: one ticket per player per occurrence. Players read only their own. |
| `activities.requires_event` | an event `kind` or event `id` | Makes the activity an **event-only card** (below). |

### Occurrences
`bl_event_occurrences(now)` expands every event into occurrences around today (weekly: yesterday, today and tomorrow in
WAT; one-off: its own times). `bl_events_now(location)` keeps the ones that count as **on today**: LIVE now, or starting
today (WAT date) and not over yet, or starting within `events.banner_lead_hours`. One per event. Inactive events and
events at **hidden places never show** (and their tickets can't be bought). Time is `bl_now()`, so tests move it with
`bl.test_offset_seconds`. Events follow the real WAT clock (the game runs `clock.mode = real`).

### RPCs
| Name | What |
|---|---|
| `events_on_today(p_location default null)` | Today's / LIVE events (all places, or one): id, place (name, scene, district), title with this week's variant, description, kind, icon, `occurs_on`, `starts_at`, `ends_at`, `live`, `time_label` ("4 PM – 6 PM"), `starts_label`, `ticket_price`, `free`, `capacity`, `sold`, `has_ticket`, `perks`, `actions` (the event-only cards there). LIVE first, then by start. Signed-in players only. |
| `event_buy_ticket(p_event)` | Buys a ticket for the current occurrence: **bank first, then cash** (like a car), ledger reason `event_ticket`. Refuses: unknown event, hidden place (`inactive`), nothing today (`no_occurrence`), already have one (`already_have`), sold out (`sold_out`, the event row is locked so capacity holds under races), not enough money (`insufficient`). A free event returns `free: true` and charges nothing. Returns the ticket and the updated event. |
| `place_interior` (re-created) | Event-only cards show **only on a day their event is on at that place**: locked "Starts 4 PM" before it, "Needs a ticket" while LIVE without one, open while LIVE with a ticket (or free). The card's effects include the perks and it carries `event {id, title, state, price}`. The interior also returns `events` (today's events here). |
| `do_activity` (re-created) | The same gate (hints `no_event`, `event_later`, `no_ticket`) and the perks added to the effects (+ street cred); returns `event`. |
| `bl_admin_table_spec` / `bl_admin_check_value` (re-created) | Whitelist `place_events` and `activities.requires_event`; new column type `ts_null` (a date-time); `weekday` 0–6, `start_time` / `end_time` 0–24. |
| Helpers (revoked from clients) | `bl_event_occurrences`, `bl_events_now`, `bl_event_json`, `bl_event_access`, `bl_event_title`, `bl_time_label`. |

### Seeded (once per id; edit in admin)
| Event | Where | When | Ticket |
|---|---|---|---|
| Bendel Insurance vs {Enyimba, Rangers, Rivers United, Kano Pillars...} | Samuel Ogbemudia Stadium | Sun 4–6 PM | ₦1,000, 5,000 seats |
| Amapiano Night (two rows, Fri + Sat) | 360 Signature | 10 PM – 4 AM | ₦10,000, 300 |
| Big market day | Oba Market | Sat 7 AM – 6 PM | free |
| Sunday owambe | Golden Tulip Essential | Sun 1–7 PM | free |
| New Nollywood premiere | Kada Plaza (Kada Cinemas) | Fri 6–11 PM | ₦5,000, 120 |
| Pool party | Protea Hotel Emotan | Sat 1–7 PM | ₦15,000, 150 |
| Ladies' Night / Rome Saturday / Owambe Friday | Club De Medici, Rome, Owambe Republic (hidden) | Thu / Sat / Fri nights | stay hidden until the club is switched on |

Event-only cards (zone): Watch the match live + Lead the chant (stadium popular stand), VIP at Amapiano Night (club VIP,
₦80k) + Dance at Amapiano Night (dance floor), Market day bargains (market traders' row), Dance and spray at the owambe +
Party jollof (hotel restaurant), Red carpet premiere (cinema screen), Pool party vibes (hotel pool). Each has bigger
effects than the everyday card, plus the event's perks.

### Config (category `events`)
`events.banner_enabled` (true), `events.banner_lead_hours` (3). See docs/ADMIN.md.

## Client
| Piece | Files |
|---|---|
| API types + calls | `src/api/events.ts` |
| One city-wide list (reload every 3 min, on tab focus, just after the next start / end, after a ticket); `live` re-derived from the server-corrected clock so LIVE flips at kick-off; banner dismissals per session | `src/state/events.ts` |
| "On today" cards (LIVE badge, time, price, Buy ticket / You have a ticket / No ticket needed / Sold out / x left), the top banner, map badges hook | `src/screens/game/Events.tsx` |
| **Map place sheet**: name + type icon + district + description + risk chips (header, kept), open / closed now from the hours, people count (crowd profile + online players), **Share** (copies `/play?place=<id>`), activity chips from the place's cards (event cards first, "+N more"), On today, **travel mode cards** (quoted at once with `travel_quote`: walk, keke, ECTS bus, drop, own car / bicycle / motorcycle; price, time, risk, locked reason) and a big **Go** (`travel_start`). Already there: Go inside, On today here, people and tabs as before. | `src/screens/game/LocationSheet.tsx`, `TravelCards` in `src/screens/game/TravelPicker.tsx` (the old picker stays for the Ride app) |
| Deep link: `/play?place=<id>` opens the map with that place's sheet (hidden place → "closed for now" toast); the param is removed | `src/screens/Game.tsx` |
| Banner: "LIVE: Bendel Insurance vs Enyimba at Ogbemudia Stadium" / "Amapiano Night at 360 Signature starts in 2h"; rotates every 6 s (n/N), × hides that occurrence for the session, tap opens the place sheet (on the map if you're elsewhere). Never for the place you're in (the place card has its own strip). Hidden while the P2 hype ticker or a club hype banner is on screen (hype wins). Phone: under the map chips / the left rail; desktop: under the map chips. | `EventBanner` |
| Map pins: a red **LIVE** pill on the label (soft pulse, none with reduced motion) or a 🎟️ for later today; dots get a small coloured dot. LIVE places label like landmarks in the S3 greedy placement (later-today ones get a small lift), so they show without crowding. The 2D lite map has no badge yet. | `src/art/city3d/engine/CityScene.tsx`, `city3d.css` |
| Inside: a strip on the place card ("LIVE · Bendel Insurance vs … · ⚽ Popular stand ›") jumps to the zone with the event cards; event cards have a red outline and "LIVE · title"; a card that needs a ticket says "Buy a ticket (₦1,000)" and opens the place sheet. | `src/screens/game/PlaceCard.tsx` |
| Admin → Content → **Events** (Active switch per row, ticket price inline, weekday / times / one-off times, perks JSON, variants); Activities gained **Needs event**. Audited by `admin_row_upsert`. | `src/admin/Content.tsx` |

## Check
`bash scripts/sql-test.sh -- supabase/tests/events_test.sql`: 1 weekly recurrence in WAT (LIVE at 4:30 PM Sunday, on today at
10 AM, gone after, nothing on Tuesday, Saturday's club night still LIVE at 2 AM Sunday, 00:30 WAT Sunday counts as Sunday
although UTC is still Saturday, the banner lead) · 2 hidden places' and inactive events never show (RPC, RLS, ticket refused)
· 3 one ticket per occurrence, bank first then cash, next week is a new occurrence, free events charge nothing, not enough
money · 4 capacity · 5 event-only cards hidden without the event, "Starts 4 PM", "Needs a ticket", open with a ticket with
the perks applied, free market day open, gone on Monday, not at another market · 6 admin edits / adds a one-off (audited),
bad weekday / time refused, players can't edit, can't insert tickets, helpers revoked.

## How to add an event
Admin → Content → Events → Add: place id, title, kind, icon, weekly (weekday 0–6 + start / end time) or one-off (starts at /
ends at with the +01 offset), ticket price (0 = free), capacity, perks. For special action cards: add an activity (SQL; the
admin can't insert activities) with `requires_event` = the kind or the event id, then a row in Zone actions for the zone.
