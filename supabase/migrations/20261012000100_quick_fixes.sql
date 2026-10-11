-- Q1 quick fixes. Idempotent and safe on a non-empty DB; guarded updates only touch rows still at the
-- old defaults, so anything the admin already tuned is kept.
--   1. Shorter shared house interactions (interaction_types.seconds, still admin-tunable).
--      Solo activities are already short (activities.max_seconds <= 15, action.* <= 45 s): unchanged.
--   2. Slower needs decay: needs.decay_speed 2.5 -> 1 (hunger empties in ~25 real hours instead of ~10).
--   3. Leaving the house (location change, visit ended, travel) ends any running house interaction for
--      BOTH players; stopping it (activity_stop) or anything else that replaces one player's busy timer
--      frees the partner too. New status 'ended'.
--   4. The Go Crazy wardrobe brand is switched off (brand + its items inactive; owned rows kept).

-- ---------------------------------------------------------------- 1. interaction durations
update public.interaction_types set seconds = 5  where kind = 'greet'     and seconds = 6;
update public.interaction_types set seconds = 22 where kind = 'dance'     and seconds = 25;
update public.interaction_types set seconds = 35 where kind = 'movie'     and seconds = 60;
update public.interaction_types set seconds = 12 where kind = 'gist'      and seconds = 30;
update public.interaction_types set seconds = 15 where kind = 'cook_meal' and seconds = 45;
update public.interaction_types set seconds = 20 where kind = 'play_game' and seconds = 45;

-- ---------------------------------------------------------------- 2. needs decay
update public.game_config
   set value = '1',
       description = 'Need-hours that pass per real hour on the real clock. 1 = hunger empties in about 25 real hours (Q1; was 2.5).'
 where key = 'needs.decay_speed' and value = '2.5'::jsonb;

-- ---------------------------------------------------------------- 3. leaving ends shared interactions
alter table public.house_interactions drop constraint if exists house_interactions_status_check;
alter table public.house_interactions add constraint house_interactions_status_check
  check (status in ('pending', 'accepted', 'declined', 'expired', 'ended'));

-- End every running (accepted, someone still busy with it) interaction p_uid is part of: both players'
-- busy timers stop now (effects already applied stay), the row becomes 'ended', and the other player
-- gets an event so their client stops the pose and the music. Pending requests involving p_uid expire.
create or replace function public.bl_house_interactions_end(p_uid uuid, p_reason text default 'left')
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_now  timestamptz := bl_now();
  r      record;
  v_n    integer := 0;
  v_who  text;
  v_other uuid;
begin
  if p_uid is null then return 0; end if;
  update house_interactions set status = 'expired', responded_at = coalesce(responded_at, now())
   where status = 'pending' and p_uid in (requester_id, target_id);
  for r in
    select hi.id, hi.requester_id, hi.target_id, hi.kind, t.label
      from house_interactions hi join interaction_types t on t.kind = hi.kind
     where hi.status = 'accepted' and p_uid in (hi.requester_id, hi.target_id)
       and hi.responded_at > now() - make_interval(secs => (t.seconds + 120)::double precision)
       and exists (select 1 from profiles pr where pr.id in (hi.requester_id, hi.target_id)
                      and pr.busy_label = t.label and pr.busy_until > v_now)
     for update of hi
  loop
    -- status first: the busy_until trigger below sees nothing left to end (no recursion)
    update house_interactions set status = 'ended' where id = r.id;
    update profiles set busy_until = v_now, busy_needs_from = null
     where id in (r.requester_id, r.target_id) and busy_label = r.label and busy_until > v_now;
    v_other := case when r.requester_id = p_uid then r.target_id else r.requester_id end;
    select '@' || username into v_who from profiles where id = p_uid;
    perform bl_event(v_other, 'house_interact_end',
      case when p_reason = 'left' then coalesce(v_who, 'They') || ' left the house'
           else coalesce(v_who, 'They') || ' stopped' end,
      r.label || ' ended.', jsonb_build_object('id', r.id, 'kind', r.kind, 'reason', p_reason, 'by', p_uid));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.bl_house_interactions_end(uuid, text) from public, anon, authenticated;

-- Location / visit / travel change -> end shared interactions.
create or replace function public.bl_house_interactions_on_leave() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.bl_house_interactions_end(new.id, 'left');
  return null;
end $$;
revoke all on function public.bl_house_interactions_on_leave() from public, anon, authenticated;

drop trigger if exists profiles_end_interactions_on_leave on public.profiles;
create trigger profiles_end_interactions_on_leave
  after update of location_id, home_visit_host_id, travel_to on public.profiles
  for each row
  when (old.location_id is distinct from new.location_id
        or old.home_visit_host_id is distinct from new.home_visit_host_id
        or (old.travel_to is null and new.travel_to is not null))
  execute function public.bl_house_interactions_on_leave();

-- One player's running timer stopped early or was replaced (activity_stop, hospital, admin) -> free the partner.
create or replace function public.bl_house_interactions_on_stop() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := public.bl_now();
begin
  if old.busy_label is not null and old.busy_until > v_now
     and (new.busy_until is null or new.busy_until <= v_now or new.busy_label is distinct from old.busy_label)
     and exists (select 1 from public.interaction_types where label = old.busy_label) then
    perform public.bl_house_interactions_end(new.id, 'stopped');
  end if;
  return null;
end $$;
revoke all on function public.bl_house_interactions_on_stop() from public, anon, authenticated;

drop trigger if exists profiles_end_interactions_on_stop on public.profiles;
create trigger profiles_end_interactions_on_stop
  after update of busy_until, busy_label on public.profiles
  for each row
  when (old.busy_until is distinct from new.busy_until or old.busy_label is distinct from new.busy_label)
  execute function public.bl_house_interactions_on_stop();

-- ---------------------------------------------------------------- 4. Go Crazy off
update public.wardrobe_brands set active = false where id = 'go_crazy' and active;
update public.wardrobe_items set active = false where brand_id = 'go_crazy' and active;

notify pgrst, 'reload schema';
