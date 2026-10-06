-- Benin Life — S2 welcome back + "New life" (docs/SHIP_TODAY.md S2, docs/HUD_HOME.md "S2 welcome back").
--
-- 1. Config (category `life`): welcome-back screen switch + absence threshold, restart switch + cooldown.
-- 2. profile_archive: a jsonb snapshot of every life a player gave up (profile row, Bag, furniture,
--    recent money history). Nothing is hard-lost.
-- 3. Moderation/audit links survive a restart: chat messages, reports, blocks and the audit tables now
--    reference the auth account (auth.users) instead of the profile row, so restarting cannot wipe a
--    block, a report or the admin history (deleting the auth account still cleans them up).
-- 4. life_restart(): archives the caller's profile, then deletes it. Gameplay rows (ledger, events,
--    inventory, player_furniture) go with it through their ON DELETE CASCADE foreign keys. The auth
--    account stays, so the client lands in the creator again and create_profile_v2 rolls a new origin
--    (origin.force_next / origin.nepo_pct apply as for any new Sim).
--    Admin rights and a running chat mute carry over to the next life (trigger on profiles insert).
-- 5. bank_transfer: the new-account wait reads in hours from 120 minutes up.
-- Idempotent: safe to run twice and on a non-empty DB.

-- ---------- 1. config ----------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('life.welcome_enabled', 'true', 'life', 'Welcome-back screen',
 'Show the welcome-back screen (your house, your Sim, your money, Continue / New life / Log out) when a player opens the game in a new tab or after being away.',
 'bool', null, null),
('life.welcome_after_minutes', '30', 'life', 'Welcome back after (real minutes away)',
 'In the same browser tab, the welcome-back screen shows again after the player has been away this many real minutes. A new tab always shows it once.',
 'minutes', 1, 10080),
('life.restart_enabled', 'true', 'life', 'Allow "New life"',
 'Players can give up their Sim and start over (new Sim, new origin roll). The old life is archived; the account stays.',
 'bool', null, null),
('life.restart_cooldown_hours', '0', 'life', 'Hours between new lives',
 'How long a player must wait after starting a new life before they can do it again. 0 = no wait.',
 'number', 0, 720)
on conflict (key) do nothing;

-- ---------- 2. archive ----------
create table if not exists public.profile_archive (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  life_no     int not null default 1,
  username    text not null,
  origin      text,
  cash        bigint not null default 0,
  bank        bigint not null default 0,
  profile     jsonb not null,
  extra       jsonb not null default '{}'::jsonb,
  archived_at timestamptz not null default now()
);
create index if not exists profile_archive_user_idx on public.profile_archive (user_id, archived_at desc);
alter table public.profile_archive enable row level security;
drop policy if exists profile_archive_own on public.profile_archive;
create policy profile_archive_own on public.profile_archive for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.profile_archive from anon, authenticated;
grant select on public.profile_archive to authenticated;

-- ---------- 3. links that must survive a restart -> the auth account ----------
do $$
declare
  r record;
  v_del text;
begin
  for r in
    select * from (values
      ('chat_messages', 'user_id',     'cascade'),
      ('chat_reports',  'reporter_id', 'cascade'),
      ('chat_blocks',   'blocker_id',  'cascade'),
      ('chat_blocks',   'blocked_id',  'cascade'),
      ('admin_audit',   'admin_id',    'set null'),
      ('admin_audit',   'target_user', 'set null'),
      ('config_audit',  'admin_id',    'set null')
    ) t(tbl, col, ondel)
  loop
    if to_regclass('public.' || r.tbl) is null then continue; end if;
    -- drop any FK on that column that still points at profiles
    for v_del in
      select c.conname
        from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
       where c.contype = 'f' and c.conrelid = ('public.' || r.tbl)::regclass
         and a.attname = r.col and c.confrelid = 'public.profiles'::regclass
    loop
      execute format('alter table public.%I drop constraint %I', r.tbl, v_del);
    end loop;
    -- add the auth.users FK once
    if not exists (
      select 1 from pg_constraint c
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
       where c.contype = 'f' and c.conrelid = ('public.' || r.tbl)::regclass
         and a.attname = r.col and c.confrelid = 'auth.users'::regclass
    ) then
      execute format('alter table public.%I add constraint %I foreign key (%I) references auth.users(id) on delete %s',
                     r.tbl, r.tbl || '_' || r.col || '_auth_fkey', r.col, r.ondel);
    end if;
  end loop;
end $$;

-- ---------- 4a. carry admin rights and a running chat mute into the next life ----------
create or replace function public.bl_profiles_carry_life()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  a profile_archive;
  v_mute timestamptz;
begin
  select * into a from profile_archive where user_id = new.id order by archived_at desc, id desc limit 1;
  if found then
    if coalesce((a.profile->>'is_admin')::boolean, false) then
      new.is_admin := true;
    end if;
    v_mute := nullif(a.profile->>'chat_muted_until', '')::timestamptz;
    if v_mute is not null and v_mute > bl_now() and (new.chat_muted_until is null or new.chat_muted_until < v_mute) then
      new.chat_muted_until := v_mute;
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.bl_profiles_carry_life() from public, anon, authenticated;

drop trigger if exists profiles_carry_life on public.profiles;
create trigger profiles_carry_life before insert on public.profiles
  for each row execute function public.bl_profiles_carry_life();

-- ---------- 4b. life_restart() ----------
create or replace function public.life_restart()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     profiles;
  v_now    timestamptz := bl_now();
  v_cool   numeric;
  v_last   timestamptz;
  v_left   numeric;
  v_life   int;
  v_extra  jsonb;
  v_id     bigint;
begin
  v_me := bl_me_any();   -- logged in, has a profile, not banned (works before a home is chosen too)

  if not bl_cfg_bool('life.restart_enabled') then
    raise exception 'Starting a new life is switched off right now.' using errcode = 'P0001', hint = 'restart_disabled';
  end if;

  v_cool := greatest(coalesce(bl_cfg('life.restart_cooldown_hours'), 0), 0);
  select max(archived_at), count(*) + 1 into v_last, v_life from profile_archive where user_id = v_me.id;
  if v_cool > 0 and v_last is not null then
    v_left := v_cool * 3600 - extract(epoch from v_now - v_last);
    if v_left > 0 then
      raise exception 'You started a new life recently. You can start another in about %.',
        case when v_left >= 7200 then ceil(v_left / 3600)::text || ' hours'
             when v_left >= 3600 then '1 hour ' || ceil((v_left - 3600) / 60)::text || ' min'
             else ceil(v_left / 60)::text || ' min' end
        using errcode = 'P0001', hint = 'restart_cooldown';
    end if;
  end if;

  v_extra := jsonb_build_object(
    'inventory', coalesce((select jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty) order by i.item_id)
                             from inventory i where i.user_id = v_me.id), '[]'::jsonb),
    'furniture', coalesce((select jsonb_agg(to_jsonb(f) - 'user_id' order by f.furniture_id)
                             from player_furniture f where f.user_id = v_me.id), '[]'::jsonb),
    'ledger_count', (select count(*) from ledger l where l.user_id = v_me.id),
    'ledger_recent', coalesce((select jsonb_agg(to_jsonb(x) - 'user_id' order by x.id desc)
                                 from (select * from ledger l where l.user_id = v_me.id order by l.id desc limit 100) x), '[]'::jsonb),
    'events_count', (select count(*) from events e where e.user_id = v_me.id),
    'chat_messages', (select count(*) from chat_messages c where c.user_id = v_me.id)
  );

  insert into profile_archive (user_id, life_no, username, origin, cash, bank, profile, extra, archived_at)
  values (v_me.id, v_life, v_me.username, v_me.origin, v_me.cash, v_me.bank, to_jsonb(v_me), v_extra, v_now)
  returning id into v_id;

  insert into admin_audit (admin_id, action, target_user, data)
  values (null, 'life_restart', v_me.id,
          jsonb_build_object('archive_id', v_id, 'life_no', v_life, 'username', v_me.username, 'origin', v_me.origin,
                             'cash', v_me.cash, 'bank', v_me.bank));

  -- ledger, events, inventory and player_furniture go with the profile (ON DELETE CASCADE);
  -- chat, blocks, reports and audit rows point at the auth account and stay.
  delete from profiles where id = v_me.id;

  return jsonb_build_object(
    'message', 'Your old life is archived. Create your new Sim.',
    'archive_id', v_id,
    'life_no', v_life + 1
  );
end $$;
revoke execute on function public.life_restart() from public, anon;
grant execute on function public.life_restart() to authenticated;

-- ---------- 5. bank_transfer: new-account wait in hours from 120 minutes ----------
-- Re-created from the live definition; only the message changes (owner and grants are kept).
do $$
declare
  f   regprocedure := 'public.bank_transfer(text, bigint, text)'::regprocedure;
  src text;
  old_msg text := $m$    raise exception 'New accounts can send money after % real minutes. About % min to go.',
      round(v_age / 60), ceil(v_left / 60) using errcode = 'P0001', hint = 'limit';$m$;
  new_msg text := $m$    if round(v_age / 60) >= 120 then
      raise exception 'New accounts can send money % after joining. About % to go.',
        case when round(v_age / 60)::bigint % 60 = 0 then (round(v_age / 60)::bigint / 60)::text || ' hours'
             else (round(v_age / 60)::bigint / 60)::text || ' h ' || (round(v_age / 60)::bigint % 60)::text || ' min' end,
        case when ceil(v_left / 60)::bigint >= 60
             then (ceil(v_left / 60)::bigint / 60)::text || ' h'
                  || case when ceil(v_left / 60)::bigint % 60 > 0 then ' ' || (ceil(v_left / 60)::bigint % 60)::text || ' min' else '' end
             else ceil(v_left / 60)::bigint::text || ' min' end
        using errcode = 'P0001', hint = 'limit';
    end if;
    raise exception 'New accounts can send money after % real minutes. About % min to go.',
      round(v_age / 60), ceil(v_left / 60) using errcode = 'P0001', hint = 'limit';$m$;
begin
  src := pg_get_functiondef(f);
  if position('after joining' in src) = 0 then
    if position(old_msg in src) = 0 then
      raise exception 'bank_transfer: new-account message not found in the live definition';
    end if;
    execute replace(src, old_msg, new_msg);
  end if;
end $$;
revoke execute on function public.bank_transfer(text, bigint, text) from public, anon;
grant execute on function public.bank_transfer(text, bigint, text) to authenticated;
