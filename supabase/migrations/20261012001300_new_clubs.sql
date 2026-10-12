-- K1 "New clubs" (docs/PLACES.md "K1 new clubs", docs/LANDMARKS.md).
-- * Two real Benin City nightclubs, wired exactly like the other clubs (scene 'club' = the club zones, cards,
--   hype, crowd, chat, interior; bottles + Star at the bar; their own mood line, DJ and weekly club night):
--     club_raptor        Club Raptor & Lounge, 60 Stadium Rd, Ogogugbo (near Samuel Ogbemudia Stadium)
--     patricia_nightlife Patricia Nightlife, 35 Etete Rd, GRA
--   Both open 10 PM - 5 AM (the other clubs close at 5 AM). Hours are per place (no per-weekday schedule),
--   so they open every night; Fri/Sat are busier through the existing weekend crowd profiles + club nights.
-- * Weekend club prices: on Friday and Saturday NIGHTS (Benin time; a night belongs to the day it started, so
--   Sat 01:00 is still Friday night; the night rolls over at club.night_rollover_hour, default noon) every
--   club price (activities: entry, drinks, VIP table, shout-out, shut down...; shop: bottles, Star) is
--   multiplied by club.weekend_price_mult (default 1.5), server-side, in do_activity / shop_buy (what you pay),
--   place_interior / shop_list / club_prices (what you see, with a `weekend` flag for the badge).
--   club.weekend_exempt (csv of activity/item ids) keeps some prices as they are (spraying money, the restroom).
--   Set the multiplier to 1 to switch it off.
-- Idempotent and safe on a non-empty DB: seeds use "on conflict do nothing" (admin edits survive a re-run),
-- array appends are guarded, functions are patched from their live definitions with guarded replacements
-- (create or replace keeps the grants).

-- ---------------------------------------------------------------------
-- 1. Config (category club)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('club.weekend_price_mult', '1.5', 'club', 'Weekend club prices (x)',
 'On Friday and Saturday nights every club price (entry, drinks, VIP table, shout-out, bottles...) is multiplied by this. 1 = same price every night.',
 'number', 1, 5),
('club.weekend_exempt', '"spray_money,ease_yourself"', 'club', 'Not marked up on weekends',
 'Comma-separated activity / item ids that keep their normal price on weekend nights (spraying money, the restroom).',
 'text', null, null),
('club.night_rollover_hour', '12', 'club', 'Club night ends at (hour)',
 'A club night belongs to the day it started until this hour the next day (12 = noon: Sat 1 AM still counts as Friday night).',
 'number', 0, 23)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. The two clubs
-- ---------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active) values
('club_raptor', 'Club Raptor', 'ekenwan', 'club',
 'Club Raptor & Lounge, 60 Stadium Rd, Ogogugbo, close to Ogbemudia Stadium. Loud dance floor inside, a quiet lounge side for people wey no want noise.',
 .30, 1.7, true, true, 1.2, 0, 352, 562, '{activities,shop}', 58, 22, 5, true),
('patricia_nightlife', 'Patricia Nightlife', 'gra', 'club',
 'Patricia Nightlife, 35 Etete Rd, GRA. Theme nights, table bookings by DM and live PA on weekends.',
 .15, 1.4, true, false, 1.1, 0, 520, 686, '{activities,shop}', 59, 22, 5, true)
on conflict (id) do nothing;

-- bar: bottles + cold Star like the other clubs (guarded append)
update public.items set sold_at = sold_at || array['club_raptor']
 where id in ('club_bottle', 'star_beer') and not ('club_raptor' = any (sold_at));
update public.items set sold_at = sold_at || array['patricia_nightlife']
 where id in ('club_bottle', 'star_beer') and not ('patricia_nightlife' = any (sold_at));

-- the house DJ of the other clubs plays here too
update public.npc_roster set location_ids = location_ids || array['club_raptor']
 where id = 'dj_uyi' and not ('club_raptor' = any (location_ids));
update public.npc_roster set location_ids = location_ids || array['patricia_nightlife']
 where id = 'dj_uyi' and not ('patricia_nightlife' = any (location_ids));

-- their own mood lines (the club type's lines show too)
insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
  ('club_raptor.1', null, 'club_raptor', 'night', '🦖', 'Raptor neon is glowing green over the dance floor', 1),
  ('club_raptor.2', null, 'club_raptor', 'night', '🛋️', 'The lounge side is chilling, the floor side is shaking', 2),
  ('patricia_nightlife.1', null, 'patricia_nightlife', 'night', '✨', 'Theme night at Patricia: everybody dressed to code', 1),
  ('patricia_nightlife.2', null, 'patricia_nightlife', 'night', '🎤', 'Live PA on the stage: the crowd knows every word', 2)
on conflict (id) do nothing;

-- weekly club nights (the event-only club cards light up during them)
insert into public.place_events (id, location_id, title, description, kind, icon, recurrence, weekday, start_time, end_time,
                                 ticket_price, capacity, perks, variants, sort)
select v.id, v.loc, v.title, v.descr, 'club_night', v.icon, 'weekly', v.wd, 22, 4, v.price, v.cap, v.perks::jsonb, '', v.sort
  from (values
  ('raptor_saturday', 'club_raptor', 'Raptor Saturday', 'Saturday at Club Raptor, Stadium Rd: afrobeats on the floor, shisha on the lounge side.', '🦖', 5, 10000, 300,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 2}', 73),
  ('patricia_friday', 'patricia_nightlife', 'Patricia Theme Friday', 'Friday theme night at Patricia Nightlife, Etete Rd GRA. Dress code on, tables booked.', '✨', 4, 10000, 250,
   '{"effects": {"fun": 15, "social": 15}, "street_cred": 2}', 74)
  ) as v(id, loc, title, descr, icon, wd, price, cap, perks, sort)
 where exists (select 1 from public.locations where id = v.loc)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Weekend price helpers (server-only)
-- ---------------------------------------------------------------------
-- Friday or Saturday night at p_at (Benin clock; weekday 0 = Monday, 4 = Friday, 5 = Saturday).
create or replace function public.bl_club_weekend(p_at timestamptz default null) returns boolean
language plpgsql stable set search_path = public as $$
declare
  c   jsonb := bl_game_clock(p_at);
  wd  int := (c->>'weekday')::int;
  h   int := (c->>'hour')::int;
  ro  int := greatest(0, least(23, coalesce(bl_cfg('club.night_rollover_hour'), 12)))::int;
begin
  if h < ro then wd := (wd + 6) % 7; end if;   -- before the rollover it is still the night before
  return wd in (4, 5);
end $$;

-- The multiplier for one activity / item at one place right now (1 = normal price).
create or replace function public.bl_club_price_mult(p_loc public.locations, p_ref text) returns numeric
language plpgsql stable set search_path = public as $$
declare m numeric;
begin
  if p_loc.id is null or p_loc.scene is distinct from 'club' then return 1; end if;
  m := greatest(1, least(5, coalesce(bl_cfg('club.weekend_price_mult'), 1)));
  if m = 1 or not bl_club_weekend() then return 1; end if;
  if bl_csv_has(bl_cfg_text('club.weekend_exempt'), p_ref) then return 1; end if;
  return m;
end $$;

-- What a club price is right now: base x the weekend multiplier, rounded to ₦50 (₦10 under ₦1,000).
create or replace function public.bl_club_price(p_loc public.locations, p_ref text, p_base bigint) returns bigint
language plpgsql stable set search_path = public as $$
declare m numeric;
begin
  if coalesce(p_base, 0) <= 0 then return coalesce(p_base, 0); end if;
  m := bl_club_price_mult(p_loc, p_ref);
  if m = 1 then return p_base; end if;
  if p_base * m < 1000 then return (round(p_base * m / 10.0) * 10)::bigint; end if;
  return (round(p_base * m / 50.0) * 50)::bigint;
end $$;

-- Is the weekend markup on at this place right now (for the "Weekend price" badge)?
create or replace function public.bl_club_weekend_on(p_loc public.locations) returns boolean
language sql stable set search_path = public as $$
  select coalesce(p_loc.scene = 'club', false)
     and greatest(1, least(5, coalesce(bl_cfg('club.weekend_price_mult'), 1))) > 1
     and bl_club_weekend()
$$;

revoke execute on function public.bl_club_weekend(timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_club_price_mult(public.locations, text) from public, anon, authenticated;
revoke execute on function public.bl_club_price(public.locations, text, bigint) from public, anon, authenticated;
revoke execute on function public.bl_club_weekend_on(public.locations) from public, anon, authenticated;

-- Client: today's prices of every activity at a place (the Activities tab reads the activities table, so it
-- asks the server for the price to show). Only places whose scene is 'club' can differ.
create or replace function public.club_prices(p_location text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  l     locations := bl_location(p_location);
begin
  return jsonb_build_object(
    'location', l.id,
    'weekend', bl_club_weekend_on(l),
    'mult', case when bl_club_weekend_on(l) then greatest(1, least(5, bl_cfg('club.weekend_price_mult'))) else 1 end,
    'activities', coalesce((
      select jsonb_object_agg(a.id, jsonb_build_object(
               'cost', bl_club_price(l, a.id, case when a.id = 'shut_down_club'
                                                   then greatest(0, round(bl_cfg('hype.shutdown_cost')))::bigint else a.cost end),
               'base', a.cost))
        from activities a where l.scene = any (a.scenes)), '{}'::jsonb));
end $$;
revoke execute on function public.club_prices(text) from public, anon;
grant execute on function public.club_prices(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Patch the live functions (guarded string replacements)
-- ---------------------------------------------------------------------
create or replace function pg_temp.k1_patch(p_sig text, p_old text, p_new text, p_marker text) returns void
language plpgsql as $$
declare src text; out text;
begin
  src := pg_get_functiondef(p_sig::regprocedure);
  if position(p_marker in src) > 0 then return; end if;          -- already patched
  if position(p_old in src) = 0 then
    raise exception 'K1: % has changed: expected text not found: %', p_sig, left(p_old, 120);
  end if;
  out := replace(src, p_old, p_new);
  execute out;
end $$;

-- do_activity: the price you pay
select pg_temp.k1_patch('public.do_activity(text)',
  E'  select * into v_loc from locations where id = v_me.location_id;\n  v_scene := v_loc.scene;\n',
  E'  select * into v_loc from locations where id = v_me.location_id;\n  v_scene := v_loc.scene;\n'
  || E'  -- K1: club weekend prices (Fri/Sat nights, club.weekend_price_mult)\n'
  || E'  a.cost := bl_club_price(v_loc, a.id, a.cost);\n',
  'bl_club_price(v_loc, a.id, a.cost)');

-- shop_buy: the price you pay (bottles, Star at a club)
select pg_temp.k1_patch('public.shop_buy(text,integer)',
  'v_total := bl_dealer_price(it, l.id) * p_qty;',
  'v_total := bl_club_price(l, it.id, bl_dealer_price(it, l.id)) * p_qty;  -- K1: club weekend prices',
  'bl_club_price(l, it.id');

-- shop_list: the price you see + weekend flag
select pg_temp.k1_patch('public.shop_list(text)',
  E'''price'', bl_dealer_price(it, l.id), ''base_price'', it.price,',
  E'''price'', bl_club_price(l, it.id, bl_dealer_price(it, l.id)), ''base_price'', it.price, '
  || E'''weekend'', bl_club_price(l, it.id, bl_dealer_price(it, l.id)) <> bl_dealer_price(it, l.id),',
  'bl_club_price(l, it.id');
select pg_temp.k1_patch('public.shop_list(text)',
  E'''affordable'', v_me.cash >= bl_dealer_price(it, l.id))',
  E'''affordable'', v_me.cash >= bl_club_price(l, it.id, bl_dealer_price(it, l.id)))',
  E'v_me.cash >= bl_club_price(');
select pg_temp.k1_patch('public.shop_list(text)',
  E'''cash'', v_me.cash,',
  E'''cash'', v_me.cash, ''weekend_price'', bl_club_weekend_on(l),',
  'bl_club_weekend_on(l)');

-- place_interior: card prices + weekend flags
select pg_temp.k1_patch('public.place_interior(text)',
  E'''cost'', a.cost, ''effects'', case when ev.acc is null',
  E'''cost'', bl_club_price(l, a.id, a.cost), ''weekend'', bl_club_price(l, a.id, a.cost) <> a.cost, ''effects'', case when ev.acc is null',
  'bl_club_price(l, a.id, a.cost)');
select pg_temp.k1_patch('public.place_interior(text)',
  E'''cost'', bl_dealer_price(it, l.id), ''effects'', it.effects,',
  E'''cost'', bl_club_price(l, it.id, bl_dealer_price(it, l.id)), '
  || E'''weekend'', bl_club_price(l, it.id, bl_dealer_price(it, l.id)) <> bl_dealer_price(it, l.id), ''effects'', it.effects,',
  'bl_club_price(l, it.id');
select pg_temp.k1_patch('public.place_interior(text)',
  E'''night'', v_night, ''part'', v_part,',
  E'''night'', v_night, ''part'', v_part, ''weekend_price'', bl_club_weekend_on(l),',
  'bl_club_weekend_on(l)');

notify pgrst, 'reload schema';
