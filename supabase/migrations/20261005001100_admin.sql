-- Benin Life — V1-7 "Admin page": server side of /admin (docs/ADMIN.md).
-- Every RPC here starts with bl_admin_guard() (bl_is_admin(): is_admin and not banned), so the
-- client gate in src/screens/AdminRoute.tsx is only a door. Every write is audited:
-- game_config changes in config_audit, everything else in admin_audit.
--
-- Safe on a non-empty hosted DB and idempotent: config rows use `on conflict do nothing`,
-- the one policy we touch is dropped and re-created, functions are `create or replace`.

-- ---------------------------------------------------------------------
-- 1. Config: admin bootstrap list (category `admin`)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('admin.bootstrap_emails', '"dev.shalom1@gmail.com,code.devshalom@gmail.com"', 'admin', 'Owner emails (claim admin)',
 'Comma-separated login emails that may press "Claim admin" on /admin to become admin. Clear it once the owners are admins. Hidden from players.',
 'text', null, null)
on conflict (key) do nothing;

-- admin.* keys are private (the bootstrap emails must not be readable by every visitor).
-- Players' config loads and realtime both obey this policy; admins read everything via admin_config_list().
drop policy if exists game_config_read on public.game_config;
create policy game_config_read on public.game_config for select to anon, authenticated
  using (key not like 'admin.%');

-- ---------------------------------------------------------------------
-- 2. Helpers (internal)
-- ---------------------------------------------------------------------
create or replace function public.bl_admin_guard() returns uuid
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Please log in first.' using errcode = 'P0001', hint = 'not_logged_in';
  end if;
  if not bl_is_admin() then
    raise exception 'Only admins can do that.' using errcode = 'P0001', hint = 'not_admin';
  end if;
  return auth.uid();
end $$;

-- Start of "today" in Benin (WAT), as a timestamptz.
create or replace function public.bl_admin_day_start() returns timestamptz
language sql stable set search_path = public as $$
  select date_trunc('day', bl_now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';
$$;

-- Whitelist for admin_row_upsert / admin_table_rows.
-- cols: column -> type (text | int | money | num | bool | obj | arr | text_null | int_null).
-- pk columns must be sent on every call; `insert` says whether new rows may be created.
create or replace function public.bl_admin_table_spec(p_table text) returns jsonb
language sql immutable as $$
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
              "effects":"obj","sort":"int"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
  end::jsonb;
$$;

-- Type check one value against a spec type; raises a friendly message.
create or replace function public.bl_admin_check_value(p_col text, p_type text, p_val jsonb) returns void
language plpgsql immutable as $$
declare t text := jsonb_typeof(p_val); n numeric;
begin
  if t is null or t = 'null' then
    if p_type in ('text_null', 'int_null') then return; end if;
    raise exception '% can''t be empty.', p_col using errcode = 'P0001', hint = 'bad_value';
  end if;
  case p_type
    when 'text', 'text_null' then
      if t <> 'string' then raise exception '% must be text.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if length(p_val #>> '{}') > 4000 then raise exception '% is too long.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'bool' then
      if t <> 'boolean' then raise exception '% must be true or false.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'obj' then
      if t <> 'object' then raise exception '% must be a JSON object ({...}).', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
    when 'arr' then
      if t <> 'array' or exists (select 1 from jsonb_array_elements(p_val) e where jsonb_typeof(e) <> 'string') then
        raise exception '% must be a list of text values.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
    when 'int', 'int_null', 'money', 'num' then
      if t <> 'number' then raise exception '% must be a number.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      n := p_val::text::numeric;
      if p_type <> 'num' and n <> trunc(n) then
        raise exception '% must be a whole number.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col <> 'sort' and n < 0 then
        raise exception '% can''t be negative.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if abs(n) > 1e13 then raise exception '% is too big.', p_col using errcode = 'P0001', hint = 'bad_value'; end if;
      if p_col in ('resale_pct') and n > 100 then
        raise exception '% must be 0–100.', p_col using errcode = 'P0001', hint = 'bad_value';
      end if;
      if p_col = 'risk' and n > 1 then
        raise exception 'risk must be between 0 and 1.' using errcode = 'P0001', hint = 'bad_value';
      end if;
    else
      raise exception 'Unknown column type %', p_type using errcode = 'P0001';
  end case;
end $$;

revoke execute on function public.bl_admin_guard()                          from public, anon, authenticated;
revoke execute on function public.bl_admin_day_start()                      from public, anon, authenticated;
revoke execute on function public.bl_admin_table_spec(text)                 from public, anon, authenticated;
revoke execute on function public.bl_admin_check_value(text, text, jsonb)   from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Config RPCs
-- ---------------------------------------------------------------------
-- All rows with metadata + the previous value from the latest audit entry (for "Revert").
create or replace function public.admin_config_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'key', c.key, 'value', c.value, 'category', c.category, 'label', c.label,
             'description', c.description, 'kind', c.kind, 'min', c.min, 'max', c.max,
             'updated_at', c.updated_at, 'updated_by', c.updated_by,
             'updated_by_name', (select username from profiles where id = c.updated_by),
             'prev_value', a.old_value, 'prev_at', a.created_at)
           order by c.category, c.key)
      from game_config c
      left join lateral (select old_value, created_at from config_audit ca
                          where ca.key = c.key order by ca.id desc limit 1) a on true), '[]'::jsonb);
end $$;

create or replace function public.bl_admin_config_apply(p_admin uuid, p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c game_config; t text := jsonb_typeof(p_value); n numeric; v_new game_config;
begin
  select * into c from game_config where key = p_key for update;
  if not found then
    raise exception 'Unknown setting: %', coalesce(p_key, '(empty)') using errcode = 'P0001', hint = 'no_key';
  end if;
  if p_value is null or t = 'null' then
    raise exception '% can''t be empty.', c.label using errcode = 'P0001', hint = 'bad_value';
  end if;
  case c.kind
    when 'number', 'percent', 'naira', 'minutes' then
      if t <> 'number' then
        raise exception '% must be a number.', c.label using errcode = 'P0001', hint = 'bad_value';
      end if;
      n := p_value::text::numeric;
      if c.kind = 'naira' and n <> trunc(n) then
        raise exception '% must be a whole naira amount.', c.label using errcode = 'P0001', hint = 'bad_value';
      end if;
      if c.min is not null and n < c.min then
        raise exception '% must be at least %.', c.label, c.min using errcode = 'P0001', hint = 'out_of_range';
      end if;
      if c.max is not null and n > c.max then
        raise exception '% must be at most %.', c.label, c.max using errcode = 'P0001', hint = 'out_of_range';
      end if;
    when 'bool' then
      if t <> 'boolean' then
        raise exception '% must be on or off.', c.label using errcode = 'P0001', hint = 'bad_value';
      end if;
    when 'text' then
      if t <> 'string' then
        raise exception '% must be text.', c.label using errcode = 'P0001', hint = 'bad_value';
      end if;
      if length(p_value #>> '{}') > 4000 then
        raise exception '% is too long.', c.label using errcode = 'P0001', hint = 'bad_value';
      end if;
    else
      null; -- 'json' (or future kinds): any JSON value
  end case;

  if c.value = p_value then
    return jsonb_build_object('key', c.key, 'value', c.value, 'changed', false);
  end if;
  -- The game_config triggers (epoch, force_next, arrival location checks; rent switch) still run here.
  update game_config set value = p_value, updated_by = p_admin where key = p_key returning * into v_new;
  insert into config_audit (admin_id, key, old_value, new_value) values (p_admin, p_key, c.value, p_value);
  return jsonb_build_object('key', v_new.key, 'value', v_new.value, 'changed', true, 'updated_at', v_new.updated_at);
end $$;
revoke execute on function public.bl_admin_config_apply(uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.admin_config_set(p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); r jsonb;
begin
  r := bl_admin_config_apply(v_admin, p_key, p_value);
  return r || jsonb_build_object('message',
    case when (r->>'changed')::boolean then 'Saved. Players get it right away.' else 'No change.' end);
end $$;

-- {"key": value, ...} — all or nothing.
create or replace function public.admin_config_set_many(p_changes jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); k text; v jsonb; n int := 0; r jsonb;
begin
  if jsonb_typeof(p_changes) is distinct from 'object' then
    raise exception 'Send the changes as {"key": value}.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  for k, v in select * from jsonb_each(p_changes) loop
    r := bl_admin_config_apply(v_admin, k, v);
    if (r->>'changed')::boolean then n := n + 1; end if;
  end loop;
  return jsonb_build_object('message', n || case when n = 1 then ' setting saved.' else ' settings saved.' end, 'changed', n);
end $$;

-- Put a setting back to the old value of one config_audit entry.
create or replace function public.admin_config_revert(p_audit_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a config_audit; r jsonb;
begin
  select * into a from config_audit where id = p_audit_id;
  if not found or a.old_value is null then
    raise exception 'Nothing to revert there.' using errcode = 'P0001', hint = 'not_found';
  end if;
  r := bl_admin_config_apply(v_admin, a.key, a.old_value);
  return r || jsonb_build_object('message', 'Reverted ' || a.key || '.');
end $$;

-- ---------------------------------------------------------------------
-- 4. Content tables (whitelisted generic read + upsert)
-- ---------------------------------------------------------------------
create or replace function public.admin_table_rows(p_table text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s jsonb := bl_admin_table_spec(p_table); r jsonb;
begin
  perform bl_admin_guard();
  if s is null then
    raise exception 'That table can''t be edited here.' using errcode = 'P0001', hint = 'bad_table';
  end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by %s), ''[]'') from %I t', s->>'order', p_table) into r;
  return r;
end $$;

-- Update one row (only the whitelisted columns you send) or insert it where allowed.
-- p_row must contain the primary key column(s). Soft-disable with "active": false (no deletes).
create or replace function public.admin_row_upsert(p_table text, p_row jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  s       jsonb := bl_admin_table_spec(p_table);
  k       text;
  v_set   text[] := '{}';
  v_cols  text[] := '{}';
  v_where text;
  v_old   jsonb;
  v_new   jsonb;
  v_pk    text;
  v_bad   text;
begin
  if s is null then
    raise exception 'That table can''t be edited here.' using errcode = 'P0001', hint = 'bad_table';
  end if;
  if jsonb_typeof(p_row) is distinct from 'object' then
    raise exception 'Send the row as a JSON object.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  -- primary key present and well-typed
  for v_pk in select jsonb_array_elements_text(s->'pk') loop
    if not p_row ? v_pk or jsonb_typeof(p_row->v_pk) not in ('string', 'number') or coalesce(p_row->>v_pk, '') = '' then
      raise exception 'Missing %.', v_pk using errcode = 'P0001', hint = 'bad_value';
    end if;
  end loop;
  -- only whitelisted columns, each with the right type
  for k in select jsonb_object_keys(p_row) loop
    if s->'pk' ? k then continue; end if;
    if not (s->'cols') ? k then
      raise exception 'Column "%" can''t be edited here.', k using errcode = 'P0001', hint = 'bad_column';
    end if;
    perform bl_admin_check_value(k, s->'cols'->>k, p_row->k);
    v_set := v_set || format('%I = r.%I', k, k);
    v_cols := v_cols || quote_ident(k);
  end loop;
  -- references that have no FK
  if p_table = 'items' and p_row ? 'sold_at' then
    select string_agg(e, ', ') into v_bad from jsonb_array_elements_text(p_row->'sold_at') e
     where not exists (select 1 from locations where id = e);
    if v_bad is not null then
      raise exception 'Unknown place id(s) in sold_at: %', v_bad using errcode = 'P0001', hint = 'bad_value';
    end if;
  end if;
  if p_table = 'career_tracks' and p_row ? 'location_ids' then
    select string_agg(e, ', ') into v_bad from jsonb_array_elements_text(p_row->'location_ids') e
     where not exists (select 1 from locations where id = e);
    if v_bad is not null then
      raise exception 'Unknown place id(s): %', v_bad using errcode = 'P0001', hint = 'bad_value';
    end if;
  end if;
  if p_table = 'start_homes' and p_row ? 'allowed_origins' then
    select string_agg(e, ', ') into v_bad from jsonb_array_elements_text(p_row->'allowed_origins') e
     where not exists (select 1 from origin_tiers where id = e);
    if v_bad is not null then
      raise exception 'Unknown origin(s): %', v_bad using errcode = 'P0001', hint = 'bad_value';
    end if;
  end if;

  select string_agg(format('t.%I = r.%I', pk, pk), ' and ') into v_where
    from jsonb_array_elements_text(s->'pk') pk;

  execute format('select to_jsonb(t) from %I t, jsonb_populate_record(null::%I, $1) r where %s',
                 p_table, p_table, v_where) into v_old using p_row;

  begin
    if v_old is not null then
      if cardinality(v_set) = 0 then
        return jsonb_build_object('message', 'No change.', 'row', v_old);
      end if;
      execute format('update %I t set %s from jsonb_populate_record(null::%I, $1) r where %s returning to_jsonb(t)',
                     p_table, array_to_string(v_set, ', '), p_table, v_where) into v_new using p_row;
    else
      if not (s->>'insert')::boolean then
        raise exception 'New rows can''t be added to % here.', p_table using errcode = 'P0001', hint = 'no_insert';
      end if;
      select v_cols || array_agg(quote_ident(pk)) into v_cols from jsonb_array_elements_text(s->'pk') pk;
      execute format('insert into %I (%s) select %s from jsonb_populate_record(null::%I, $1) r returning to_jsonb(%I)',
                     p_table, array_to_string(v_cols, ', '),
                     (select string_agg('r.' || c, ', ') from unnest(v_cols) c), p_table, p_table)
        into v_new using p_row;
    end if;
  exception
    when raise_exception then raise;
    when others then
      raise exception 'Could not save: %', sqlerrm using errcode = 'P0001', hint = 'bad_value';
  end;

  insert into admin_audit (admin_id, action, data)
  values (v_admin, case when v_old is null then 'row_insert' else 'row_update' end,
          jsonb_build_object('table', p_table, 'row', p_row, 'old', v_old));
  return jsonb_build_object('message', case when v_old is null then 'Added.' else 'Saved.' end, 'row', v_new);
end $$;

-- ---------------------------------------------------------------------
-- 5. Players
-- ---------------------------------------------------------------------
create or replace function public.admin_players(p_search text default '', p_limit int default 50, p_offset int default 0)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q text := lower(trim(coalesce(p_search, '')));
  v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_presence numeric := bl_cfg('time.presence_real_minutes');
begin
  perform bl_admin_guard();
  return (
    with m as (
      select p.*, u.email from profiles p left join auth.users u on u.id = p.id
       where q = '' or lower(p.username) like '%' || q || '%' or lower(coalesce(u.email, '')) like '%' || q || '%'
          or p.id::text = q
    )
    select jsonb_build_object(
      'total', (select count(*) from m),
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'username', x.username, 'email', x.email, 'origin', x.origin, 'cash', x.cash, 'bank', x.bank,
                 'job_id', x.job_id, 'job_level', x.job_level, 'location_id', x.location_id,
                 'location_name', (select name from locations where id = x.location_id),
                 'created_at', x.created_at, 'last_seen', x.last_seen,
                 'online', x.last_seen > bl_now() - make_interval(secs => v_presence * 60),
                 'banned', x.banned, 'is_admin', x.is_admin, 'chat_muted_until', x.chat_muted_until,
                 'avatar', x.avatar)
               order by x.last_seen desc)
          from (select * from m order by last_seen desc limit v_lim offset v_off) x), '[]'::jsonb)));
end $$;

create or replace function public.admin_player_detail(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p profiles; v_email text;
begin
  perform bl_admin_guard();
  select * into p from profiles where id = p_id;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select email into v_email from auth.users where id = p_id;
  return jsonb_build_object(
    'profile', to_jsonb(p) - 'avatar' || jsonb_build_object('email', v_email, 'avatar', p.avatar,
               'location_name', (select name from locations where id = p.location_id),
               'job_title', (select title from career_levels where track_id = p.job_id and level = p.job_level)),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'account', l.account, 'delta', l.delta,
                                 'balance_after', l.balance_after, 'reason', l.reason,
                                 'label', bl_ledger_label(l.reason, l.meta), 'created_at', l.created_at) order by l.id desc)
                         from (select * from ledger where user_id = p_id order by id desc limit 30) l), '[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty,
                                    'name', (select name from items where id = i.item_id)) order by i.item_id)
                            from inventory i where i.user_id = p_id), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'action', a.action, 'data', a.data,
                                'created_at', a.created_at, 'admin', (select username from profiles where id = a.admin_id))
                                order by a.id desc)
                        from (select * from admin_audit where target_user = p_id order by id desc limit 20) a), '[]'::jsonb));
end $$;

create or replace function public.admin_grant_money(p_id uuid, p_account text, p_delta bigint, p_reason text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_bal bigint; v_note text := left(trim(coalesce(p_reason, '')), 200);
begin
  if p_account not in ('cash', 'bank') then
    raise exception 'Pick cash or bank.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 1000000000000 then
    raise exception 'Enter an amount (not zero).' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if not exists (select 1 from profiles where id = p_id) then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  begin
    v_bal := bl_add_money(p_id, p_account, p_delta, 'admin_grant', jsonb_build_object('admin', v_admin, 'note', v_note));
  exception when others then
    if sqlerrm like 'Your money no reach%' then
      raise exception 'They don''t have that much in their %.', p_account using errcode = 'P0001', hint = 'insufficient_funds';
    end if;
    raise;
  end;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'grant_money', p_id,
          jsonb_build_object('account', p_account, 'delta', p_delta, 'balance_after', v_bal, 'note', v_note));
  perform bl_event(p_id, 'admin_money', case when p_delta > 0 then 'Money received' else 'Account adjusted' end,
                   case when p_delta > 0 then bl_naira(p_delta) || ' was added to your ' || p_account || '.'
                        else bl_naira(-p_delta) || ' was taken from your ' || p_account || '.' end
                   || case when v_note <> '' then ' Note: ' || v_note else '' end,
                   jsonb_build_object('account', p_account, 'delta', p_delta));
  return jsonb_build_object('message', case when p_delta > 0 then 'Added ' || bl_naira(p_delta) else 'Took ' || bl_naira(-p_delta) end
                                       || ' (' || p_account || '). New balance ' || bl_naira(v_bal) || '.',
                            'account', p_account, 'balance', v_bal);
end $$;

create or replace function public.admin_ban(p_id uuid, p_banned boolean, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_name text;
begin
  if p_id = v_admin then
    raise exception 'You can''t ban yourself.' using errcode = 'P0001', hint = 'self';
  end if;
  update profiles set banned = coalesce(p_banned, true) where id = p_id returning username into v_name;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_banned, true) then 'ban' else 'unban' end, p_id,
          jsonb_build_object('reason', left(coalesce(p_reason, ''), 200)));
  return jsonb_build_object('message', case when coalesce(p_banned, true) then v_name || ' is banned.' else v_name || ' is unbanned.' end,
                            'banned', coalesce(p_banned, true));
end $$;

-- p_minutes real minutes; 0 (or less) unmutes.
create or replace function public.admin_mute(p_id uuid, p_minutes int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_until timestamptz; v_name text;
begin
  if coalesce(p_minutes, 0) > 525600 then
    raise exception 'A mute can last at most a year.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  v_until := case when coalesce(p_minutes, 0) > 0 then bl_now() + make_interval(mins => p_minutes) end;
  update profiles set chat_muted_until = v_until where id = p_id returning username into v_name;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when v_until is null then 'unmute' else 'mute' end, p_id,
          jsonb_build_object('minutes', greatest(coalesce(p_minutes, 0), 0), 'until', v_until));
  return jsonb_build_object('message', case when v_until is null then v_name || ' can chat again.'
                                            else v_name || ' is muted for ' || p_minutes || ' min.' end,
                            'chat_muted_until', v_until);
end $$;

create or replace function public.admin_set_admin(p_id uuid, p_is_admin boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_name text;
begin
  if not coalesce(p_is_admin, false) and p_id = v_admin
     and (select count(*) from profiles where is_admin and not banned) <= 1 then
    raise exception 'You are the last admin. Make someone else admin first.' using errcode = 'P0001', hint = 'last_admin';
  end if;
  update profiles set is_admin = coalesce(p_is_admin, false) where id = p_id returning username into v_name;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_is_admin, false) then 'make_admin' else 'remove_admin' end, p_id, '{}');
  return jsonb_build_object('message', case when coalesce(p_is_admin, false) then v_name || ' is now an admin.'
                                            else v_name || ' is no longer an admin.' end,
                            'is_admin', coalesce(p_is_admin, false));
end $$;

-- Owner bootstrap: a logged-in player whose auth email is in admin.bootstrap_emails becomes admin.
create or replace function public.admin_claim() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_list  text;
  p       profiles;
begin
  if v_uid is null then
    raise exception 'Please log in first.' using errcode = 'P0001', hint = 'not_logged_in';
  end if;
  select * into p from profiles where id = v_uid for update;
  if not found then
    raise exception 'Create your Sim first, then come back here.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if p.banned then
    raise exception 'This account is banned.' using errcode = 'P0001', hint = 'banned';
  end if;
  if p.is_admin then
    return jsonb_build_object('message', 'You are already an admin.', 'is_admin', true);
  end if;
  select lower(trim(email)) into v_email from auth.users where id = v_uid;
  select coalesce(value #>> '{}', '') into v_list from game_config where key = 'admin.bootstrap_emails';
  if v_email is null or v_email = '' or not exists (
       select 1 from unnest(string_to_array(coalesce(v_list, ''), ',')) e where lower(trim(e)) = v_email) then
    raise exception 'This account''s email isn''t on the owner list, so it can''t claim admin.'
      using errcode = 'P0001', hint = 'not_listed';
  end if;
  update profiles set is_admin = true where id = v_uid;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_uid, 'admin_claim', v_uid, jsonb_build_object('email', v_email));
  return jsonb_build_object('message', 'Welcome, boss. You are now an admin.', 'is_admin', true);
end $$;

-- ---------------------------------------------------------------------
-- 6. Stats, audit, chat moderation
-- ---------------------------------------------------------------------
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := bl_admin_day_start();
  v_presence numeric := bl_cfg('time.presence_real_minutes');
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'day_start', v_day,
    'players', (select count(*) from profiles),
    'online', (select count(*) from profiles where last_seen > bl_now() - make_interval(secs => v_presence * 60) and not banned),
    'online_minutes', v_presence,
    'new_today', (select count(*) from profiles where created_at >= v_day),
    'banned', (select count(*) from profiles where banned),
    'admins', (select count(*) from profiles where is_admin and not banned),
    'cash_total', (select coalesce(sum(cash), 0) from profiles),
    'bank_total', (select coalesce(sum(bank), 0) from profiles),
    'money_today', coalesce((
      select jsonb_agg(jsonb_build_object('reason', reason, 'label', bl_ledger_label(reason, '{}'),
                                          'created', created, 'destroyed', destroyed, 'count', n)
                       order by created + destroyed desc)
        from (select reason, sum(greatest(delta, 0)) as created, sum(greatest(-delta, 0)) as destroyed, count(*) as n
                from ledger where created_at >= v_day group by reason) r), '[]'::jsonb),
    'created_today', (select coalesce(sum(delta), 0) from ledger where created_at >= v_day and delta > 0),
    'destroyed_today', (select coalesce(-sum(delta), 0) from ledger where created_at >= v_day and delta < 0),
    'jobs', coalesce((
      select jsonb_agg(jsonb_build_object('track', coalesce(j.job_id, ''), 'name', coalesce(t.name, 'No job'),
                                          'emoji', coalesce(t.emoji, ''), 'count', j.n) order by j.n desc)
        from (select job_id, count(*) as n from profiles group by job_id) j
        left join career_tracks t on t.id = j.job_id), '[]'::jsonb),
    'origins', coalesce((
      select jsonb_agg(jsonb_build_object('origin', o.origin, 'name', coalesce(t.name, o.origin), 'count', o.n) order by o.n desc)
        from (select origin, count(*) as n from profiles group by origin) o
        left join origin_tiers t on t.id = o.origin), '[]'::jsonb),
    'richest', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'username', username, 'cash', cash, 'bank', bank, 'total', cash + bank)
                       order by cash + bank desc)
        from (select id, username, cash, bank from profiles order by cash + bank desc limit 10) r), '[]'::jsonb),
    'chat_today', (select count(*) from chat_messages where created_at >= v_day),
    'reports_pending', (select count(distinct r.message_id) from chat_reports r
                          join chat_messages m on m.id = r.message_id where not m.hidden));
end $$;

create or replace function public.admin_audit_list(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  perform bl_admin_guard();
  return coalesce((
    select jsonb_agg(s.x order by s.at desc, s.x->>'id' desc)
      from (
        select * from (
          select jsonb_build_object('id', 'c' || c.id, 'audit_id', c.id, 'type', 'config', 'action', 'config_set',
                                    'key', c.key, 'old_value', c.old_value, 'new_value', c.new_value,
                                    'admin', coalesce((select username from profiles where id = c.admin_id), 'system'),
                                    'created_at', c.created_at) as x, c.created_at as at
            from (select * from config_audit order by id desc limit v_lim) c
          union all
          select jsonb_build_object('id', 'a' || a.id, 'audit_id', a.id, 'type', 'admin', 'action', a.action,
                                    'target', (select username from profiles where id = a.target_user),
                                    'target_id', a.target_user, 'data', a.data,
                                    'admin', coalesce((select username from profiles where id = a.admin_id), 'system'),
                                    'created_at', a.created_at), a.created_at
            from (select * from admin_audit order by id desc limit v_lim) a
        ) u order by at desc limit v_lim
      ) s), '[]'::jsonb);
end $$;

create or replace function public.admin_chat_reports(p_include_hidden boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', m.id, 'body', m.body, 'username', m.username, 'user_id', m.user_id,
             'location_id', m.location_id, 'location_name', (select name from locations where id = m.location_id),
             'created_at', m.created_at, 'hidden', m.hidden, 'reports', r.n, 'last_report', r.last_at,
             'reasons', r.reasons, 'reporters', r.reporters,
             'author_muted_until', (select chat_muted_until from profiles where id = m.user_id))
           order by m.hidden, r.last_at desc)
      from (select message_id, count(*) as n, max(created_at) as last_at,
                   jsonb_agg(distinct reason) filter (where coalesce(reason, '') <> '') as reasons,
                   jsonb_agg((select username from profiles where id = reporter_id)) as reporters
              from chat_reports group by message_id) r
      join chat_messages m on m.id = r.message_id
     where coalesce(p_include_hidden, true) or not m.hidden), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 7. Privileges
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'admin_config_list()', 'admin_config_set(text, jsonb)', 'admin_config_set_many(jsonb)', 'admin_config_revert(bigint)',
    'admin_table_rows(text)', 'admin_row_upsert(text, jsonb)',
    'admin_players(text, int, int)', 'admin_player_detail(uuid)', 'admin_grant_money(uuid, text, bigint, text)',
    'admin_ban(uuid, boolean, text)', 'admin_mute(uuid, int)', 'admin_set_admin(uuid, boolean)', 'admin_claim()',
    'admin_stats()', 'admin_audit_list(int)', 'admin_chat_reports(boolean)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
