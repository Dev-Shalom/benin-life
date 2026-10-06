-- P2 club hype (docs/SHIP_TODAY.md "P2", docs/PLACES.md "P2 hype").
-- * place_announcements: server-written hype lines ("Make una hail @Nosa!..."). Read by any signed-in player,
--   never written by clients (no insert/update/delete grants, RLS on). In the supabase_realtime publication, so
--   players in that club get the row live (filter location_id=eq.<club>) and big ones (global = true) go app-wide.
-- * hype_templates: the MC's lines per kind (vip / bottles / spray / shoutout / shutdown), admin-editable
--   (Content -> Hype lines). Placeholders: {name} {place} {count} {bottles} {amount}.
-- * Rows are inserted ONLY by bl_hype_announce(), called from do_activity (VIP table, spray money, hype man
--   shout-out, Shut down the club) and shop_buy (club bottles, aggregated over hype.bottle_window_s).
-- * Rate limits: one announcement per player per hype.cooldown_s (Shut down the club always announces in the
--   club), and one app-wide ticker per hype.global_cooldown_s. Spends >= hype.global_min go app-wide.
-- * New activity "Shut down the club" (club.dj zone): costs hype.shutdown_cost (default ₦2M; the card price
--   follows the setting), + hype.shutdown_cred street cred, and buys a round for every player in the club
--   (+hype.round_fun fun, +hype.round_social social).
-- * music.club_track_url (empty): a licensed track URL replaces the synthesized club groove when set.
-- Re-created from their live definitions (grants kept): do_activity, shop_buy, bl_admin_table_spec.
-- Idempotent and safe on a non-empty DB.

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('hype.enabled', 'true', 'hype', 'Club hype announcements',
 'The hype man announces big spends in clubs (banner, bubble, chat line) and the biggest ones app-wide.', 'bool', null, null),
('hype.cooldown_s', '30', 'hype', 'Per-player hype cooldown (seconds)',
 'At most one announcement per player in this many seconds (Shut down the club always announces in the club).', 'number', 0, 3600),
('hype.global_min', '500000', 'hype', 'App-wide ticker from',
 'Spends at or above this also show as a slim ticker to everyone in the game.', 'naira', 0, null),
('hype.global_cooldown_s', '90', 'hype', 'App-wide ticker cooldown (seconds)',
 'At most one app-wide ticker in this many seconds, so the screen never floods.', 'number', 0, 86400),
('hype.bottle_window_s', '300', 'hype', 'Bottle count window (seconds)',
 'Bottles bought by the same player in this window count up in one line ("E don pop 3 bottles").', 'number', 10, 7200),
('hype.shutdown_cost', '2000000', 'hype', 'Shut down the club: price',
 'What "Shut down the club" costs (cash). The card price follows this.', 'naira', 0, null),
('hype.shutdown_cred', '25', 'hype', 'Shut down the club: street cred',
 'Street cred for shutting down the club.', 'number', 0, 1000),
('hype.round_fun', '10', 'hype', 'Round for the club: fun',
 'Fun every other player in the club gets when someone shuts it down.', 'number', 0, 100),
('hype.round_social', '8', 'hype', 'Round for the club: social',
 'Social every other player in the club gets when someone shuts it down.', 'number', 0, 100),
('hype.retention_hours', '24', 'hype', 'Keep announcements (hours)',
 'Older announcements are cleaned up.', 'number', 1, 720),
('music.club_track_url', '""', 'music', 'Club track URL (licensed)',
 'Empty = the game''s own synthesized amapiano groove. Set a URL to a track you hold the rights to and clubs play it instead.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.hype_templates (
  id     text primary key,
  kind   text not null,
  line   text not null,
  ticker text not null default '',
  sort   int  not null default 0,
  active boolean not null default true,
  constraint hype_templates_kind_chk check (kind in ('vip', 'bottles', 'spray', 'shoutout', 'shutdown')),
  constraint hype_templates_len_chk check (char_length(line) between 1 and 300 and char_length(ticker) <= 160)
);
alter table public.hype_templates enable row level security;
revoke all on table public.hype_templates from public, anon, authenticated;
grant select on table public.hype_templates to authenticated;
drop policy if exists hype_templates_read on public.hype_templates;
create policy hype_templates_read on public.hype_templates for select to authenticated using (true);

create table if not exists public.place_announcements (
  id          bigserial primary key,
  location_id text not null references public.locations(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  username    text not null,
  kind        text not null,
  amount      bigint not null default 0,
  qty         int not null default 1,
  text        text not null,
  ticker      text,
  global      boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists place_announcements_loc_idx on public.place_announcements (location_id, created_at desc);
create index if not exists place_announcements_user_idx on public.place_announcements (user_id, created_at desc);
create index if not exists place_announcements_global_idx on public.place_announcements (created_at desc) where global;
alter table public.place_announcements enable row level security;
revoke all on table public.place_announcements from public, anon, authenticated;
grant select on table public.place_announcements to authenticated;
revoke all on sequence public.place_announcements_id_seq from public, anon, authenticated;
drop policy if exists place_announcements_read on public.place_announcements;
create policy place_announcements_read on public.place_announcements for select to authenticated using (true);

-- Realtime: add once (only when the publication exists and the table isn't in it yet)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'place_announcements') then
      execute 'alter publication supabase_realtime add table public.place_announcements';
    end if;
  else
    raise notice 'supabase_realtime publication not found: place_announcements not published';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. MC lines (seeded once per id; the admin edits them in Content -> Hype lines)
-- ---------------------------------------------------------------------
insert into public.hype_templates (id, kind, line, ticker, sort) values
('vip.1', 'vip', 'Make una hail @{name}! VIP table don land, bottles dey come. {place}, una see big boy?', '🔥 @{name} just took a VIP table at {place}', 1),
('vip.2', 'vip', 'Oya clear road for @{name}! VIP section don get new oga tonight. {place}, make some noise!', '👑 @{name} is holding court at {place}', 2),
('bottles.1', 'bottles', 'Make una hail @{name}! E don pop {bottles} of champagne, sparklers up! {place} na una own tonight!', '🍾 @{name} is popping bottles at {place}', 1),
('bottles.2', 'bottles', 'Sparklers dey parade! @{name} don order {bottles}. Waiter, carry am go VIP! {place}, shout!', '🍾 @{name} has {bottles} going at {place}', 2),
('spray.1', 'spray', 'Money dey rain for dance floor! @{name} dey spray {amount}. {place}, hands up!', '💸 @{name} is spraying money at {place}', 1),
('spray.2', 'spray', 'E be like say na Central Bank @{name} carry come! Spray am, spray am! {place}!', '💸 @{name} is making it rain at {place}', 2),
('shoutout.1', 'shoutout', 'Special shout-out to my person @{name}! Odogwu of the night! {place}, make una hail am!', '🎤 @{name} got a shout-out at {place}', 1),
('shoutout.2', 'shoutout', 'DJ, hold am small! This one na for @{name}, the main character tonight! {place}, scream!', '🎤 MC is hailing @{name} at {place}', 2),
('shutdown.1', 'shutdown', 'STOP EVERYTHING! @{name} don shut down {place}! Drinks dey on am for everybody tonight! Make una hail!', '🔥 @{name} is shutting down {place}', 1),
('shutdown.2', 'shutdown', 'Omo! @{name} just bought the whole club! Every table, every glass, na @{name} pay. {place}, we no dey go home!', '🔥 @{name} bought out {place}. Everybody is drinking', 2)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. "Shut down the club"
-- ---------------------------------------------------------------------
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, location_ids, risky, rush, icon) values
('shut_down_club', 'Shut down the club', '{club}', false, 2000000, 60,
 '{"fun": 50, "social": 50, "stress": -25, "street_cred": 25}', false, 304, 15, 8, false, '{}', false, '{}', '🔥')
on conflict (id) do nothing;
update public.activities set cost = greatest(0, (select (value #>> '{}')::numeric from public.game_config where key = 'hype.shutdown_cost'))::bigint
 where id = 'shut_down_club';
insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select 'club.dj.shut_down_club', 'club.dj', 'activity', 'shut_down_club', null, 2
 where exists (select 1 from public.place_zones where id = 'club.dj')
on conflict (id) do nothing;

-- the card price follows hype.shutdown_cost
create or replace function public.bl_hype_cost_sync() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update activities set cost = greatest(0, round((new.value #>> '{}')::numeric))::bigint where id = 'shut_down_club';
  return new;
end $$;
revoke execute on function public.bl_hype_cost_sync() from public, anon, authenticated;
drop trigger if exists game_config_hype_cost on public.game_config;
create trigger game_config_hype_cost after update on public.game_config
  for each row when (new.key = 'hype.shutdown_cost') execute function public.bl_hype_cost_sync();

-- ---------------------------------------------------------------------
-- 5. The announcer (server only)
-- ---------------------------------------------------------------------
-- kind of a club spend from an activity / item id, or null
create or replace function public.bl_hype_kind(p_ref text) returns text
language sql immutable as $$
  select case p_ref
    when 'vip_table' then 'vip'
    when 'spray_money' then 'spray'
    when 'hype_shoutout' then 'shoutout'
    when 'shut_down_club' then 'shutdown'
    when 'club_bottle' then 'bottles'
  end
$$;
revoke execute on function public.bl_hype_kind(text) from public, anon, authenticated;

create or replace function public.bl_hype_announce(p_user uuid, p_loc text, p_kind text, p_amount bigint, p_qty int, p_force boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l        locations;
  v_name   text;
  t        hype_templates;
  v_place  text;
  v_text   text;
  v_ticker text;
  v_global boolean := false;
  v_row    place_announcements;
begin
  if p_kind is null or not coalesce(bl_cfg_bool('hype.enabled'), false) then return null; end if;
  select * into l from locations where id = p_loc;
  if not found or l.scene <> 'club' then return null; end if;
  -- per-player cooldown (Shut down the club always announces in the club)
  if not p_force and exists (select 1 from place_announcements
                              where user_id = p_user and created_at > now() - make_interval(secs => greatest(0, bl_cfg('hype.cooldown_s')))) then
    return null;
  end if;
  select * into t from hype_templates where kind = p_kind and active order by random() limit 1;
  if not found then return null; end if;
  select username into v_name from profiles where id = p_user;
  v_place := regexp_replace(l.name, '\s*\(.*\)\s*$', '');
  v_text := t.line;
  v_ticker := nullif(t.ticker, '');
  v_text := replace(replace(replace(replace(replace(v_text, '{name}', v_name), '{place}', v_place), '{count}', p_qty::text),
              '{bottles}', p_qty || case when p_qty = 1 then ' bottle' else ' bottles' end), '{amount}', bl_naira(p_amount));
  if p_amount >= bl_cfg('hype.global_min') and v_ticker is not null
     and not exists (select 1 from place_announcements
                      where global and created_at > now() - make_interval(secs => greatest(0, bl_cfg('hype.global_cooldown_s')))) then
    v_global := true;
    v_ticker := replace(replace(replace(replace(replace(v_ticker, '{name}', v_name), '{place}', v_place), '{count}', p_qty::text),
                  '{bottles}', p_qty || case when p_qty = 1 then ' bottle' else ' bottles' end), '{amount}', bl_naira(p_amount));
  else
    v_ticker := null;
  end if;
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, ticker, global)
  values (l.id, p_user, v_name, p_kind, p_amount, greatest(1, p_qty), left(v_text, 400), left(v_ticker, 200), v_global)
  returning * into v_row;
  -- now and then, clean up old rows
  if random() < 0.05 then
    delete from place_announcements where created_at < now() - make_interval(hours => greatest(1, bl_cfg('hype.retention_hours'))::int);
  end if;
  return to_jsonb(v_row);
end $$;
revoke execute on function public.bl_hype_announce(uuid, text, text, bigint, int, boolean) from public, anon, authenticated;
revoke execute on function public.bl_hype_cost_sync() from public, anon, authenticated;

-- Shut down the club: a round for every other player in the club
create or replace function public.bl_hype_round(p_user uuid, p_loc text) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_eff jsonb;
begin
  v_eff := jsonb_build_object('fun', greatest(0, bl_cfg('hype.round_fun')), 'social', greatest(0, bl_cfg('hype.round_social')));
  for r in select id from profiles where location_id = p_loc and id <> p_user and travel_to is null order by last_seen desc nulls last limit 200 loop
    perform bl_adjust_needs(r.id, v_eff);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.bl_hype_round(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. do_activity (live definition + Shut down the club price/cred + hype)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.do_activity(p_activity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me     profiles := bl_me();
  a        activities;
  v_scene  text;
  v_until  timestamptz;
  v_eff    jsonb;
  v_used   text[] := '{}';
  r        record;
  v_pct    numeric;
  v_rent   boolean := false;
  v_msg    text;
  v_from   jsonb;
  v_secs   numeric;
  v_furn   jsonb;
  v_loc    locations;
  v_hour   numeric;
  v_robbed jsonb;
  v_hype   jsonb;
  v_round  int;
begin
  perform bl_assert_free(v_me);
  select * into a from activities where id = p_activity;
  if not found then
    raise exception 'That activity doesn''t exist.' using errcode = 'P0001';
  end if;
  -- P2: Shut down the club follows its admin settings
  if a.id = 'shut_down_club' then
    a.cost := greatest(0, round(bl_cfg('hype.shutdown_cost')))::bigint;
    a.effects := a.effects || jsonb_build_object('street_cred', greatest(0, round(bl_cfg('hype.shutdown_cred')))::int);
  end if;
  select * into v_loc from locations where id = v_me.location_id;
  v_scene := v_loc.scene;
  if not (v_scene = any(a.scenes)) then
    raise exception 'You can''t do "%" here. Go where it is offered.', a.name using errcode = 'P0001';
  end if;
  if cardinality(a.location_ids) > 0 and not (v_loc.id = any (a.location_ids)) then
    raise exception '"%" is only at %.', a.name,
      (select string_agg(name, ', ' order by sort) from locations where id = any (a.location_ids))
      using errcode = 'P0001', hint = 'wrong_place';
  end if;
  if a.home_only and v_me.location_id <> v_me.home_location_id then
    raise exception 'You can only do "%" in your own home.', a.name using errcode = 'P0001';
  end if;
  v_furn := bl_furniture_for(v_me.id, a.id);
  if a.home_only and a.needs_furniture and not (v_furn->>'owned')::boolean then
    raise exception 'You don''t have the furniture for "%" at home yet.', a.name
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  if a.night_only and not (bl_game_clock()->>'is_night')::boolean then
    raise exception '"%" is a night-time thing. Come back after dark.', a.name using errcode = 'P0001';
  end if;
  -- opening hours (after the night-only rule, so its message stays the same)
  if not a.home_only then
    perform bl_assert_place_open(v_loc);
  end if;
  -- rush hour: it can sell out (nothing is charged)
  if coalesce(a.rush->>'pct', '') <> '' and (a.rush->>'pct')::numeric > 0 then
    v_hour := (bl_game_clock()->>'hour')::numeric;
    if v_hour >= coalesce((a.rush->>'from')::numeric, 0) and v_hour < coalesce((a.rush->>'to')::numeric, 24)
       and bl_rand() < (a.rush->>'pct')::numeric / 100.0 then
      raise exception '%', coalesce(nullif(a.rush->>'line', ''), a.name || ' is sold out right now. Try again soon.')
        using errcode = 'P0001', hint = 'sold_out';
    end if;
  end if;
  if a.cost > 0 then
    perform bl_add_money(v_me.id, 'cash', -a.cost, 'activity', jsonb_build_object('activity', a.id));
  end if;

  v_eff := a.effects;
  for r in select it.id, it.name, it.effects->'boost'->a.id as bonus
             from inventory i join items it on it.id = i.item_id
            where i.user_id = v_me.id and i.qty > 0 and jsonb_typeof(it.effects->'boost'->a.id) = 'object'
            order by it.sort, it.id loop
    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(r.bonus));
    perform bl_give_item(v_me.id, r.id, -1);
    v_used := v_used || r.name;
  end loop;
  -- how well this piece rests you (foam mat < bed)
  if a.home_only and (v_furn->>'owned')::boolean and (v_furn->>'rest_pct')::numeric <> 100
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_eff := v_eff || jsonb_build_object('energy',
               round((v_eff->>'energy')::numeric * greatest(0, least(200, (v_furn->>'rest_pct')::numeric)) / 100, 1));
  end if;
  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text('rent.owed_sleep_activities'), a.id)
     and coalesce((v_eff->>'energy')::numeric, 0) > 0 then
    v_pct := greatest(0, least(100, bl_cfg('rent.owed_sleep_energy_pct')));
    if v_pct < 100 then
      v_eff := v_eff || jsonb_build_object('energy', round((v_eff->>'energy')::numeric * v_pct / 100, 1));
      v_rent := true;
    end if;
  end if;

  v_from := bl_needs_snapshot(v_me);
  v_secs := bl_activity_seconds(v_me, a, a.effects);
  perform bl_adjust_needs(v_me.id, v_eff);
  if coalesce((v_eff->>'street_cred')::int, 0) <> 0 then
    update profiles set street_cred = greatest(0, street_cred + (v_eff->>'street_cred')::int) where id = v_me.id;
  end if;
  v_until := bl_set_busy_seconds(v_me.id, v_secs, a.name);
  update profiles set busy_needs_from = v_from where id = v_me.id;
  v_msg := 'You started "' || a.name || '"'
           || case when a.cost > 0 then ' (' || bl_naira(a.cost) || ').' else '. Enjoy!' end;
  if cardinality(v_used) > 0 then
    v_msg := v_msg || ' Used: ' || array_to_string(v_used, ', ') || '.';
  end if;
  if v_rent then
    v_msg := v_msg || ' The landlord keeps knocking: "Where my rent? You owe ' || bl_naira(v_me.rent_owed)
             || '!" You won''t rest well until you pay.';
  end if;
  -- Risky: flashing money here can attract the wrong boys (the usual street robbery roll at this place)
  if a.risky then
    v_robbed := bl_roll_street_robbery(v_me.id, v_loc.id, 'walk', 1.0);
    if v_robbed is not null then
      v_msg := v_msg || ' Omo! Somebody dipped hand for your pocket: ' || bl_naira((v_robbed->>'amount')::bigint) || ' gone.';
    end if;
  end if;
  -- P2: club spends get the hype man's announcement (server-side only); Shut down the club buys a round
  if v_scene = 'club' and bl_hype_kind(a.id) is not null then
    if a.id = 'shut_down_club' then
      v_round := bl_hype_round(v_me.id, v_loc.id);
      v_msg := v_msg || ' The DJ cuts the music, the MC calls your name: drinks on you for '
               || coalesce(v_round, 0) || case when v_round = 1 then ' other player' else ' other players' end || ' here!';
    end if;
    v_hype := bl_hype_announce(v_me.id, v_loc.id, bl_hype_kind(a.id), a.cost, 1, a.id = 'shut_down_club');
  end if;
  return jsonb_build_object('message', v_msg, 'busy_until', v_until, 'effects', v_eff,
                            'used', to_jsonb(v_used), 'rent_penalty', v_rent, 'real_seconds', v_secs,
                            'robbed', v_robbed, 'hype', v_hype);
end $function$;
revoke execute on function public.do_activity(text) from public, anon;
grant execute on function public.do_activity(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 7. shop_buy (live definition + bottles hype, counted over the window)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shop_buy(p_item text, p_qty integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me    profiles := bl_me();
  it      items;
  l       locations;
  v_total bigint;
  v_owned int;
  v_where text;
  v_msg   text;
  v_bank  bigint := 0;
  v_cash  bigint := 0;
  v_hype  jsonb;
  v_n     int;
  v_sum   bigint;
begin
  perform bl_assert_free(v_me);
  it := bl_item(p_item);
  perform bl_check_qty(p_qty);
  l := bl_location(v_me.location_id);
  if not (l.id = any (it.sold_at)) then
    select string_agg(x.name, ', ' order by x.sort) into v_where
      from (select name, sort from locations where id = any (it.sold_at) order by sort limit 3) x;
    raise exception '% is not sold here.%', it.name,
      case when v_where is null then ' It is not sold anywhere right now.' else ' Try ' || v_where || '.' end
      using errcode = 'P0001', hint = 'not_sold_here';
  end if;
  perform bl_assert_place_open(l);
  v_total := it.price * p_qty;

  if it.category = 'vehicle' then
    if p_qty <> 1 then
      raise exception 'One car at a time, please.' using errcode = 'P0001', hint = 'bad_qty';
    end if;
    if exists (select 1 from inventory where user_id = v_me.id and item_id = it.id and qty > 0) then
      raise exception 'You already own a %. Pick a different car.', it.name using errcode = 'P0001', hint = 'already_owned';
    end if;
    if bl_cfg_bool('cars.bank_first') then
      v_bank := least(v_me.bank, v_total);
      v_cash := v_total - v_bank;
    else
      v_cash := v_total;
    end if;
    if v_cash > v_me.cash then
      raise exception 'Not enough money. % costs % and you have % (bank % + cash %).', it.name, bl_naira(v_total),
        bl_naira(v_me.bank + v_me.cash), bl_naira(v_me.bank), bl_naira(v_me.cash)
        using errcode = 'P0001', hint = 'not_enough_cash';
    end if;
    if v_bank > 0 then
      perform bl_add_money(v_me.id, 'bank', -v_bank, 'car_purchase', jsonb_build_object('item', it.id, 'location', l.id));
    end if;
    if v_cash > 0 then
      perform bl_add_money(v_me.id, 'cash', -v_cash, 'car_purchase', jsonb_build_object('item', it.id, 'location', l.id));
    end if;
    v_owned := bl_give_item(v_me.id, it.id, 1);
    v_msg := 'Congrats! You bought a ' || it.name || ' for ' || bl_naira(v_total)
             || '. "Your car" is now a travel option in the Ride app and the place sheets.';
    return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', 1, 'owned', v_owned, 'spent', v_total,
                              'from_bank', v_bank, 'from_cash', v_cash, 'cash', v_me.cash - v_cash, 'bank', v_me.bank - v_bank,
                              'car', true);
  end if;

  if v_total > v_me.cash then
    raise exception 'Not enough cash. % costs % and you have % on you.',
      case when p_qty > 1 then p_qty || ' × ' || it.name else it.name end, bl_naira(v_total), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_total > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_total, 'shop',
                         jsonb_build_object('item', it.id, 'qty', p_qty, 'location', l.id));
  end if;
  v_owned := bl_give_item(v_me.id, it.id, p_qty);
  v_msg := 'You bought ' || case when p_qty > 1 then p_qty || ' × ' else '' end || it.name
           || ' for ' || bl_naira(v_total) || '. It''s in your Bag.';
  if l.scene = 'market' then v_msg := v_msg || ' "Thank you o, come back again!"'; end if;
  -- P2: bottles in a club count up over the window ("E don pop 3 bottles") and get announced
  if l.scene = 'club' and bl_hype_kind(it.id) is not null then
    select coalesce(sum((meta->>'qty')::int), 0), coalesce(-sum(delta), 0) into v_n, v_sum
      from ledger
     where user_id = v_me.id and reason = 'shop' and meta->>'item' = it.id and meta->>'location' = l.id
       and created_at > now() - make_interval(secs => greatest(10, bl_cfg('hype.bottle_window_s')));
    v_hype := bl_hype_announce(v_me.id, l.id, bl_hype_kind(it.id), greatest(v_sum, v_total), greatest(v_n, p_qty), false);
  end if;
  return jsonb_build_object('message', v_msg, 'item', it.id, 'qty', p_qty, 'owned', v_owned,
                            'spent', v_total, 'cash', v_me.cash - v_total, 'hype', v_hype);
end $function$;
revoke execute on function public.shop_buy(text, integer) from public, anon;
grant execute on function public.shop_buy(text, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 8. Admin: Content -> Hype lines (live definition + hype_templates)
-- ---------------------------------------------------------------------
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
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null"}}'
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
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;
