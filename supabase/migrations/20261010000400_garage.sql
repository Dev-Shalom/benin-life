-- G1: garage and parked car (docs/GARAGE.md).
-- * garage_types: admin-editable catalogue (Content -> Garage types): carport / standard garage / luxury double garage,
--   real Benin City 2025-2026 build prices (sources in docs/GARAGE.md), capacity in cars, allowed housing kinds.
-- * player_garages: one garage per player, tied to the home it was built at (housing_id + home_location_id).
--   Moving home does not transfer it: a row for another home reads as "no garage" and the player builds again.
-- * garage_build(p_type): bank first, then cash (like shop_buy for cars), ledger "Garage: <name>". Instant.
--   Upgrading (or rebuilding after a move) replaces the old garage at the full new price.
-- * garage_home(p_owner): the garage + owned vehicles for the 3D home, for the owner or an admitted house guest
--   (bl_social_can_view_owner_home). player_garages is readable under the same rule; clients never write.
-- * config garage.enabled (default true). bl_ledger_label + bl_admin_table_spec re-created from live + one branch.
-- Idempotent: tables `if not exists`, seeds `on conflict do nothing`, functions `create or replace`.

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('garage.enabled', 'true', 'garage', 'Garages on',
 'G1 (docs/GARAGE.md): after buying a car the player is offered a garage, and the home has "Build a garage". Off = no offer, building refused; owned cars still park outside the home. Prices: Content -> Garage types.', 'bool', null, null)
on conflict (key) do nothing;

create table if not exists public.garage_types (
  id              text primary key,
  name            text not null,
  description     text not null default '',
  price           bigint not null check (price >= 0),
  capacity        int not null default 1 check (capacity between 1 and 4),
  -- housing kinds (bl_housing_kind): hostel, face_me, self_contain, mini_flat, duplex
  allowed_housing text[] not null default '{}',
  style           text not null default 'garage' check (style in ('carport', 'garage')),
  sort            int not null default 100,
  active          boolean not null default true
);

create table if not exists public.player_garages (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  garage_type      text not null references public.garage_types(id) on update cascade,
  housing_id       text,
  home_location_id text,
  price_paid       bigint not null default 0,
  built_at         timestamptz not null default now()
);

alter table public.garage_types   enable row level security;
alter table public.player_garages enable row level security;
revoke all on public.garage_types, public.player_garages from anon, authenticated;
grant select on public.garage_types, public.player_garages to authenticated;
drop policy if exists garage_types_read on public.garage_types;
create policy garage_types_read on public.garage_types for select to authenticated using (true);
drop policy if exists player_garages_read on public.player_garages;
create policy player_garages_read on public.player_garages for select to authenticated
  using (user_id = (select auth.uid()) or public.bl_social_can_view_owner_home(user_id));

-- Real-life defaults (Benin City, 2025-2026; docs/GARAGE.md). Admin can change every value.
insert into public.garage_types (id, name, description, price, capacity, allowed_housing, style, sort) values
('carport', 'Carport', 'Steel posts, long-span aluminium roof and a concrete pad. Keeps sun and rain off one car.',
 1500000, 1, '{hostel,face_me,self_contain,mini_flat,duplex}', 'carport', 10),
('garage_standard', 'Standard garage', 'Single-car blockwork garage: plastered walls, roof, concrete floor, roller door and a bulb.',
 5000000, 1, '{self_contain,mini_flat,duplex}', 'garage', 20),
('garage_luxury', 'Luxury double garage', 'Two-car garage with tiled floor, automatic sectional door, lighting and a paved apron.',
 12000000, 2, '{duplex}', 'garage', 30)
on conflict (id) do nothing;

-- housing_id -> kind (same prefixes as the client's homeLayoutFor).
create or replace function public.bl_housing_kind(p_housing text) returns text
language sql immutable set search_path = public as $$
  select case
    when coalesce(p_housing, '') like 'hostel%' then 'hostel'
    when coalesce(p_housing, '') like 'face_me%' then 'face_me'
    when coalesce(p_housing, '') like 'self_con%' then 'self_contain'
    when coalesce(p_housing, '') like '%flat%' then 'mini_flat'
    when coalesce(p_housing, '') like '%duplex%' then 'duplex'
    else 'face_me' end
$$;
revoke execute on function public.bl_housing_kind(text) from public, anon, authenticated;

create or replace function public.garage_build(p_type text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  g       garage_types;
  old     player_garages;
  v_kind  text;
  v_bank  bigint := 0;
  v_cash  bigint := 0;
  v_stale boolean;
  v_msg   text;
begin
  if not bl_cfg_bool('garage.enabled') then
    raise exception 'Garages are switched off right now.' using errcode = 'P0001', hint = 'garage_disabled';
  end if;
  select * into g from garage_types where id = p_type and active;
  if not found then
    raise exception 'That garage type isn''t available.' using errcode = 'P0001', hint = 'unknown_garage';
  end if;
  v_kind := bl_housing_kind(v_me.housing_id);
  if not (v_kind = any (g.allowed_housing)) then
    raise exception 'A % can''t be built at your % home. %', lower(g.name), replace(v_kind, '_', ' '),
      case when v_kind in ('hostel', 'face_me') then 'There is only space for a carport.'
           when v_kind in ('self_contain', 'mini_flat') then 'A carport or a standard garage fits here.'
           else '' end
      using errcode = 'P0001', hint = 'not_allowed_here';
  end if;
  select * into old from player_garages where user_id = v_me.id for update;
  v_stale := old.user_id is not null and (old.housing_id is distinct from v_me.housing_id
                                          or old.home_location_id is distinct from v_me.home_location_id);
  if old.user_id is not null and not v_stale and old.garage_type = g.id then
    raise exception 'You already have a % at home.', lower(g.name) using errcode = 'P0001', hint = 'already_built';
  end if;
  v_bank := least(greatest(v_me.bank, 0), g.price);
  v_cash := g.price - v_bank;
  if v_cash > v_me.cash then
    raise exception 'Not enough money. A % costs % and you have % (bank % + cash %).', lower(g.name), bl_naira(g.price),
      bl_naira(v_me.bank + v_me.cash), bl_naira(v_me.bank), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'garage', jsonb_build_object('garage', g.id, 'name', g.name));
  end if;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'garage', jsonb_build_object('garage', g.id, 'name', g.name));
  end if;
  insert into player_garages (user_id, garage_type, housing_id, home_location_id, price_paid, built_at)
  values (v_me.id, g.id, v_me.housing_id, v_me.home_location_id, g.price, bl_now())
  on conflict (user_id) do update set garage_type = excluded.garage_type, housing_id = excluded.housing_id,
    home_location_id = excluded.home_location_id, price_paid = excluded.price_paid, built_at = excluded.built_at;
  v_msg := case when old.user_id is not null and not v_stale
                then 'Upgrade done! Your new ' || lower(g.name) || ' is ready'
                else 'Your ' || lower(g.name) || ' is ready' end
           || ' for ' || bl_naira(g.price) || '. Your car is parked at home.';
  return jsonb_build_object('message', v_msg, 'garage', g.id, 'name', g.name, 'capacity', g.capacity, 'style', g.style,
                            'spent', g.price, 'from_bank', v_bank, 'from_cash', v_cash,
                            'cash', v_me.cash - v_cash, 'bank', v_me.bank - v_bank,
                            'replaced', case when old.user_id is not null and not v_stale then old.garage_type end);
end $$;
revoke execute on function public.garage_build(text) from public, anon;
grant execute on function public.garage_build(text) to authenticated;

-- Garage + vehicles for the 3D home of p_owner (default: me). Owner or admitted guest only.
create or replace function public.garage_home(p_owner uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid := coalesce(p_owner, auth.uid());
  h       profiles;
  pg      player_garages;
  g       garage_types;
  v_kind  text;
  v_cars  jsonb;
  v_types jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = 'P0001', hint = 'not_signed_in';
  end if;
  if v_owner <> v_uid and not bl_social_can_view_owner_home(v_owner) then
    raise exception 'You can only see the garage of a home you are inside.' using errcode = 'P0001', hint = 'not_allowed';
  end if;
  select * into h from profiles where id = v_owner;
  if not found then
    raise exception 'Dis person no dey.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  v_kind := bl_housing_kind(h.housing_id);
  select * into pg from player_garages where user_id = v_owner
     and housing_id is not distinct from h.housing_id and home_location_id is not distinct from h.home_location_id;
  if pg.user_id is not null then select * into g from garage_types where id = pg.garage_type; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', it.id, 'name', it.name, 'price', it.price) order by it.price desc, it.id), '[]'::jsonb)
    into v_cars
    from inventory i join items it on it.id = i.item_id
   where i.user_id = v_owner and i.qty > 0 and it.category = 'vehicle';
  if v_owner = v_uid then
    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'description', t.description, 'price', t.price,
                                                 'capacity', t.capacity, 'style', t.style,
                                                 'allowed', v_kind = any (t.allowed_housing)) order by t.sort, t.id), '[]'::jsonb)
      into v_types from garage_types t where t.active;
  end if;
  return jsonb_build_object(
    'enabled', bl_cfg_bool('garage.enabled'), 'owner', v_owner, 'kind', v_kind,
    'garage', case when g.id is null then null else jsonb_build_object('type', g.id, 'name', g.name, 'capacity', g.capacity,
                                                                         'style', g.style, 'built_at', pg.built_at) end,
    'cars', v_cars, 'types', v_types);
end $$;
revoke execute on function public.garage_home(uuid) from public, anon;
grant execute on function public.garage_home(uuid) to authenticated;

-- Ledger label "Garage: <name>" (live definition + one branch)
CREATE OR REPLACE FUNCTION public.bl_ledger_label(p_reason text, p_meta jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  case p_reason
    when 'salary' then
      select 'Salary · ' || title into v from career_levels
       where track_id = p_meta->>'track' and level = (p_meta->>'level')::int;
      return coalesce(v, 'Salary');
    when 'shop' then
      select name into v from items where id = p_meta->>'item';
      return 'Bought ' || coalesce(v, 'something');
    when 'shop_sell' then
      select name into v from items where id = p_meta->>'item';
      return 'Sold ' || coalesce(v, 'something');
    when 'food_delivery' then
      select name into v from items where id = p_meta->>'item';
      return 'Chowdeck · ' || coalesce(v, 'food');
    when 'activity' then
      select name into v from activities where id = p_meta->>'activity';
      return coalesce(v, 'Activity');
    when 'travel' then
      return 'Transport · ' || case p_meta->>'mode' when 'keke' then 'keke' when 'bus' then 'bus'
                                    when 'drop' then 'drop taxi' when 'car' then 'fuel' else 'fare' end;
    when 'rent' then return case when (p_meta->>'settle')::boolean then 'Rent paid (owed)' else 'Rent' end;
    when 'street_robbery' then return 'Robbed on the street';
    when 'start_bonus' then return 'Starting money';
    when 'allowance' then return 'Dad''s allowance';
    when 'admin_origin' then return 'Account adjustment';
    when 'bank_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'Deposit · ' || coalesce(v, 'bank');
    when 'bank_withdraw' then
      select name into v from locations where id = p_meta->>'location';
      return 'Withdrawal · ' || coalesce(v, 'bank');
    when 'pos_cashout' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS cash-out' || coalesce(' · ' || v, '');
    when 'pos_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS deposit' || coalesce(' · ' || v, '');
    when 'pos_fee' then return 'PoS charge';
    when 'transfer_out' then return 'Sent to @' || coalesce(p_meta->>'to_username', 'player');
    when 'transfer_in' then return 'From @' || coalesce(p_meta->>'from_username', 'player');
    when 'transfer_fee' then return 'Transfer fee';
    when 'garage' then return 'Garage: ' || coalesce(p_meta->>'name', 'garage');
    when 'topup' then return 'Top-up via ' || coalesce(initcap(p_meta->>'provider'), 'Paystack');
    else return initcap(replace(coalesce(p_reason, 'money'), '_', ' '));
  end case;
end $function$;

-- Admin: Content -> Garage types (live whitelist + garage_types)
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_table
    when 'origin_tiers' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","welcome":"text","sort":"int","perks":"obj"}}'
    when 'traits' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","effects":"obj","sort":"int","active":"bool"}}'
    when 'dreams' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","goal":"obj","sort":"int","active":"bool"}}'
    when 'start_homes' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","location_id":"text","district":"text","tag":"text","description":"text",
              "weekly_rent":"money","start_cash":"obj","allowed_origins":"arr","locked_quip":"text","housing_id":"text",
              "sort":"int","active":"bool"}}'
    when 'career_tracks' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","location_ids":"arr","skill":"text_null","sort":"int","active":"bool"}}'
    when 'career_levels' then '{"pk":["track_id","level"],"insert":true,"order":"track_id, level",
      "cols":{"title":"text","pay_per_shift":"money","shift_game_minutes":"int","energy_cost":"int","effects":"obj",
              "xp_per_shift":"int","xp_to_next":"int_null","requirements":"obj","perks":"obj"}}'
    when 'items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","category":"text","price":"money","description":"text","effects":"obj","sold_at":"arr",
              "sellable":"bool","resale_pct":"num","icon":"text_null","sort":"int"}}'
    when 'activities' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","scenes":"arr","home_only":"bool","night_only":"bool","cost":"money","game_minutes":"int",
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null","requires_event":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
    when 'npc_roster' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","role":"text","motion":"text","avatar":"obj","lines":"text","pidgin":"text","scenes":"arr",
              "location_ids":"arr","zone_key":"text_null","headliner":"bool","sort":"int","active":"bool"}}'
    when 'crowd_profiles' then '{"pk":["id"],"insert":true,"order":"scene, from_hour, days, id",
      "cols":{"scene":"text","days":"text","from_hour":"int","to_hour":"int","npcs":"int","sort":"int","active":"bool"}}'
    when 'hype_templates' then '{"pk":["id"],"insert":true,"order":"kind, sort, id",
      "cols":{"kind":"text","line":"text","ticker":"text","sort":"int","active":"bool"}}'
    when 'place_events' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"location_id":"text","title":"text","description":"text","kind":"text","icon":"text","recurrence":"text",
              "weekday":"int_null","start_time":"num_null","end_time":"num_null","starts_at":"ts_null","ends_at":"ts_null",
              "ticket_price":"money","capacity":"int_null","perks":"obj","variants":"text","sort":"int","active":"bool"}}'
    when 'topup_packs' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"label":"text","game_naira":"money","price_kobo":"money","bonus_tag":"text_null","sort":"int","active":"bool"}}'
    when 'daily_reward_steps' then '{"pk":["day"],"insert":false,"order":"day",
      "cols":{"cash":"money","item_id":"text_null","label":"text"}}'
    when 'gem_finds' then '{"pk":["user_id","hunt_date","location_id"],"insert":false,"order":"hunt_date desc, found_at desc",
      "cols":{}}'
    when 'wardrobe_brands' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","colour":"text","is_house":"bool","sponsor":"bool","sort":"int","active":"bool"}}'
    when 'wardrobe_items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","brand_id":"text_null","category":"text","gender":"text_null","patch":"obj","colours":"arr",
              "price":"money","tag":"text","default_slots":"arr","icon":"text","description":"text","sort":"int","active":"bool"}}'
    when 'garage_types' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","description":"text","price":"money","capacity":"int","allowed_housing":"arr","style":"text",
              "sort":"int","active":"bool"}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
