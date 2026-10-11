-- V2 house visits that feel real: tap a person in the house to cook for them, watch a movie, gist,
-- dance, play Ludo, or greet them. The other player accepts or declines; on accept both get the
-- effects and a busy timer (like do_activity). Server-authoritative; idempotent and safe on a non-empty DB.
--   interaction_types   admin-editable catalogue (Admin → Content → House interactions)
--   house_interactions  one row per request: pending → accepted | declined | expired (60 s)
--   social_interact_request(p_user, p_kind) / social_interact_respond(p_id, p_accept)
--   game_config social.interact_cooldown_s (default 60): per pair, per kind
-- Notifications go through the existing events table (postgres_changes on events, already live).

-- ---------------------------------------------------------------- catalogue
create table if not exists public.interaction_types (
  kind        text primary key,
  label       text not null,
  icon        text not null default '✨',
  description text not null default '',
  effects     jsonb not null default '{}'::jsonb,
  -- the host's furniture must offer at least one of these home activities (cook_home, watch_tv, sit_rest ...); {} = none
  requires    text[] not null default '{}',
  cost        bigint not null default 0 check (cost >= 0),
  seconds     integer not null default 30 check (seconds between 1 and 3600),
  sort        integer not null default 0,
  active      boolean not null default true
);

insert into public.interaction_types (kind, label, icon, description, effects, requires, cost, seconds, sort) values
  ('cook_meal', 'Cook a meal for them', '🍲', 'You cook rice and stew, they eat with you. Both of you get full.',
   '{"hunger": 30, "social": 6}', '{cook_home}', 500, 45, 10),
  ('movie', 'Watch a movie together', '🎬', 'Sit on the sofa and watch Nollywood together.',
   '{"fun": 22, "social": 14, "stress": -6}', '{watch_tv}', 0, 60, 20),
  ('gist', 'Gist and chat', '💬', 'Sit down and catch up on the latest gist.',
   '{"social": 18}', '{}', 0, 30, 30),
  ('dance', 'Dance together', '💃', 'Put on Afrobeats and dance.',
   '{"fun": 18, "social": 6, "energy": -4}', '{}', 0, 25, 40),
  ('play_game', 'Play Ludo or cards', '🎲', 'Find a seat and play a round of Ludo or Whot.',
   '{"fun": 16, "social": 12}', '{sit_rest,relax_sofa}', 0, 45, 50),
  ('greet', 'Greet with a hug', '🤗', 'A warm hug and a hello.',
   '{"social": 8}', '{}', 0, 6, 60)
on conflict (kind) do nothing;

alter table public.interaction_types enable row level security;
revoke all on public.interaction_types from anon, authenticated;
grant select on public.interaction_types to authenticated;
drop policy if exists interaction_types_read on public.interaction_types;
create policy interaction_types_read on public.interaction_types for select to authenticated using (true);

-- ---------------------------------------------------------------- requests
create table if not exists public.house_interactions (
  id           bigserial primary key,
  host_id      uuid not null references public.profiles(id) on delete cascade,
  location_id  text not null,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  target_id    uuid not null references public.profiles(id) on delete cascade,
  kind         text not null references public.interaction_types(kind) on update cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '60 seconds',
  responded_at timestamptz,
  check (requester_id <> target_id)
);
create index if not exists house_interactions_target_idx on public.house_interactions (target_id, status);
create index if not exists house_interactions_pair_idx on public.house_interactions (requester_id, target_id, kind, created_at desc);

alter table public.house_interactions enable row level security;
revoke all on public.house_interactions from anon, authenticated;
grant select on public.house_interactions to authenticated;
drop policy if exists house_interactions_read on public.house_interactions;
create policy house_interactions_read on public.house_interactions for select to authenticated
  using (auth.uid() in (requester_id, target_id));
revoke all on sequence public.house_interactions_id_seq from anon, authenticated;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
  ('social.interact_cooldown_s', '60', 'social', 'House interaction cooldown (s)',
   'Seconds before the same player can ask the same person for the same house interaction again (V2).', 'number', 0, 86400)
on conflict (key) do nothing;

-- ---------------------------------------------------------------- helpers (internal)
-- The house owner when both players are inside the same private home (owner at home, or an admitted guest).
create or replace function public.bl_house_together(p_a uuid, p_b uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select l.private_home_owner_id
    from public.profiles a
    join public.profiles b on b.id = p_b and b.location_id = a.location_id
    join public.locations l on l.id = a.location_id and l.private_home_owner_id is not null
   where a.id = p_a and p_a <> p_b
     and a.travel_to is null and b.travel_to is null and not a.banned and not b.banned
     and (a.id = l.private_home_owner_id or a.home_visit_host_id = l.private_home_owner_id)
     and (b.id = l.private_home_owner_id or b.home_visit_host_id = l.private_home_owner_id)
$$;
revoke all on function public.bl_house_together(uuid, uuid) from public, anon, authenticated;

-- Does the house owner's furniture offer one of these activities? An empty list needs nothing.
create or replace function public.bl_house_has(p_host uuid, p_requires text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(cardinality(p_requires), 0) = 0 or exists (
    select 1 from public.player_furniture pf join public.furniture f on f.id = pf.furniture_id
     where pf.user_id = p_host and f.active and f.activities && p_requires)
$$;
revoke all on function public.bl_house_has(uuid, text[]) from public, anon, authenticated;

create or replace function public.bl_house_need_label(p_requires text[]) returns text
language sql immutable set search_path = public as $$
  select case when 'watch_tv' = any(p_requires) then 'a TV'
              when 'cook_home' = any(p_requires) then 'a cooker'
              when p_requires && '{sit_rest,relax_sofa}'::text[] then 'a seat or sofa'
              else 'the right furniture' end
$$;
revoke all on function public.bl_house_need_label(text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------- RPCs
create or replace function public.social_interact_request(p_user uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   public.profiles;
  v_them public.profiles;
  t      public.interaction_types;
  v_host uuid;
  v_cool numeric := coalesce((select (value #>> '{}')::numeric from public.game_config where key = 'social.interact_cooldown_s'), 60);
  v_id   bigint;
  v_exp  timestamptz;
begin
  select * into t from public.interaction_types where kind = p_kind and active;
  if t.kind is null then
    raise exception 'That is not something you can do together.' using errcode = 'P0001', hint = 'bad_kind';
  end if;
  select * into v_me from public.profiles where id = v_uid;
  select * into v_them from public.profiles where id = p_user;
  v_host := public.bl_house_together(v_uid, p_user);
  if v_them.id is null or v_host is null then
    raise exception 'That player is not with you in the house.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if public.bl_social_blocked(v_uid, p_user) then
    raise exception 'You cannot do that with this player.' using errcode = 'P0001', hint = 'blocked';
  end if;
  if not public.bl_house_has(v_host, t.requires) then
    raise exception '"%" needs % in this house.', t.label, public.bl_house_need_label(t.requires)
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  update public.house_interactions set status = 'expired'
   where status = 'pending' and expires_at <= now() and v_uid in (requester_id, target_id);
  if exists (select 1 from public.house_interactions
              where status = 'pending' and ((requester_id = v_uid and target_id = p_user) or (requester_id = p_user and target_id = v_uid))) then
    raise exception 'You already have a request waiting with @%.', v_them.username using errcode = 'P0001', hint = 'pending';
  end if;
  if exists (select 1 from public.house_interactions
              where requester_id = v_uid and target_id = p_user and kind = t.kind
                and created_at > now() - make_interval(secs => v_cool::double precision)) then
    raise exception 'Give @% a moment before asking that again.', v_them.username using errcode = 'P0001', hint = 'cooldown';
  end if;
  insert into public.house_interactions (host_id, location_id, requester_id, target_id, kind)
  values (v_host, v_me.location_id, v_uid, p_user, t.kind)
  returning id, expires_at into v_id, v_exp;
  perform public.bl_event(p_user, 'house_interact', '@' || v_me.username || ': ' || t.label || '?',
    'Tap Accept to join in.', jsonb_build_object('id', v_id, 'kind', t.kind, 'from', v_uid, 'username', v_me.username,
      'label', t.label, 'icon', t.icon, 'expires_at', v_exp));
  return jsonb_build_object('id', v_id, 'kind', t.kind, 'label', t.label, 'expires_at', v_exp, 'status', 'pending',
    'message', 'Asked @' || v_them.username || ': ' || t.label || '. Waiting for an answer.');
end $$;

create or replace function public.social_interact_respond(p_id bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  r       public.house_interactions;
  t       public.interaction_types;
  v_req   public.profiles;
  v_tgt   public.profiles;
  v_host  uuid;
  v_eff   jsonb;
  v_fromr jsonb;
  v_fromt jsonb;
  v_until timestamptz;
begin
  select * into r from public.house_interactions where id = p_id for update;
  if r.id is null or r.target_id <> v_uid then
    raise exception 'That request is not for you.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if r.status <> 'pending' then
    raise exception 'That request was already answered.' using errcode = 'P0001', hint = 'answered';
  end if;
  select * into t from public.interaction_types where kind = r.kind;
  if r.expires_at <= now() then
    update public.house_interactions set status = 'expired', responded_at = now() where id = r.id;
    return jsonb_build_object('id', r.id, 'status', 'expired', 'message', 'That request expired.');
  end if;
  if not coalesce(p_accept, false) then
    update public.house_interactions set status = 'declined', responded_at = now() where id = r.id;
    select * into v_tgt from public.profiles where id = v_uid;
    perform public.bl_event(r.requester_id, 'house_interact_reply', '@' || v_tgt.username || ' said not now',
      t.label || ' maybe later.', jsonb_build_object('id', r.id, 'kind', r.kind, 'status', 'declined'));
    return jsonb_build_object('id', r.id, 'status', 'declined', 'message', 'Maybe next time.');
  end if;

  v_host := public.bl_house_together(r.requester_id, r.target_id);
  if v_host is null or v_host <> r.host_id then
    raise exception 'You are no longer in the same house.' using errcode = 'P0001', hint = 'not_here';
  end if;
  if not public.bl_house_has(v_host, t.requires) then
    raise exception '"%" needs % in this house.', t.label, public.bl_house_need_label(t.requires)
      using errcode = 'P0001', hint = 'no_furniture';
  end if;
  -- lock both rows in a fixed order
  perform 1 from public.profiles where id in (r.requester_id, r.target_id) order by id for update;
  perform public.bl_apply_needs(r.requester_id);
  perform public.bl_apply_needs(r.target_id);
  select * into v_req from public.profiles where id = r.requester_id;
  select * into v_tgt from public.profiles where id = r.target_id;
  perform public.bl_assert_free(v_tgt);
  begin
    perform public.bl_assert_free(v_req);
  exception when raise_exception then
    raise exception '@% is busy right now. Try again soon.', v_req.username using errcode = 'P0001', hint = 'busy';
  end;
  if t.cost > 0 then
    if v_req.cash < t.cost then
      raise exception '@% can''t cover the % for this right now.', v_req.username, bl_naira(t.cost)
        using errcode = 'P0001', hint = 'no_cash';
    end if;
    perform public.bl_add_money(r.requester_id, 'cash', -t.cost, 'house_interaction', jsonb_build_object('kind', t.kind, 'id', r.id));
  end if;
  v_eff := coalesce(t.effects, '{}'::jsonb);
  v_fromr := public.bl_needs_snapshot(v_req);
  v_fromt := public.bl_needs_snapshot(v_tgt);
  perform public.bl_adjust_needs(r.requester_id, v_eff);
  perform public.bl_adjust_needs(r.target_id, v_eff);
  v_until := public.bl_set_busy_seconds(r.requester_id, t.seconds, t.label);
  perform public.bl_set_busy_seconds(r.target_id, t.seconds, t.label);
  update public.profiles set busy_needs_from = v_fromr where id = r.requester_id;
  update public.profiles set busy_needs_from = v_fromt where id = r.target_id;
  update public.house_interactions set status = 'accepted', responded_at = now() where id = r.id;
  perform public.bl_event(r.requester_id, 'house_interact_reply', '@' || v_tgt.username || ' is in!',
    t.label || '. Enjoy!', jsonb_build_object('id', r.id, 'kind', r.kind, 'status', 'accepted', 'role', 'requester',
      'partner', r.target_id, 'busy_until', v_until));
  return jsonb_build_object('id', r.id, 'status', 'accepted', 'kind', r.kind, 'label', t.label, 'role', 'target',
    'partner', r.requester_id, 'seconds', t.seconds, 'busy_until', v_until, 'effects', v_eff,
    'message', t.label || ' with @' || v_req.username || '. Enjoy!');
end $$;

revoke all on function public.social_interact_request(uuid, text) from public, anon;
revoke all on function public.social_interact_respond(bigint, boolean) from public, anon;
grant execute on function public.social_interact_request(uuid, text) to authenticated;
grant execute on function public.social_interact_respond(bigint, boolean) to authenticated;

-- ---------------------------------------------------------------- admin: Content → House interactions
-- Re-created from the live definition (20261010000400_garage.sql) with interaction_types added.
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
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
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null","requires_event":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
    when 'npc_roster' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","role":"text","motion":"text","avatar":"obj","lines":"text","pidgin":"text","scenes":"arr",
              "location_ids":"arr","zone_key":"text_null","headliner":"bool","sort":"int","active":"bool"}}'
    when 'crowd_profiles' then '{"pk":["id"],"insert":true,"order":"scene, from_hour, days, id",
      "cols":{"scene":"text","days":"text","from_hour":"int","to_hour":"int","npcs":"int","sort":"int","active":"bool"}}'
    when 'hype_templates' then '{"pk":["id"],"insert":true,"order":"kind, sort, id",
      "cols":{"kind":"text","line":"text","ticker":"text","sort":"int","active":"bool"}}'
    when 'place_events' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"location_id":"text","title":"text","description":"text","kind":"text","icon":"text","recurrence":"text",
              "weekday":"int_null","start_time":"num_null","end_time":"num_null","starts_at":"ts_null","ends_at":"ts_null",
              "ticket_price":"money","capacity":"int_null","perks":"obj","variants":"text","sort":"int","active":"bool"}}'
    when 'topup_packs' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"label":"text","game_naira":"money","price_kobo":"money","bonus_tag":"text_null","sort":"int","active":"bool"}}'
    when 'daily_reward_steps' then '{"pk":["day"],"insert":false,"order":"day",
      "cols":{"cash":"money","item_id":"text_null","label":"text"}}'
    when 'gem_finds' then '{"pk":["user_id","hunt_date","location_id"],"insert":false,"order":"hunt_date desc, found_at desc",
      "cols":{}}'
    when 'wardrobe_brands' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","colour":"text","is_house":"bool","sponsor":"bool","sort":"int","active":"bool"}}'
    when 'wardrobe_items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","brand_id":"text_null","category":"text","gender":"text_null","patch":"obj","colours":"arr",
              "price":"money","tag":"text","default_slots":"arr","icon":"text","description":"text","sort":"int","active":"bool"}}'
    when 'garage_types' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","description":"text","price":"money","capacity":"int","allowed_housing":"arr","style":"text",
              "sort":"int","active":"bool"}}'
    when 'interaction_types' then '{"pk":["kind"],"insert":true,"order":"sort, kind",
      "cols":{"label":"text","icon":"text","description":"text","effects":"obj","requires":"arr","cost":"money",
              "seconds":"int","sort":"int","active":"bool"}}'
  end::jsonb;
$function$;

notify pgrst, 'reload schema';
