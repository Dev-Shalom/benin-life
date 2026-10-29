-- Filling stations and the black market (docs/POWER.md, part 2). Needs 20261104000100_power.sql.
--   GOOD SIDE: seven filling stations on the map (places, scene motorpark, a normal shop panel). They sell petrol and diesel
--     (litres and jerrycans). The price is bl_fuel_price (daily move, scarcity). A player-owned Filling station business
--     (business_types.filling_station, same scene) sells the same shelf, so the existing visitor cut pays its owner.
--   BAD SIDE: a hidden place (bm_yard). Not on the map until the player has street cred or is in a crew (RLS on locations).
--     Opens at night only (admin hours). Grey fuel (cheap, may be adulterated), tokunbo gear (cheap, may be faulty),
--     with a scam, police raid (existing crime system: jail_cases), robbery and a street-cred change on every deal.
-- No profiles DDL, no loops over players. Idempotent.

create or replace function pg_temp.fm_patch(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n <> 1 then raise exception 'fuel_market: % : marker found % times: %', p_sig, v_n, left(p_marker, 90); end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('blackmarket.enabled', 'true', 'blackmarket', 'Black market on', 'Off = the yard vanishes from the map and every deal is refused.', 'bool', null, null),
('blackmarket.unlock_cred', '20', 'blackmarket', 'Unlock: street cred needed', 'A player with this much street cred hears about the yard and sees it on the map. (The other way in is belonging to a crew.)', 'number', 0, 1000),
('blackmarket.crew_unlocks', 'true', 'blackmarket', 'Unlock: crew members get in', 'Anybody who belongs to a crew can find the yard even without the street cred.', 'bool', null, null),
('blackmarket.open_hour', '21', 'blackmarket', 'Opens at (Benin hour)', 'The yard opens at this hour. 21 = 9 PM.', 'number', 0, 24),
('blackmarket.close_hour', '5', 'blackmarket', 'Closes at (Benin hour)', 'The yard shuts at this hour (the next morning when it is smaller than the opening hour).', 'number', 0, 24),
('blackmarket.fuel_mult', '0.8', 'blackmarket', 'Grey fuel price (x the station price)', 'On a normal day grey fuel costs this share of the station price (the same daily move applies).', 'number', 0.1, 5),
('blackmarket.fuel_scarcity_mult', '1.9', 'blackmarket', 'Grey fuel price in a scarcity (x the base price)', 'During a fuel scarcity grey fuel is dearer than the already dear stations, but always in stock.', 'number', 0.1, 10),
('blackmarket.scam_pct', '6', 'blackmarket', 'Deal: chance of a scam (%)', 'The seller takes the money and vanishes. Nothing is delivered.', 'percent', 0, 100),
('blackmarket.raid_pct', '4', 'blackmarket', 'Deal: chance of a police raid (%)', 'Police burst in: a jail case (the usual bail, jail and escape choices) and wanted +1. No money changes hands.', 'percent', 0, 100),
('blackmarket.robbery_pct', '6', 'blackmarket', 'Deal: chance of a robbery on the way out (%)', 'Boys take the goods and a share of your cash.', 'percent', 0, 100),
('blackmarket.robbery_cash_pct', '5', 'blackmarket', 'Robbery: % of your cash taken as well', 'On top of the goods. Never more than the robbery cap below.', 'percent', 0, 100),
('blackmarket.robbery_cash_cap', '200000', 'blackmarket', 'Robbery: most cash taken', 'The cash part of a robbery never goes over this.', 'naira', 0, 100000000),
('blackmarket.hot_night_pct', '8', 'blackmarket', 'Police patrol the yard: chance per night (%)', 'On a hot night (fixed by the date) the yard stays open but raids are likelier. Players see "police dey around".', 'percent', 0, 100),
('blackmarket.hot_raid_mult', '4', 'blackmarket', 'Hot night: raid chance multiplier', 'The raid chance is multiplied by this on a hot night.', 'number', 1, 20),
('blackmarket.crew_raid_cut_pct', '40', 'blackmarket', 'Crew protection: raid chance cut (%)', 'A crew member pays for protection: the raid chance is cut by this much.', 'percent', 0, 100),
('blackmarket.cred_gain', '1', 'blackmarket', 'Street cred gained on a clean deal', 'A deal that works builds a little name in the yard.', 'number', 0, 20),
('blackmarket.cred_raid_loss', '3', 'blackmarket', 'Street cred lost in a raid', 'Taken when police catch you at the yard.', 'number', 0, 100),
('blackmarket.cred_scam_loss', '0', 'blackmarket', 'Street cred lost when scammed', 'Being scammed is embarrassing. 0 = no loss.', 'number', 0, 100),
('blackmarket.max_qty', '20', 'blackmarket', 'Most units per deal', 'Litres of fuel or pieces of gear in one deal.', 'number', 1, 200),
('blackmarket.faulty_batt_pct', '60', 'blackmarket', 'Faulty tokunbo battery: health left (%)', 'A faulty second-hand battery or inverter holds only this much until a mechanic services it.', 'percent', 10, 100),
('blackmarket.faulty_days', '30', 'blackmarket', 'Faulty tokunbo generator: days until it stops coughing', 'A faulty generator burns extra fuel until repaired, or for this many real days.', 'number', 1, 365)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Places: seven filling stations and the hidden yard
-- ---------------------------------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active)
values
('fs_sapele',    'Sapele Road Filling Station',   'sapele_rd',   'motorpark', 'Pumps under a big canopy on the busy Sapele Road. Petrol, diesel and jerrycans for generators.', 0.15, 1.6, true,  true, 1.4, 0, 640, 610, '{shop}', 400, null, null, true),
('fs_airport',   'Airport Road Filling Station',  'airport_rd',  'motorpark', 'The airport-side station: quicker queues, same price. Petrol, diesel and cans.', 0.15, 1.6, true,  true, 1.2, 0, 300, 570, '{shop}', 401, null, null, true),
('fs_ring_road', 'Ring Road Filling Station',     'oredo',       'motorpark', 'Always busy. The attendants know every okada boy by name. Petrol, diesel and cans.', 0.2, 1.8, true,  true, 1.6, 0, 520, 395, '{shop}', 402, null, null, true),
('fs_uselu',     'Uselu Filling Station',         'uselu',       'motorpark', 'Near the campus road: students with jerrycans for the hostel generator.', 0.2, 1.8, true,  true, 1.3, 0, 430, 350, '{shop}', 403, null, null, true),
('fs_ugbowo',    'Ugbowo Filling Station',        'ugbowo',      'motorpark', 'Beside the UNIBEN road. Petrol, diesel and cans for the lecturers'' generators.', 0.2, 1.8, true,  true, 1.3, 0, 500, 160, '{shop}', 404, null, null, true),
('fs_ikpoba',    'Ikpoba Hill Filling Station',   'ikpoba_hill', 'motorpark', 'Up on the hill. When fuel is scarce the queue reaches the junction.', 0.2, 1.8, false, true, 1.2, 0, 745, 415, '{shop}', 405, null, null, true),
('fs_new_benin', 'New Benin Filling Station',     'new_benin',   'motorpark', 'Off Mission Road, close to the market. Petrol, diesel and cans.', 0.2, 1.8, true,  true, 1.3, 0, 690, 350, '{shop}', 406, null, null, true),
('bm_yard',      'The Yard (Ogida timber sheds)', 'ogida',       'street',    'Behind the timber sheds at Ogida. No sign, no receipt, nobody asks your name. Opens after dark.', 0.5, 2.5, false, false, 1.0, 0, 230, 470, '{}', 900, null, null, true)
on conflict (id) do nothing;

-- the stations sell the fuel items; a player-owned Filling station (same scene) sells them too through bl_biz_sells
update public.items set sold_at = (select array_agg(id order by sort) from public.locations where id like 'fs\_%')
 where id in ('petrol', 'petrol_can', 'diesel', 'diesel_can') and coalesce(cardinality(sold_at), 0) = 0;

-- the yard is hidden from players who have not earned their way in (the map and every place list read this policy)
drop policy if exists locations_read on public.locations;
create policy locations_read on public.locations for select to anon, authenticated
  using (((private_home_owner_id is null) and (coalesce(active, true) or (scene = 'club'))
          and (id not like 'bm\_%' or (select public.bl_bm_unlocked((select auth.uid())))))
         or public.bl_social_can_view_private_home(id, private_home_owner_id));

-- ---------------------------------------------------------------------------------------------
-- 3. Black market catalogue and per-deal state
-- ---------------------------------------------------------------------------------------------
create table if not exists public.bm_offers (
  id        text primary key check (id ~ '^[a-z0-9_]{2,32}$'),
  name      text not null,
  emoji     text not null default '📦',
  blurb     text not null default '',
  kind      text not null check (kind in ('grey_fuel', 'gear')),
  ref       text not null,                       -- item id (grey_fuel) or furniture id (gear)
  price_pct numeric not null default 100 check (price_pct > 0),   -- gear: % of the shop price
  faulty_pct  numeric not null default 0 check (faulty_pct between 0 and 100),
  stolen_pct  numeric not null default 0 check (stolen_pct between 0 and 100),
  sort      int not null default 100,
  active    boolean not null default true
);
alter table public.bm_offers enable row level security;
revoke all on public.bm_offers from public, anon, authenticated;
-- no client read: bm_status() is the only way to see the shelf (and only for players who got in)

insert into public.bm_offers (id, name, emoji, blurb, kind, ref, price_pct, faulty_pct, stolen_pct, sort) values
('grey_petrol',  'Grey petrol (litre)',            '⛽', 'Poured from a drum. Cheap, no queue. Sometimes it is mixed with something.', 'grey_fuel', 'petrol_bm', 100, 0, 0, 10),
('grey_diesel',  'Grey diesel (litre)',            '⛽', 'For the big generators. Same story as the petrol.', 'grey_fuel', 'diesel_bm', 100, 0, 0, 20),
('tk_tiger',     'Tokunbo Tiger gen',              '🔌', 'Used. It does start. Mostly.', 'gear', 'gen_tiger', 60, 20, 8, 30),
('tk_firman',    'Tokunbo Firman 2.8KVA gen',      '🔌', 'Fell off a truck at Ugbowo. Probably.', 'gear', 'gen_firman', 60, 20, 8, 40),
('tk_inverter',  'Tokunbo 1.5KVA inverter',        '🔋', 'Comes with a battery that "still dey strong".', 'gear', 'inverter_small', 60, 25, 8, 50),
('tk_battery',   'Tokunbo tubular battery',        '🔋', 'Second-hand 200Ah. Ask no questions.', 'gear', 'battery_tubular', 55, 25, 6, 60),
('tk_panels',    'Tokunbo solar panels',           '☀️', 'A frame of used panels, dust and all.', 'gear', 'solar_panels', 60, 10, 10, 70)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. Station info (the attendant) and the black market
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_fuel_line(p_loc text, p_state text) returns text
language plpgsql stable set search_path = public as $$
declare v_lines text[]; v_h double precision := bl_power_h(to_char(bl_now() at time zone bl_clock_tz(), 'YYYY-MM-DD HH24') || ':line:' || coalesce(p_loc, '') || p_state);
begin
  v_lines := case p_state
    when 'dry' then array['Oga, pump don dry today. The depot never load us. Try another station o.',
                          'No fuel! Make you no waste your time. Even the manager don go home.',
                          'Sorry sir, na empty tank we dey show. Check the next station, or ask the boys for the yard.']
    when 'scarce' then array['Queue long o! Fuel scarce, na so e be. Take your turn.',
                            'Everybody dey run come here. Price don jump, no vex me, na the depot.',
                            'Oga, the line reach the junction. Cash only, no change.']
    when 'up' then array['Price don climb small today, oga. Na the depot.',
                         'Dollar dey do wahala, so petrol follow. But we still dey sell am.',
                         'E don cost small pass yesterday. No be our fault o.']
    when 'down' then array['Oga, price don drop small today. Fill am up!',
                           'Good day for you: e cheap small pass yesterday.',
                           'Come buy before price change o. Today na your day.']
    else array['Welcome, oga! Park well make I fill am. Petrol or diesel?',
               'Pump dey ready. How much you wan buy? Jerrycan too dey.',
               'Good afternoon sir. Na cash or transfer?'] end;
  return v_lines[1 + floor(v_h * array_length(v_lines, 1))::int];
end $$;

create or replace function public.fuel_station_info(p_loc text default null) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_loc text; l public.locations; v_dry boolean; v_scarce boolean; v_today bigint; v_yest bigint; v_state text; it public.items; v_owner text;
  v_save text := current_setting('bl.test_offset_seconds', true);
begin
  select location_id into v_loc from public.profiles where id = v_uid;
  v_loc := coalesce(p_loc, v_loc);
  select * into l from public.locations where id = v_loc;
  if not found then return jsonb_build_object('station', false); end if;
  if l.id not like 'fs\_%' and not (l.biz_type = 'filling_station') then return jsonb_build_object('station', false); end if;
  v_dry := bl_fuel_dry(l.id); v_scarce := bl_fuel_scarce();
  select * into it from public.items where id = 'petrol';
  v_today := bl_fuel_price(it, l.id);
  -- yesterday: the same price one Benin day back (scarcity left out)
  perform set_config('bl.test_offset_seconds', (coalesce(nullif(v_save, '')::double precision, 0) - 86400)::text, true);
  v_yest := bl_fuel_price(it, l.id);
  perform set_config('bl.test_offset_seconds', coalesce(nullif(v_save, ''), '0'), true);
  v_state := case when v_dry then 'dry' when v_scarce then 'scarce' when v_today > v_yest * 1.01 then 'up' when v_today < v_yest * 0.99 then 'down' else 'normal' end;
  select biz_owner into v_owner from public.locations where id = l.id;
  return jsonb_build_object('station', true, 'id', l.id, 'name', l.name, 'dry', v_dry, 'scarce', v_scarce, 'state', v_state, 'petrol', v_today,
    'diesel', bl_fuel_price((select i from public.items i where i.id = 'diesel'), l.id), 'yesterday', v_yest,
    'queue_seconds', case when v_scarce then bl_power_num('power.queue_seconds_scarce', 25) else bl_power_num('power.queue_seconds', 0) end,
    'owner', v_owner, 'line', bl_fuel_line(l.id, v_state));
end $$;

-- helpers for the yard
create or replace function public.bl_bm_open_now() returns boolean
language plpgsql stable set search_path = public as $$
declare v_h numeric; v_o numeric := bl_power_num('blackmarket.open_hour', 21); v_c numeric := bl_power_num('blackmarket.close_hour', 5);
begin
  v_h := (bl_game_clock() ->> 'hour')::numeric + coalesce((bl_game_clock() ->> 'minute')::numeric, 0) / 60.0;
  if v_o = v_c then return true; end if;
  if v_o < v_c then return v_h >= v_o and v_h < v_c; end if;
  return v_h >= v_o or v_h < v_c;
end $$;

-- police patrol the yard on some nights (fixed by the date of the evening)
create or replace function public.bl_bm_hot() returns boolean
language sql stable set search_path = public as $$
  select bl_power_h((to_char((bl_now() at time zone bl_clock_tz()) - interval '6 hours', 'YYYY-MM-DD')) || ':bmhot:' || bl_power_salt()) * 100 < bl_power_num('blackmarket.hot_night_pct', 8)
$$;

create or replace function public.bl_bm_guard(p_loc public.locations) returns void
language plpgsql stable set search_path = public as $$
begin
  if not bl_bm_unlocked(auth.uid()) then
    raise exception '% is closed for now. Check back soon.', p_loc.name using errcode = 'P0001', hint = 'inactive';
  end if;
  if not bl_bm_open_now() then
    raise exception 'The yard is shut. Come back after % o''clock at night.', bl_power_num('blackmarket.open_hour', 21)::int using errcode = 'P0001', hint = 'closed';
  end if;
end $$;

create or replace function public.bl_bm_unit_price(o public.bm_offers) returns bigint
language plpgsql stable set search_path = public as $$
declare v_p numeric;
begin
  if o.kind = 'grey_fuel' then
    return bl_fuel_price((select i from public.items i where i.id = o.ref), null);
  end if;
  select bl_gross('furniture', f.category, f.price) * o.price_pct / 100.0 into v_p from public.furniture f where f.id = o.ref;
  return greatest(1000, (round(coalesce(v_p, 0) / 1000.0) * 1000)::bigint);
end $$;

-- the chance a deal goes bad at all, and the expected cost of a delivered unit compared with the shop (the EV)
create or replace function public.bl_bm_risk(o public.bm_offers, p_uid uuid default null) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_raid numeric := bl_power_num('blackmarket.raid_pct', 4) * case when bl_bm_hot() then bl_power_num('blackmarket.hot_raid_mult', 4) else 1 end;
  v_scam numeric := bl_power_num('blackmarket.scam_pct', 6); v_rob numeric := bl_power_num('blackmarket.robbery_pct', 6);
  v_ok numeric; v_value numeric; v_shop numeric; v_unit bigint;
begin
  if p_uid is not null and exists (select 1 from public.crew_members where user_id = p_uid) then
    v_raid := v_raid * (1 - bl_power_num('blackmarket.crew_raid_cut_pct', 40) / 100.0);
  end if;
  v_raid := least(100, v_raid);
  v_ok := (1 - v_raid / 100) * (1 - v_scam / 100) * (1 - v_rob / 100) * (1 - o.stolen_pct / 100);
  v_value := v_ok * (1 - o.faulty_pct / 100 * 0.4);   -- a faulty piece is worth about 60 % of a good one
  v_unit := bl_bm_unit_price(o);
  v_shop := case when o.kind = 'grey_fuel' then
                   bl_fuel_price((select i from public.items i where i.id = case o.ref when 'diesel_bm' then 'diesel' else 'petrol' end), null)
                 else (select bl_gross('furniture', f.category, f.price) from public.furniture f where f.id = o.ref) end;
  return jsonb_build_object('raid_pct', round(v_raid, 2), 'scam_pct', v_scam, 'robbery_pct', v_rob, 'stolen_pct', o.stolen_pct, 'faulty_pct', o.faulty_pct,
    'success_pct', round(v_ok * 100, 1), 'unit_price', v_unit, 'shop_price', v_shop,
    'ev_ratio', case when v_shop > 0 and v_value > 0 then round(v_unit / v_shop / v_value, 3) end);
end $$;

-- a jail case, the same one the pickpocket flow opens (docs/CRIME.md): the usual popup with bail, jail time and escape
create or replace function public.bl_crime_arrest(p_uid uuid, p_reason text, p_loc text) returns bigint
language plpgsql volatile set search_path = public as $$
declare
  v_now timestamptz := bl_now(); c public.jail_cases;
  v_jail int := greatest(1, ceil(bl_crime_num('action.jail_max_seconds', 45)))::int;
  v_jail_loc text := coalesce(bl_cfg_text('crime.jail_location'), 'police_hq');
begin
  perform bl_crime_close_stale(p_uid);
  insert into public.jail_cases (user_id, reason, location_id, attempt_id, bail_amount, jail_seconds, jail_until, created_at)
  values (p_uid, p_reason, p_loc, null, greatest(0, round(bl_crime_num('crime.bail_base', 20000000)))::bigint, v_jail, v_now + make_interval(secs => v_jail), v_now)
  returning * into c;
  update public.profiles set jailed_until = c.jail_until, jail_reason = c.reason, wanted = least(5, wanted + 1),
    location_id = coalesce((select id from public.locations where id = v_jail_loc), location_id),
    travel_to = null, travel_mode = null, travel_started_at = null, travel_arrives_at = null,
    busy_until = null, busy_label = null, busy_started_at = null, busy_needs_from = null
   where id = p_uid;
  perform bl_event(p_uid, 'steal_caught', 'Police don catch you!', p_reason, jsonb_build_object('case_id', c.id));
  return c.id;
end $$;

-- deliver a furniture piece the way furniture_buy does (inventory first, stored, ready to place)
create or replace function public.bl_bm_grant_furniture(p_uid uuid, p_furn text) returns int
language plpgsql volatile set search_path = public as $$
declare f public.furniture; v_qty int; v_key text; v_layout text;
begin
  select * into f from public.furniture where id = p_furn;
  v_layout := bl_furniture_materialize(p_uid);
  insert into public.player_furniture (user_id, furniture_id, slot, source, qty) values (p_uid, f.id, null, 'buy', 1)
  on conflict (user_id, furniture_id) do update set qty = player_furniture.qty + 1 returning qty into v_qty;
  v_key := case when v_qty = 1 then 'own_' || f.id else 'own_' || f.id || '-' || v_qty end;
  if coalesce((select house_qty from public.player_furniture where user_id = p_uid and furniture_id = f.id), 0) > 0 then
    delete from public.player_house_furniture where owner_id = p_uid and furniture_key = v_key;
    v_key := (select bl_furniture_key(f.id, qty - house_qty) from public.player_furniture where user_id = p_uid and furniture_id = f.id);
    update public.player_house_furniture set furniture_key = bl_furniture_key(f.id, v_qty), updated_at = bl_now() where owner_id = p_uid and furniture_key = v_key;
  end if;
  insert into public.player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  values (p_uid, v_key, 0, 0, 0, true, v_layout, bl_now())
  on conflict (owner_id, furniture_key) do update set stored = true, layout = excluded.layout, updated_at = excluded.updated_at;
  return v_qty;
end $$;

create or replace function public.bm_status() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_un boolean := bl_bm_unlocked(v_uid); v_open boolean; v_me public.profiles;
begin
  if not v_un then return jsonb_build_object('unlocked', false); end if;
  v_open := bl_bm_open_now();
  select * into v_me from public.profiles where id = v_uid;
  return jsonb_build_object('unlocked', true, 'open', v_open, 'hot', bl_bm_hot(), 'here', v_me.location_id = 'bm_yard' and v_me.travel_to is null,
    'open_hour', bl_power_num('blackmarket.open_hour', 21), 'close_hour', bl_power_num('blackmarket.close_hour', 5), 'scarce', bl_fuel_scarce(),
    'cash', v_me.cash, 'crew', exists (select 1 from public.crew_members where user_id = v_uid),
    'line', case when not v_open then 'Shop shut. Come back when the sun don go down.' when bl_bm_hot() then 'Eh, police dey around tonight. Buy quick, no talk loud.'
                 when bl_fuel_scarce() then 'Fuel scarce, na so my price. You no get choice, my friend.' else 'Oya, tell me wetin you need. No receipt, no wahala.' end,
    'offers', case when not v_open then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'emoji', o.emoji, 'blurb', o.blurb, 'kind', o.kind,
         'price', bl_bm_unit_price(o), 'risk', bl_bm_risk(o, v_uid) - 'ev_ratio',
         'risk_level', case when (bl_bm_risk(o, v_uid) ->> 'success_pct')::numeric >= 85 then 'low' when (bl_bm_risk(o, v_uid) ->> 'success_pct')::numeric >= 70 then 'medium' else 'high' end)
         order by o.sort) from public.bm_offers o where o.active), '[]'::jsonb) end);
end $$;

create or replace function public.bm_buy(p_offer text, p_qty int default 1) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me public.profiles := bl_me(); o public.bm_offers; v_qty int := coalesce(p_qty, 1); v_unit bigint; v_total bigint; v_risk jsonb;
  v_raid numeric; v_roll numeric; v_cred int; v_outcome text; v_msg text; v_have int; f public.furniture; v_case bigint; v_lost bigint := 0;
  v_faulty boolean := false; r public.player_power; g public.power_gear;
begin
  perform bl_assert_free(v_me);
  if not bl_bm_unlocked(v_me.id) then raise exception 'Nobody told you about any yard.' using errcode = 'P0001', hint = 'inactive'; end if;
  if v_me.location_id <> 'bm_yard' or v_me.travel_to is not null then
    raise exception 'You are not at the yard.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if not bl_bm_open_now() then raise exception 'The yard is shut. Come back after dark.' using errcode = 'P0001', hint = 'closed'; end if;
  select * into o from public.bm_offers where id = p_offer and active;
  if not found then raise exception 'Nobody sells that here.' using errcode = 'P0001', hint = 'unknown_offer'; end if;
  if v_qty < 1 or v_qty > bl_power_num('blackmarket.max_qty', 20) or (o.kind = 'gear' and v_qty > 1) then
    raise exception 'Bad quantity.' using errcode = 'P0001', hint = 'bad_qty';
  end if;
  v_unit := bl_bm_unit_price(o); v_total := v_unit * v_qty;
  if o.kind = 'gear' then
    select * into f from public.furniture where id = o.ref;
    select qty into v_have from public.player_furniture where user_id = v_me.id and furniture_id = o.ref;
    if coalesce(v_have, 0) >= f.max_qty then
      raise exception 'You already have the most of these (%).', f.max_qty using errcode = 'P0001', hint = 'max_owned';
    end if;
  end if;
  if v_me.cash < v_total then
    raise exception 'Cash only in the yard. % costs % and you have % on you.', o.name, bl_naira(v_total), bl_naira(v_me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_risk := bl_bm_risk(o, v_me.id);
  v_cred := 0;
  -- 1. police raid: nothing is paid, you are arrested (existing jail case)
  v_raid := (v_risk ->> 'raid_pct')::numeric;
  if bl_rand() * 100 < v_raid then
    v_cred := -round(bl_power_num('blackmarket.cred_raid_loss', 3))::int;
    update public.profiles set street_cred = greatest(0, street_cred + v_cred) where id = v_me.id;
    v_case := bl_crime_arrest(v_me.id, 'Caught in a police raid at the yard (Ogida)', 'bm_yard');
    return jsonb_build_object('outcome', 'raid', 'message', 'Police don catch you!', 'case', v_case, 'spent', 0, 'cred', v_cred);
  end if;
  -- the deal is on: pay in cash
  perform bl_add_money(v_me.id, 'cash', -v_total, 'blackmarket', jsonb_build_object('label', 'Black market: ' || o.name || case when v_qty > 1 then ' x' || v_qty else '' end, 'offer', o.id, 'qty', v_qty));
  -- 2. scam
  if bl_rand() * 100 < (v_risk ->> 'scam_pct')::numeric then
    v_cred := -round(bl_power_num('blackmarket.cred_scam_loss', 0))::int;
    if v_cred <> 0 then update public.profiles set street_cred = greatest(0, street_cred + v_cred) where id = v_me.id; end if;
    return jsonb_build_object('outcome', 'scam', 'message', 'The seller collected the money, said "wait small" and vanished. You don dey scam.', 'spent', v_total, 'cred', v_cred);
  end if;
  -- 3. robbery on the way out: goods and some cash
  if bl_rand() * 100 < (v_risk ->> 'robbery_pct')::numeric then
    select * into v_me from public.profiles where id = v_me.id;
    v_lost := least(floor(v_me.cash * bl_power_num('blackmarket.robbery_cash_pct', 5) / 100)::bigint, round(bl_power_num('blackmarket.robbery_cash_cap', 200000))::bigint);
    if v_lost > 0 then
      perform bl_add_money(v_me.id, 'cash', -v_lost, 'street_robbery', jsonb_build_object('label', 'Robbed leaving the yard'));
    end if;
    return jsonb_build_object('outcome', 'robbery', 'message', 'Boys jumped you at the gate and carried the goods' || case when v_lost > 0 then ' and ' || bl_naira(v_lost) || ' from your pocket' else '' end || '.',
                              'spent', v_total, 'lost_cash', v_lost, 'cred', 0);
  end if;
  -- 4. stolen goods: the owner's people trace it, police take it back
  if o.stolen_pct > 0 and bl_rand() * 100 < o.stolen_pct then
    v_cred := -1;
    update public.profiles set street_cred = greatest(0, street_cred + v_cred), wanted = least(5, wanted + 1) where id = v_me.id;
    return jsonb_build_object('outcome', 'stolen', 'message', 'The goods were hot. Police traced them at the gate and took them back, and your money too. Wanted level up.', 'spent', v_total, 'cred', v_cred);
  end if;
  -- 5. delivered
  if o.kind = 'grey_fuel' then
    perform bl_give_item(v_me.id, o.ref, v_qty);
    v_msg := 'You carried ' || v_qty || ' litre' || case when v_qty > 1 then 's' else '' end || ' of grey fuel home. Pour it from the Power sheet. It may be bad.';
  else
    perform bl_bm_grant_furniture(v_me.id, o.ref);
    v_msg := o.name || ' delivered. Place am in Buy -> Arrange.';
    if o.faulty_pct > 0 and bl_rand() * 100 < o.faulty_pct then
      v_faulty := true;
      select * into g from public.power_gear where id = o.ref;
      r := bl_power_settle(v_me.id, true);
      select * into r from public.player_power where user_id = v_me.id for update;
      if not found then r := bl_power_blank(v_me.id, bl_now()); end if;
      if g.kind = 'generator' then
        r.gen_fault_until := bl_now() + make_interval(days => bl_power_num('blackmarket.faulty_days', 30)::int);
        r.gen_burn_mult := bl_power_num('power.bad_fuel_burn_mult', 1.6);
        v_msg := v_msg || ' Eh! It dey cough: the dealer lied. It burns more fuel until a mechanic fixes it.';
      else
        r.batt_health := least(coalesce(r.batt_health, 100), bl_power_num('blackmarket.faulty_batt_pct', 60));
        r.batt_kwh := least(r.batt_kwh, r.cap_seen * r.batt_health / 100);
        v_msg := v_msg || ' The battery weak: it holds only ' || round(r.batt_health) || '% until a mechanic services it.';
      end if;
      perform bl_power_save(r);
    end if;
  end if;
  v_cred := round(bl_power_num('blackmarket.cred_gain', 1))::int;
  if v_cred <> 0 then update public.profiles set street_cred = greatest(0, street_cred + v_cred) where id = v_me.id; end if;
  return jsonb_build_object('outcome', case when v_faulty then 'faulty' else 'ok' end, 'message', v_msg, 'spent', v_total, 'cred', v_cred, 'faulty', v_faulty,
                            'bag', bl_power_bag(v_me.id));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Patches (guarded)
-- ---------------------------------------------------------------------------------------------
-- the yard checks (unlocked, hours) wherever a place is checked for being active
select pg_temp.fm_patch('public.bl_assert_place_active(public.locations)', 'bl_bm_guard',
  $o$  if p_loc.id is not null and not coalesce(p_loc.active, true) then$o$,
  $o$  if p_loc.id like 'bm\_%' then perform bl_bm_guard(p_loc); end if; -- black market
  if p_loc.id is not null and not coalesce(p_loc.active, true) then$o$);

-- admin Content: the black market shelf
select pg_temp.fm_patch('public.bl_admin_table_spec(text)', 'when ''bm_offers'' then',
  E'when ''house_upgrades'' then',
  E'when ''bm_offers'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","blurb":"text","kind":"text","ref":"text","price_pct":"num","faulty_pct":"num","stolen_pct":"num","sort":"int","active":"bool"}}''\n    when ''house_upgrades'' then');

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and (proname like 'bl\_bm\_%' or proname in ('bl_fuel_line', 'bl_crime_arrest')) loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('fuel_station_info', 'bm_status', 'bm_buy') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
-- the policy calls bl_bm_unlocked for every signed-in reader
grant execute on function public.bl_bm_unlocked(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
