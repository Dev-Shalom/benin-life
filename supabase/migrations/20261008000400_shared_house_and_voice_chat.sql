-- Shared private-home interiors, saved furniture positions, house presence/chat, and voice notes.
-- Additive and safe for an already-live social system.

-- A guest temporarily treats the visited home as their home for the existing house renderer and
-- home-only activities. The original home is restored as soon as they leave the private location.
alter table public.profiles add column if not exists home_visit_original_home_location_id text;

create or replace function public.bl_social_restore_home_layout() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_host_home text;
begin
  if old.home_visit_host_id is null or new.location_id is not distinct from old.location_id then
    return new;
  end if;
  select home_location_id into v_host_home from public.profiles where id = old.home_visit_host_id;
  if new.location_id is distinct from v_host_home then
    new.housing_id := old.home_visit_original_housing_id;
    new.home_location_id := coalesce(old.home_visit_original_home_location_id, old.home_location_id);
    new.home_visit_host_id := null;
    new.home_visit_original_housing_id := null;
    new.home_visit_original_home_location_id := null;
  end if;
  return new;
end $$;

create or replace function public.social_home_admit(p_invite_id bigint, p_admit boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_host public.profiles; v_guest public.profiles; v_invite public.player_house_invites;
begin
  select * into v_invite from public.player_house_invites where id = p_invite_id for update;
  if not found or v_invite.host_id <> v_uid or v_invite.status <> 'knocking' or v_invite.expires_at <= bl_now() then
    raise exception 'That guest is no longer waiting at your door.' using errcode = 'P0001', hint = 'knock_expired';
  end if;
  select * into v_host from public.profiles where id = v_uid for update;
  select * into v_guest from public.profiles where id = v_invite.guest_id for update;
  if p_admit then
    if v_host.location_id <> v_host.home_location_id or v_host.travel_to is not null then
      raise exception 'Go home first. Your guest is waiting at the door.' using errcode = 'P0001', hint = 'host_not_home';
    end if;
    if v_host.banned or v_guest.banned or v_guest.travel_to is not null or v_guest.home_visit_host_id is not null then
      raise exception 'Your guest cannot enter right now. Ask them to arrive and try again.' using errcode = 'P0001', hint = 'guest_unavailable';
    end if;
    if (select count(*) from public.profiles where home_visit_host_id = v_uid) >= 8 then
      raise exception 'Your home already has the maximum of 8 guests inside.' using errcode = 'P0001', hint = 'house_full';
    end if;
    if public.bl_social_blocked(v_uid, v_guest.id)
       or not exists (select 1 from public.player_friendships f where f.user_a = least(v_uid, v_guest.id) and f.user_b = greatest(v_uid, v_guest.id) and f.status = 'accepted') then
      update public.player_house_invites set status = 'cancelled', updated_at = bl_now() where id = p_invite_id;
      raise exception 'This guest is no longer your friend.' using errcode = 'P0001', hint = 'not_friend';
    end if;
    update public.profiles
       set location_id = v_host.home_location_id,
           home_visit_host_id = v_host.id,
           home_visit_original_housing_id = v_guest.housing_id,
           home_visit_original_home_location_id = v_guest.home_location_id,
           home_location_id = v_host.home_location_id,
           housing_id = v_host.housing_id
     where id = v_guest.id;
    update public.player_house_invites set status = 'admitted', updated_at = bl_now() where id = p_invite_id;
    perform public.bl_event(v_guest.id, 'house_admitted', '@' || v_host.username || ' opened the door',
      'You are inside ' || coalesce((select name from public.locations where id = v_host.home_location_id), 'their home') || '.',
      jsonb_build_object('invite_id', p_invite_id, 'host_id', v_uid, 'location_id', v_host.home_location_id));
    return jsonb_build_object('id', p_invite_id, 'status', 'admitted', 'message', '@' || v_guest.username || ' is inside.');
  end if;
  update public.player_house_invites set status = 'declined', updated_at = bl_now() where id = p_invite_id;
  perform public.bl_event(v_guest.id, 'house_declined', '@' || v_host.username || ' cannot let you in',
    'The house visit was declined this time.', jsonb_build_object('invite_id', p_invite_id, 'host_id', v_uid));
  return jsonb_build_object('id', p_invite_id, 'status', 'declined', 'message', 'You turned away the guest.');
end $$;

-- Reuse the host's owned furniture for activity validation/rest quality while a guest visits.
create or replace function public.bl_furniture_for(p_uid uuid, p_activity text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('owned', count(*) > 0, 'rest_pct', coalesce(max(f.rest_pct), 100))
    from public.player_furniture pf join public.furniture f on f.id = pf.furniture_id
   where pf.user_id = coalesce((select p.home_visit_host_id from public.profiles p
                                  where p.id = p_uid and p.home_visit_host_id is not null
                                    and p.location_id = p.home_location_id), p_uid)
     and f.active and p_activity = any (f.activities);
$$;

-- Only the owner can change their layout. Visitors can read it while they are admitted.
create table if not exists public.player_house_furniture (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  furniture_key text not null check (furniture_key ~ '^own_[a-z0-9_-]+$'),
  x numeric(6,3) not null,
  z numeric(6,3) not null,
  rotation smallint not null default 0 check (rotation between 0 and 3),
  updated_at timestamptz not null default now(),
  primary key (owner_id, furniture_key)
);
alter table public.player_house_furniture enable row level security;
revoke all on public.player_house_furniture from anon, authenticated;
grant select on public.player_house_furniture to authenticated;

create or replace function public.bl_social_can_view_owner_home(p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles h join public.locations l on l.id = h.home_location_id
                  where h.id = p_owner and l.private_home_owner_id = p_owner
                    and public.bl_social_can_view_private_home(l.id, p_owner))
$$;
revoke all on function public.bl_social_can_view_owner_home(uuid) from public, anon;
grant execute on function public.bl_social_can_view_owner_home(uuid) to authenticated;
drop policy if exists player_furniture_visit_read on public.player_furniture;
create policy player_furniture_visit_read on public.player_furniture for select to authenticated
  using (user_id = (select auth.uid()) or public.bl_social_can_view_owner_home(user_id));
drop policy if exists player_house_furniture_read on public.player_house_furniture;
create policy player_house_furniture_read on public.player_house_furniture for select to authenticated
  using (public.bl_social_can_view_owner_home(owner_id));

create or replace function public.social_house_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me public.profiles; v_owner public.profiles; v_home text;
begin
  select * into v_me from public.profiles where id = v_uid;
  v_owner := v_me;
  if v_me.home_visit_host_id is not null then
    select * into v_owner from public.profiles where id = v_me.home_visit_host_id;
  end if;
  v_home := v_owner.home_location_id;
  if v_me.location_id <> v_home or v_me.travel_to is not null
     or not public.bl_social_can_view_private_home(v_home, v_owner.id) then
    raise exception 'You need to be inside this private home.' using errcode = 'P0001', hint = 'not_house_member';
  end if;
  return jsonb_build_object('owner_id', v_owner.id, 'username', v_owner.username, 'housing_id', v_owner.housing_id,
                            'origin', v_owner.origin, 'home_location_id', v_home);
end $$;

create or replace function public.social_home_place_furniture(p_furniture_key text, p_x numeric, p_z numeric, p_rotation smallint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_me public.profiles; v_w numeric; v_d numeric; v_rot smallint := ((coalesce(p_rotation, 0) % 4) + 4) % 4;
begin
  select * into v_me from public.profiles where id = v_uid for update;
  if v_me.home_visit_host_id is not null or v_me.location_id <> v_me.home_location_id or v_me.travel_to is not null then
    raise exception 'Only the homeowner can arrange furniture while at home.' using errcode = 'P0001', hint = 'not_homeowner';
  end if;
  if p_furniture_key !~ '^own_[a-z0-9_-]+$' then
    raise exception 'Choose one of your movable furniture pieces.' using errcode = 'P0001', hint = 'fixed_furniture';
  end if;
  if not exists (select 1 from public.player_furniture pf join public.furniture f on f.id = pf.furniture_id
                   where pf.user_id = v_uid and 'own_' || pf.furniture_id = p_furniture_key and f.active) then
    raise exception 'You do not own that furniture.' using errcode = 'P0001', hint = 'not_owned';
  end if;
  v_w := case when v_me.housing_id like 'hostel%' then 5.2 when v_me.housing_id like 'face_me%' then 4.2
              when v_me.housing_id like 'self_con%' then 6 when v_me.housing_id like '%flat%' then 8
              when v_me.housing_id like '%duplex%' then 10 else 4.2 end;
  v_d := case when v_me.housing_id like 'hostel%' then 4.4 when v_me.housing_id like 'face_me%' then 3.8
              when v_me.housing_id like 'self_con%' then 4.8 when v_me.housing_id like '%flat%' then 6.2
              when v_me.housing_id like '%duplex%' then 7.6 else 3.8 end;
  if p_x is null or p_z is null or p_x < 0 or p_z < 0 or p_x > v_w or p_z > v_d then
    raise exception 'Place furniture on the floor inside your home.' using errcode = 'P0001', hint = 'outside_home';
  end if;
  insert into public.player_house_furniture (owner_id, furniture_key, x, z, rotation, updated_at)
  values (v_uid, p_furniture_key, round(p_x, 3), round(p_z, 3), v_rot, bl_now())
  on conflict (owner_id, furniture_key) do update
    set x = excluded.x, z = excluded.z, rotation = excluded.rotation, updated_at = excluded.updated_at;
  return jsonb_build_object('furniture_key', p_furniture_key, 'x', round(p_x, 3), 'z', round(p_z, 3), 'rotation', v_rot);
end $$;

-- Realtime room topic authorization: only the homeowner while at home and admitted guests can join.
create or replace function public.bl_social_active_house_topic() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.locations l join public.profiles h on h.id = l.private_home_owner_id
    join public.profiles me on me.id = auth.uid()
    where l.private_home_owner_id is not null and l.id = substr(realtime.topic(), 7)
      and me.location_id = l.id and me.travel_to is null
      and (me.id = h.id or me.home_visit_host_id = h.id)
  )
$$;
revoke all on function public.bl_social_active_house_topic() from public, anon;
grant execute on function public.bl_social_active_house_topic() to authenticated;
drop policy if exists house_room_presence_read on realtime.messages;
create policy house_room_presence_read on realtime.messages for select to authenticated
  using (realtime.topic() like 'house:%' and realtime.messages.extension in ('broadcast', 'presence')
         and public.bl_social_active_house_topic());
drop policy if exists house_room_presence_write on realtime.messages;
create policy house_room_presence_write on realtime.messages for insert to authenticated
  with check (realtime.topic() like 'house:%' and realtime.messages.extension in ('broadcast', 'presence')
              and public.bl_social_active_house_topic());

-- Both direct and location messages use the same private bucket and custom player-side audio controls.
alter table public.player_messages drop constraint if exists player_messages_check;
alter table public.player_messages drop constraint if exists player_messages_body_check;
alter table public.player_messages add constraint player_messages_payload_check check (
  (body is not null and char_length(body) > 0 and audio_path is null and audio_mime is null)
  or (body is null and audio_path is not null and audio_mime is not null)
);
alter table public.chat_messages alter column body drop not null;
alter table public.chat_messages drop constraint if exists chat_messages_body_check;
alter table public.chat_messages add column if not exists audio_path text;
alter table public.chat_messages add column if not exists audio_mime text;
alter table public.chat_messages add constraint chat_messages_payload_check check (
  (body is not null and char_length(body) > 0 and audio_path is null and audio_mime is null)
  or (body is null and audio_path is not null and audio_mime is not null)
);
create unique index if not exists chat_messages_audio_path_idx on public.chat_messages(audio_path) where audio_path is not null;
delete from public.game_config where key = 'chat.max_len';

create or replace function public.social_send_message(
  p_conversation_id bigint,
  p_body text default null,
  p_audio_path text default null,
  p_audio_mime text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  if v_body is not null then
    insert into public.player_messages (conversation_id, sender_id, body, created_at)
    values (p_conversation_id, v_uid, v_body, bl_now()) returning * into v_message;
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
    insert into public.player_messages (conversation_id, sender_id, audio_path, audio_mime, created_at)
    values (p_conversation_id, v_uid, v_path, v_mime, bl_now()) returning * into v_message;
  end if;
  update public.player_conversations set last_message_at = bl_now() where id = p_conversation_id;
  perform public.bl_event(v_recipient.id, 'private_message', 'Message from @' || v_sender.username,
                          case when v_body is null then 'You received a voice message.' else left(v_body, 160) end,
                          jsonb_build_object('conversation_id', p_conversation_id, 'sender_id', v_uid));
  return jsonb_build_object('id', v_message.id, 'conversation_id', p_conversation_id, 'sender_id', v_uid,
                            'sender_username', v_sender.username, 'body', v_message.body,
                            'audio_path', v_message.audio_path, 'audio_mime', v_message.audio_mime,
                            'created_at', v_message.created_at, 'read_at', v_message.read_at, 'mine', true);
end $$;

create or replace function public.bl_chat_row(m public.chat_messages, p_avatar jsonb, p_me uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('id', m.id, 'location_id', m.location_id, 'user_id', m.user_id,
    'username', m.username, 'body', m.body, 'audio_path', m.audio_path, 'audio_mime', m.audio_mime,
    'created_at', m.created_at, 'avatar', p_avatar, 'mine', m.user_id = p_me)
$$;

create or replace function public.chat_send(p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  insert into public.chat_messages(location_id,user_id,username,body,created_at) values(v_me.location_id,v_me.id,v_me.username,v_masked,v_now) returning * into m;
  return public.bl_chat_row(m,v_me.avatar,v_me.id)||jsonb_build_object('message','Sent.','masked',v_masked<>v_body);
end $$;

create or replace function public.bl_social_can_chat_voice(p_location text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p join public.locations l on l.id=p.location_id
    where p.id=auth.uid() and p.location_id=p_location and p.travel_to is null and not p.banned
      and (l.private_home_owner_id is null or public.bl_social_can_view_private_home(l.id,l.private_home_owner_id)))
$$;
revoke all on function public.bl_social_can_chat_voice(text) from public,anon;
grant execute on function public.bl_social_can_chat_voice(text) to authenticated;

drop policy if exists player_voice_friend_read on storage.objects;
create policy player_voice_friend_read on storage.objects for select to authenticated using (
  bucket_id='player-voice' and (
    ((storage.foldername(name))[1] ~ '^[0-9]+$' and public.bl_social_can_use_conversation(((storage.foldername(name))[1])::bigint))
    or ((storage.foldername(name))[1]='chat' and public.bl_social_can_chat_voice((storage.foldername(name))[2]))
  ));
drop policy if exists player_voice_friend_upload on storage.objects;
create policy player_voice_friend_upload on storage.objects for insert to authenticated with check (
  bucket_id='player-voice' and (
    ((storage.foldername(name))[1] ~ '^[0-9]+$' and (storage.foldername(name))[2]=auth.uid()::text
      and public.bl_social_can_use_conversation(((storage.foldername(name))[1])::bigint))
    or ((storage.foldername(name))[1]='chat' and (storage.foldername(name))[3]=auth.uid()::text
      and public.bl_social_can_chat_voice((storage.foldername(name))[2]))
  ));
drop policy if exists player_voice_orphan_cleanup on storage.objects;
create policy player_voice_orphan_cleanup on storage.objects for delete to authenticated using (
  bucket_id='player-voice' and (
    (((storage.foldername(name))[1] ~ '^[0-9]+$') and (storage.foldername(name))[2]=auth.uid()::text
      and not exists(select 1 from public.player_messages m where m.audio_path=storage.objects.name))
    or (((storage.foldername(name))[1]='chat') and (storage.foldername(name))[3]=auth.uid()::text
      and not exists(select 1 from public.chat_messages m where m.audio_path=storage.objects.name))
  ));

create or replace function public.chat_send_voice(p_audio_path text,p_audio_mime text) returns jsonb
language plpgsql security definer set search_path=public as $$
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
  select max(created_at),count(*) filter(where created_at>v_now-interval '60 seconds') into v_last,v_n from public.chat_messages where user_id=v_me.id and created_at>v_now-interval '1 hour';
  if v_last is not null and v_rate>0 and v_last>v_now-make_interval(secs=>v_rate::double precision) then v_wait:=greatest(1,ceil(v_rate-extract(epoch from v_now-v_last))); raise exception 'Slow down small. Wait % sec before your next message.',v_wait using errcode='P0001',hint='too_fast'; end if;
  if v_n>=v_burst then raise exception 'You are sending too many messages. Take a short break.' using errcode='P0001',hint='too_fast'; end if;
  insert into public.chat_messages(location_id,user_id,username,body,audio_path,audio_mime,created_at) values(v_loc.id,v_me.id,v_me.username,null,p_audio_path,v_mime,v_now) returning * into m;
  return public.bl_chat_row(m,v_me.avatar,v_me.id)||jsonb_build_object('message','Voice note sent.','masked',false);
end $$;

create or replace function public.social_home_offer(p_guest uuid,p_item text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=bl_require_uid(); v_me public.profiles; v_guest_row public.profiles; v_item_row public.items;
begin
  select * into v_me from public.profiles where id=v_uid for update;
  select * into v_guest_row from public.profiles where id=p_guest for update;
  if p_guest=v_uid or v_guest_row.id is null or v_me.location_id is null or v_me.travel_to is not null
     or v_guest_row.location_id is distinct from v_me.location_id or v_guest_row.travel_to is not null or v_guest_row.banned or v_me.banned then
    raise exception 'That player is not with you in the house.' using errcode='P0001',hint='not_here';
  end if;
  if not exists(select 1 from public.locations l where l.id=v_me.location_id and l.private_home_owner_id is not null
                 and public.bl_social_can_view_private_home(l.id,l.private_home_owner_id)) then raise exception 'Food and drink offers are for private house visits.' using errcode='P0001',hint='not_private_home'; end if;
  if public.bl_social_blocked(v_uid,p_guest) then raise exception 'You cannot send an offer to a player you blocked.' using errcode='P0001',hint='blocked'; end if;
  select * into v_item_row from public.items where id=p_item and category in ('food','drink')
    and public.bl_item_kind(effects)='use';
  if v_item_row.id is null then raise exception 'Choose food or a drink from your Bag.' using errcode='P0001',hint='not_food'; end if;
  perform public.bl_give_item(v_uid,p_item,-1); perform public.bl_give_item(p_guest,p_item,1);
  perform public.bl_event(p_guest,'house_offer','@'||v_me.username||' shared something with you',v_item_row.name||' was added to your Bag.',jsonb_build_object('from',v_uid,'item',p_item));
  return jsonb_build_object('message','Shared '||v_item_row.name||' with @'||v_guest_row.username||'.','item',p_item);
end $$;

-- Permissions and realtime publication.
revoke all on function public.social_house_info() from public,anon;
revoke all on function public.social_home_place_furniture(text,numeric,numeric,smallint) from public,anon;
revoke all on function public.social_home_offer(uuid,text) from public,anon;
revoke all on function public.chat_send_voice(text,text) from public,anon;
grant execute on function public.social_house_info() to authenticated;
grant execute on function public.social_home_place_furniture(text,numeric,numeric,smallint) to authenticated;
grant execute on function public.social_home_offer(uuid,text) to authenticated;
grant execute on function public.chat_send_voice(text,text) to authenticated;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='player_house_furniture') then
    alter publication supabase_realtime add table public.player_house_furniture;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='player_furniture') then
    alter publication supabase_realtime add table public.player_furniture;
  end if;
end $$;
