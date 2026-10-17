# Club switch (R2)

The owner can switch each nightclub on or off in **Admin -> Content -> Clubs**, so the few players there are gather in one or two clubs and the place feels full. Migration `20261017000200_club_switch.sql`, test `supabase/tests/club_switch_test.sql`.

## How it works
- There is no new column: the switch is `locations.active` (the F1 soft-launch flag). All clubs are ON by default; nothing changes until a switch is flipped.
- A club that is OFF is "Closed for now":
  - Map: the pin stays, greyed, with a "Closed for now" tag (3D map pill and SVG lite map). Place sheet and place card say "Closed for now".
  - Server: travel, activities, shop, spray, tickets and shifts are refused with "<Club> is closed for now. Check back soon." (hint `inactive`). This is the existing `bl_place_open` / `bl_assert_place_open` logic, so nothing else needed patching.
  - Events: `bl_events_now` / `events_on_today` skip events at an inactive place, so there is no banner or pin badge, and `event_buy_ticket` is refused. The events themselves are not deleted: they come back when the club is ON again.
- RLS: `locations_read` now also lets players read an OFF club (otherwise the pin would vanish). Other hidden places stay hidden. The five clubs hidden by the F1 soft launch (Medici, Rome, Cube, Versus, Owambe Republic) therefore show as "Closed for now" pins.
- Players inside when a club is switched off:
  - Idle players (not travelling, not busy) are sent home at once with a `place_closed` alert.
  - Busy players are sent home by `place_closed_eject()` (called by the client, the same closed-hours logic) as soon as they are free. The alert says "closed for now" instead of "opens again at ...".
  - Until then they can't act (all actions are refused).

## Admin
- `admin_club_list()`: every club with ON/OFF, hours, who is inside and how many events. `admin_club_set(id, on)`: the switch. Only clubs (scene `club`) can be switched here; the Places editor still edits `active` per place.
- Each real change writes `admin_audit` action `club_switch` (`name`, `on`, `moved_home`), shown in the Audit tab. Switching to the state it is already in changes and logs nothing.
