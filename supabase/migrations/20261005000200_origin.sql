-- =====================================================================
-- Benin Life — starting class roll: LAPO baby vs Nepo baby     (owner: P1-ORIGIN)
-- Reference: docs/ORIGIN.md.  Idempotent: safe to re-run.
--
-- * origin_tiers: data-driven tiers. Adding a tier = one row + its origin.<tier>.* config rows
--   (+ the roll % key named in chance_key). Any origin.<tier>.* key that is missing falls back to
--   the matching start.* key (cash/bank/home/housing) or to 0 / nothing.
-- * create_profile (same signature) rolls the tier and applies its starter pack.
-- * get_my_state (still read-only) adds an `origin` block for the client.
-- * claim_allowance(): daily "Papa money" for tiers whose allowance_daily > 0.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. origin_tiers + profiles columns
-- ---------------------------------------------------------------------
create table if not exists public.origin_tiers (
  id         text primary key check (id ~ '^[a-z0-9_]{2,24}$'),
  name       text not null,
  tagline    text not null default '',
  -- welcome event body; placeholders {name} {home} {cash} {bank}
  welcome    text not null default '',
  chance_key text,                      -- game_config key with this tier's roll % (null = default tier)
  is_default boolean not null default false,
  sort       int not null default 0,
  perks      jsonb not null default '{}'::jsonb,   -- future hooks, e.g. {"micro_loan_access": "easy"}
  check (is_default or chance_key is not null)
);
-- exactly one default tier (at most one by index; the seed below provides it)
create unique index if not exists origin_tiers_one_default on public.origin_tiers ((true)) where is_default;

alter table public.origin_tiers enable row level security;
revoke all on table public.origin_tiers from anon, authenticated;
grant select on public.origin_tiers to anon, authenticated;
drop policy if exists origin_tiers_read on public.origin_tiers;
create policy origin_tiers_read on public.origin_tiers for select to anon, authenticated using (true);

insert into public.origin_tiers (id, name, tagline, welcome, chance_key, is_default, sort, perks) values
('lapo', 'LAPO baby',
 'Na hustle go carry you. Small room, small money, big dream.',
 'Oya {name}, you don land for {home} with {cash} for pocket. Na hustle go carry you — find work, chop well, and no carry too much cash for night o.',
 null, true, 100,
 '{"micro_loan_access": "easy"}'),
('nepo', 'Nepo baby',
 'Omo! Papa get connection. Duplex, motor, laptop — just no spoil the family name.',
 'Omo {name}! Papa don settle you: {home}, {cash} for pocket and {bank} for bank. Motor dey outside. Abeg no spoil the family name o.',
 'origin.nepo_pct', false, 10,
 '{"papa_allowance": true}')
on conflict (id) do nothing;

alter table public.profiles add column if not exists origin text not null default 'lapo'
  references public.origin_tiers(id) on update cascade;
alter table public.profiles add column if not exists allowance_claimed_day int;

-- ---------------------------------------------------------------------
-- 2. Config (admin-tunable)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('origin.nepo_pct', '10', 'origin', 'Nepo baby chance (%)', 'Chance a new player is rolled as a Nepo baby. Everybody else is the default tier (LAPO baby).', 'percent', 0, 100),
-- LAPO baby (default tier; mirrors the start.* defaults)
('origin.lapo.start_cash', '5000', 'origin', 'LAPO baby: starting cash', 'Cash a LAPO baby lands with.', 'naira', 0, 100000000),
('origin.lapo.start_bank', '0', 'origin', 'LAPO baby: starting bank', 'Bank balance a LAPO baby starts with.', 'naira', 0, 1000000000),
('origin.lapo.home_location', '"ekenwan_room"', 'origin', 'LAPO baby: home location', 'Location id a LAPO baby lives and spawns at.', 'text', null, null),
('origin.lapo.housing', '"face_me_ekenwan"', 'origin', 'LAPO baby: housing id', 'Housing id assigned to a LAPO baby.', 'text', null, null),
('origin.lapo.items', '""', 'origin', 'LAPO baby: starting items', 'Comma-separated item ids put in the bag at creation (empty = none).', 'text', null, null),
('origin.lapo.career_head_start', '0', 'origin', 'LAPO baby: career head start (levels)', 'Levels added when they take their first job (Phase 2 careers).', 'number', 0, 10),
('origin.lapo.allowance_daily', '0', 'origin', 'LAPO baby: Papa allowance per game day', 'Daily allowance paid into bank by claim_allowance. 0 = none.', 'naira', 0, 100000000),
-- Nepo baby
('origin.nepo.start_cash', '50000', 'origin', 'Nepo baby: starting cash', 'Cash a Nepo baby lands with.', 'naira', 0, 100000000),
('origin.nepo.start_bank', '500000', 'origin', 'Nepo baby: starting bank', 'Bank balance a Nepo baby starts with.', 'naira', 0, 1000000000),
('origin.nepo.home_location', '"gra_duplex"', 'origin', 'Nepo baby: home location', 'Location id a Nepo baby lives and spawns at.', 'text', null, null),
('origin.nepo.housing', '"duplex_gra"', 'origin', 'Nepo baby: housing id', 'Housing id assigned to a Nepo baby.', 'text', null, null),
('origin.nepo.items', '"tokunbo_car,laptop"', 'origin', 'Nepo baby: starting items', 'Comma-separated item ids put in the bag at creation (empty = none).', 'text', null, null),
('origin.nepo.career_head_start', '2', 'origin', 'Nepo baby: career head start (levels)', 'Levels added when they take their first job (Phase 2 careers).', 'number', 0, 10),
('origin.nepo.allowance_daily', '5000', 'origin', 'Nepo baby: Papa allowance per game day', 'Daily allowance paid into bank by claim_allowance. 0 = none.', 'naira', 0, 100000000)
on conflict (key) do nothing;

-- start.* keys are now only fallbacks for tiers that lack their own origin.<tier>.* key.
update public.game_config set description = 'Fallback starting cash for an origin tier with no origin.<tier>.start_cash key.'
  where key = 'start.cash';
update public.game_config set description = 'Fallback starting bank for an origin tier with no origin.<tier>.start_bank key.'
  where key = 'start.bank';
update public.game_config set description = 'Fallback home location for an origin tier with no origin.<tier>.home_location key.'
  where key = 'start.home_location';
update public.game_config set description = 'Fallback housing id for an origin tier with no origin.<tier>.housing key.'
  where key = 'start.housing';

-- ---------------------------------------------------------------------
-- 3. Starter items referenced above (Phase 2 economy owns the full catalog)
-- ---------------------------------------------------------------------
insert into public.items (id, name, category, price, description, effects, sold_at, sellable, resale_pct, icon, sort) values
('tokunbo_car', 'Tokunbo Corolla', 'vehicle', 2500000,
 'Belgium-used Toyota Corolla. E don see road, but engine still dey sing. Fuel na your own palava.',
 '{}', '{}', true, 50, 'car', 500),
('laptop', 'Fairly-used Laptop', 'gadget', 250000,
 'Clean UK-used laptop. Battery fit last two hours if you pray. Na your key for tech work.',
 '{}', '{}', true, 40, 'laptop', 510)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. Helpers (internal)
-- ---------------------------------------------------------------------

-- origin.<tier>.<field> as text; falls back to start.* for cash/bank/home/housing, else null.
create or replace function public.bl_origin_cfg(p_tier text, p_field text) returns text
language plpgsql stable set search_path = public as $$
declare v jsonb; v_fb text;
begin
  select value into v from game_config where key = 'origin.' || p_tier || '.' || p_field;
  if found then return v #>> '{}'; end if;
  v_fb := case p_field when 'start_cash' then 'start.cash'
                       when 'start_bank' then 'start.bank'
                       when 'home_location' then 'start.home_location'
                       when 'housing' then 'start.housing' end;
  if v_fb is not null then return bl_cfg_text(v_fb); end if;
  return null;
end $$;

create or replace function public.bl_origin_num(p_tier text, p_field text) returns numeric
language sql stable set search_path = public as $$
  select coalesce(nullif(trim(bl_origin_cfg(p_tier, p_field)), '')::numeric, 0);
$$;

-- Starting item ids of a tier (trimmed, non-empty, in config order).
create or replace function public.bl_origin_items(p_tier text) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(t.id order by u.ord), '{}')
  from unnest(string_to_array(coalesce(bl_origin_cfg(p_tier, 'items'), ''), ',')) with ordinality as u(raw, ord)
  cross join lateral (select trim(u.raw) as id) t
  where t.id <> '';
$$;

-- One bl_rand() roll; non-default tiers by sort, their % stacking cumulatively; else the default tier.
create or replace function public.bl_roll_origin() returns text
language plpgsql volatile set search_path = public as $$
declare
  v_roll double precision := bl_rand() * 100;
  v_acc  numeric := 0;
  r      record;
  v_id   text;
begin
  for r in select id, chance_key from origin_tiers
           where not is_default and chance_key is not null order by sort, id loop
    v_acc := v_acc + greatest(0, bl_cfg(r.chance_key));
    if v_roll < v_acc then return r.id; end if;
  end loop;
  select id into v_id from origin_tiers where is_default order by sort limit 1;
  if v_id is null then
    raise exception 'Origin setup never complete — admin abeg add default tier.' using errcode = 'P0001';
  end if;
  return v_id;
end $$;

-- Client-facing tier block (pure read).
create or replace function public.bl_origin_info(p_tier text, p_claimed_day int, p_today bigint) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  t origin_tiers;
  v_allow bigint;
begin
  select * into t from origin_tiers where id = p_tier;
  if not found then return null; end if;
  v_allow := bl_origin_num(p_tier, 'allowance_daily')::bigint;
  return jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'tagline', t.tagline,
    'perks', t.perks,
    'career_head_start', bl_origin_num(p_tier, 'career_head_start')::int,
    'allowance_daily', v_allow,
    'allowance_claimable', v_allow > 0 and (p_claimed_day is null or p_claimed_day <> p_today),
    'start_cash', bl_origin_num(p_tier, 'start_cash')::bigint,
    'start_bank', bl_origin_num(p_tier, 'start_bank')::bigint,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', it.id, 'name', it.name, 'category', it.category)
                                        order by array_position(bl_origin_items(p_tier), it.id))
                       from items it where it.id = any (bl_origin_items(p_tier))), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------
-- 5. RPCs
-- ---------------------------------------------------------------------

-- Same as core, plus the `origin` block. Still read-mostly: the only write is the throttled last_seen.
create or replace function public.get_my_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_now   timestamptz := bl_now();
  v_me    profiles;
  v_clock jsonb;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You never create your person yet. Go create am first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_me.banned then
    raise exception 'Dem don ban this account. If na mistake, contact admin.' using errcode = 'P0001', hint = 'banned';
  end if;
  if v_me.last_seen is null
     or v_me.last_seen < v_now - make_interval(secs => bl_cfg('time.last_seen_throttle_real_seconds')::double precision) then
    update profiles set last_seen = v_now where id = v_uid returning * into v_me;
  end if;
  v_me := bl_decay_row(v_me, v_now);
  v_clock := bl_game_clock(v_now);
  return jsonb_build_object(
    'profile', to_jsonb(v_me) - array['banned','needs_updated_at','last_seen',
                                      'travel_to','travel_mode','travel_started_at','travel_arrives_at'],
    'clock', v_clock,
    'location', (select to_jsonb(l) from locations l where l.id = v_me.location_id),
    'travel', case when v_me.travel_to is null then null
                   else jsonb_build_object('to', v_me.travel_to, 'mode', v_me.travel_mode,
                                           'started_at', v_me.travel_started_at,
                                           'arrives_at', v_me.travel_arrives_at) end,
    'origin', bl_origin_info(v_me.origin, v_me.allowance_claimed_day, (v_clock->>'day')::bigint),
    'server_time', v_now
  );
end $$;

-- Same signature + validation as core; the starter pack now comes from the rolled origin tier.
create or replace function public.create_profile(p_username text, p_gender text, p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := bl_require_uid();
  v_name   text := trim(coalesce(p_username, ''));
  v_gender text := lower(trim(coalesce(p_gender, '')));
  v_avatar jsonb := coalesce(p_avatar, '{}'::jsonb);
  v_now    timestamptz := bl_now();
  v_need   numeric := bl_cfg('start.need_level');
  v_tier   origin_tiers;
  v_home   locations;
  v_cash   bigint;
  v_bank   bigint;
  v_item   text;
  v_tier_id text;
begin
  if exists (select 1 from profiles where id = v_uid) then
    raise exception 'You don already create your person. One account, one person.' using errcode = 'P0001';
  end if;
  if v_name !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username suppose be 3 to 20 letters, numbers or underscore (_) — no space, no funny character.'
      using errcode = 'P0001';
  end if;
  if v_gender not in ('male','female') then
    raise exception 'Pick male or female abeg.' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_avatar) <> 'object' or length(v_avatar::text) > 4000 then
    raise exception 'Your avatar data no correct. Try again.' using errcode = 'P0001';
  end if;
  if exists (select 1 from profiles where lower(username) = lower(v_name)) then
    raise exception 'Somebody don already carry "%" as username. Try another one.', v_name using errcode = 'P0001';
  end if;

  v_tier_id := bl_roll_origin();   -- roll once (a volatile call inside WHERE would re-roll per row)
  select * into v_tier from origin_tiers where id = v_tier_id;
  v_home := bl_location(bl_origin_cfg(v_tier.id, 'home_location'));
  v_cash := greatest(0, bl_origin_num(v_tier.id, 'start_cash'))::bigint;
  v_bank := greatest(0, bl_origin_num(v_tier.id, 'start_bank'))::bigint;

  begin
    insert into profiles (id, username, gender, avatar, cash, bank,
                          hunger, energy, hygiene, fun, social, health, stress, needs_updated_at,
                          location_id, home_location_id, housing_id, origin,
                          protected_until, last_seen, created_at)
    values (v_uid, v_name, v_gender, v_avatar, 0, 0,
            v_need, v_need, v_need, v_need, v_need, bl_cfg('start.health'), bl_cfg('start.stress'), v_now,
            v_home.id, v_home.id, bl_origin_cfg(v_tier.id, 'housing'), v_tier.id,
            v_now + make_interval(mins => bl_cfg('start.protection_real_minutes')::int), v_now, v_now);
  exception when unique_violation then
    raise exception 'Somebody don already carry "%" as username. Try another one.', v_name using errcode = 'P0001';
  end;

  if v_cash > 0 then perform bl_add_money(v_uid, 'cash', v_cash, 'start_bonus', jsonb_build_object('origin', v_tier.id)); end if;
  if v_bank > 0 then perform bl_add_money(v_uid, 'bank', v_bank, 'start_bonus', jsonb_build_object('origin', v_tier.id)); end if;

  -- starter items; unknown ids are skipped so a config typo never blocks sign-up
  foreach v_item in array bl_origin_items(v_tier.id) loop
    if exists (select 1 from items where id = v_item) then
      insert into inventory (user_id, item_id, qty) values (v_uid, v_item, 1)
      on conflict (user_id, item_id) do update set qty = inventory.qty + 1;
    end if;
  end loop;

  perform bl_event(v_uid, 'welcome', 'Welcome to Benin!',
                   replace(replace(replace(replace(v_tier.welcome,
                     '{name}', v_name), '{home}', v_home.name), '{cash}', bl_naira(v_cash)), '{bank}', bl_naira(v_bank)),
                   jsonb_build_object('origin', v_tier.id));
  return get_my_state();
end $$;

-- Daily Papa allowance into bank. Works while busy, on the road or in hospital (it's a bank
-- transfer); not while jailed. Once per game day (bl_game_clock day).
create or replace function public.claim_allowance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_amt   bigint;
  v_day   int := (bl_game_clock()->>'day')::int;
  v_bal   bigint;
begin
  v_amt := bl_origin_num(v_me.origin, 'allowance_daily')::bigint;
  if v_amt <= 0 then
    raise exception 'No Papa allowance for your side o. Na your own hustle go pay you — and e go sweet you pass.'
      using errcode = 'P0001', hint = 'no_allowance';
  end if;
  if v_me.jailed_until is not null and v_me.jailed_until > bl_now() then
    raise exception 'Papa hear say you dey cell. Him no go send kobo until you comot.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.allowance_claimed_day is not distinct from v_day then
    raise exception 'Papa don already send today own. Wait till tomorrow abeg.' using errcode = 'P0001', hint = 'already_claimed';
  end if;
  update profiles set allowance_claimed_day = v_day where id = v_me.id;
  v_bal := bl_add_money(v_me.id, 'bank', v_amt, 'allowance', jsonb_build_object('origin', v_me.origin, 'day', v_day));
  return jsonb_build_object(
    'message', 'Papa don send ' || bl_naira(v_amt) || ' enter your account. No spend am anyhow o.',
    'amount', v_amt, 'account', 'bank', 'bank', v_bal, 'day', v_day);
end $$;

-- ---------------------------------------------------------------------
-- 6. Function privileges
-- ---------------------------------------------------------------------
revoke execute on function public.bl_origin_cfg(text, text)          from public, anon, authenticated;
revoke execute on function public.bl_origin_num(text, text)          from public, anon, authenticated;
revoke execute on function public.bl_origin_items(text)              from public, anon, authenticated;
revoke execute on function public.bl_roll_origin()                   from public, anon, authenticated;
revoke execute on function public.bl_origin_info(text, int, bigint)  from public, anon, authenticated;

revoke execute on function public.get_my_state()                  from public, anon;
revoke execute on function public.create_profile(text, text, jsonb) from public, anon;
revoke execute on function public.claim_allowance()               from public, anon;
grant execute on function public.get_my_state()                  to authenticated;
grant execute on function public.create_profile(text, text, jsonb) to authenticated;
grant execute on function public.claim_allowance()               to authenticated;
