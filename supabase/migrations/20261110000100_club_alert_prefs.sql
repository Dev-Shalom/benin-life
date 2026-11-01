-- Fix it 3: "Club spray alerts". Players choose how loud other people's spraying is.
--   toasts  the shout-out card inside the club you are standing in (default ON)
--   strip   the app-wide strip for a big spray in a DIFFERENT club (default OFF)
--   push    a phone push for club hype (default OFF; still needs the Game events push category and a saved device)
-- One small table keyed by the user id (nothing touches profiles). No loops, no backfill: a player without a row gets the defaults.

create table if not exists public.club_alert_prefs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  toasts     boolean not null default true,
  strip      boolean not null default false,
  push       boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.club_alert_prefs enable row level security;
drop policy if exists club_alert_prefs_own_read on public.club_alert_prefs;
create policy club_alert_prefs_own_read on public.club_alert_prefs for select to authenticated using (user_id = auth.uid());
revoke all on public.club_alert_prefs from anon, authenticated;
grant select on public.club_alert_prefs to authenticated;

create or replace function public.club_alert_prefs_get() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); p club_alert_prefs;
begin
  select * into p from club_alert_prefs where user_id = v_uid;
  return jsonb_build_object('toasts', coalesce(p.toasts, true), 'strip', coalesce(p.strip, false), 'push', coalesce(p.push, false));
end $$;

-- Partial update: {"toasts": false, "strip": true, "push": false}. Unknown keys are refused.
create or replace function public.club_alert_prefs_set(p_prefs jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); k text; v jsonb;
begin
  if p_prefs is null or jsonb_typeof(p_prefs) <> 'object' then
    raise exception 'Send the switches as an object.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  for k, v in select * from jsonb_each(p_prefs) loop
    if k not in ('toasts', 'strip', 'push') or jsonb_typeof(v) <> 'boolean' then
      raise exception 'Unknown club alert switch "%".', k using errcode = 'P0001', hint = 'bad_value';
    end if;
  end loop;
  insert into club_alert_prefs (user_id) values (v_uid) on conflict (user_id) do nothing;
  update club_alert_prefs set
    toasts = coalesce((p_prefs->>'toasts')::boolean, toasts),
    strip  = coalesce((p_prefs->>'strip')::boolean, strip),
    push   = coalesce((p_prefs->>'push')::boolean, push),
    updated_at = now()
  where user_id = v_uid;
  return club_alert_prefs_get();
end $$;

-- Hype pushes (bl_push_on_hype) go only to players who switched "Club spray alerts: phone pushes" on.
create or replace function pg_temp.fx3_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'fixit3: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.fx3_patch('public.bl_push_on_hype()',
  'and exists (select 1 from push_subscriptions s where s.user_id = p.id)',
  E'and exists (select 1 from push_subscriptions s where s.user_id = p.id)\n       and exists (select 1 from club_alert_prefs cp where cp.user_id = p.id and cp.push)',
  'club_alert_prefs');

revoke all on function public.bl_push_on_hype() from public, anon, authenticated;
revoke all on function public.club_alert_prefs_get() from public, anon;
grant execute on function public.club_alert_prefs_get() to authenticated;
revoke all on function public.club_alert_prefs_set(jsonb) from public, anon;
grant execute on function public.club_alert_prefs_set(jsonb) to authenticated;

notify pgrst, 'reload schema';
