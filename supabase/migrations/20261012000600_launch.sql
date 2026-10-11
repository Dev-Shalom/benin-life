-- L1 launch pass (2026-10-12). Idempotent and safe on a database with players.
--  1. client_errors: the app reports crashes and unhandled errors (ErrorBoundary, window.onerror,
--     unhandledrejection) through client_error_log(); size-capped, rate-limited, no PII beyond the user id.
--     Admins read them grouped by message with admin_client_errors() (Admin -> Errors).
--  2. furniture_sell: a parallel double sell of the same piece could pay out twice (the second call found
--     no row after waiting on the lock and still paid). Now refused.
--  3. home_layouts: drop the default table write grants (RLS already blocked writes; belt and braces), and no
--     TRUNCATE grant to anon/authenticated on any public table (profile_archive still had one; TRUNCATE skips RLS).
-- docs: docs/DEPLOY.md "Client errors", docs/BALANCE.md, docs/LAUNCH_CHECKLIST.md.

-- ---------- 1. client errors ----------
create table if not exists public.client_errors (
  id          bigserial primary key,
  user_id     uuid,
  kind        text not null default 'error',
  message     text not null,
  stack       text,
  url         text,
  build       text,
  ua          text,
  created_at  timestamptz not null default now()
);
create index if not exists client_errors_created_idx on public.client_errors (created_at desc);
create index if not exists client_errors_user_idx on public.client_errors (user_id, created_at desc);
alter table public.client_errors enable row level security;
revoke all on table public.client_errors from anon, authenticated;
revoke all on sequence public.client_errors_id_seq from anon, authenticated;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('errors.enabled', 'true', 'admin', 'Collect app errors',
 'L1: the app reports crashes and errors to Admin -> Errors (client_error_log). Off = nothing is stored.', 'bool', null, null),
('errors.per_user_per_hour', '30', 'admin', 'Error reports per player per hour',
 'L1: most error reports one player can send per hour (logged-out visitors share 10x this).', 'number', 1, 500),
('errors.keep_days', '14', 'admin', 'Keep error reports (days)',
 'L1: error reports older than this are deleted.', 'number', 1, 90)
on conflict (key) do nothing;

create or replace function public.client_error_log(p_kind text, p_message text, p_stack text default null,
                                                   p_url text default null, p_build text default null, p_ua text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_max  int := greatest(1, coalesce((select (value #>> '{}')::int from game_config where key = 'errors.per_user_per_hour'), 30));
  v_keep int := greatest(1, coalesce((select (value #>> '{}')::int from game_config where key = 'errors.keep_days'), 14));
  v_msg  text := left(btrim(coalesce(p_message, '')), 500);
  v_n    int;
begin
  if coalesce((select (value #>> '{}')::boolean from game_config where key = 'errors.enabled'), true) is not true then
    return jsonb_build_object('logged', false, 'reason', 'off');
  end if;
  if v_msg = '' then return jsonb_build_object('logged', false, 'reason', 'empty'); end if;
  -- rate limit: per player, or all logged-out visitors together (x10)
  if v_uid is null then
    select count(*) into v_n from client_errors where user_id is null and created_at > now() - interval '1 hour';
    if v_n >= v_max * 10 then return jsonb_build_object('logged', false, 'reason', 'rate'); end if;
  else
    select count(*) into v_n from client_errors where user_id = v_uid and created_at > now() - interval '1 hour';
    if v_n >= v_max then return jsonb_build_object('logged', false, 'reason', 'rate'); end if;
  end if;
  insert into client_errors (user_id, kind, message, stack, url, build, ua)
  values (v_uid,
          case when p_kind in ('error', 'rejection', 'boundary', 'chunk') then p_kind else 'error' end,
          v_msg,
          nullif(left(coalesce(p_stack, ''), 4000), ''),
          -- path only: no query string or hash (could carry tokens)
          nullif(left(regexp_replace(coalesce(p_url, ''), '[?#].*$', ''), 300), ''),
          nullif(left(coalesce(p_build, ''), 80), ''),
          nullif(left(coalesce(p_ua, ''), 200), ''));
  -- housekeeping, roughly 1 in 50 calls
  if random() < 0.02 then
    delete from client_errors where created_at < now() - make_interval(days => v_keep);
  end if;
  return jsonb_build_object('logged', true);
end $$;
revoke all on function public.client_error_log(text, text, text, text, text, text) from public;
grant execute on function public.client_error_log(text, text, text, text, text, text) to anon, authenticated;

-- Admin: latest errors grouped by message (newest group first) + a few recent samples per group.
create or replace function public.admin_client_errors(p_hours int default 72)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 72), 24 * 30)));
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'since', v_since,
    'total', (select count(*) from client_errors where created_at >= v_since),
    'players', (select count(distinct user_id) from client_errors where created_at >= v_since),
    'groups', coalesce((
      select jsonb_agg(g order by g->>'last' desc) from (
        select jsonb_build_object(
          'message', e.message,
          'kind', (array_agg(e.kind order by e.created_at desc))[1],
          'count', count(*),
          'players', count(distinct e.user_id),
          'first', min(e.created_at),
          'last', max(e.created_at),
          'builds', (select jsonb_agg(distinct x.build) from client_errors x where x.message = e.message and x.created_at >= v_since and x.build is not null),
          'samples', (select jsonb_agg(jsonb_build_object('at', s.created_at, 'user', s.user_id,
                                                          'username', (select username from profiles p where p.id = s.user_id),
                                                          'url', s.url, 'build', s.build, 'ua', s.ua, 'stack', s.stack))
                        from (select * from client_errors y where y.message = e.message and y.created_at >= v_since
                               order by y.created_at desc limit 3) s)
        ) g
        from client_errors e
        where e.created_at >= v_since
        group by e.message
        order by max(e.created_at) desc
        limit 100
      ) q), '[]'::jsonb));
end $$;
revoke all on function public.admin_client_errors(int) from public, anon;
grant execute on function public.admin_client_errors(int) to authenticated;

-- ---------- 2. furniture_sell: no double payout on a parallel sell ----------
CREATE OR REPLACE FUNCTION public.furniture_sell(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me    profiles := bl_me();
  pf      player_furniture;
  f       furniture;
  v_id    text;
  v_copy  int;
  v_key   text;
  v_last  text;
  v_moved text;
  v_pct   numeric;
  v_pay   bigint;
  v_cash  bigint;
begin
  perform bl_assert_free(v_me);
  if not bl_cfg_bool('furniture.sell_enabled') then
    raise exception 'Selling furniture is paused right now.' using errcode = 'P0001', hint = 'sell_disabled';
  end if;
  perform bl_furniture_require_owned(v_me.id, p_key);
  v_id := bl_furniture_id_of(p_key);
  v_copy := bl_furniture_copy_of(p_key);
  v_key := case when v_copy = 1 then 'own_' || v_id else 'own_' || v_id || '-' || v_copy end;
  select * into pf from player_furniture where user_id = v_me.id and furniture_id = v_id for update;
  -- L1: a second, parallel sell of the same piece waits on the lock above and then finds the row gone
  -- (or fewer copies than the key names). Refuse it instead of paying out twice.
  if not found or pf.qty < v_copy then
    raise exception 'You don''t have that piece any more.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  select * into f from furniture where id = v_id;
  if pf.source = 'starter' and pf.qty <= 1 then
    raise exception '% came with your house. You fit store am, but you no fit sell am.', f.name
      using errcode = 'P0001', hint = 'starter_piece';
  end if;
  v_pct := greatest(0, least(100, coalesce(bl_cfg('furniture.resale_pct'), 45)));
  v_pay := (floor(f.price * v_pct / 100.0 / 100) * 100)::bigint;
  if v_pay <= 0 then
    raise exception 'Nobody go buy % from you.', f.name using errcode = 'P0001', hint = 'not_sellable';
  end if;
  -- every copy gets its row first, so the renumbering below sees them all
  perform bl_furniture_materialize(v_me.id);
  v_last := case when pf.qty <= 1 then 'own_' || v_id else 'own_' || v_id || '-' || pf.qty end;
  delete from player_house_furniture where owner_id = v_me.id and furniture_key = v_key;
  if v_last <> v_key then
    -- the last copy takes the sold key, so the keys stay own_x, own_x-2 ... own_x-(qty-1)
    update player_house_furniture set furniture_key = v_key, updated_at = bl_now()
     where owner_id = v_me.id and furniture_key = v_last;
    v_moved := v_last;
  end if;
  if pf.qty <= 1 then
    delete from player_furniture where user_id = v_me.id and furniture_id = v_id;
  else
    update player_furniture set qty = qty - 1 where user_id = v_me.id and furniture_id = v_id;
  end if;
  v_cash := bl_add_money(v_me.id, 'cash', v_pay, 'furniture_sell',
                         jsonb_build_object('furniture', f.id, 'name', f.name, 'key', v_key, 'price', f.price));
  return jsonb_build_object(
    'message', 'You sold ' || f.name || ' for ' || bl_naira(v_pay) || '. The buyer don carry am go.',
    'furniture_key', v_key, 'moved_from', v_moved, 'id', f.id, 'name', f.name, 'earned', v_pay,
    'price', f.price, 'resale_pct', v_pct, 'qty', greatest(pf.qty - 1, 0), 'cash', v_cash);
end $function$;
revoke all on function public.furniture_sell(text) from public, anon;
grant execute on function public.furniture_sell(text) to authenticated, service_role;

-- ---------- 3. home_layouts: no table write grants ----------
revoke insert, update, delete, truncate on table public.home_layouts from anon, authenticated;
-- profile_archive kept a default TRUNCATE grant (TRUNCATE skips RLS). No player role needs TRUNCATE anywhere.
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r', 'p') loop
    execute format('revoke truncate on table public.%I from anon, authenticated', t);
  end loop;
end $$;

notify pgrst, 'reload schema';
