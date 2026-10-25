-- Money ranges on leaderboards (docs/RANKS.md): players must not see another player's exact money in a ranking, only a range
-- ("₦1M – ₦10M", top "₦10B+"). The ORDER still follows the real value; prizes and thresholds the game pays stay exact.
--
--   1. Settings ranks.band_edges (the thresholds, ascending, comma separated naira) and ranks.hide_amounts (false = old exact numbers)
--   2. Private helpers bl_ranks_hide, bl_money_short (₦250K / ₦1.5B) and bl_money_band (the label); no client may call them
--   3. leaderboard_rich, leaderboard_vip, weekly_leaderboard (rows, me, last-week winners), crew_top (rows, mine, last-week winners)
--      and donors_top (rows) return `band` and a null exact number while the setting is on. Your own row shows the band too.
--
-- Idempotent. The five RPCs are replaced whole (create or replace keeps the grants), copied from the live definitions.

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind) values
  ('ranks.hide_amounts', 'true', 'leaderboard', 'Ranks: show money ranges',
   'On = rankings show a range (₦1M – ₦10M) instead of the exact money. Off = the old exact numbers.', 'bool'),
  ('ranks.band_edges', '"1000000,10000000,100000000,1000000000,10000000000"', 'leaderboard', 'Ranks: range edges (₦)',
   'Comma separated naira thresholds, lowest first. Labels are built from them: Under ₦1M, ₦1M – ₦10M, … ₦10B+.', 'text')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Helpers (private)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_ranks_hide() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from game_config where key = 'ranks.hide_amounts'), true)
$$;

-- ₦250K · ₦1M · ₦1.5B · ₦2T (up to two decimals, trailing zeros dropped)
create or replace function public.bl_money_short(p_amount numeric) returns text
language sql immutable set search_path = public as $$
  select '₦' || case
    when p_amount >= 1e12 then trim_scale(round(p_amount / 1e12, 2))::text || 'T'
    when p_amount >= 1e9  then trim_scale(round(p_amount / 1e9, 2))::text || 'B'
    when p_amount >= 1e6  then trim_scale(round(p_amount / 1e6, 2))::text || 'M'
    when p_amount >= 1e3  then trim_scale(round(p_amount / 1e3, 2))::text || 'K'
    else trim_scale(round(p_amount, 0))::text end
$$;

-- the range label of an amount; null for 0 / null (nothing to show). Bad edges in the setting fall back to the defaults.
create or replace function public.bl_money_band(p_amount numeric) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_raw   text := (select value #>> '{}' from game_config where key = 'ranks.band_edges');
  v_edges numeric[];
  v_k     int;
  v_n     int;
begin
  if p_amount is null or p_amount <= 0 then return null; end if;
  begin
    select array_agg(x::numeric order by x::numeric) into v_edges
      from unnest(string_to_array(regexp_replace(coalesce(v_raw, ''), '\s', '', 'g'), ',')) x where x <> '';
  exception when others then v_edges := null;
  end;
  if v_edges is null or cardinality(v_edges) = 0 or v_edges[1] <= 0 then
    v_edges := array[1000000, 10000000, 100000000, 1000000000, 10000000000]::numeric[];
  end if;
  v_n := cardinality(v_edges);
  select count(*) into v_k from unnest(v_edges) e where e <= p_amount;
  if v_k = 0 then return 'Under ' || bl_money_short(v_edges[1]); end if;
  if v_k = v_n then return bl_money_short(v_edges[v_n]) || '+'; end if;
  return bl_money_short(v_edges[v_k]) || ' – ' || bl_money_short(v_edges[v_k + 1]);
end $$;

revoke all on function public.bl_ranks_hide() from public, anon, authenticated;
revoke all on function public.bl_money_short(numeric) from public, anon, authenticated;
revoke all on function public.bl_money_band(numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. The boards
-- ---------------------------------------------------------------------------------------------
create or replace function public.leaderboard_rich(p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_hide boolean := bl_ranks_hide();
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  with r as materialized (select * from bl_rich_ranked())
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'total', case when not v_hide then r.total end,
                                                       'band', case when v_hide then bl_money_band(r.total) end,
                                                       'tier', bl_lb_tier('leaderboard.rich_tiers', r.total), 'me', r.id = v_uid)
                                    order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         (select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                                    'total', case when not v_hide then p.cash + p.bank end,
                                    'band', case when v_hide then bl_money_band(p.cash + p.bank) end,
                                    'tier', bl_lb_tier('leaderboard.rich_tiers', p.cash + p.bank))
            from profiles p left join r on r.id = p.id where p.id = v_uid)
    into v_n, v_rows, v_me;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n,
                            'tiers', bl_lb_tiers('leaderboard.rich_tiers'));
end $function$;

create or replace function public.leaderboard_vip(p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_show boolean := coalesce(bl_cfg_bool('leaderboard.vip_show_amounts'), false);
  v_hide boolean := bl_ranks_hide();
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  with r as materialized (select * from bl_vip_ranked())
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'tier', bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0),
                                                       'amount', case when v_show and not v_hide then r.kobo / 100 end,
                                                       'band', case when v_show and v_hide then bl_money_band(r.kobo / 100.0) end,
                                                       'me', r.id = v_uid)
                                    order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         -- your own row: you always see your money (the band while ranges are on)
         (select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                                    'tier', case when r.id is not null then bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0) end,
                                    'amount', case when not v_hide then coalesce(r.kobo, 0) / 100 end,
                                    'band', case when v_hide then bl_money_band(coalesce(r.kobo, 0) / 100.0) end)
            from profiles p left join r on r.id = p.id where p.id = v_uid)
    into v_n, v_rows, v_me;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n, 'show_amounts', v_show,
                            'tiers', bl_lb_tiers('leaderboard.vip_tiers'));
end $function$;

create or replace function public.weekly_leaderboard(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid  uuid := bl_require_uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_wk   date := bl_week_start();
  v_hide boolean := bl_ranks_hide();
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
  v_last date;
begin
  perform bl_weekly_settle();
  with r as materialized (select * from bl_weekly_ranked(v_wk))
  select (select count(*) from r),
         (select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                                       'origin', r.origin, 'total', case when not v_hide then r.total end,
                                                       'band', case when v_hide then bl_money_band(r.total) end,
                                                       'me', r.id = v_uid) order by r.rank), '[]'::jsonb)
            from r where r.rank <= v_lim),
         (select jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar, 'origin', r.origin,
                                    'total', case when not v_hide then r.total end,
                                    'band', case when v_hide then bl_money_band(r.total) end)
            from r where r.id = v_uid)
    into v_n, v_rows, v_me;
  if v_me is null then
    select jsonb_build_object('rank', null, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                              'total', case when not v_hide then 0 end, 'band', null)
      into v_me from profiles p where p.id = v_uid;
  end if;
  select max(week_start) into v_last from weekly_earn_winners;
  return jsonb_build_object(
    'enabled', bl_hustle_on('leaderboard.weekly_enabled', true),
    'week_start', v_wk, 'ends_at', bl_week_from(v_wk + 7), 'players', v_n,
    'rows', v_rows, 'me', v_me,
    'prizes', jsonb_build_array(
        jsonb_build_object('rank', 1, 'amount', bl_hustle_num('leaderboard.weekly_prize_1', 200000)),
        jsonb_build_object('rank', 2, 'amount', bl_hustle_num('leaderboard.weekly_prize_2', 100000)),
        jsonb_build_object('rank', 3, 'amount', bl_hustle_num('leaderboard.weekly_prize_3', 50000))),
    'min_earned', bl_hustle_num('leaderboard.weekly_min_earned', 20000),
    'reasons', to_jsonb(bl_earn_reasons()),
    'last_week', case when v_last is null then null else jsonb_build_object(
        'week_start', v_last,
        'winners', coalesce((select jsonb_agg(jsonb_build_object('rank', w.rank, 'username', w.username,
                                                                 'total', case when not v_hide then w.total end,
                                                                 'band', case when v_hide then bl_money_band(w.total) end,
                                                                 'prize', w.prize) order by w.rank)
                               from weekly_earn_winners w where w.week_start = v_last), '[]'::jsonb)) end);
end $function$;

create or replace function public.crew_top(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_uid uuid := bl_require_uid(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 50); v_wk date := bl_week_start(); v_mine bigint; v_last date; v_rows jsonb;
  v_hide boolean := bl_ranks_hide();
begin
  perform bl_crew_week_settle();
  select crew_id into v_mine from crew_members where user_id = v_uid;
  select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'crew_id', r.crew_id, 'name', r.name, 'tag', r.tag, 'emblem', r.emblem, 'color', r.color, 'level', r.level,
                                               'jobs', r.jobs, 'loot', case when not v_hide then r.loot end,
                                               'band', case when v_hide then bl_money_band(r.loot) end, 'mine', r.crew_id = v_mine) order by r.rank), '[]'::jsonb)
    into v_rows from bl_crew_week_ranked(v_wk) r where r.rank <= v_lim;
  select max(week_start) into v_last from crew_week_winners;
  return jsonb_build_object(
    'enabled', coalesce((select (value #>> '{}')::boolean from game_config where key = 'crew.weekly_enabled'), true),
    'week_start', v_wk, 'ends_at', bl_week_from(v_wk + 7), 'rows', v_rows,
    'prizes', jsonb_build_array(jsonb_build_object('rank', 1, 'amount', bl_crew_num('crew.weekly_prize_1', 500000)),
                                jsonb_build_object('rank', 2, 'amount', bl_crew_num('crew.weekly_prize_2', 250000)),
                                jsonb_build_object('rank', 3, 'amount', bl_crew_num('crew.weekly_prize_3', 100000))),
    'min_jobs', bl_crew_num('crew.weekly_min_jobs', 2),
    'mine', (select jsonb_build_object('rank', r.rank, 'jobs', r.jobs, 'loot', case when not v_hide then r.loot end,
                                       'band', case when v_hide then bl_money_band(r.loot) end)
               from bl_crew_week_ranked(v_wk) r where r.crew_id = v_mine),
    'last_week', case when v_last is null then null else jsonb_build_object('week_start', v_last,
        'winners', coalesce((select jsonb_agg(jsonb_build_object('rank', w.rank, 'name', w.crew_name, 'tag', w.tag, 'jobs', w.jobs,
                                                                 'loot', case when not v_hide then w.loot end,
                                                                 'band', case when v_hide then bl_money_band(w.loot) end, 'prize', w.prize) order by w.rank)
                               from crew_week_winners w where w.week_start = v_last), '[]'::jsonb)) end);
end $function$;

create or replace function public.donors_top(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
declare v_uid uuid := bl_require_uid(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 100); v_hide boolean := bl_ranks_hide();
begin
  return jsonb_build_object(
    'tiers', coalesce((select jsonb_agg(jsonb_build_object('name', t.name, 'amount', t.amount) order by t.amount) from bl_econ_tiers('economy.donor_tiers', 'Helper:10000') t), '[]'::jsonb),
    'min', bl_econ_num('economy.donate_min', 10000),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('rank', x.rank, 'username', x.username, 'total', case when not v_hide then x.total end,
                          'band', case when v_hide then bl_money_band(x.total) end, 'badge', bl_donor_badge(x.user_id),
                          'title', bl_pol_title(x.user_id), 'me', x.user_id = v_uid) order by x.rank)
                        from (select d.user_id, p.username, d.total, row_number() over (order by d.total desc, d.last_at) as rank
                                from city_donors d join profiles p on p.id = d.user_id where not p.banned and not p.is_admin
                               order by d.total desc, d.last_at limit v_lim) x), '[]'::jsonb),
    -- your own giving stays exact (you made the donations; the Bank text shows it)
    'me', (select jsonb_build_object('total', d.total, 'donations', d.donations, 'badge', bl_donor_badge(v_uid)) from city_donors d where d.user_id = v_uid));
end $function$;

notify pgrst, 'reload schema';
