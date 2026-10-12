-- A2 Admin broadcast + mass gift (docs/ADMIN.md "Broadcast").
-- * broadcasts: ONE row per announcement (not one per player). Audience everyone / lapo / nepo / joined_after is
--   matched when a player reads it (RLS + broadcast_inbox), so new players who fit still see it until it expires.
--   Audience 'online' and every gift are "targeted": the exact recipients are frozen at send time as
--   broadcast_reads rows (one set-based insert), so a player who comes online later never gets them.
-- * broadcast_reads(broadcast_id, user_id, seen_at, dismissed_at): per-player seen / dismissed tracking (reach count).
-- * admin_gift_send: admin-only, set-based balance update + ledger insert (reason 'admin_gift', meta.narration
--   is the Bank -> History line via bl_ledger_label), idempotency key (unique gift_key), per-player cap
--   admin.gift_max (default ₦1,000,000) and total cap admin.gift_total_max (default ₦20B), audit row, and one
--   targeted broadcast "You received ₦X" carrying the narration.
-- * Clients learn about a new broadcast from game_config 'broadcast.last_id' (already live on every tab via the
--   game_config Realtime channel / poll fallback), then call broadcast_inbox() once (jittered).
-- * Each send also writes admin_notifications (push to the owner's admin devices via admin-push).
-- Idempotent; safe on a non-empty DB.

create table if not exists public.broadcasts (
  id            bigserial primary key,
  kind          text not null default 'message' check (kind in ('message', 'gift')),
  title         text not null check (char_length(title) between 1 and 80),
  body          text not null default '' check (char_length(body) <= 500),
  style         text not null default 'info' check (style in ('info', 'celebration', 'warning')),
  audience      text not null default 'everyone' check (audience in ('everyone', 'lapo', 'nepo', 'online', 'joined_after')),
  joined_after  timestamptz,
  popup         boolean not null default true,
  expires_at    timestamptz,
  targeted      boolean not null default false,
  target_count  int not null default 0,
  gift_account  text check (gift_account is null or gift_account in ('cash', 'bank')),
  gift_amount   bigint check (gift_amount is null or gift_amount > 0),
  gift_total    numeric,
  gift_key      text,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  cancelled_at  timestamptz,
  check (audience <> 'joined_after' or joined_after is not null)
);
create unique index if not exists broadcasts_gift_key_uidx on public.broadcasts (gift_key) where gift_key is not null;
create index if not exists broadcasts_live_idx on public.broadcasts (id desc) where cancelled_at is null;
create index if not exists broadcasts_created_by_idx on public.broadcasts (created_by) where created_by is not null;

create table if not exists public.broadcast_reads (
  broadcast_id bigint not null references public.broadcasts(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  seen_at      timestamptz,
  dismissed_at timestamptz,
  primary key (broadcast_id, user_id)
);
create index if not exists broadcast_reads_user_idx on public.broadcast_reads (user_id, broadcast_id desc);

alter table public.broadcasts enable row level security;
alter table public.broadcast_reads enable row level security;
revoke all on table public.broadcasts from public, anon, authenticated;
revoke all on table public.broadcast_reads from public, anon, authenticated;
revoke all on sequence public.broadcasts_id_seq from public, anon, authenticated;
grant select on table public.broadcasts to authenticated;
grant select on table public.broadcast_reads to authenticated;

-- A player reads a broadcast only while it is live (not cancelled, not expired) and only when it is for them.
drop policy if exists broadcasts_audience on public.broadcasts;
create policy broadcasts_audience on public.broadcasts for select to authenticated
  using (cancelled_at is null and (expires_at is null or expires_at > now())
         and case when targeted
                  then exists (select 1 from public.broadcast_reads r
                                where r.broadcast_id = broadcasts.id and r.user_id = (select auth.uid()))
                  else exists (select 1 from public.profiles p
                                where p.id = (select auth.uid()) and not p.banned
                                  and (broadcasts.audience = 'everyone'
                                       or (broadcasts.audience in ('lapo', 'nepo') and p.origin = broadcasts.audience)
                                       or (broadcasts.audience = 'joined_after' and p.created_at >= broadcasts.joined_after)))
             end);
drop policy if exists broadcast_reads_own on public.broadcast_reads;
create policy broadcast_reads_own on public.broadcast_reads for select to authenticated
  using (user_id = (select auth.uid()));

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('admin.gift_max', '1000000', 'admin', 'Biggest mass gift per player',
 'A2: most one "Gift money to everyone" may give each player (default ₦1,000,000).', 'naira', 1, 1000000000000),
('admin.gift_total_max', '20000000000', 'admin', 'Biggest mass gift in total',
 'A2: sanity cap on one mass gift: players × amount may not pass this (default ₦20B).', 'naira', 1, 9000000000000000),
('broadcast.last_id', '0', 'news', 'Latest broadcast (automatic)',
 'A2: set by Admin → Broadcast. Every open game sees the change and fetches the new announcement. Do not edit.', 'number', 0, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Private helpers (revoked from clients)
-- ---------------------------------------------------------------------------------------------
-- Players an audience covers right now: finished Sims, not banned.
create or replace function public.bl_broadcast_targets(p_audience text, p_joined_after timestamptz)
returns table (id uuid)
language sql stable set search_path = public as $$
  select p.id from profiles p
   where p.home_chosen and not p.banned
     and case p_audience
           when 'everyone' then true
           when 'lapo' then p.origin = 'lapo'
           when 'nepo' then p.origin = 'nepo'
           when 'joined_after' then p.created_at >= p_joined_after
           when 'online' then p.last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision)
           else false
         end
$$;

-- Validates the shared audience/style/expiry inputs (raises friendly errors).
create or replace function public.bl_broadcast_check(p_audience text, p_joined_after timestamptz, p_style text, p_expires_at timestamptz)
returns void
language plpgsql stable set search_path = public as $$
begin
  if p_audience is null or p_audience not in ('everyone', 'lapo', 'nepo', 'online', 'joined_after') then
    raise exception 'Pick who gets it: everyone, LAPO, Nepo, online now or joined after a date.' using errcode = 'P0001', hint = 'bad_audience';
  end if;
  if p_audience = 'joined_after' and p_joined_after is null then
    raise exception 'Pick the date: players who joined after it get it.' using errcode = 'P0001', hint = 'bad_audience';
  end if;
  if p_style is null or p_style not in ('info', 'celebration', 'warning') then
    raise exception 'Pick a style: info, celebration or warning.' using errcode = 'P0001', hint = 'bad_style';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'The expiry is already in the past.' using errcode = 'P0001', hint = 'bad_expiry';
  end if;
end $$;

-- Tells every open game that a new broadcast exists (game_config is on the Realtime channel / poll fallback).
create or replace function public.bl_broadcast_bump(p_id bigint) returns void
language sql set search_path = public as $$
  update game_config set value = to_jsonb(p_id) where key = 'broadcast.last_id';
$$;

revoke all on function public.bl_broadcast_targets(text, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_broadcast_check(text, timestamptz, text, timestamptz) from public, anon, authenticated;
revoke all on function public.bl_broadcast_bump(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Player side
-- ---------------------------------------------------------------------------------------------
-- Live broadcasts for me (newest first, max 20) with my seen / dismissed flags.
create or replace function public.broadcast_inbox() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  p profiles;
begin
  select * into p from profiles where id = v_uid;
  if not found or p.banned then
    return jsonb_build_object('rows', '[]'::jsonb, 'last_id', 0);
  end if;
  return jsonb_build_object(
    'last_id', coalesce((select max(id) from broadcasts), 0),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', b.id, 'kind', b.kind, 'title', b.title, 'body', b.body, 'style', b.style, 'popup', b.popup,
               'gift_amount', b.gift_amount, 'gift_account', b.gift_account, 'expires_at', b.expires_at,
               'created_at', b.created_at, 'seen', r.seen_at is not null, 'dismissed', r.dismissed_at is not null)
             order by b.id desc)
        from (select b0.* from broadcasts b0
               where b0.cancelled_at is null and (b0.expires_at is null or b0.expires_at > now())
                 and case when b0.targeted
                          then exists (select 1 from broadcast_reads r0 where r0.broadcast_id = b0.id and r0.user_id = v_uid)
                          else b0.audience = 'everyone'
                               or (b0.audience in ('lapo', 'nepo') and p.origin = b0.audience)
                               or (b0.audience = 'joined_after' and p.created_at >= b0.joined_after)
                     end
               order by b0.id desc limit 20) b
        left join broadcast_reads r on r.broadcast_id = b.id and r.user_id = v_uid), '[]'::jsonb));
end $$;
revoke all on function public.broadcast_inbox() from public, anon;
grant execute on function public.broadcast_inbox() to authenticated, service_role;

-- Mark broadcasts seen (and optionally dismissed). Ignores ids that are not for me / not live.
create or replace function public.broadcast_mark(p_ids bigint[], p_dismiss boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid();
  v_ids bigint[];
  n int;
begin
  select array_agg(x.id) into v_ids
    from (select (bi->>'id')::bigint as id from jsonb_array_elements(broadcast_inbox()->'rows') bi) x
   where x.id = any (coalesce(p_ids, '{}'::bigint[]));
  if v_ids is null then
    return jsonb_build_object('marked', 0);
  end if;
  insert into broadcast_reads (broadcast_id, user_id, seen_at, dismissed_at)
  select i, v_uid, now(), case when p_dismiss then now() end from unnest(v_ids) i
  on conflict (broadcast_id, user_id) do update
    set seen_at = coalesce(broadcast_reads.seen_at, excluded.seen_at),
        dismissed_at = coalesce(broadcast_reads.dismissed_at, excluded.dismissed_at);
  get diagnostics n = row_count;
  return jsonb_build_object('marked', n);
end $$;
revoke all on function public.broadcast_mark(bigint[], boolean) from public, anon;
grant execute on function public.broadcast_mark(bigint[], boolean) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Admin side
-- ---------------------------------------------------------------------------------------------
-- How many players an audience reaches now (+ the gift total when p_amount is given).
create or replace function public.admin_broadcast_preview(p_audience text, p_joined_after timestamptz default null,
                                                          p_amount bigint default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n bigint;
begin
  perform bl_admin_guard();
  perform bl_broadcast_check(p_audience, p_joined_after, 'info', null);
  select count(*) into n from bl_broadcast_targets(p_audience, p_joined_after);
  return jsonb_build_object('count', n, 'amount', p_amount,
    'total', case when p_amount is not null then n * p_amount::numeric end,
    'gift_max', bl_cfg('admin.gift_max'), 'gift_total_max', bl_cfg('admin.gift_total_max'));
end $$;
revoke all on function public.admin_broadcast_preview(text, timestamptz, bigint) from public, anon;
grant execute on function public.admin_broadcast_preview(text, timestamptz, bigint) to authenticated, service_role;

create or replace function public.admin_broadcast_send(p_title text, p_body text, p_style text default 'info',
                                                       p_audience text default 'everyone', p_joined_after timestamptz default null,
                                                       p_popup boolean default true, p_expires_at timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_style text := lower(btrim(coalesce(p_style, 'info')));
  v_aud text := lower(btrim(coalesce(p_audience, 'everyone')));
  v_targeted boolean;
  v_id bigint;
  n int;
begin
  perform bl_broadcast_check(v_aud, p_joined_after, v_style, p_expires_at);
  if char_length(v_title) < 1 or char_length(v_title) > 80 then
    raise exception 'Give it a title (up to 80 characters).' using errcode = 'P0001', hint = 'bad_title';
  end if;
  if char_length(v_body) < 1 then
    raise exception 'Write the message.' using errcode = 'P0001', hint = 'too_short';
  end if;
  if char_length(v_body) > 500 then
    raise exception 'Keep the message under 500 characters.' using errcode = 'P0001', hint = 'too_long';
  end if;
  v_targeted := v_aud = 'online';
  insert into broadcasts (kind, title, body, style, audience, joined_after, popup, expires_at, targeted, created_by)
  values ('message', v_title, v_body, v_style, v_aud, case when v_aud = 'joined_after' then p_joined_after end,
          coalesce(p_popup, true), p_expires_at, v_targeted, v_admin)
  returning id into v_id;
  if v_targeted then
    insert into broadcast_reads (broadcast_id, user_id) select v_id, t.id from bl_broadcast_targets(v_aud, p_joined_after) t;
    get diagnostics n = row_count;
  else
    select count(*) into n from bl_broadcast_targets(v_aud, p_joined_after);
  end if;
  update broadcasts set target_count = n where id = v_id;
  perform bl_broadcast_bump(v_id);
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'broadcast', jsonb_build_object('broadcast_id', v_id, 'title', v_title, 'audience', v_aud,
                                                   'joined_after', p_joined_after, 'popup', coalesce(p_popup, true),
                                                   'expires_at', p_expires_at, 'reach', n));
  perform bl_admin_notify('broadcast', 'Broadcast sent to ' || n || ' player' || case when n = 1 then '' else 's' end,
                          v_title, jsonb_build_object('broadcast_id', v_id), '/admin/broadcast');
  return jsonb_build_object('id', v_id, 'count', n,
                            'message', 'Sent to ' || n || ' player' || case when n = 1 then '' else 's' end || '.');
end $$;
revoke all on function public.admin_broadcast_send(text, text, text, text, timestamptz, boolean, timestamptz) from public, anon;
grant execute on function public.admin_broadcast_send(text, text, text, text, timestamptz, boolean, timestamptz) to authenticated, service_role;

-- Pay every player in the audience once (set-based), ledger 'admin_gift' with the narration, one targeted broadcast.
-- p_key: idempotency key from the confirm dialog; the same key never pays twice (returns the first result).
create or replace function public.admin_gift_send(p_key text, p_amount bigint, p_account text, p_narration text,
                                                  p_audience text default 'everyone', p_joined_after timestamptz default null,
                                                  p_popup boolean default true, p_expires_at timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  v_key text := btrim(coalesce(p_key, ''));
  v_acc text := lower(btrim(coalesce(p_account, '')));
  v_narr text := btrim(coalesce(p_narration, ''));
  v_aud text := lower(btrim(coalesce(p_audience, 'everyone')));
  v_max numeric := coalesce(bl_cfg('admin.gift_max'), 1000000);
  v_total_max numeric := coalesce(bl_cfg('admin.gift_total_max'), 20000000000);
  v_ceiling constant bigint := 9000000000000000;
  b broadcasts;
  v_id bigint;
  n bigint;
  v_paid bigint;
begin
  if char_length(v_key) < 8 or char_length(v_key) > 100 then
    raise exception 'Missing gift key. Reload the page and try again.' using errcode = 'P0001', hint = 'bad_key';
  end if;
  -- one key at a time: a double-click waits here, then finds the first gift and returns it
  perform pg_advisory_xact_lock(hashtextextended('admin_gift:' || v_key, 0));
  select * into b from broadcasts where gift_key = v_key;
  if found then
    return jsonb_build_object('id', b.id, 'count', b.target_count, 'amount', b.gift_amount, 'total', b.gift_total,
                              'duplicate', true, 'message', 'Already sent: ' || b.target_count || ' players got ' || bl_naira(b.gift_amount) || '.');
  end if;
  perform bl_broadcast_check(v_aud, p_joined_after, 'celebration', p_expires_at);
  if v_acc not in ('cash', 'bank') then
    raise exception 'Pick cash or bank.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Enter an amount above zero.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  if p_amount > v_max then
    raise exception 'That is more than the gift limit per player (%). Change admin.gift_max in Settings first.', bl_naira(v_max)
      using errcode = 'P0001', hint = 'too_big';
  end if;
  if char_length(v_narr) < 2 or char_length(v_narr) > 120 then
    raise exception 'Write the narration players will see (2 to 120 characters).' using errcode = 'P0001', hint = 'bad_narration';
  end if;
  select count(*) into n from bl_broadcast_targets(v_aud, p_joined_after);
  if n = 0 then
    raise exception 'Nobody is in that group right now.' using errcode = 'P0001', hint = 'no_targets';
  end if;
  if n * p_amount::numeric > v_total_max then
    raise exception '% players × % = %, more than the total cap %. Change admin.gift_total_max in Settings first.',
      n, bl_naira(p_amount), bl_naira(n * p_amount::numeric), bl_naira(v_total_max) using errcode = 'P0001', hint = 'total_cap';
  end if;

  insert into broadcasts (kind, title, body, style, audience, joined_after, popup, expires_at, targeted,
                          gift_account, gift_amount, gift_key, created_by)
  values ('gift', 'You received ' || bl_naira(p_amount) || ' 🎁', v_narr, 'celebration', v_aud,
          case when v_aud = 'joined_after' then p_joined_after end, coalesce(p_popup, true),
          coalesce(p_expires_at, now() + interval '14 days'), true, v_acc, p_amount, v_key, v_admin)
  returning id into v_id;

  -- set-based: lock + pay every target once (skip anyone the ₦9Q ceiling would overflow), ledger, recipients
  with t as (
    select p.id from profiles p join bl_broadcast_targets(v_aud, p_joined_after) x on x.id = p.id
     where (case when v_acc = 'cash' then p.cash else p.bank end)::numeric + p_amount <= v_ceiling
     order by p.id
       for update of p
  ), upd as (
    update profiles p
       set cash = case when v_acc = 'cash' then p.cash + p_amount else p.cash end,
           bank = case when v_acc = 'bank' then p.bank + p_amount else p.bank end
      from t where p.id = t.id
    returning p.id, case when v_acc = 'cash' then p.cash else p.bank end as bal
  ), led as (
    insert into ledger (user_id, account, delta, balance_after, reason, meta, created_at)
    select u.id, v_acc, p_amount, u.bal, 'admin_gift',
           jsonb_build_object('narration', v_narr, 'broadcast_id', v_id, 'admin', v_admin), bl_now()
      from upd u
    returning user_id
  )
  insert into broadcast_reads (broadcast_id, user_id) select v_id, l.user_id from led l;
  get diagnostics v_paid = row_count;

  update broadcasts set target_count = v_paid, gift_total = v_paid * p_amount::numeric where id = v_id;
  perform bl_broadcast_bump(v_id);
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'mass_gift', jsonb_build_object('broadcast_id', v_id, 'key', v_key, 'account', v_acc, 'amount', p_amount,
                                                   'narration', v_narr, 'audience', v_aud, 'joined_after', p_joined_after,
                                                   'players', v_paid, 'total', v_paid * p_amount::numeric, 'skipped', n - v_paid));
  perform bl_admin_notify('broadcast', 'Gift paid: ' || v_paid || ' players got ' || bl_naira(p_amount),
                          v_narr || ' (total ' || bl_naira(v_paid * p_amount::numeric) || ')',
                          jsonb_build_object('broadcast_id', v_id), '/admin/broadcast');
  return jsonb_build_object('id', v_id, 'count', v_paid, 'amount', p_amount, 'total', v_paid * p_amount::numeric,
                            'skipped', n - v_paid, 'duplicate', false,
                            'message', v_paid || ' players got ' || bl_naira(p_amount) || ' (total ' || bl_naira(v_paid * p_amount::numeric) || ').');
end $$;
revoke all on function public.admin_gift_send(text, bigint, text, text, text, timestamptz, boolean, timestamptz) from public, anon;
grant execute on function public.admin_gift_send(text, bigint, text, text, text, timestamptz, boolean, timestamptz) to authenticated, service_role;

-- History with reach: targeted = frozen recipients, seen = opened the popup / alerts, dismissed = closed the popup.
create or replace function public.admin_broadcast_list(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  perform bl_admin_guard();
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', b.id, 'kind', b.kind, 'title', b.title, 'body', b.body, 'style', b.style, 'audience', b.audience,
             'joined_after', b.joined_after, 'popup', b.popup, 'expires_at', b.expires_at, 'cancelled_at', b.cancelled_at,
             'target_count', b.target_count, 'gift_account', b.gift_account, 'gift_amount', b.gift_amount, 'gift_total', b.gift_total,
             'created_at', b.created_at, 'created_by', (select username from profiles where id = b.created_by),
             'live', b.cancelled_at is null and (b.expires_at is null or b.expires_at > now()),
             'seen_count', (select count(*) from broadcast_reads r where r.broadcast_id = b.id and r.seen_at is not null),
             'dismissed_count', (select count(*) from broadcast_reads r where r.broadcast_id = b.id and r.dismissed_at is not null))
           order by b.id desc)
      from (select * from broadcasts order by id desc limit v_lim) b), '[]'::jsonb));
end $$;
revoke all on function public.admin_broadcast_list(int) from public, anon;
grant execute on function public.admin_broadcast_list(int) to authenticated, service_role;

-- End a broadcast early (players stop seeing it). A gift's money stays paid.
create or replace function public.admin_broadcast_end(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
begin
  update broadcasts set cancelled_at = now() where id = p_id and cancelled_at is null;
  if not found then
    raise exception 'That broadcast is not live.' using errcode = 'P0001', hint = 'not_found';
  end if;
  insert into admin_audit (admin_id, action, data) values (v_admin, 'broadcast_end', jsonb_build_object('broadcast_id', p_id));
  return jsonb_build_object('message', 'Ended. Players no longer see it.');
end $$;
revoke all on function public.admin_broadcast_end(bigint) from public, anon;
grant execute on function public.admin_broadcast_end(bigint) to authenticated, service_role;

-- Bank -> History: the gift's narration is the statement line (re-created from the live definition, grants kept).
do $mig$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.bl_ledger_label(text,jsonb)'::regprocedure);
  if position('''admin_gift''' in v_def) = 0 then
    if position('    when ''topup'' then' in v_def) = 0 then raise exception 'A2: bl_ledger_label marker not found'; end if;
    v_def := replace(v_def, '    when ''topup'' then',
      E'    when ''admin_gift'' then return coalesce(nullif(btrim(p_meta->>''narration''), ''''), ''Gift from Benin Life'');\n    when ''topup'' then');
    execute v_def;
  end if;
end $mig$;
revoke execute on function public.bl_ledger_label(text, jsonb) from public, anon, authenticated;

notify pgrst, 'reload schema';
