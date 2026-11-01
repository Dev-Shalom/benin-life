-- Fix it 5: a gang Boss handed over by mistake can be taken back.
--   * the NEW Boss can hand it back to the previous Boss at any time (crew_boss_handback)
--   * the PREVIOUS Boss can ask for it back within crew.boss_request_hours (24) of the handover (crew_boss_request);
--     the new Boss accepts or declines (crew_boss_respond). An old request expires with the 24 hours.
--   * every move (handover, hand-back, request, accept, decline, admin set) is a row in crew_boss_log (the audit trail);
--     an admin set also goes to admin_audit.
--   * admin_crew_set_boss: the Admin Grant toolbox can now make anybody Boss (the old Boss becomes Lieutenant).
-- New small tables keyed by crew / user id. Nothing touches profiles. No loops over players.
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('crew.boss_request_hours', '24', 'crew', 'Ask for the Boss rank back within (hours)',
 'Fix it 5: after handing the Boss rank over, the previous Boss can ask for it back for this long (the new Boss decides). The new Boss can hand it back any time.', 'number', 1, 720)
on conflict (key) do nothing;

create table if not exists public.crew_boss_log (
  id        bigserial primary key,
  crew_id   bigint not null references public.crews(id) on delete cascade,
  kind      text not null check (kind in ('transfer', 'handback', 'request', 'accepted', 'declined', 'admin')),
  from_user uuid,
  to_user   uuid,
  by_admin  uuid,
  note      text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists crew_boss_log_crew_idx on public.crew_boss_log (crew_id, id desc);
alter table public.crew_boss_log enable row level security;
revoke all on public.crew_boss_log from anon, authenticated;

create table if not exists public.crew_boss_requests (
  crew_id    bigint primary key references public.crews(id) on delete cascade,
  requester  uuid not null,
  holder     uuid not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.crew_boss_requests enable row level security;
revoke all on public.crew_boss_requests from anon, authenticated;

create or replace function public.bl_crew_boss_log(p_crew bigint, p_kind text, p_from uuid, p_to uuid, p_admin uuid default null, p_note text default '') returns void
language sql security definer set search_path = public as $$
  insert into crew_boss_log (crew_id, kind, from_user, to_user, by_admin, note) values (p_crew, p_kind, p_from, p_to, p_admin, coalesce(p_note, ''));
$$;

-- The one place the Boss rank moves (old Boss first, so the one-boss index never trips)
create or replace function public.bl_crew_swap_boss(p_crew bigint, p_old uuid, p_new uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update crew_members set rank = 'lieutenant' where user_id = p_old and crew_id = p_crew and rank = 'boss';
  update crew_members set rank = 'boss' where user_id = p_new and crew_id = p_crew;
  delete from crew_boss_requests where crew_id = p_crew;
end $$;

-- A normal handover is logged (so it can be handed back / asked for back)
create or replace function pg_temp.fx5_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'fixit5: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;
select pg_temp.fx5_patch('public.crew_transfer(uuid)',
  E'  select username into v_name from profiles where id = p_user;\n  perform bl_crew_notify(c.id, null, ''crew_rank''',
  E'  delete from crew_boss_requests where crew_id = c.id;\n  perform bl_crew_boss_log(c.id, ''transfer'', v_uid, p_user);\n  select username into v_name from profiles where id = p_user;\n  perform bl_crew_notify(c.id, null, ''crew_rank''',
  'bl_crew_boss_log');

-- What the Gang app needs to show: hand back / ask back / a waiting request
create or replace function public.crew_boss_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); m crew_members; v_hours numeric; rq crew_boss_requests;
  v_last crew_boss_log; v_prev text; v_can_back boolean := false; v_can_ask boolean := false;
begin
  select * into m from crew_members where user_id = v_uid;
  if not found then return jsonb_build_object('in_crew', false); end if;
  v_hours := greatest(1, coalesce((select (value #>> '{}')::numeric from game_config where key = 'crew.boss_request_hours'), 24));
  select * into v_last from crew_boss_log where crew_id = m.crew_id and kind in ('transfer', 'handback', 'admin', 'accepted') order by id desc limit 1;
  select * into rq from crew_boss_requests where crew_id = m.crew_id and expires_at > now();
  if v_last.id is not null and v_last.kind in ('transfer', 'handback') then
    if m.rank = 'boss' and v_last.to_user = v_uid and exists (select 1 from crew_members where user_id = v_last.from_user and crew_id = m.crew_id) then
      v_can_back := v_last.kind = 'transfer';
      select username into v_prev from profiles where id = v_last.from_user;
    end if;
    if m.rank <> 'boss' and v_last.from_user = v_uid and v_last.created_at > now() - make_interval(hours => v_hours::int) and rq.crew_id is null then
      v_can_ask := true;
    end if;
  end if;
  return jsonb_build_object('in_crew', true, 'can_handback', v_can_back, 'handback_to', v_prev, 'can_request', v_can_ask,
    'request_open_until', case when v_can_ask then v_last.created_at + make_interval(hours => v_hours::int) end,
    'request', case when rq.crew_id is not null then jsonb_build_object('requester', rq.requester, 'username', (select username from profiles where id = rq.requester),
                     'mine', rq.requester = v_uid, 'to_me', rq.holder = v_uid, 'expires_at', rq.expires_at) end);
end $$;

create or replace function public.crew_boss_handback() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; v_last crew_boss_log; v_name text;
begin
  m := bl_crew_need(v_uid, 3);
  select * into c from crews where id = m.crew_id;
  select * into v_last from crew_boss_log where crew_id = m.crew_id and kind in ('transfer', 'handback', 'admin', 'accepted') order by id desc limit 1;
  if v_last.id is null or v_last.kind <> 'transfer' or v_last.to_user <> v_uid then
    raise exception 'Nobody handed you this gang. There is nothing to hand back.' using errcode = 'P0001', hint = 'no_handover';
  end if;
  if not exists (select 1 from crew_members where user_id = v_last.from_user and crew_id = m.crew_id) then
    raise exception 'The previous Boss is not in the gang any more.' using errcode = 'P0001', hint = 'gone';
  end if;
  perform bl_crew_swap_boss(m.crew_id, v_uid, v_last.from_user);
  perform bl_crew_boss_log(m.crew_id, 'handback', v_uid, v_last.from_user);
  select username into v_name from profiles where id = v_last.from_user;
  perform bl_crew_notify(c.id, null, 'crew_rank', '@' || v_name || ' is the Boss again', 'The Boss rank of ' || c.name || ' went back to @' || v_name || '.', false);
  return jsonb_build_object('message', 'You handed the gang back to @' || v_name || '. You are a Lieutenant.');
end $$;

create or replace function public.crew_boss_request() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; v_last crew_boss_log; v_hours numeric; v_boss uuid; v_name text;
begin
  m := bl_crew_need(v_uid, 0);
  select * into c from crews where id = m.crew_id;
  v_hours := greatest(1, coalesce((select (value #>> '{}')::numeric from game_config where key = 'crew.boss_request_hours'), 24));
  select * into v_last from crew_boss_log where crew_id = m.crew_id and kind in ('transfer', 'handback', 'admin', 'accepted') order by id desc limit 1;
  if m.rank = 'boss' or v_last.id is null or v_last.kind not in ('transfer', 'handback') or v_last.from_user <> v_uid then
    raise exception 'Only the Boss who handed the gang over can ask for it back.' using errcode = 'P0001', hint = 'not_previous_boss';
  end if;
  if v_last.created_at <= now() - make_interval(hours => v_hours::int) then
    raise exception 'The % hours to ask for it back are over.', v_hours::int using errcode = 'P0001', hint = 'too_late';
  end if;
  if exists (select 1 from crew_boss_requests where crew_id = m.crew_id and expires_at > now()) then
    raise exception 'You already asked. Wait for the Boss to answer.' using errcode = 'P0001', hint = 'pending';
  end if;
  select user_id into v_boss from crew_members where crew_id = m.crew_id and rank = 'boss';
  delete from crew_boss_requests where crew_id = m.crew_id;
  insert into crew_boss_requests (crew_id, requester, holder, expires_at) values (m.crew_id, v_uid, v_boss, v_last.created_at + make_interval(hours => v_hours::int));
  perform bl_crew_boss_log(m.crew_id, 'request', v_uid, v_boss);
  select username into v_name from profiles where id = v_uid;
  perform bl_event(v_boss, 'crew_rank', '@' || v_name || ' wants the Boss rank back', 'Open Gang to accept or say no.', jsonb_build_object('crew', m.crew_id));
  return jsonb_build_object('message', 'Request sent. The new Boss decides.');
end $$;

create or replace function public.crew_boss_respond(p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); m crew_members; c crews; rq crew_boss_requests; v_name text;
begin
  m := bl_crew_need(v_uid, 3);
  select * into c from crews where id = m.crew_id;
  select * into rq from crew_boss_requests where crew_id = m.crew_id and holder = v_uid and expires_at > now() for update;
  if not found then
    raise exception 'There is no request waiting.' using errcode = 'P0001', hint = 'no_request';
  end if;
  select username into v_name from profiles where id = rq.requester;
  if coalesce(p_accept, false) then
    if not exists (select 1 from crew_members where user_id = rq.requester and crew_id = m.crew_id) then
      delete from crew_boss_requests where crew_id = m.crew_id;
      raise exception 'They are not in the gang any more.' using errcode = 'P0001', hint = 'gone';
    end if;
    perform bl_crew_swap_boss(m.crew_id, v_uid, rq.requester);
    perform bl_crew_boss_log(m.crew_id, 'accepted', v_uid, rq.requester);
    perform bl_crew_notify(c.id, null, 'crew_rank', '@' || v_name || ' is the Boss again', 'The Boss rank of ' || c.name || ' went back to @' || v_name || '.', false);
    return jsonb_build_object('message', '@' || v_name || ' is the Boss again. You are a Lieutenant.');
  end if;
  delete from crew_boss_requests where crew_id = m.crew_id;
  perform bl_crew_boss_log(m.crew_id, 'declined', v_uid, rq.requester);
  perform bl_event(rq.requester, 'crew_rank', 'The Boss said no', 'Your request for the Boss rank of ' || c.name || ' was declined.', jsonb_build_object('crew', m.crew_id));
  return jsonb_build_object('message', 'Request declined.');
end $$;

-- Admin Grant toolbox: make a player the Boss (audited). The old Boss becomes Lieutenant.
create or replace function public.admin_crew_set_boss(p_user uuid, p_crew bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; c crews; m crew_members; v_old uuid;
begin
  p := bl_ag_target(p_user);
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then perform bl_ag_fail('That gang doesn''t exist.', 'bad_crew'); end if;
  select * into m from crew_members where user_id = p_user for update;
  if found and m.crew_id <> c.id then
    perform bl_ag_fail('They are in another gang. Remove them from it first.', 'in_other_crew');
  end if;
  if found and m.rank = 'boss' then perform bl_ag_fail('They are already the Boss.', 'same_rank'); end if;
  if not found and (select count(*) from crew_members where crew_id = c.id) >= bl_crew_max_members(c.level) then
    perform bl_ag_fail(c.name || ' is full.', 'crew_full');
  end if;
  select user_id into v_old from crew_members where crew_id = c.id and rank = 'boss';
  if m.user_id is null then
    perform bl_crew_add_member(c.id, p_user, 'member');
  end if;
  perform bl_crew_swap_boss(c.id, v_old, p_user);
  perform bl_crew_boss_log(c.id, 'admin', v_old, p_user, v_admin, v_reason);
  perform bl_ag_log(v_admin, p_user, 'grant_crew_boss', jsonb_build_object('crew', c.id, 'name', c.name, 'old_boss', v_old, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'You are the Boss of ' || c.name, 'An admin made you the Boss.', v_reason, jsonb_build_object('crew', c.id));
  if v_old is not null then
    perform bl_ag_alert(v_old, 'admin_take', 'Boss rank moved', 'An admin gave the Boss rank of ' || c.name || ' to @' || p.username || '. You are a Lieutenant.', v_reason, jsonb_build_object('crew', c.id));
  end if;
  return jsonb_build_object('message', '@' || p.username || ' is the Boss of ' || c.name || '.', 'crew', c.id);
end $$;

revoke all on function public.bl_crew_boss_log(bigint, text, uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.bl_crew_swap_boss(bigint, uuid, uuid) from public, anon, authenticated;
revoke all on function public.crew_boss_state() from public, anon;
grant execute on function public.crew_boss_state() to authenticated;
revoke all on function public.crew_boss_handback() from public, anon;
grant execute on function public.crew_boss_handback() to authenticated;
revoke all on function public.crew_boss_request() from public, anon;
grant execute on function public.crew_boss_request() to authenticated;
revoke all on function public.crew_boss_respond(boolean) from public, anon;
grant execute on function public.crew_boss_respond(boolean) to authenticated;
revoke all on function public.admin_crew_set_boss(uuid, bigint, text) from public, anon;
grant execute on function public.admin_crew_set_boss(uuid, bigint, text) to authenticated;
notify pgrst, 'reload schema';
