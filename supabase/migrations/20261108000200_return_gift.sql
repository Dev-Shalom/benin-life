-- Daily return pack, part 2: WELCOME-BACK GIFT and "WE MISS YOU" NUDGES (docs/DAILY_RETURN.md).
-- * A player away 3+ calendar days (player_return_state.prev_day -> today, recorded by the heartbeat) gets ONE gift row for that
--   absence: cash (base + a little per extra day, capped) and a food item. return_gift_status() / return_gift_claim().
--   Ledger reason 'Welcome-back gift' is not an earn reason: no tax garnish, no leaderboard, no challenge progress.
-- * bl_return_push_tick() (called from bl_push_tick, which cron runs): at about 2, 5 and 10 days away one personal push each
--   (never more than three per absence, remembered in return_nudges), plus two "something needs you" gaps: rent due tomorrow
--   and business takings ready. Bounded: 200 players per tick, throttled to once per return.tick_seconds, quiet at night.
-- Every push goes through bl_push_enqueue, so opt-in categories, the master switch, devices, the hourly cap and dedupe all apply.
-- Idempotent. Nothing touches the profiles table. No loops over all players: every scan is index-bounded and limited.

create or replace function pg_temp.dr2_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'return_gift: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings (Admin -> Settings -> Welcome back)
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('return.gift_enabled', 'true', 'return', 'Welcome-back gift on',
 'A player who comes back after being away for the number of days below gets a gift (money and a food item), once for that absence. Not counted as earnings.', 'bool', null, null),
('return.gift_after_days', '3', 'return', 'Gift after (days away)',
 'How many Benin days away before the gift. 3 = last seen on Monday, back on Thursday or later.', 'number', 2, 30),
('return.gift_cash', '5000', 'return', 'Gift: base money', 'Naira in the gift for someone away exactly the days above.', 'naira', 0, 1000000),
('return.gift_per_day', '500', 'return', 'Gift: extra per day away', 'Extra naira for each day away beyond the days above (a little, so a long absence feels noticed).', 'naira', 0, 100000),
('return.gift_cash_cap', '10000', 'return', 'Gift: money cap', 'The gift money never goes above this, however long the player was away.', 'naira', 0, 1000000),
('return.gift_item', '"kada_chicken"', 'return', 'Gift: food item (id)', 'Item id of the food in the gift (default Kada fried chicken + chips). Empty = no item.', 'text', null, null),
('return.gift_item_qty', '1', 'return', 'Gift: food quantity', 'How many of the food item.', 'number', 0, 10),
('return.gift_keep_days', '7', 'return', 'Gift stays claimable (days)', 'A gift nobody claims is dropped after this many days.', 'number', 1, 60),
('return.push_enabled', 'true', 'return', 'Lapsed-player pushes on', 'One personal "we miss you" push at about 2, 5 and 10 days away (opt-in Game events category, never more than three per absence).', 'bool', null, null),
('return.push_day_1', '2', 'return', 'First push (days away)', 'About how many days away for the first "we miss you" push.', 'number', 1, 30),
('return.push_day_2', '5', 'return', 'Second push (days away)', 'The second one.', 'number', 2, 60),
('return.push_day_3', '10', 'return', 'Third push (days away)', 'The third and last one.', 'number', 3, 90),
('return.push_window_days', '2', 'return', 'Push window (days)', 'A push still goes out if the player is up to this many days past its mark (cron was down, batch was full). After that it is skipped.', 'number', 1, 7),
('return.push_batch', '200', 'return', 'Players per tick', 'At most this many players are looked at per push tick, so it never scans everyone at once.', 'number', 10, 2000),
('return.push_from_hour', '9', 'return', 'Quiet hours: start sending at', 'Benin hour (0-23). Nothing from this pack is sent before it.', 'number', 0, 23),
('return.push_to_hour', '20', 'return', 'Quiet hours: stop sending at', 'Benin hour (1-24). Nothing from this pack is sent from this hour on.', 'number', 1, 24),
('return.tick_seconds', '300', 'return', 'Tick throttle (seconds)', 'The push job runs at most this often, however often cron calls it.', 'number', 0, 3600),
('return.gap_push_enabled', 'true', 'return', '"Something needs you" pushes on', 'Rent due tomorrow and business takings ready (Money category, once a day per player, never to someone in the game right now).', 'bool', null, null),
('return.takings_hours', '12', 'return', 'Takings ready after (hours)', 'A business that has not been collected for this long gets a "takings are waiting" push.', 'number', 1, 48)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables (RLS on, closed to players)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.return_gifts (
  id bigserial primary key,
  user_id uuid not null,
  came_back_on date not null,
  away_days integer not null,
  cash bigint not null check (cash >= 0),
  item_id text,
  qty integer not null default 0,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  unique (user_id, came_back_on)
);
create unique index if not exists return_gifts_one_open_idx on public.return_gifts (user_id) where claimed_at is null;

create table if not exists public.return_nudges (
  user_id uuid not null,
  absence_day date not null,       -- the WAT day the player was last seen: one absence = one value
  stage smallint not null check (stage between 1 and 3),
  sent_at timestamptz not null default now(),
  primary key (user_id, absence_day, stage)
);
create index if not exists return_nudges_sent_idx on public.return_nudges (sent_at);

create table if not exists public.return_job (
  id smallint primary key default 1 check (id = 1),
  last_run timestamptz not null default '-infinity'
);
insert into public.return_job (id) values (1) on conflict (id) do nothing;

do $$
declare t text;
begin
  foreach t in array array['return_gifts', 'return_nudges', 'return_job'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Detect the return (the part-1 heartbeat hook, now also making the gift)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_return_gift_make(p_uid uuid, p_prev date, p_day date) returns void
language plpgsql security definer set search_path = public as $$
declare v_after int := greatest(2, coalesce(bl_cfg('return.gift_after_days'), 3))::int; v_away int := p_day - p_prev;
        v_cash bigint; v_item text := nullif(btrim(coalesce(bl_cfg_text('return.gift_item'), '')), ''); v_qty int;
begin
  if p_prev is null or v_away < v_after or not coalesce(bl_cfg_bool('return.gift_enabled'), false) then return; end if;
  v_cash := least(greatest(0, bl_cfg('return.gift_cash_cap')),
                  greatest(0, bl_cfg('return.gift_cash') + bl_cfg('return.gift_per_day') * (v_away - v_after)))::bigint;
  v_qty := greatest(0, bl_cfg('return.gift_item_qty'))::int;
  if v_item is not null and not exists (select 1 from items where id = v_item) then v_item := null; end if;
  if v_item is null then v_qty := 0; end if;
  delete from return_gifts where user_id = p_uid and claimed_at is null;      -- an older unclaimed gift is replaced by this absence's
  insert into return_gifts (user_id, came_back_on, away_days, cash, item_id, qty) values (p_uid, p_day, v_away, v_cash, v_item, v_qty)
  on conflict (user_id, came_back_on) do nothing;
end $$;
revoke all on function public.bl_return_gift_make(uuid, date, date) from public, anon, authenticated;

create or replace function public.bl_growth_touch(p_uid uuid, p_now timestamptz, p_prev_seen timestamptz) returns void
language plpgsql security definer set search_path = public as $$
declare v_day date := bl_wat_date(p_now); v_last date;
begin
  select last_day into v_last from player_return_state where user_id = p_uid;
  if v_last = v_day then return; end if;                 -- already recorded today: no write at all
  if v_last is null and p_prev_seen is not null then v_last := bl_wat_date(p_prev_seen); end if;
  insert into player_days (user_id, day) values (p_uid, v_day) on conflict do nothing;
  insert into player_return_state (user_id, last_day, prev_day) values (p_uid, v_day, v_last)
  on conflict (user_id) do update set last_day = excluded.last_day, prev_day = excluded.prev_day, updated_at = now();
  begin
    perform bl_return_gift_make(p_uid, v_last, v_day);   -- once per absence: only reached on the first heartbeat of a new day
  exception when others then null;
  end;
exception when others then
  null;   -- a measuring problem must never break the heartbeat
end $$;
revoke all on function public.bl_growth_touch(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs
-- ---------------------------------------------------------------------------------------------
create or replace function public.return_gift_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g return_gifts; it items;
begin
  if not coalesce(bl_cfg_bool('return.gift_enabled'), false) then return jsonb_build_object('pending', false); end if;
  select * into g from return_gifts
   where user_id = v_uid and claimed_at is null and created_at > now() - make_interval(days => greatest(1, bl_cfg('return.gift_keep_days'))::int);
  if not found then return jsonb_build_object('pending', false); end if;
  if g.item_id is not null then select * into it from items where id = g.item_id; end if;
  return jsonb_build_object('pending', true, 'id', g.id, 'away_days', g.away_days, 'cash', g.cash,
    'item', case when g.item_id is null then null else jsonb_build_object('id', g.item_id, 'name', it.name, 'icon', it.icon, 'qty', g.qty) end);
end $$;

create or replace function public.return_gift_claim() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); g return_gifts; it items;
begin
  perform 1 from profiles where id = v_uid for update;
  select * into g from return_gifts
   where user_id = v_uid and claimed_at is null and created_at > now() - make_interval(days => greatest(1, bl_cfg('return.gift_keep_days'))::int)
   for update;
  if not found or not coalesce(bl_cfg_bool('return.gift_enabled'), false) then
    raise exception 'No welcome-back gift waiting for you.' using errcode = 'P0001', hint = 'no_gift';
  end if;
  update return_gifts set claimed_at = now() where id = g.id;
  if g.cash > 0 then
    perform bl_add_money(v_uid, 'cash', g.cash, 'Welcome-back gift', jsonb_build_object('away_days', g.away_days, 'gift_id', g.id));
  end if;
  if g.item_id is not null and g.qty > 0 then
    perform bl_give_item(v_uid, g.item_id, g.qty);
    select * into it from items where id = g.item_id;
  end if;
  return jsonb_build_object('claimed', true, 'cash', g.cash, 'away_days', g.away_days,
    'item', case when g.item_id is null or g.qty = 0 then null else jsonb_build_object('id', g.item_id, 'name', it.name, 'icon', it.icon, 'qty', g.qty) end);
end $$;

revoke all on function public.return_gift_status() from public, anon;
grant execute on function public.return_gift_status() to authenticated;
revoke all on function public.return_gift_claim() from public, anon;
grant execute on function public.return_gift_claim() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. The pushes
-- ---------------------------------------------------------------------------------------------
-- One personal line from something real in the player's life. Returns title, body, link.
create or replace function public.bl_return_msg(p_uid uuid, p_stage int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_kid text; v_has_kid boolean; v_biz boolean; v_story boolean; v_gift boolean := coalesce(bl_cfg_bool('return.gift_enabled'), false);
begin
  select true, coalesce(k.name, 'Your baby') into v_has_kid, v_kid from kids_children k
   where k.status = 'home' and (k.parent_a = p_uid or k.parent_b = p_uid) order by k.id limit 1;
  v_biz := exists (select 1 from businesses b where b.owner_id = p_uid and not b.listed and b.ready_at <= bl_now()
                    and b.last_collect_at < bl_now() - make_interval(hours => greatest(1, bl_cfg('return.takings_hours'))::int));
  v_story := coalesce(bl_cfg_bool('stories.daily_enabled'), true);
  if p_stage = 3 then
    return jsonb_build_object('title', '🇧🇯 Benin don miss you',
      'body', case when v_gift then 'Come back small. A welcome-back gift dey wait you.' else 'Your people dey ask of you. Come back small.' end, 'url', '/play');
  end if;
  if p_stage = 1 and coalesce(v_has_kid, false) then
    return jsonb_build_object('title', '👶 ' || case when v_kid = 'Your baby' then 'Your baby misses you' else v_kid || ' misses you' end, 'body', 'Come and carry am. Small love go make am happy.', 'url', '/play?go=family:family');
  end if;
  if v_biz then
    return jsonb_build_object('title', '💰 Your shop takings are waiting', 'body', 'Your business don dey work. Come collect your money.', 'url', '/play?go=business');
  end if;
  if coalesce(v_has_kid, false) then
    return jsonb_build_object('title', '👶 ' || case when v_kid = 'Your baby' then 'Your baby misses you' else v_kid || ' misses you' end, 'body', 'Come and carry am. Small love go make am happy.', 'url', '/play?go=family:family');
  end if;
  if v_story then
    return jsonb_build_object('title', '📖 Today''s story has a twist for you', 'body', 'Something small is happening in Benin City. Come see wetin you go choose.', 'url', '/play?go=stories');
  end if;
  return jsonb_build_object('title', '🇧🇯 Benin don miss you', 'body', 'Your people dey ask of you. Come back small.', 'url', '/play');
end $$;
revoke all on function public.bl_return_msg(uuid, int) from public, anon, authenticated;

create or replace function public.bl_return_push_tick() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now); v_hour numeric := extract(hour from (v_now at time zone bl_clock_tz()));
  v_batch int := greatest(10, coalesce(bl_cfg('return.push_batch'), 200))::int;
  v_win int := greatest(1, coalesce(bl_cfg('return.push_window_days'), 2))::int;
  v_last timestamptz; v_stage int; v_d int; v_lo bigint; v_hi bigint; r record; m jsonb; v_n int[] := array[0, 0, 0]; v_rent int := 0; v_tak int := 0; v_left int;
begin
  if not coalesce(bl_cfg_bool('push.enabled'), false) then return jsonb_build_object('skipped', 'push off'); end if;
  if v_hour < bl_cfg('return.push_from_hour') or v_hour >= bl_cfg('return.push_to_hour') then return jsonb_build_object('skipped', 'quiet hours'); end if;
  -- throttle: cron calls bl_push_tick every minute; this job runs every return.tick_seconds
  select last_run into v_last from return_job where id = 1 for update;
  if v_last > v_now - make_interval(secs => greatest(0, bl_cfg('return.tick_seconds'))::double precision) then return jsonb_build_object('skipped', 'throttled'); end if;
  update return_job set last_run = v_now where id = 1;

  v_left := v_batch;
  if coalesce(bl_cfg_bool('return.push_enabled'), true) and coalesce(bl_cfg_bool('push.cat_events'), false) then
    for v_stage in 1..3 loop
      exit when v_left <= 0;
      v_d := greatest(1, bl_cfg('return.push_day_' || v_stage))::int;
      v_hi := floor(extract(epoch from v_now - make_interval(days => v_d)) / 300)::bigint;
      v_lo := floor(extract(epoch from v_now - make_interval(days => v_d + v_win)) / 300)::bigint;
      for r in
        select p.id, bl_wat_date(p.last_seen) as seen_day
          from profiles p
         where p.home_chosen and not p.banned and p.seen_bucket between v_lo and v_hi
           and p.last_seen <= v_now - make_interval(days => v_d)
           and exists (select 1 from push_prefs pp where pp.user_id = p.id and pp.master and pp.events)
           and exists (select 1 from push_subscriptions ps where ps.user_id = p.id)
           and not exists (select 1 from return_nudges n where n.user_id = p.id and n.absence_day = bl_wat_date(p.last_seen) and n.stage = v_stage)
           and not exists (select 1 from return_nudges n where n.user_id = p.id and n.sent_at > v_now - interval '20 hours')
         order by p.seen_bucket
         limit v_left
      loop
        v_left := v_left - 1;
        insert into return_nudges (user_id, absence_day, stage, sent_at) values (r.id, r.seen_day, v_stage, v_now) on conflict do nothing;
        if found then
          m := bl_return_msg(r.id, v_stage);
          if bl_push_enqueue(r.id, 'events', 'return_lapsed', m->>'title', m->>'body', m->>'url', null, null, null, 'lapse:' || v_stage || ':' || r.seen_day) is not null then
            v_n[v_stage] := v_n[v_stage] + 1;
          end if;
        end if;
      end loop;
    end loop;
  end if;

  if coalesce(bl_cfg_bool('return.gap_push_enabled'), true) and coalesce(bl_cfg_bool('push.cat_money'), false) then
    -- rent due tomorrow (players seen in the last 7 days; the indexed bucket keeps the scan small)
    if coalesce(bl_cfg_bool('rent.enabled'), false) then
      for r in
        select p.id, p.weekly_rent, bl_wat_date(p.rent_due_at) as due
          from profiles p
         where p.home_chosen and not p.banned and p.seen_bucket >= floor(extract(epoch from v_now - interval '7 days') / 300)::bigint
           and p.weekly_rent > 0 and p.rent_due_at is not null and bl_wat_date(p.rent_due_at) = v_today + 1
           and exists (select 1 from push_subscriptions ps where ps.user_id = p.id)
         limit v_batch
      loop
        if bl_push_enqueue(r.id, 'money', 'rent_due', '🏠 Rent is due tomorrow', 'Your rent is ' || bl_naira(r.weekly_rent) || '. Keep the money ready.',
                           '/play?go=bank', null, null, null, 'rentdue:' || r.due, true) is not null then
          v_rent := v_rent + 1;
        end if;
      end loop;
    end if;
    -- business takings ready (owner seen in the last 2 days: the lapsed pushes handle the rest)
    for r in
      select b.owner_id, b.id, b.name, b.last_collect_at
        from businesses b
       where not b.listed and b.ready_at <= v_now
         and b.last_collect_at <= v_now - make_interval(hours => greatest(1, bl_cfg('return.takings_hours'))::int)
         and b.last_collect_at > v_now - interval '4 days'
         and exists (select 1 from profiles p where p.id = b.owner_id and p.home_chosen and not p.banned
                      and p.seen_bucket >= floor(extract(epoch from v_now - interval '2 days') / 300)::bigint)
         and exists (select 1 from push_subscriptions ps where ps.user_id = b.owner_id)
       order by b.last_collect_at
       limit v_batch
    loop
      if bl_push_enqueue(r.owner_id, 'money', 'takings_ready', '💰 Your takings are ready', r.name || ' has money waiting. Come collect am.',
                         '/play?go=business', null, null, null, 'takings:' || r.id || ':' || floor(extract(epoch from r.last_collect_at))::bigint, true) is not null then
        v_tak := v_tak + 1;
      end if;
    end loop;
  end if;

  delete from return_nudges where ctid in (select ctid from return_nudges where sent_at < v_now - interval '60 days' limit 2000);
  return jsonb_build_object('stage1', v_n[1], 'stage2', v_n[2], 'stage3', v_n[3], 'rent', v_rent, 'takings', v_tak);
exception when others then
  return jsonb_build_object('error', sqlerrm);
end $$;
revoke all on function public.bl_return_push_tick() from public, anon, authenticated;

select pg_temp.dr2_patch('public.bl_push_tick()',
  E'jsonb_build_object(''stories_pushed'', bl_story_push_tick());',
  E'jsonb_build_object(''stories_pushed'', bl_story_push_tick())\n         || jsonb_build_object(''return_pushed'', bl_return_push_tick());',
  'bl_return_push_tick(');

notify pgrst, 'reload schema';
