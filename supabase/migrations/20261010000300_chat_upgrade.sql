-- M3: messaging upgrade (docs/CHAT.md, docs/SOCIAL.md).
-- Place chat, house chat (a private-home location) and DMs get:
--   * reply_to (swipe to reply) with a small quote preview in every row the server returns;
--   * delete for me (per-user hidden list) and delete for everyone (author-only tombstone, within
--     chat.delete_everyone_hours, broadcast live as a Realtime UPDATE);
--   * paged history (before-id + limit) capped at chat.history_days (max 14);
--   * chat retention default 48 h -> 14 days (only if still the old default; admin-tunable).
-- Idempotent and safe on a non-empty DB. Functions re-created from their live definitions, grants kept.

-- ---------------------------------------------------------------- columns
alter table public.chat_messages   add column if not exists reply_to bigint;
alter table public.chat_messages   add column if not exists deleted_at timestamptz;
alter table public.player_messages add column if not exists reply_to bigint;
alter table public.player_messages add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chat_messages_reply_to_fkey') then
    alter table public.chat_messages add constraint chat_messages_reply_to_fkey
      foreign key (reply_to) references public.chat_messages(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'player_messages_reply_to_fkey') then
    alter table public.player_messages add constraint player_messages_reply_to_fkey
      foreign key (reply_to) references public.player_messages(id) on delete set null;
  end if;
end $$;

create index if not exists chat_messages_reply_to_idx   on public.chat_messages(reply_to)   where reply_to is not null;
create index if not exists player_messages_reply_to_idx on public.player_messages(reply_to) where reply_to is not null;
create index if not exists chat_messages_loc_id_idx     on public.chat_messages(location_id, id desc);
create index if not exists player_messages_conv_id_idx  on public.player_messages(conversation_id, id desc);

-- A tombstone has no body and no audio.
alter table public.chat_messages drop constraint if exists chat_messages_payload_check;
alter table public.chat_messages add constraint chat_messages_payload_check check (
  (deleted_at is null and ((body is not null and char_length(body) > 0 and audio_path is null and audio_mime is null)
                        or (body is null and audio_path is not null and audio_mime is not null)))
  or (deleted_at is not null and body is null and audio_path is null and audio_mime is null));
alter table public.player_messages drop constraint if exists player_messages_payload_check;
alter table public.player_messages add constraint player_messages_payload_check check (
  (deleted_at is null and ((body is not null and char_length(body) > 0 and audio_path is null and audio_mime is null)
                        or (body is null and audio_path is not null and audio_mime is not null)))
  or (deleted_at is not null and body is null and audio_path is null and audio_mime is null));

-- ---------------------------------------------------------------- delete for me
create table if not exists public.chat_hidden_messages (
  user_id uuid not null references auth.users(id) on delete cascade,
  chat_message_id bigint references public.chat_messages(id) on delete cascade,
  player_message_id bigint references public.player_messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint chat_hidden_messages_one check ((chat_message_id is null) <> (player_message_id is null))
);
create unique index if not exists chat_hidden_messages_chat_uq on public.chat_hidden_messages(user_id, chat_message_id) where chat_message_id is not null;
create unique index if not exists chat_hidden_messages_dm_uq   on public.chat_hidden_messages(user_id, player_message_id) where player_message_id is not null;
create index if not exists chat_hidden_messages_chat_idx on public.chat_hidden_messages(chat_message_id) where chat_message_id is not null;
create index if not exists chat_hidden_messages_dm_idx   on public.chat_hidden_messages(player_message_id) where player_message_id is not null;
alter table public.chat_hidden_messages enable row level security;
revoke all on public.chat_hidden_messages from anon, authenticated;
grant select on public.chat_hidden_messages to authenticated;
drop policy if exists chat_hidden_messages_own on public.chat_hidden_messages;
create policy chat_hidden_messages_own on public.chat_hidden_messages for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- config
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('chat.delete_everyone_hours', '48', 'chat', 'Delete for everyone window (real hours)',
 'How long after sending a player can still delete their own message for everyone (place, house and private chat).', 'number', 0, 720),
('chat.history_days', '14', 'chat', 'Chat history players can scroll back (days)',
 'Scrolling up loads older messages, at most this many days back (hard cap 14).', 'number', 1, 14)
on conflict (key) do nothing;

update public.game_config
   set value = '336'::jsonb,
       description = 'Older place and house chat messages are deleted (a few at a time, whenever someone sends a message). Default 336 h = 14 days.'
 where key = 'chat.retention_hours' and value = '48'::jsonb;

-- ---------------------------------------------------------------- helpers
create or replace function public.bl_chat_history_cutoff()
returns timestamptz language sql stable set search_path = public as $$
  select bl_now() - make_interval(days => least(14, greatest(1, coalesce(bl_cfg('chat.history_days'), 14)))::int)
$$;
revoke all on function public.bl_chat_history_cutoff() from public, anon, authenticated;

-- Quote preview of the message a place/house chat row replies to (null when none).
create or replace function public.bl_chat_reply_preview(p_id bigint, p_me uuid)
returns jsonb language sql stable set search_path = public as $$
  select case when p_id is null then null else coalesce((
    select jsonb_build_object('id', r.id, 'username', r.username, 'user_id', r.user_id,
             'snippet', case when r.hidden or r.deleted_at is not null then null else left(r.body, 140) end,
             'voice', r.audio_path is not null and not r.hidden,
             'deleted', r.deleted_at is not null,
             'unavailable', r.hidden or exists (select 1 from chat_blocks b where b.blocker_id = p_me and b.blocked_id = r.user_id))
      from chat_messages r where r.id = p_id),
    jsonb_build_object('id', p_id, 'username', null, 'snippet', null, 'voice', false, 'deleted', false, 'unavailable', true)) end
$$;
revoke all on function public.bl_chat_reply_preview(bigint, uuid) from public, anon, authenticated;

create or replace function public.bl_dm_reply_preview(p_id bigint)
returns jsonb language sql stable set search_path = public as $$
  select case when p_id is null then null else coalesce((
    select jsonb_build_object('id', r.id, 'username', s.username, 'user_id', r.sender_id,
             'snippet', case when r.deleted_at is not null then null else left(r.body, 140) end,
             'voice', r.audio_path is not null, 'deleted', r.deleted_at is not null, 'unavailable', false)
      from player_messages r join profiles s on s.id = r.sender_id where r.id = p_id),
    jsonb_build_object('id', p_id, 'username', null, 'snippet', null, 'voice', false, 'deleted', false, 'unavailable', true)) end
$$;
revoke all on function public.bl_dm_reply_preview(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- place / house chat rows
create or replace function public.bl_chat_row(m chat_messages, p_avatar jsonb, p_me uuid)
 returns jsonb language sql stable set search_path to 'public'
as $function$
  select jsonb_build_object('id', m.id, 'location_id', m.location_id, 'user_id', m.user_id,
    'username', m.username, 'body', m.body, 'audio_path', m.audio_path, 'audio_mime', m.audio_mime,
    'created_at', m.created_at, 'avatar', p_avatar, 'mine', m.user_id = p_me,
    'reply_to', m.reply_to, 'reply', public.bl_chat_reply_preview(m.reply_to, p_me), 'deleted_at', m.deleted_at)
$function$;

create or replace function public.chat_recent(p_location text, p_limit integer default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := bl_require_uid();
  v     profiles;
  v_lim int := least(greatest(coalesce(p_limit, 30), 1), bl_cfg('chat.recent_limit')::int);
begin
  select * into v from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.location_id is distinct from p_location or v.travel_to is not null then
    raise exception 'You can only read the chat of the place you are at.' using errcode = 'P0001', hint = 'not_here';
  end if;
  return coalesce((
    select jsonb_agg(bl_chat_row(x, p.avatar, v_uid) order by x.id)
      from (select * from chat_messages c
             where c.location_id = p_location and not c.hidden
               and not exists (select 1 from chat_blocks b where b.blocker_id = v_uid and b.blocked_id = c.user_id)
               and not exists (select 1 from chat_hidden_messages h where h.user_id = v_uid and h.chat_message_id = c.id)
             order by c.id desc limit v_lim) x
      left join profiles p on p.id = x.user_id
  ), '[]'::jsonb);
end $function$;

-- Paged history: rows older than p_before (null = newest), oldest first, at most chat.history_days back.
create or replace function public.chat_history(p_location text, p_before bigint default null, p_limit integer default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := bl_require_uid();
  v     profiles;
  v_lim int := least(greatest(coalesce(p_limit, 30), 1), 60);
  v_cut timestamptz := public.bl_chat_history_cutoff();
begin
  select * into v from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v.location_id is distinct from p_location or v.travel_to is not null then
    raise exception 'You can only read the chat of the place you are at.' using errcode = 'P0001', hint = 'not_here';
  end if;
  return coalesce((
    select jsonb_agg(bl_chat_row(x, p.avatar, v_uid) order by x.id)
      from (select * from chat_messages c
             where c.location_id = p_location and not c.hidden and c.created_at >= v_cut
               and (p_before is null or c.id < p_before)
               and not exists (select 1 from chat_blocks b where b.blocker_id = v_uid and b.blocked_id = c.user_id)
               and not exists (select 1 from chat_hidden_messages h where h.user_id = v_uid and h.chat_message_id = c.id)
             order by c.id desc limit v_lim) x
      left join profiles p on p.id = x.user_id
  ), '[]'::jsonb);
end $function$;
revoke all on function public.chat_history(text, bigint, integer) from public, anon;
grant execute on function public.chat_history(text, bigint, integer) to authenticated, service_role;

-- New signatures take p_reply_to without defaults so PostgREST never sees two candidates. (An early
-- local draft of this migration gave them defaults; drop those so CREATE OR REPLACE can run.)
do $$
begin
  if (select pronargdefaults from pg_proc where oid = to_regprocedure('public.chat_send(text,bigint)')) > 0 then
    drop function public.chat_send(text, bigint); end if;
  if (select pronargdefaults from pg_proc where oid = to_regprocedure('public.chat_send_voice(text,text,bigint)')) > 0 then
    drop function public.chat_send_voice(text, text, bigint); end if;
  if (select pronargdefaults from pg_proc where oid = to_regprocedure('public.social_send_message(bigint,text,text,text,bigint)')) > 0 then
    drop function public.social_send_message(bigint, text, text, text, bigint); end if;
end $$;

-- Reply target for place/house chat: same room, visible, not deleted, inside the history window.
create or replace function public.bl_chat_check_reply(p_reply_to bigint, p_location text, p_me uuid)
returns void language plpgsql stable set search_path = public as $$
begin
  if p_reply_to is null then return; end if;
  if not exists (select 1 from chat_messages r
                  where r.id = p_reply_to and r.location_id = p_location and not r.hidden and r.deleted_at is null
                    and r.created_at >= public.bl_chat_history_cutoff()
                    and not exists (select 1 from chat_blocks b where b.blocker_id = p_me and b.blocked_id = r.user_id)) then
    raise exception 'That message can''t be replied to any more.' using errcode = 'P0001', hint = 'bad_reply';
  end if;
end $$;
revoke all on function public.bl_chat_check_reply(bigint, text, uuid) from public, anon, authenticated;

create or replace function public.chat_send(p_body text, p_reply_to bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_me profiles := bl_chat_me(); v_now timestamptz := bl_now(); v_body text := bl_chat_clean(p_body);
  v_rate numeric := bl_cfg('chat.rate_seconds'); v_burst int := bl_cfg('chat.burst_per_minute')::int;
  v_dup numeric := bl_cfg('chat.duplicate_window_seconds'); v_new numeric := bl_cfg('chat.min_account_real_minutes');
  v_last timestamptz; v_wait int; v_n int; v_masked text; m public.chat_messages;
begin
  if not bl_cfg_bool('chat.enabled') then raise exception 'Chat is switched off for now. Try again later.' using errcode = 'P0001', hint = 'chat_off'; end if;
  if v_me.chat_muted_until is not null and v_me.chat_muted_until > v_now then
    raise exception 'You can''t chat for now (muted by a moderator). Try again in about % min.', ceil(extract(epoch from v_me.chat_muted_until-v_now)/60) using errcode='P0001', hint='muted';
  end if;
  if v_me.travel_to is not null then raise exception 'You are on the road. You can chat when you arrive.' using errcode='P0001', hint='traveling'; end if;
  if v_me.location_id is null then raise exception 'You need to be at a place to chat.' using errcode='P0001', hint='not_here'; end if;
  if v_new > 0 and v_me.created_at > v_now - make_interval(secs => (v_new*60)::double precision) then
    raise exception 'New Sims can chat after % minutes. Look around first!', ceil(v_new) using errcode='P0001', hint='too_new';
  end if;
  if v_body = '' then raise exception 'Type a message first.' using errcode='P0001', hint='empty'; end if;
  perform public.bl_chat_check_reply(p_reply_to, v_me.location_id, v_me.id);
  select max(created_at), count(*) filter (where created_at > v_now-interval '60 seconds') into v_last,v_n
    from public.chat_messages where user_id=v_me.id and created_at>v_now-interval '1 hour';
  if v_last is not null and v_rate>0 and v_last>v_now-make_interval(secs=>v_rate::double precision) then
    v_wait:=greatest(1,ceil(v_rate-extract(epoch from v_now-v_last)));
    raise exception 'Slow down small. Wait % sec before your next message.',v_wait using errcode='P0001',hint='too_fast';
  end if;
  if v_n>=v_burst then raise exception 'You are sending too many messages. Take a short break.' using errcode='P0001',hint='too_fast'; end if;
  if v_dup>0 and exists(select 1 from public.chat_messages where user_id=v_me.id and created_at>v_now-make_interval(secs=>v_dup::double precision)
       and body is not null and lower(regexp_replace(body,'\W','','g'))=lower(regexp_replace(public.bl_chat_mask(v_body),'\W','','g'))) then
    raise exception 'You just sent that. Say something new.' using errcode='P0001',hint='duplicate';
  end if;
  v_masked:=public.bl_chat_mask(v_body);
  delete from public.chat_messages where id in (select id from public.chat_messages where created_at<v_now-make_interval(secs=>(bl_cfg('chat.retention_hours')*3600)::double precision) order by created_at limit 200);
  insert into public.chat_messages(location_id,user_id,username,body,created_at,reply_to) values(v_me.location_id,v_me.id,v_me.username,v_masked,v_now,p_reply_to) returning * into m;
  return public.bl_chat_row(m,v_me.avatar,v_me.id)||jsonb_build_object('message','Sent.','masked',v_masked<>v_body);
end $function$;
revoke all on function public.chat_send(text, bigint) from public, anon;
grant execute on function public.chat_send(text, bigint) to authenticated, service_role;
-- The old signature stays (older clients, and PostgREST resolves by argument names: p_reply_to has no
-- default above, so the two never collide).
create or replace function public.chat_send(p_body text)
 returns jsonb language sql security definer set search_path to 'public'
as $$ select public.chat_send(p_body, null::bigint) $$;
revoke all on function public.chat_send(text) from public, anon;
grant execute on function public.chat_send(text) to authenticated, service_role;

create or replace function public.chat_send_voice(p_audio_path text, p_audio_mime text, p_reply_to bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_me public.profiles:=public.bl_chat_me(); v_now timestamptz:=bl_now(); v_mime text:=lower(split_part(coalesce(p_audio_mime,''),';',1));
  v_rate numeric:=bl_cfg('chat.rate_seconds'); v_burst int:=bl_cfg('chat.burst_per_minute')::int; v_new numeric:=bl_cfg('chat.min_account_real_minutes');
  v_last timestamptz; v_wait int; v_n int; v_loc public.locations; m public.chat_messages;
begin
  select * into v_loc from public.locations where id=v_me.location_id;
  if not bl_cfg_bool('chat.enabled') then raise exception 'Chat is switched off for now. Try again later.' using errcode='P0001',hint='chat_off'; end if;
  if v_me.chat_muted_until is not null and v_me.chat_muted_until>v_now then raise exception 'You are muted from chat right now.' using errcode='P0001',hint='muted'; end if;
  if v_me.travel_to is not null or v_loc.id is null then raise exception 'Arrive at a place before sending a voice note.' using errcode='P0001',hint='traveling'; end if;
  if v_new>0 and v_me.created_at>v_now-make_interval(secs=>(v_new*60)::double precision) then raise exception 'New Sims can chat after % minutes.',ceil(v_new) using errcode='P0001',hint='too_new'; end if;
  if v_mime not in ('audio/webm','audio/mp4','audio/ogg','audio/mpeg','audio/aac','audio/wav') then raise exception 'This voice format is not supported.' using errcode='P0001',hint='bad_audio'; end if;
  if p_audio_path !~ ('^chat/'||v_loc.id||'/'||v_me.id::text||'/[A-Za-z0-9_-]+[.](webm|mp4|ogg|mp3|aac|wav)$') then raise exception 'That voice note is not valid.' using errcode='P0001',hint='bad_audio'; end if;
  if not exists(select 1 from storage.objects where bucket_id='player-voice' and name=p_audio_path) then raise exception 'Voice upload did not finish.' using errcode='P0001',hint='audio_missing'; end if;
  perform public.bl_chat_check_reply(p_reply_to, v_loc.id, v_me.id);
  select max(created_at),count(*) filter(where created_at>v_now-interval '60 seconds') into v_last,v_n from public.chat_messages where user_id=v_me.id and created_at>v_now-interval '1 hour';
  if v_last is not null and v_rate>0 and v_last>v_now-make_interval(secs=>v_rate::double precision) then v_wait:=greatest(1,ceil(v_rate-extract(epoch from v_now-v_last))); raise exception 'Slow down small. Wait % sec before your next message.',v_wait using errcode='P0001',hint='too_fast'; end if;
  if v_n>=v_burst then raise exception 'You are sending too many messages. Take a short break.' using errcode='P0001',hint='too_fast'; end if;
  insert into public.chat_messages(location_id,user_id,username,body,audio_path,audio_mime,created_at,reply_to) values(v_loc.id,v_me.id,v_me.username,null,p_audio_path,v_mime,v_now,p_reply_to) returning * into m;
  return public.bl_chat_row(m,v_me.avatar,v_me.id)||jsonb_build_object('message','Voice note sent.','masked',false);
end $function$;
revoke all on function public.chat_send_voice(text, text, bigint) from public, anon;
grant execute on function public.chat_send_voice(text, text, bigint) to authenticated, service_role;
create or replace function public.chat_send_voice(p_audio_path text, p_audio_mime text)
 returns jsonb language sql security definer set search_path to 'public'
as $$ select public.chat_send_voice(p_audio_path, p_audio_mime, null::bigint) $$;
revoke all on function public.chat_send_voice(text, text) from public, anon;
grant execute on function public.chat_send_voice(text, text) to authenticated, service_role;

-- ---------------------------------------------------------------- DMs
create or replace function public.bl_dm_row(m player_messages, p_sender text, p_me uuid)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'conversation_id', m.conversation_id, 'sender_id', m.sender_id,
    'sender_username', p_sender, 'body', m.body, 'audio_path', m.audio_path,
    'audio_mime', m.audio_mime, 'created_at', m.created_at, 'read_at', m.read_at,
    'mine', m.sender_id = p_me, 'reply_to', m.reply_to, 'reply', public.bl_dm_reply_preview(m.reply_to),
    'deleted_at', m.deleted_at)
$$;
revoke all on function public.bl_dm_row(player_messages, text, uuid) from public, anon, authenticated;

create or replace function public.social_message_history(p_conversation_id bigint, p_before bigint default null::bigint, p_limit integer default 50)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_uid uuid := bl_require_uid(); v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_cut timestamptz := public.bl_chat_history_cutoff();
begin
  if not public.bl_social_can_use_conversation(p_conversation_id) then
    raise exception 'That conversation is not available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  return coalesce((
    select jsonb_agg(public.bl_dm_row(page, sender.username, v_uid) order by page.id)
    from (
      select m.* from public.player_messages m
       where m.conversation_id = p_conversation_id and (p_before is null or m.id < p_before)
         and m.created_at >= v_cut
         and not exists (select 1 from public.chat_hidden_messages h where h.user_id = v_uid and h.player_message_id = m.id)
       order by m.id desc limit v_limit
    ) page
    join public.profiles sender on sender.id = page.sender_id
  ), '[]'::jsonb);
end $function$;

create or replace function public.social_send_message(p_conversation_id bigint, p_body text, p_audio_path text, p_audio_mime text, p_reply_to bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := bl_require_uid(); v_conversation public.player_conversations;
  v_sender public.profiles; v_recipient public.profiles; v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_message public.player_messages; v_path text := nullif(btrim(coalesce(p_audio_path, '')), '');
  v_mime text := lower(split_part(coalesce(p_audio_mime, ''), ';', 1));
begin
  select * into v_conversation from public.player_conversations where id = p_conversation_id;
  if not found or not public.bl_social_can_use_conversation(p_conversation_id) then
    raise exception 'That conversation is not available.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  select * into v_sender from public.profiles where id = v_uid for update;
  select * into v_recipient from public.profiles where id = case when v_conversation.user_a = v_uid then v_conversation.user_b else v_conversation.user_a end;
  if v_sender.banned or v_recipient.banned then raise exception 'This conversation is not available.' using errcode = 'P0001', hint = 'banned'; end if;
  if (v_body is null) = (v_path is null) then
    raise exception 'Send text or one voice note at a time.' using errcode = 'P0001', hint = 'bad_message';
  end if;
  if p_reply_to is not null and not exists (
       select 1 from public.player_messages r where r.id = p_reply_to and r.conversation_id = p_conversation_id
          and r.deleted_at is null and r.created_at >= public.bl_chat_history_cutoff()) then
    raise exception 'That message can''t be replied to any more.' using errcode = 'P0001', hint = 'bad_reply';
  end if;
  if v_body is not null then
    insert into public.player_messages (conversation_id, sender_id, body, created_at, reply_to)
    values (p_conversation_id, v_uid, v_body, bl_now(), p_reply_to) returning * into v_message;
  else
    if v_mime not in ('audio/webm', 'audio/mp4', 'audio/ogg', 'audio/mpeg', 'audio/aac', 'audio/wav') then
      raise exception 'This voice format is not supported on this device.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if v_path !~ ('^' || p_conversation_id::text || '/' || v_uid::text || '/[A-Za-z0-9_-]+[.](webm|mp4|ogg|mp3|aac|wav)$') then
      raise exception 'That voice note is not valid.' using errcode = 'P0001', hint = 'bad_audio';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'player-voice' and o.name = v_path) then
      raise exception 'Voice upload did not finish. Please try again.' using errcode = 'P0001', hint = 'audio_missing';
    end if;
    insert into public.player_messages (conversation_id, sender_id, audio_path, audio_mime, created_at, reply_to)
    values (p_conversation_id, v_uid, v_path, v_mime, bl_now(), p_reply_to) returning * into v_message;
  end if;
  update public.player_conversations set last_message_at = bl_now() where id = p_conversation_id;
  perform public.bl_event(v_recipient.id, 'private_message', 'Message from @' || v_sender.username,
                          case when v_body is null then 'You received a voice message.' else left(v_body, 160) end,
                          jsonb_build_object('conversation_id', p_conversation_id, 'sender_id', v_uid));
  return public.bl_dm_row(v_message, v_sender.username, v_uid);
end $function$;
revoke all on function public.social_send_message(bigint, text, text, text, bigint) from public, anon;
grant execute on function public.social_send_message(bigint, text, text, text, bigint) to authenticated, service_role;
create or replace function public.social_send_message(p_conversation_id bigint, p_body text default null::text, p_audio_path text default null::text, p_audio_mime text default null::text)
 returns jsonb language sql security definer set search_path to 'public'
as $$ select public.social_send_message(p_conversation_id, p_body, p_audio_path, p_audio_mime, null::bigint) $$;
revoke all on function public.social_send_message(bigint, text, text, text) from public, anon;
grant execute on function public.social_send_message(bigint, text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------- delete
-- p_kind: 'place' (place and house chat, chat_messages) or 'dm' (player_messages).
create or replace function public.chat_delete_for_me(p_kind text, p_message_id bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_uid uuid := bl_require_uid(); v_conv bigint;
begin
  if p_kind = 'place' then
    if not exists (select 1 from chat_messages where id = p_message_id) then
      raise exception 'That message is gone.' using errcode = 'P0001', hint = 'not_found';
    end if;
    insert into chat_hidden_messages (user_id, chat_message_id) values (v_uid, p_message_id)
      on conflict (user_id, chat_message_id) where chat_message_id is not null do nothing;
  elsif p_kind = 'dm' then
    select conversation_id into v_conv from player_messages where id = p_message_id;
    if v_conv is null or not exists (select 1 from player_conversations c where c.id = v_conv and v_uid in (c.user_a, c.user_b)) then
      raise exception 'That message is gone.' using errcode = 'P0001', hint = 'not_found';
    end if;
    insert into chat_hidden_messages (user_id, player_message_id) values (v_uid, p_message_id)
      on conflict (user_id, player_message_id) where player_message_id is not null do nothing;
  else
    raise exception 'Unknown chat.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  return jsonb_build_object('message', 'Deleted for you.', 'id', p_message_id);
end $function$;
revoke all on function public.chat_delete_for_me(text, bigint) from public, anon;
grant execute on function public.chat_delete_for_me(text, bigint) to authenticated, service_role;

-- Author-only tombstone inside chat.delete_everyone_hours. Returns the old audio_path so the client can
-- remove the file from storage (direct deletes on storage.objects are blocked; the orphan-cleanup policy
-- lets the author delete it once no row references it). The UPDATE reaches open chats through Realtime.
create or replace function public.chat_delete_for_everyone(p_kind text, p_message_id bigint)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now();
  v_hours numeric := coalesce(bl_cfg('chat.delete_everyone_hours'), 48);
  v_author uuid; v_at timestamptz; v_del timestamptz; v_path text;
begin
  if p_kind = 'place' then
    select user_id, created_at, deleted_at, audio_path into v_author, v_at, v_del, v_path from chat_messages where id = p_message_id for update;
  elsif p_kind = 'dm' then
    select sender_id, created_at, deleted_at, audio_path into v_author, v_at, v_del, v_path from player_messages where id = p_message_id for update;
  else
    raise exception 'Unknown chat.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  if v_author is null then raise exception 'That message is gone.' using errcode = 'P0001', hint = 'not_found'; end if;
  if v_author <> v_uid then
    raise exception 'You can only delete your own messages for everyone.' using errcode = 'P0001', hint = 'not_author';
  end if;
  if v_del is not null then
    return jsonb_build_object('message', 'Already deleted.', 'id', p_message_id, 'deleted_at', v_del, 'audio_path', null);
  end if;
  if v_at < v_now - make_interval(secs => (v_hours * 3600)::double precision) then
    raise exception 'Too late to delete this for everyone (only within % hours).', v_hours using errcode = 'P0001', hint = 'too_late';
  end if;
  if p_kind = 'place' then
    update chat_messages set deleted_at = v_now, body = null, audio_path = null, audio_mime = null where id = p_message_id;
  else
    update player_messages set deleted_at = v_now, body = null, audio_path = null, audio_mime = null where id = p_message_id;
  end if;
  return jsonb_build_object('message', 'Deleted for everyone.', 'id', p_message_id, 'deleted_at', v_now, 'audio_path', v_path);
end $function$;
revoke all on function public.chat_delete_for_everyone(text, bigint) from public, anon;
grant execute on function public.chat_delete_for_everyone(text, bigint) to authenticated, service_role;
