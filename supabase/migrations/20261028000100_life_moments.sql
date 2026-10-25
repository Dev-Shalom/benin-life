-- Life moments (docs/MOMENTS.md): the reusable BitLife-style pop-up engine. A short card with a speaker, a story and up to four choices.
-- Content is written in Admin -> Content -> Life moments; the server only runs a CLOSED list of effects, so a moment can never run code.
--   * life_moments    : the stories (conditions, choices with cost / effects / outcome / chance, cooldown, weight).
--   * player_moments  : one row per card a player got (pending / snoozed / scheduled / answered / expired).
--   * player_moment_state : one row per player, the next time a random moment may be rolled (so polling costs one primary-key read).
-- Everything is lazy (no cron): moments_pending() expires old cards, rolls at most one new random card when the gap has passed and the
-- daily cap (moments.daily_cap, Benin day) allows it, and returns at most moments.max_shown due cards. Kids illness cards are created
-- by the kids logic (20261028000200_kids_v2.sql) for BOTH parents through bl_moment_create(); school requests and cooking can do the same.
-- Clients never touch the tables: RLS on, no grants. Idempotent: tables `if not exists`, seeds `on conflict do nothing`, live functions
-- patched ONLY through guarded replaces (raise when the marker is missing, skip when already applied).

create or replace function pg_temp.lm_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'life_moments: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Life moments)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('moments.enabled', 'true', 'moments', 'Life moments on',
 'Master switch for the story pop-ups (landlord, NEPA, a friend asking for a loan, the doctor...). Off = no new cards and none are shown.', 'bool', null, null),
('moments.daily_cap', '3', 'moments', 'Most moments per player per day',
 'Random moments stop for the day after this many cards (a Benin day). Kids illness cards count too, but a sick child always gets its doctor card.', 'number', 0, 20),
('moments.max_shown', '2', 'moments', 'Cards the app can hold at once',
 'How many due cards the server hands to the app in one read. The app still shows them one at a time.', 'number', 1, 5),
('moments.gap_min_minutes', '45', 'moments', 'Shortest wait between random moments (minutes)',
 'After a random moment the next one waits at least this long (a random time between the shortest and longest wait).', 'minutes', 1, 1440),
('moments.gap_max_minutes', '180', 'moments', 'Longest wait between random moments (minutes)',
 'See the shortest wait.', 'minutes', 1, 2880),
('moments.first_gap_minutes', '5', 'moments', 'First card after opening the game (minutes)',
 'The first time the server sees a player (or a new day) it waits this long before rolling a random moment.', 'minutes', 0, 1440),
('moments.snooze_hours', '2', 'moments', 'Remind me later (hours)',
 'How long "Remind me later" hides a card.', 'number', 0, 72),
('moments.max_snoozes', '3', 'moments', 'Most "Remind me later" per card',
 'After this many snoozes the next "Remind me later" counts as Ignore (the card''s Ignore choice, if it has one, is applied).', 'number', 0, 10),
('moments.expire_hours', '36', 'moments', 'A card expires after (hours)',
 'A card nobody answered for this long expires as Ignore.', 'number', 1, 720),
('moments.max_cash_effect', '1000000', 'moments', 'Biggest money effect in a moment',
 'A moment''s cost or cash effect above this is refused when it is saved in Admin (a safety limit).', 'naira', 0, 1000000000),
('moments.poll_seconds', '90', 'moments', 'App check for new moments (seconds)',
 'How often the game asks the server for a card. It never asks while the tab is hidden or the player is away, and it slows down when idle.', 'number', 30, 600)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.life_moments (
  id            text primary key check (id ~ '^[a-z][a-z0-9_]{1,40}$'),
  title         text not null check (char_length(title) between 2 and 60),
  body          text not null check (char_length(body) between 5 and 500),
  icon          text not null default '✨' check (char_length(icon) between 1 and 8),
  speaker       text not null default '' check (char_length(speaker) <= 60),
  kind          text not null default 'random' check (kind in ('random', 'kids_ill', 'system')),
  conditions    jsonb not null default '{}'::jsonb check (jsonb_typeof(conditions) = 'object'),
  choices       jsonb not null default '[]'::jsonb check (jsonb_typeof(choices) = 'array'),
  cooldown_days numeric not null default 7 check (cooldown_days between 0 and 365),
  weight        numeric not null default 1 check (weight between 0 and 1000),
  push          boolean not null default false,
  active        boolean not null default true,
  sort          integer not null default 100
);

create table if not exists public.player_moments (
  id            bigserial primary key,
  user_id       uuid not null,
  moment_id     text not null references public.life_moments(id) on delete cascade,
  context       jsonb not null default '{}'::jsonb,
  status        text not null default 'pending' check (status in ('pending', 'answered', 'snoozed', 'scheduled', 'expired')),
  created_at    timestamptz not null default now(),
  due_at        timestamptz not null default now(),
  show_at       timestamptz not null default now(),
  snoozes       integer not null default 0 check (snoozes >= 0),
  answered_choice text,
  outcome       text,
  answered_at   timestamptz,
  seen_at       timestamptz,
  handled_by    uuid,
  counts        boolean not null default true
);
-- the due lookup (one player, a handful of rows) and the daily cap count
create index if not exists player_moments_due on public.player_moments (user_id, show_at) where status in ('pending', 'snoozed', 'scheduled');
create index if not exists player_moments_user_moment on public.player_moments (user_id, moment_id, id desc);
create index if not exists player_moments_user_day on public.player_moments (user_id, created_at desc);
create index if not exists player_moments_unseen on public.player_moments (user_id) where handled_by is not null and seen_at is null;
-- the other parent's card for the same child and illness
create index if not exists player_moments_child on public.player_moments ((context ->> 'child_id'), moment_id) where status in ('pending', 'snoozed', 'scheduled');

create table if not exists public.player_moment_state (
  user_id      uuid primary key,
  next_roll_at timestamptz not null
);

do $$
declare t text;
begin
  foreach t in array array['life_moments', 'player_moments', 'player_moment_state'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  revoke all on sequence public.player_moments_id_seq from public, anon, authenticated;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Validation: the CLOSED list of conditions and effects (checked when a moment is saved AND again when it runs)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_moment_need_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress', 'bladder']
$$;

create or replace function public.bl_moment_bad(p_msg text) returns void
language plpgsql immutable set search_path = public as $$
begin
  raise exception 'Life moment: %', p_msg using errcode = 'P0001', hint = 'bad_value';
end $$;

-- conditions: min_days, max_days, has_child (list of stage ids, or ["any"]), at (place ids), need_below / need_above ({"fun": 40}),
-- hours ([from, to] Benin hours), min_cash, max_cash (cash + bank), has_item (item ids, any of them)
create or replace function public.bl_moment_check_conditions(p_c jsonb) returns void
language plpgsql stable set search_path = public as $$
declare k text; v jsonb; e text; n text;
begin
  if jsonb_typeof(p_c) is distinct from 'object' then perform bl_moment_bad('conditions must be a JSON object'); end if;
  for k, v in select * from jsonb_each(p_c) loop
    if k in ('min_days', 'max_days', 'min_cash', 'max_cash') then
      if jsonb_typeof(v) is distinct from 'number' or (v #>> '{}')::numeric < 0 then perform bl_moment_bad(k || ' must be a number, 0 or more'); end if;
    elsif k in ('has_child', 'at', 'has_item') then
      if jsonb_typeof(v) is distinct from 'array' or exists (select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) is distinct from 'string') then
        perform bl_moment_bad(k || ' must be a list of text values');
      end if;
      if k = 'at' then
        for e in select jsonb_array_elements_text(v) loop
          if not exists (select 1 from locations where id = e) then perform bl_moment_bad('unknown place id ' || e); end if;
        end loop;
      elsif k = 'has_item' then
        for e in select jsonb_array_elements_text(v) loop
          if not exists (select 1 from items where id = e) then perform bl_moment_bad('unknown item id ' || e); end if;
        end loop;
      end if;
    elsif k in ('need_below', 'need_above') then
      if jsonb_typeof(v) is distinct from 'object' then perform bl_moment_bad(k || ' must look like {"fun": 40}'); end if;
      for n in select jsonb_object_keys(v) loop
        if n <> all (bl_moment_need_keys()) then perform bl_moment_bad('unknown need ' || n); end if;
        if jsonb_typeof(v -> n) is distinct from 'number' or (v ->> n)::numeric not between 0 and 100 then perform bl_moment_bad(n || ' must be 0 to 100'); end if;
      end loop;
    elsif k = 'hours' then
      if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v) <> 2 or exists (select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) is distinct from 'number' or (x #>> '{}')::numeric not between 0 and 24) then
        perform bl_moment_bad('hours must look like [18, 23]');
      end if;
    else
      perform bl_moment_bad('unknown condition "' || k || '"');
    end if;
  end loop;
end $$;

-- one effect: cash, needs, kid_need, kid_cure, kid_ignore, item, skill_xp, street_cred, follow_up
create or replace function public.bl_moment_check_effect(e jsonb) returns void
language plpgsql stable set search_path = public as $$
declare t text; v_max numeric := bl_love_num('moments.max_cash_effect', 1000000); n text; d jsonb;
begin
  if jsonb_typeof(e) is distinct from 'object' then perform bl_moment_bad('an effect must be a JSON object'); end if;
  t := e ->> 't';
  case t
    when 'cash' then
      if jsonb_typeof(e -> 'amount') is distinct from 'number' or (e ->> 'amount')::numeric = 0 or (e ->> 'amount')::numeric <> trunc((e ->> 'amount')::numeric) then
        perform bl_moment_bad('cash needs a whole "amount" (negative = pay, positive = gain)');
      end if;
      if abs((e ->> 'amount')::numeric) > v_max then perform bl_moment_bad('cash amount is above moments.max_cash_effect'); end if;
    when 'needs' then
      d := e -> 'delta';
      if jsonb_typeof(d) is distinct from 'object' then perform bl_moment_bad('needs needs a "delta" object like {"fun": 10}'); end if;
      for n in select jsonb_object_keys(d) loop
        if n <> all (bl_moment_need_keys()) then perform bl_moment_bad('unknown need ' || n); end if;
        if jsonb_typeof(d -> n) is distinct from 'number' or abs((d ->> n)::numeric) > 50 then perform bl_moment_bad(n || ' must be a number from -50 to 50'); end if;
      end loop;
    when 'kid_need' then
      if (e ->> 'need') is null or (e ->> 'need') <> all (array['hunger', 'sleep', 'fun', 'health', 'love', 'clean']) then perform bl_moment_bad('kid_need needs a child need'); end if;
      if jsonb_typeof(e -> 'delta') is distinct from 'number' or abs((e ->> 'delta')::numeric) > 50 then perform bl_moment_bad('kid_need delta must be -50 to 50'); end if;
    when 'kid_cure', 'kid_ignore' then
      null;
    when 'item' then
      if not exists (select 1 from items where id = e ->> 'id') then perform bl_moment_bad('unknown item id ' || coalesce(e ->> 'id', '?')); end if;
      if jsonb_typeof(e -> 'qty') is distinct from 'number' or (e ->> 'qty')::numeric = 0 or abs((e ->> 'qty')::numeric) > 20 or (e ->> 'qty')::numeric <> trunc((e ->> 'qty')::numeric) then
        perform bl_moment_bad('item qty must be a whole number from -20 to 20, not 0');
      end if;
    when 'skill_xp' then
      if not exists (select 1 from skills where id = e ->> 'skill') then perform bl_moment_bad('unknown skill ' || coalesce(e ->> 'skill', '?')); end if;
      if jsonb_typeof(e -> 'xp') is distinct from 'number' or (e ->> 'xp')::numeric not between 1 and 500 then perform bl_moment_bad('skill_xp xp must be 1 to 500'); end if;
    when 'street_cred' then
      if jsonb_typeof(e -> 'delta') is distinct from 'number' or abs((e ->> 'delta')::numeric) > 20 or (e ->> 'delta')::numeric = 0 then perform bl_moment_bad('street_cred delta must be -20 to 20, not 0'); end if;
    when 'follow_up' then
      if (e ->> 'moment') is null or (e ->> 'moment') !~ '^[a-z][a-z0-9_]{1,40}$' then perform bl_moment_bad('follow_up needs a "moment" id'); end if;
      if e ? 'delay_hours' and (jsonb_typeof(e -> 'delay_hours') is distinct from 'number' or (e ->> 'delay_hours')::numeric not between 0 and 720) then perform bl_moment_bad('delay_hours must be 0 to 720'); end if;
      if e ? 'chance' and (jsonb_typeof(e -> 'chance') is distinct from 'number' or (e ->> 'chance')::numeric not between 0 and 100) then perform bl_moment_bad('chance must be 0 to 100'); end if;
    else
      perform bl_moment_bad('unknown effect type "' || coalesce(t, '?') || '"');
  end case;
end $$;

create or replace function public.bl_moment_check_effects(p_e jsonb) returns void
language plpgsql stable set search_path = public as $$
declare e jsonb;
begin
  if p_e is null then return; end if;
  if jsonb_typeof(p_e) is distinct from 'array' then perform bl_moment_bad('effects must be a list'); end if;
  if jsonb_array_length(p_e) > 8 then perform bl_moment_bad('at most 8 effects per choice'); end if;
  for e in select * from jsonb_array_elements(p_e) loop perform bl_moment_check_effect(e); end loop;
end $$;

-- choices: 1 to 4 of {id, label, cost, effects, outcome, chance?, fail_effects?, fail_outcome?, ignore?, next_moment?, next_delay_hours?, next_chance?}
create or replace function public.bl_moment_check_choices(p_choices jsonb) returns void
language plpgsql stable set search_path = public as $$
declare c jsonb; v_ids text[] := '{}'; v_max numeric := bl_love_num('moments.max_cash_effect', 1000000); k text;
begin
  if jsonb_typeof(p_choices) is distinct from 'array' then perform bl_moment_bad('choices must be a list'); end if;
  if jsonb_array_length(p_choices) > 4 then perform bl_moment_bad('at most 4 choices'); end if;
  for c in select * from jsonb_array_elements(p_choices) loop
    if jsonb_typeof(c) is distinct from 'object' then perform bl_moment_bad('a choice must be a JSON object'); end if;
    for k in select jsonb_object_keys(c) loop
      if k <> all (array['id', 'label', 'cost', 'effects', 'outcome', 'chance', 'fail_effects', 'fail_outcome', 'ignore', 'next_moment', 'next_delay_hours', 'next_chance']) then
        perform bl_moment_bad('unknown choice field "' || k || '"');
      end if;
    end loop;
    if coalesce(c ->> 'id', '') !~ '^[a-z][a-z0-9_]{0,23}$' then perform bl_moment_bad('each choice needs an id (lowercase letters, digits, _)'); end if;
    if (c ->> 'id') = any (v_ids) then perform bl_moment_bad('two choices share the id ' || (c ->> 'id')); end if;
    v_ids := v_ids || (c ->> 'id');
    if char_length(coalesce(c ->> 'label', '')) not between 1 and 40 then perform bl_moment_bad('a choice label is 1 to 40 characters'); end if;
    if char_length(coalesce(c ->> 'outcome', '')) not between 1 and 300 then perform bl_moment_bad('a choice outcome is 1 to 300 characters'); end if;
    if c ? 'fail_outcome' and char_length(coalesce(c ->> 'fail_outcome', '')) not between 1 and 300 then perform bl_moment_bad('fail_outcome is 1 to 300 characters'); end if;
    if c ? 'cost' and (jsonb_typeof(c -> 'cost') is distinct from 'number' or (c ->> 'cost')::numeric < 0 or (c ->> 'cost')::numeric <> trunc((c ->> 'cost')::numeric) or (c ->> 'cost')::numeric > v_max) then
      perform bl_moment_bad('cost must be a whole naira amount, 0 up to moments.max_cash_effect');
    end if;
    if c ? 'chance' and (jsonb_typeof(c -> 'chance') is distinct from 'number' or (c ->> 'chance')::numeric not between 0 and 100) then perform bl_moment_bad('chance must be 0 to 100'); end if;
    if c ? 'ignore' and jsonb_typeof(c -> 'ignore') is distinct from 'boolean' then perform bl_moment_bad('ignore must be true or false'); end if;
    if c ? 'ignore' and jsonb_typeof(c -> 'ignore') = 'boolean' and (c ->> 'ignore')::boolean and coalesce((c ->> 'cost')::numeric, 0) > 0 then perform bl_moment_bad('an Ignore choice must be free'); end if;
    if c ? 'next_moment' and (coalesce(c ->> 'next_moment', '') !~ '^[a-z][a-z0-9_]{1,40}$') then perform bl_moment_bad('next_moment must be a moment id'); end if;
    if c ? 'next_delay_hours' and (jsonb_typeof(c -> 'next_delay_hours') is distinct from 'number' or (c ->> 'next_delay_hours')::numeric not between 0 and 720) then perform bl_moment_bad('next_delay_hours must be 0 to 720'); end if;
    if c ? 'next_chance' and (jsonb_typeof(c -> 'next_chance') is distinct from 'number' or (c ->> 'next_chance')::numeric not between 0 and 100) then perform bl_moment_bad('next_chance must be 0 to 100'); end if;
    perform bl_moment_check_effects(c -> 'effects');
    perform bl_moment_check_effects(c -> 'fail_effects');
  end loop;
end $$;

-- The row guard: valid content and clean words (the chat banned-words list).
create or replace function public.bl_moments_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare c jsonb;
begin
  if bl_chat_mask(new.title) <> new.title or bl_chat_mask(new.body) <> new.body or bl_chat_mask(new.speaker) <> new.speaker then
    raise exception 'Keep the words clean: the title, story or speaker has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
  end if;
  perform bl_moment_check_conditions(new.conditions);
  perform bl_moment_check_choices(new.choices);
  for c in select * from jsonb_array_elements(new.choices) loop
    if bl_chat_mask(coalesce(c ->> 'label', '')) <> coalesce(c ->> 'label', '') or bl_chat_mask(coalesce(c ->> 'outcome', '')) <> coalesce(c ->> 'outcome', '')
       or bl_chat_mask(coalesce(c ->> 'fail_outcome', '')) <> coalesce(c ->> 'fail_outcome', '') then
      raise exception 'Keep the words clean: a choice has a banned word.' using errcode = 'P0001', hint = 'blocked_text';
    end if;
  end loop;
  if new.active and jsonb_array_length(new.choices) = 0 then
    raise exception 'Life moment: a moment that is on needs at least one choice.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  return new;
end $$;
drop trigger if exists life_moments_guard on public.life_moments;
create trigger life_moments_guard before insert or update on public.life_moments for each row execute function public.bl_moments_guard();

-- ---------------------------------------------------------------------------------------------
-- 4. Private helpers (revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_moments_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('moments.enabled'), true)
$$;

-- start of the player's Benin day
create or replace function public.bl_moment_day_start(p_at timestamptz default null) returns timestamptz
language sql stable set search_path = public as $$
  select date_trunc('day', coalesce(p_at, bl_now()) at time zone bl_clock_tz()) at time zone bl_clock_tz()
$$;

-- {name} = the player, {child} = the child on the card, {partner} = the other parent
create or replace function public.bl_moment_text(p_text text, p_uid uuid, p_ctx jsonb) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_name text; v_child text; v_partner text; v_cid bigint := nullif(p_ctx ->> 'child_id', '')::bigint; v_a uuid; v_b uuid;
begin
  if p_text is null or position('{' in p_text) = 0 then return p_text; end if;
  select username into v_name from profiles where id = p_uid;
  if v_cid is not null then
    select coalesce(k.name, 'your baby'), k.parent_a, k.parent_b into v_child, v_a, v_b from kids_children k where k.id = v_cid;
    if v_a is not null or v_b is not null then
      select username into v_partner from profiles where id = case when v_a = p_uid then v_b else v_a end;
    end if;
  end if;
  return replace(replace(replace(p_text, '{name}', coalesce(v_name, 'you')), '{child}', coalesce(v_child, 'your child')),
                 '{partner}', coalesce(v_partner, 'your partner'));
end $$;

-- Does this player pass the moment's conditions right now? (p is a profile whose needs were already decayed)
create or replace function public.bl_moment_ok(m public.life_moments, p public.profiles, p_now timestamptz) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare c jsonb := m.conditions; k text; v jsonb; v_days numeric; v_tz text; v_h numeric; v_from numeric; v_to numeric; v_cash numeric;
begin
  if c = '{}'::jsonb then return true; end if;
  v_days := extract(epoch from (p_now - p.created_at)) / 86400;
  if c ? 'min_days' and v_days < (c ->> 'min_days')::numeric then return false; end if;
  if c ? 'max_days' and v_days > (c ->> 'max_days')::numeric then return false; end if;
  if c ? 'at' and not (p.location_id in (select jsonb_array_elements_text(c -> 'at'))) then return false; end if;
  if c ? 'has_child' then
    if not exists (select 1 from kids_children kc
                    where (kc.parent_a = p.id or kc.parent_b = p.id) and kc.status = 'home'
                      and ((c -> 'has_child') ? 'any' or bl_kids_stage_of(kc, p_now) in (select jsonb_array_elements_text(c -> 'has_child')))) then
      return false;
    end if;
  end if;
  if c ? 'need_below' then
    for k, v in select * from jsonb_each(c -> 'need_below') loop
      if coalesce((to_jsonb(p) ->> k)::numeric, 100) >= (v #>> '{}')::numeric then return false; end if;
    end loop;
  end if;
  if c ? 'need_above' then
    for k, v in select * from jsonb_each(c -> 'need_above') loop
      if coalesce((to_jsonb(p) ->> k)::numeric, 0) <= (v #>> '{}')::numeric then return false; end if;
    end loop;
  end if;
  if c ? 'hours' then
    v_tz := bl_clock_tz();
    v_h := extract(hour from (p_now at time zone v_tz)) + extract(minute from (p_now at time zone v_tz)) / 60.0;
    v_from := (c -> 'hours' ->> 0)::numeric; v_to := (c -> 'hours' ->> 1)::numeric;
    if v_from <= v_to then
      if not (v_h >= v_from and v_h < v_to) then return false; end if;
    elsif not (v_h >= v_from or v_h < v_to) then
      return false;
    end if;
  end if;
  if c ? 'min_cash' or c ? 'max_cash' then
    v_cash := p.cash + greatest(p.bank, 0);
    if c ? 'min_cash' and v_cash < (c ->> 'min_cash')::numeric then return false; end if;
    if c ? 'max_cash' and v_cash > (c ->> 'max_cash')::numeric then return false; end if;
  end if;
  if c ? 'has_item' and not exists (select 1 from inventory i where i.user_id = p.id and i.qty > 0 and i.item_id in (select jsonb_array_elements_text(c -> 'has_item'))) then
    return false;
  end if;
  return true;
end $$;

-- A new card for a player. p_due in the future = a follow-up that shows later (status scheduled). Returns the instance id.
create or replace function public.bl_moment_create(p_uid uuid, p_moment text, p_ctx jsonb default '{}'::jsonb, p_due timestamptz default null, p_counts boolean default true) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := bl_now(); v_due timestamptz := coalesce(p_due, bl_now()); v_id bigint;
begin
  if p_uid is null or not exists (select 1 from life_moments where id = p_moment) then return null; end if;
  insert into player_moments (user_id, moment_id, context, status, created_at, due_at, show_at, counts)
  values (p_uid, p_moment, coalesce(p_ctx, '{}'::jsonb), case when v_due > v_now then 'scheduled' else 'pending' end, v_now, v_due, v_due, p_counts)
  returning id into v_id;
  return v_id;
end $$;

-- Apply a list of effects for a player. Returns the short lines the app can show ("Paid ₦3,000", "Fun +10"...). Raises on any failure:
-- the caller is one transaction, so a failed payment undoes everything (all or nothing).
create or replace function public.bl_moment_apply(p_uid uuid, pm public.player_moments, p_effects jsonb, p_label text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e jsonb; t text; v_out jsonb := '[]'::jsonb; v_amt bigint; v_have bigint; n text; v_cid bigint := nullif(pm.context ->> 'child_id', '')::bigint;
  v_meta jsonb := jsonb_build_object('label', p_label, 'moment', pm.moment_id); v_due timestamptz; v_ctx jsonb; v_it items;
begin
  if p_effects is null or jsonb_typeof(p_effects) <> 'array' then return v_out; end if;
  perform bl_moment_check_effects(p_effects);
  for e in select * from jsonb_array_elements(p_effects) loop
    t := e ->> 't';
    if t = 'cash' then
      v_amt := (e ->> 'amount')::bigint;
      if v_amt < 0 then
        if coalesce((e ->> 'up_to')::boolean, false) then
          select cash + greatest(bank, 0) into v_have from profiles where id = p_uid;
          v_amt := -least(-v_amt, coalesce(v_have, 0));
        end if;
        if v_amt < 0 then
          perform bl_sink_pay(p_uid, -v_amt, 'life_moment', v_meta);
          v_out := v_out || to_jsonb('Paid ' || bl_naira(-v_amt));
        end if;
      else
        perform bl_add_money(p_uid, 'cash', v_amt, 'life_moment', v_meta);
        v_out := v_out || to_jsonb('Got ' || bl_naira(v_amt));
      end if;
    elsif t = 'needs' then
      perform bl_adjust_needs(p_uid, e -> 'delta');
      for n in select jsonb_object_keys(e -> 'delta') loop
        v_out := v_out || to_jsonb(initcap(n) || ' ' || case when (e -> 'delta' ->> n)::numeric >= 0 then '+' else '' end || (e -> 'delta' ->> n)::numeric::int);
      end loop;
    elsif t = 'kid_need' then
      if v_cid is not null then
        v_out := v_out || coalesce(bl_kids_moment_need(p_uid, v_cid, e ->> 'need', (e ->> 'delta')::numeric, coalesce((e ->> 'all')::boolean, false)), '[]'::jsonb);
      end if;
    elsif t = 'kid_cure' then
      if v_cid is not null then v_out := v_out || coalesce(bl_kids_moment_cure(p_uid, v_cid, pm.context), '[]'::jsonb); end if;
    elsif t = 'kid_ignore' then
      if v_cid is not null then perform bl_kids_moment_ignore(v_cid, pm.context); end if;
    elsif t = 'item' then
      select * into v_it from items where id = e ->> 'id';
      if not found then raise exception 'That item is gone.' using errcode = 'P0001', hint = 'no_item'; end if;
      perform bl_give_item(p_uid, v_it.id, (e ->> 'qty')::int);
      v_out := v_out || to_jsonb(case when (e ->> 'qty')::int > 0 then 'Got ' else 'Used ' end || abs((e ->> 'qty')::int) || ' x ' || v_it.name);
    elsif t = 'skill_xp' then
      perform bl_chal_skill_xp(p_uid, e ->> 'skill', (e ->> 'xp')::int);
      v_out := v_out || to_jsonb('+' || (e ->> 'xp') || ' ' || initcap(e ->> 'skill') || ' XP');
    elsif t = 'street_cred' then
      update profiles set street_cred = greatest(0, street_cred + (e ->> 'delta')::int) where id = p_uid;
      v_out := v_out || to_jsonb('Street cred ' || case when (e ->> 'delta')::int >= 0 then '+' else '' end || (e ->> 'delta')::int);
    elsif t = 'follow_up' then
      if coalesce((e ->> 'chance')::numeric, 100) >= 100 or bl_rand() * 100 < (e ->> 'chance')::numeric then
        v_due := bl_now() + make_interval(secs => (coalesce((e ->> 'delay_hours')::numeric, 0) * 3600)::double precision);
        v_ctx := case when (select kind from life_moments where id = e ->> 'moment') = 'kids_ill' then pm.context else '{}'::jsonb end;
        perform bl_moment_create(p_uid, e ->> 'moment', v_ctx, v_due, false);
      end if;
    end if;
  end loop;
  return v_out;
end $$;

-- A card nobody answered (or one snoozed too often): the choice marked "ignore" is applied (free, no chance), then the card is expired.
create or replace function public.bl_moment_expire(pm public.player_moments) returns text
language plpgsql security definer set search_path = public as $$
declare m public.life_moments; ch jsonb; v_text text;
begin
  select * into m from life_moments where id = pm.moment_id;
  select x into ch from jsonb_array_elements(m.choices) x where coalesce((x ->> 'ignore')::boolean, false) limit 1;
  begin
    if ch is not null then
      perform bl_moment_apply(pm.user_id, pm, ch -> 'effects', m.title);
      v_text := bl_moment_text(ch ->> 'outcome', pm.user_id, pm.context);
    end if;
  exception when others then
    v_text := null;
  end;
  update player_moments set status = 'expired', answered_choice = ch ->> 'id', outcome = v_text, answered_at = bl_now(), seen_at = bl_now() where id = pm.id;
  return v_text;
end $$;

-- Roll one random moment for a player when the wait is over and the day's cap allows it. Never raises.
create or replace function public.bl_moment_roll(p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); st public.player_moment_state; p public.profiles; v_n int; v_cap int := bl_love_num('moments.daily_cap', 3)::int;
  m public.life_moments; v_sum numeric := 0; v_r numeric; v_pick text; v_scene text; v_gmin numeric := bl_love_num('moments.gap_min_minutes', 45);
  v_gmax numeric := greatest(bl_love_num('moments.gap_max_minutes', 180), bl_love_num('moments.gap_min_minutes', 45)); v_id bigint; v_next timestamptz;
begin
  select * into st from player_moment_state where user_id = p_uid for update;
  if not found then
    insert into player_moment_state (user_id, next_roll_at)
    values (p_uid, v_now + make_interval(mins => bl_love_num('moments.first_gap_minutes', 5)::int)) on conflict (user_id) do nothing;
    return null;
  end if;
  if st.next_roll_at > v_now then return null; end if;
  select * into p from profiles where id = p_uid;
  if not found then return null; end if;
  -- not while busy, travelling, in a cell or a hospital bed, and not in a club or lounge (spray and money drops happen there)
  select scene into v_scene from locations where id = p.location_id;
  if (p.busy_until is not null and p.busy_until > v_now) or p.travel_to is not null or (p.jailed_until is not null and p.jailed_until > v_now)
     or (p.hospitalized_until is not null and p.hospitalized_until > v_now) or v_scene in ('club', 'lounge') then
    update player_moment_state set next_roll_at = v_now + interval '10 minutes' where user_id = p_uid;
    return null;
  end if;
  -- daily cap (kids cards count), and never pile up on a player who has not answered yet
  select count(*) into v_n from player_moments x where x.user_id = p_uid and x.counts and x.created_at >= bl_moment_day_start(v_now);
  if v_n >= v_cap then
    update player_moment_state set next_roll_at = bl_moment_day_start(v_now) + interval '1 day' + make_interval(mins => bl_love_num('moments.first_gap_minutes', 5)::int) where user_id = p_uid;
    return null;
  end if;
  select count(*) into v_n from player_moments x where x.user_id = p_uid and x.status in ('pending', 'snoozed') and x.show_at <= v_now;
  v_next := v_now + make_interval(secs => ((v_gmin + bl_rand() * (v_gmax - v_gmin)) * 60)::double precision);
  if v_n >= bl_love_num('moments.max_shown', 2)::int then
    update player_moment_state set next_roll_at = v_next where user_id = p_uid;
    return null;
  end if;
  p := bl_decay_row(p, v_now);
  for m in
    select * from life_moments l
     where l.active and l.kind = 'random' and l.weight > 0
       and not exists (select 1 from player_moments x where x.user_id = p_uid and x.moment_id = l.id and x.created_at > v_now - make_interval(secs => (l.cooldown_days * 86400)::double precision))
     order by l.sort, l.id
  loop
    if bl_moment_ok(m, p, v_now) then v_sum := v_sum + m.weight; end if;
  end loop;
  if v_sum > 0 then
    v_r := bl_rand() * v_sum;
    for m in
      select * from life_moments l
       where l.active and l.kind = 'random' and l.weight > 0
         and not exists (select 1 from player_moments x where x.user_id = p_uid and x.moment_id = l.id and x.created_at > v_now - make_interval(secs => (l.cooldown_days * 86400)::double precision))
       order by l.sort, l.id
    loop
      if bl_moment_ok(m, p, v_now) then
        v_pick := m.id;
        v_r := v_r - m.weight;
        if v_r < 0 then exit; end if;
      end if;
    end loop;
  end if;
  update player_moment_state set next_roll_at = v_next where user_id = p_uid;
  if v_pick is null then return null; end if;
  v_id := bl_moment_create(p_uid, v_pick, '{}'::jsonb, v_now, true);
  return v_id;
exception when others then
  return null;
end $$;

-- One card as the app shows it (the effects and outcomes stay on the server).
create or replace function public.bl_moment_json(pm public.player_moments) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.life_moments; v_cash bigint; v_ch jsonb := '[]'::jsonb; c jsonb; v_cost bigint; v_max int := bl_love_num('moments.max_snoozes', 3)::int;
begin
  select * into m from life_moments where id = pm.moment_id;
  select cash + greatest(bank, 0) into v_cash from profiles where id = pm.user_id;
  for c in select * from jsonb_array_elements(m.choices) loop
    v_cost := coalesce((c ->> 'cost')::bigint, 0);
    v_ch := v_ch || jsonb_build_object('id', c ->> 'id', 'label', bl_moment_text(c ->> 'label', pm.user_id, pm.context), 'cost', v_cost,
                                       'affordable', coalesce(v_cash, 0) >= v_cost, 'ignore', coalesce((c ->> 'ignore')::boolean, false));
  end loop;
  return jsonb_build_object('id', pm.id, 'moment', m.id, 'kind', m.kind, 'title', bl_moment_text(m.title, pm.user_id, pm.context),
    'body', bl_moment_text(m.body, pm.user_id, pm.context), 'icon', m.icon, 'speaker', m.speaker, 'choices', v_ch,
    'snoozes_left', greatest(0, v_max - pm.snoozes), 'created_at', pm.created_at, 'child_id', nullif(pm.context ->> 'child_id', '')::bigint);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- The app's one cheap read: expires old cards, rolls a random one when it is time, returns the due cards (at most moments.max_shown)
-- and the cards the other parent already handled (shown once).
create or replace function public.moments_pending() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); pm public.player_moments; v_due jsonb := '[]'::jsonb; v_handled jsonb := '[]'::jsonb;
  v_poll numeric := greatest(30, bl_love_num('moments.poll_seconds', 90)); v_max int := greatest(1, bl_love_num('moments.max_shown', 2)::int);
begin
  if not exists (select 1 from profiles where id = v_uid) or not bl_moments_on() then
    return jsonb_build_object('enabled', bl_moments_on(), 'moments', '[]'::jsonb, 'handled', '[]'::jsonb, 'poll_seconds', v_poll);
  end if;
  for pm in
    select * from player_moments x where x.user_id = v_uid and x.status in ('pending', 'snoozed', 'scheduled')
       and x.due_at < v_now - make_interval(hours => bl_love_num('moments.expire_hours', 36)::int) order by x.id limit 10 for update skip locked
  loop
    perform bl_moment_expire(pm);
  end loop;
  perform bl_moment_roll(v_uid);
  for pm in
    select * from player_moments x where x.user_id = v_uid and x.status in ('pending', 'snoozed', 'scheduled') and x.show_at <= v_now
     order by (select (l.kind = 'kids_ill') from life_moments l where l.id = x.moment_id) desc, x.show_at, x.id limit v_max
  loop
    v_due := v_due || bl_moment_json(pm);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', bl_moment_text(l.title, v_uid, x.context), 'icon', l.icon, 'speaker', l.speaker,
           'outcome', coalesce(x.outcome, 'Already handled.')) order by x.id), '[]'::jsonb) into v_handled
    from (select * from player_moments where user_id = v_uid and handled_by is not null and seen_at is null order by id limit 3) x
    join life_moments l on l.id = x.moment_id;
  return jsonb_build_object('enabled', true, 'moments', v_due, 'handled', v_handled, 'poll_seconds', v_poll, 'snooze_hours', bl_love_num('moments.snooze_hours', 2));
end $$;

-- Answer a card: pay (all or nothing), maybe roll the chance, apply the effects, schedule the follow-up. Returns the outcome text.
create or replace function public.moments_answer(p_instance bigint, p_choice text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); pm public.player_moments; m public.life_moments; ch jsonb; v_cost bigint; v_ok boolean;
  v_lines jsonb := '[]'::jsonb; v_out text; v_eff jsonb; v_who text; v_cured boolean := false;
begin
  select * into pm from player_moments where id = p_instance and user_id = v_uid for update;
  if not found then
    raise exception 'That moment is gone.' using errcode = 'P0001', hint = 'no_moment';
  end if;
  if pm.status not in ('pending', 'snoozed', 'scheduled') then
    raise exception '%', coalesce(pm.outcome, 'That moment is over.') using errcode = 'P0001', hint = 'already_answered';
  end if;
  if pm.show_at > v_now then
    raise exception 'It is not time for that yet.' using errcode = 'P0001', hint = 'not_yet';
  end if;
  select * into m from life_moments where id = pm.moment_id;
  select x into ch from jsonb_array_elements(m.choices) x where x ->> 'id' = p_choice;
  if ch is null then
    raise exception 'Pick one of the choices.' using errcode = 'P0001', hint = 'bad_choice';
  end if;
  -- a kids illness card is only for a child who is still unwell with that illness
  if m.kind = 'kids_ill' and not bl_kids_moment_open(pm.context) then
    update player_moments set status = 'expired', outcome = 'Already feeling better 💛', answered_at = v_now, seen_at = v_now where id = pm.id;
    return jsonb_build_object('outcome', 'Already feeling better 💛', 'tone', 'info', 'icon', m.icon, 'spent', 0, 'success', true, 'effects', '[]'::jsonb, 'handled', true);
  end if;
  v_cost := coalesce((ch ->> 'cost')::bigint, 0);
  if v_cost > 0 then
    perform bl_sink_pay(v_uid, v_cost, 'life_moment', jsonb_build_object('label', bl_moment_text(m.title, v_uid, pm.context), 'moment', m.id, 'choice', p_choice));
    if m.kind = 'kids_ill' then perform bl_kids_moment_paid(v_uid, pm.context, v_cost); end if;
  end if;
  v_ok := not (ch ? 'chance') or bl_rand() * 100 < (ch ->> 'chance')::numeric;
  v_eff := case when v_ok then coalesce(ch -> 'effects', '[]'::jsonb) else coalesce(ch -> 'fail_effects', '[]'::jsonb) end;
  v_lines := bl_moment_apply(v_uid, pm, v_eff, bl_moment_text(m.title, v_uid, pm.context));
  if v_ok and ch ? 'next_moment' and (coalesce((ch ->> 'next_chance')::numeric, 100) >= 100 or bl_rand() * 100 < (ch ->> 'next_chance')::numeric) then
    perform bl_moment_create(v_uid, ch ->> 'next_moment', case when (select kind from life_moments where id = ch ->> 'next_moment') = 'kids_ill' then pm.context else '{}'::jsonb end,
                             v_now + make_interval(secs => (coalesce((ch ->> 'next_delay_hours')::numeric, 0) * 3600)::double precision), false);
  end if;
  v_out := bl_moment_text(case when v_ok then ch ->> 'outcome' else coalesce(ch ->> 'fail_outcome', ch ->> 'outcome') end, v_uid, pm.context);
  update player_moments set status = 'answered', answered_choice = p_choice, outcome = v_out, answered_at = v_now, seen_at = v_now where id = pm.id;
  -- the other parent's card for the same child: handled by me (only when the child was cured)
  if m.kind = 'kids_ill' and v_ok and v_eff @> '[{"t":"kid_cure"}]'::jsonb then
    select username into v_who from profiles where id = v_uid;
    update player_moments set status = 'answered', handled_by = v_uid, outcome = 'Already handled by @' || coalesce(v_who, 'your partner') || ' 💛', answered_at = v_now
     where moment_id = pm.moment_id and user_id <> v_uid and status in ('pending', 'snoozed', 'scheduled')
       and context ->> 'child_id' = pm.context ->> 'child_id' and context ->> 'ep' = pm.context ->> 'ep';
    v_cured := true;
  end if;
  return jsonb_build_object('outcome', v_out, 'tone', case when v_ok then 'good' else 'bad' end, 'icon', m.icon, 'spent', v_cost,
                            'success', v_ok, 'effects', v_lines, 'cured', v_cured, 'moment', m.id, 'choice', p_choice);
end $$;

-- "Remind me later": hides the card for moments.snooze_hours. After moments.max_snoozes it counts as Ignore.
create or replace function public.moments_snooze(p_instance bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); pm public.player_moments; v_max int := bl_love_num('moments.max_snoozes', 3)::int; v_out text;
begin
  select * into pm from player_moments where id = p_instance and user_id = v_uid for update;
  if not found then
    raise exception 'That moment is gone.' using errcode = 'P0001', hint = 'no_moment';
  end if;
  if pm.status not in ('pending', 'snoozed', 'scheduled') then
    raise exception '%', coalesce(pm.outcome, 'That moment is over.') using errcode = 'P0001', hint = 'already_answered';
  end if;
  if pm.show_at > v_now then
    raise exception 'It is not time for that yet.' using errcode = 'P0001', hint = 'not_yet';
  end if;
  if pm.snoozes >= v_max then
    v_out := bl_moment_expire(pm);
    return jsonb_build_object('expired', true, 'outcome', coalesce(v_out, 'You let it go.'), 'tone', 'info');
  end if;
  update player_moments set status = 'snoozed', snoozes = pm.snoozes + 1,
         show_at = v_now + make_interval(secs => (bl_love_num('moments.snooze_hours', 2) * 3600)::double precision) where id = pm.id;
  return jsonb_build_object('expired', false, 'remind_at', v_now + make_interval(secs => (bl_love_num('moments.snooze_hours', 2) * 3600)::double precision),
                            'snoozes_left', v_max - pm.snoozes - 1, 'outcome', 'We will remind you later.', 'tone', 'info');
end $$;

-- A card the other parent handled has been read.
create or replace function public.moments_seen(p_instance bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  update player_moments set seen_at = bl_now() where id = p_instance and user_id = v_uid and seen_at is null;
  return jsonb_build_object('ok', true);
end $$;

-- "See the doctor": bring a snoozed or scheduled card back right now. Returns the card.
create or replace function public.moments_open(p_instance bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); pm public.player_moments;
begin
  select * into pm from player_moments where id = p_instance and user_id = v_uid for update;
  if not found then
    raise exception 'That moment is gone.' using errcode = 'P0001', hint = 'no_moment';
  end if;
  if pm.status not in ('pending', 'snoozed', 'scheduled') then
    raise exception '%', coalesce(pm.outcome, 'That moment is over.') using errcode = 'P0001', hint = 'already_answered';
  end if;
  update player_moments set status = 'pending', show_at = least(show_at, bl_now()) where id = pm.id returning * into pm;
  return bl_moment_json(pm);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5b. Seeds: everyday Benin moments (the doctor cards are seeded by the kids migration). Admin edits survive (on conflict do nothing).
-- Short, warm, PG. Fictional people only. Amounts are plain naira.
-- ---------------------------------------------------------------------------------------------
insert into public.life_moments (id, title, body, icon, speaker, kind, conditions, choices, cooldown_days, weight, sort) values
('landlord_levy', 'Landlord wahala',
 'Your landlord knocks. "Light bill, water bill, everything is going up o," he says. "The rent must rise small small this month."',
 '🏠', 'Landlord · Mr. Ehigie', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"pay","label":"Pay the levy","cost":3000,"effects":[{"t":"needs","delta":{"stress":-5}}],"outcome":"He collects the money and calls you a good tenant. Peace returns to your door."},
  {"id":"beg","label":"Beg for a discount","chance":50,"effects":[{"t":"cash","amount":-1500,"up_to":true}],"outcome":"Your sweet mouth works! He agrees to half the levy, ₦1,500, and even smiles.","fail_effects":[{"t":"cash","amount":-4500,"up_to":true},{"t":"needs","delta":{"stress":8}}],"fail_outcome":"He no gree at all. You pay ₦4,500 and he does not smile."},
  {"id":"later","label":"Say you will think about it","ignore":true,"effects":[{"t":"needs","delta":{"stress":6}}],"outcome":"He frowns. \"I will come back,\" he says, and you feel the stress already."}
 ]$j$::jsonb, 10, 1, 110),
('nepa_light', 'NEPA don take light',
 'The light just went off and the whole street is shouting. The fan is dead, it is getting dark and somebody is already boiling water by candle.',
 '💡', 'The street', 'random', '{"hours": [16, 24]}'::jsonb,
 $j$[
  {"id":"fuel","label":"Buy fuel for the generator","cost":2500,"effects":[{"t":"needs","delta":{"stress":-6,"fun":4}}],"outcome":"The generator roars to life and the neighbours come to sit with you. You are the hero of the compound tonight."},
  {"id":"dark","label":"Sit in the dark","ignore":true,"effects":[{"t":"needs","delta":{"fun":-8,"stress":8,"energy":-4}}],"outcome":"You sit in the dark and sweat. Light returns after midnight. NEPA, thank you o."}
 ]$j$::jsonb, 5, 1.2, 120),
('friend_loan', 'A friend needs help',
 'Your friend Efe sends a message: "Abeg, I need ₦5,000 for transport and small feeding. I go pay you back, I swear."',
 '🤝', 'Efe · your friend', 'random', '{"min_days": 1, "min_cash": 8000}'::jsonb,
 $j$[
  {"id":"lend","label":"Lend ₦5,000","cost":5000,"effects":[{"t":"needs","delta":{"social":4}},{"t":"follow_up","moment":"loan_repaid","delay_hours":24,"chance":35}],"outcome":"You send the money. Efe says, \"God bless you. I no go forget this one.\""},
  {"id":"sorry","label":"Say you are broke too","effects":[{"t":"needs","delta":{"social":-2,"stress":2}}],"outcome":"Efe says no wahala, but the reply has no smiley."},
  {"id":"read","label":"Leave him on read","ignore":true,"effects":[{"t":"needs","delta":{"social":-3}}],"outcome":"The message stays blue. Efe does not ask again today."}
 ]$j$::jsonb, 6, 1, 130),
('loan_repaid', 'Efe keeps his word',
 'Efe is at your door with your money wrapped in nylon. "Chief, I tell you say I go pay!" He even adds small extra for your trouble.',
 '💸', 'Efe · your friend', 'system', '{}'::jsonb,
 $j$[
  {"id":"take","label":"Collect ₦5,500","effects":[{"t":"cash","amount":5500},{"t":"needs","delta":{"social":6}}],"outcome":"You collect ₦5,500. True friends still exist."}
 ]$j$::jsonb, 0, 0, 140),
('owambe_invite', 'Owambe this Saturday',
 'Madam Ivie is celebrating her daughter''s wedding. Aso-ebi is ₦6,000, the jollof is free and the DJ does not know how to stop. "Come and show your face," she says.',
 '🎉', 'Madam Ivie', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"go","label":"Buy aso-ebi and go","cost":6000,"effects":[{"t":"needs","delta":{"fun":25,"social":20,"hunger":15,"energy":-10}},{"t":"skill_xp","skill":"charisma","xp":5}],"outcome":"You looked sharp in the aso-ebi, ate good jollof and danced until your legs complained."},
  {"id":"gift","label":"Send a ₦1,000 gift","cost":1000,"effects":[{"t":"needs","delta":{"social":5}}],"outcome":"Madam Ivie thanks you on the phone. \"You are a good one,\" she says."},
  {"id":"busy","label":"Say you have another event","ignore":true,"effects":[],"outcome":"Madam Ivie says she will remember this one. Life continues."}
 ]$j$::jsonb, 6, 1.2, 150),
('okada_scare', 'Okada scare',
 'An okada rider cuts in front of you and you jump into the roadside. Your elbow is scratched and your heart is racing like a generator.',
 '🛵', 'On the road', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"checkup","label":"Go for a check-up","cost":3000,"effects":[{"t":"needs","delta":{"health":10,"stress":-8}}],"outcome":"The nurse says it is only a scratch and tells you to rest. You walk away relieved."},
  {"id":"shrug","label":"Shrug it off","ignore":true,"chance":75,"effects":[{"t":"needs","delta":{"stress":-2}}],"outcome":"You dust your clothes and carry on. No wahala at all.","fail_effects":[{"t":"needs","delta":{"health":-8,"stress":8}}],"fail_outcome":"By evening the elbow is swollen and sore. Maybe a check-up was not a bad idea."}
 ]$j$::jsonb, 7, 1, 160),
('money_on_road', 'Money on the road',
 'You see ₦5,000 folded on the ground near the roadside. Nobody is looking. Nobody is shouting. Just you and the money.',
 '💵', 'On the road', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"keep","label":"Keep it","effects":[{"t":"cash","amount":5000}],"outcome":"You pocket the ₦5,000. Your conscience whispers a little, but the money is real."},
  {"id":"police","label":"Take it to the police","effects":[{"t":"street_cred","delta":2},{"t":"needs","delta":{"social":3}}],"outcome":"The officer writes your name in a big book and says, \"Good citizen.\" You feel taller."},
  {"id":"walk","label":"Walk away","ignore":true,"effects":[],"outcome":"You keep walking. Somebody else will find it."}
 ]$j$::jsonb, 10, 0.7, 170),
('stranger_job', 'Too good to be true',
 'An unknown number calls: "Congratulations! You are selected for an online job. Pay ₦3,000 registration and earn ₦200,000 every week!" Hmm. Sounds sweet.',
 '📞', 'Unknown number', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"decline","label":"Decline and block","ignore":true,"effects":[{"t":"street_cred","delta":1}],"outcome":"You hang up and block the number. If it is too good to be true, it is. Wise move!"},
  {"id":"pay","label":"Pay the registration","cost":3000,"effects":[{"t":"needs","delta":{"stress":5}}],"outcome":"The number never picks up again. Small lesson, small price. Next time you will know."}
 ]$j$::jsonb, 14, 0.8, 180),
('church_harvest', 'Harvest Sunday',
 'It is harvest Sunday. The choir is loud, the baskets are full of yam and the offering bowl is coming down your row.',
 '⛪', 'Church usher', 'random', '{"min_days": 1}'::jsonb,
 $j$[
  {"id":"big","label":"Give ₦5,000","cost":5000,"effects":[{"t":"needs","delta":{"social":10,"stress":-10}}],"outcome":"The congregation says \"Amen!\" and you feel your heart is lighter."},
  {"id":"small","label":"Give ₦500","cost":500,"effects":[{"t":"needs","delta":{"social":3,"stress":-3}}],"outcome":"Every little helps. The usher smiles and says thank you."},
  {"id":"keep","label":"Keep your money this time","ignore":true,"effects":[],"outcome":"You nod and look at your shoes. The bowl moves on."}
 ]$j$::jsonb, 8, 0.8, 190),
('market_extra', 'Mama Eki''s gift',
 'Mama Eki at the market weighs your tomatoes and, with a wink, adds three extra ones for free. "For my favourite customer," she says.',
 '🍅', 'Mama Eki · market woman', 'random',
 '{"at": ["oba_market","new_benin_market","uselu_market","oregbeni_market","ekiosa_market","santana_market"]}'::jsonb,
 $j$[
  {"id":"thanks","label":"Say thank you well well","effects":[{"t":"needs","delta":{"hunger":10,"social":6}}],"outcome":"She laughs and packs the tomatoes in a nylon. Your day just got sweeter."},
  {"id":"pepper","label":"Buy her pepper too","cost":800,"effects":[{"t":"needs","delta":{"hunger":12,"social":8}},{"t":"skill_xp","skill":"cooking","xp":3}],"outcome":"Her face lights up. \"This one knows food!\" she says and throws in one more tomato."},
  {"id":"smile","label":"Smile and go","ignore":true,"effects":[],"outcome":"You wave and carry on with your shopping."}
 ]$j$::jsonb, 3, 4, 200)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 6. Patches on live functions (guarded, written against the CURRENT definitions)
-- ---------------------------------------------------------------------------------------------
-- the Admin Content editor takes a JSON list of objects (the choices)
select pg_temp.lm_patch('public.bl_admin_check_value(text, text, jsonb)',
  $o$    when 'arr' then$o$,
  $o$    when 'jarr' then
      if t <> 'array' then raise exception '% must be a JSON list ([...]).', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'arr' then$o$,
  $o$when 'jarr' then$o$);
-- ledger: label, category, never earned
select pg_temp.lm_patch('public.bl_ledger_label(text, jsonb)',
  $o$when 'kid_reclaim' then return coalesce(nullif(p_meta->>'label', ''), 'Bringing a child home');$o$,
  $o$when 'kid_reclaim' then return coalesce(nullif(p_meta->>'label', ''), 'Bringing a child home');
    when 'life_moment' then return coalesce(nullif(p_meta->>'label', ''), 'Life moment');$o$,
  $o$when 'life_moment' then$o$);
select pg_temp.lm_patch('public.bl_econ_category(text)',
  $o$when p_reason in ('spray') then 'Clubs and spray'$o$,
  $o$when p_reason in ('spray') then 'Clubs and spray'
    when p_reason in ('life_moment') then 'Life moments'$o$,
  $o$'Life moments'$o$);
select pg_temp.lm_patch('public.bl_earn_reasons()',
  $o$'kid_try', 'kid_care', 'kid_reclaim'])$o$,
  $o$'kid_try', 'kid_care', 'kid_reclaim', 'life_moment'])$o$,
  $o$'life_moment'$o$);
-- Admin Content editors: Life moments
select pg_temp.lm_patch('public.bl_admin_table_spec(text)',
  $o$when 'kids_auto_names' then$o$,
  E'when ''life_moments'' then ''{"pk":["id"],"insert":true,"order":"kind, sort, id",\n      "cols":{"title":"text","body":"text","icon":"text","speaker":"text","kind":"text","conditions":"obj","choices":"jarr","cooldown_days":"num","weight":"num","push":"bool","sort":"int","active":"bool"}}\'\n    when ''kids_auto_names'' then',
  $o$when 'life_moments' then$o$);

-- ---------------------------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'bl\_moment%') loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname in ('moments_pending', 'moments_answer', 'moments_snooze', 'moments_seen', 'moments_open') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
