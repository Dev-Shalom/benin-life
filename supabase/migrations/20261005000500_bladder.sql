-- R4: Bladder need + toilet activities + a few home activities for the 3D home furniture,
-- and a tiny players_online() count for the HUD pill.
-- Never edit applied migrations: everything here is additive or `create or replace` with the same
-- signatures. get_my_state is untouched (it returns to_jsonb(profile), so `bladder` shows up by itself).
--
-- Bladder works like the other needs: 100 = comfortable, it drops every game hour
-- (needs.bladder_per_hour × trait multiplier effects.decay.bladder), restored by toilet activities.
-- While it sits at 0 hygiene drops faster (needs.bladder_empty_hygiene_per_hour): an "accident".
-- Decay stays a pure function of elapsed time (path-independent), like the starvation health loss.

-- ---------------------------------------------------------------------
-- 1. Column + config
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists bladder numeric not null default 100;

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('needs.bladder_per_hour', '5', 'needs', 'Bladder drop / game hour',
 'How fast the bladder fills (the bar drops). 5 = empty after 20 game hours from full. Traits can scale it with effects.decay.bladder.', 'number', 0, 50),
('needs.bladder_empty_hygiene_per_hour', '4', 'needs', 'Hygiene loss / game hour at empty bladder',
 'Extra hygiene lost every game hour while the bladder bar sits at 0 (an accident). 0 = off.', 'number', 0, 50)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Decay / apply / adjust (same signatures as before)
-- ---------------------------------------------------------------------
create or replace function public.bl_decay_row(p_row public.profiles, p_at timestamptz) returns public.profiles
language plpgsql stable set search_path = public as $$
declare
  v        profiles := p_row;
  v_hours  numeric;
  r_hun    numeric; r_en numeric; r_hy numeric; r_fun numeric; r_soc numeric; r_str numeric; r_bl numeric;
  r_starve numeric; v_floor numeric; r_acc numeric;
  v_zero   numeric; v_bzero numeric;
  v_health numeric; v_hyg numeric;
begin
  if v.id is null then return v; end if;
  v_hours := extract(epoch from (p_at - v.needs_updated_at))::numeric / 3600.0
             * bl_cfg('clock.game_minutes_per_real_minute');
  if v_hours <= 0 then return v; end if;

  r_hun := bl_cfg('needs.hunger_per_hour')  * bl_trait_mult(v.traits, 'hunger');
  r_en  := bl_cfg('needs.energy_per_hour')  * bl_trait_mult(v.traits, 'energy');
  r_hy  := bl_cfg('needs.hygiene_per_hour') * bl_trait_mult(v.traits, 'hygiene');
  r_fun := bl_cfg('needs.fun_per_hour')     * bl_trait_mult(v.traits, 'fun');
  r_soc := bl_cfg('needs.social_per_hour')  * bl_trait_mult(v.traits, 'social');
  r_str := bl_cfg('needs.stress_per_hour')  * bl_trait_mult(v.traits, 'stress');
  r_bl  := coalesce(bl_cfg('needs.bladder_per_hour'), 0) * bl_trait_mult(v.traits, 'bladder');
  r_acc := greatest(0, coalesce(bl_cfg('needs.bladder_empty_hygiene_per_hour'), 0));
  r_starve := bl_cfg('needs.starve_health_per_hour');
  v_floor  := bl_cfg('needs.starve_health_floor');

  -- starvation: health drops for the time hunger or energy sits at 0
  v_zero := least(case when r_hun > 0 then greatest(v.hunger, 0) / r_hun else 1e9 end,
                  case when r_en  > 0 then greatest(v.energy, 0) / r_en  else 1e9 end);
  v_health := v.health - greatest(0, v_hours - v_zero) * r_starve;
  v_health := greatest(v_health, least(v.health, v_floor));

  -- bladder accident: extra hygiene loss for the time the bladder sits at 0
  v_bzero := case when r_bl > 0 then greatest(coalesce(v.bladder, 100), 0) / r_bl else 1e9 end;
  v_hyg := v.hygiene - r_hy * v_hours - greatest(0, v_hours - v_bzero) * r_acc;

  v.hunger  := round(greatest(0, least(100, v.hunger  - r_hun * v_hours)), 4);
  v.energy  := round(greatest(0, least(100, v.energy  - r_en  * v_hours)), 4);
  v.hygiene := round(greatest(0, least(100, v_hyg)), 4);
  v.fun     := round(greatest(0, least(100, v.fun     - r_fun * v_hours)), 4);
  v.social  := round(greatest(0, least(100, v.social  - r_soc * v_hours)), 4);
  v.stress  := round(greatest(0, least(100, v.stress  + r_str * v_hours)), 4);
  v.bladder := round(greatest(0, least(100, coalesce(v.bladder, 100) - r_bl * v_hours)), 4);
  v.health  := round(greatest(0, least(100, v_health)), 4);
  v.needs_updated_at := p_at;
  return v;
end $$;

create or replace function public.bl_apply_needs(p_uid uuid) returns public.profiles
language plpgsql set search_path = public as $$
declare
  v     profiles;
  v_now timestamptz := bl_now();
begin
  select * into v from profiles where id = p_uid for update;
  if not found then return null; end if;
  if v.needs_updated_at >= v_now then return v; end if;
  v := bl_decay_row(v, v_now);
  update profiles set
    hunger = v.hunger, energy = v.energy, hygiene = v.hygiene, fun = v.fun, social = v.social,
    stress = v.stress, health = v.health, bladder = v.bladder, needs_updated_at = v.needs_updated_at
  where id = p_uid
  returning * into v;
  return v;
end $$;

create or replace function public.bl_adjust_needs(p_uid uuid, p_delta jsonb) returns void
language plpgsql set search_path = public as $$
begin
  perform bl_apply_needs(p_uid);
  update profiles set
    hunger  = greatest(0, least(100, hunger  + coalesce((p_delta->>'hunger')::numeric, 0))),
    energy  = greatest(0, least(100, energy  + coalesce((p_delta->>'energy')::numeric, 0))),
    hygiene = greatest(0, least(100, hygiene + coalesce((p_delta->>'hygiene')::numeric, 0))),
    fun     = greatest(0, least(100, fun     + coalesce((p_delta->>'fun')::numeric, 0))),
    social  = greatest(0, least(100, social  + coalesce((p_delta->>'social')::numeric, 0))),
    health  = greatest(0, least(100, health  + coalesce((p_delta->>'health')::numeric, 0))),
    stress  = greatest(0, least(100, stress  + coalesce((p_delta->>'stress')::numeric, 0))),
    bladder = greatest(0, least(100, bladder + coalesce((p_delta->>'bladder')::numeric, 0)))
  where id = p_uid;
end $$;

-- ---------------------------------------------------------------------
-- 3. Activities (data, admin-editable). Home ones map to furniture in the 3D home (docs/HUD_HOME.md).
-- ---------------------------------------------------------------------
insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort) values
('use_toilet', 'Use the toilet', '{home_face_me,home_flat,home_duplex}', true, 0, 5,
  '{"bladder": 100, "stress": -2}', false, 35),
('watch_tv', 'Watch Nollywood on TV', '{home_flat,home_duplex}', true, 0, 60,
  '{"fun": 22, "stress": -6}', false, 45),
('listen_radio', 'Listen to the radio', '{home_face_me}', true, 0, 45,
  '{"fun": 15, "stress": -5}', false, 46),
('ease_yourself', 'Use the restroom', '{buka,club,cyber,campus,hospital}', false, 50, 5,
  '{"bladder": 100}', false, 215),
('public_toilet', 'Pay-to-use public toilet', '{market,motorpark,street}', false, 50, 5,
  '{"bladder": 100, "hygiene": -2}', false, 216)
on conflict (id) do nothing;

-- Drinks fill the bladder (only if the row has no bladder effect yet, so admin edits survive re-runs).
update public.activities set effects = effects || '{"bladder": -15}'::jsonb
 where id in ('lounge_chill') and not effects ? 'bladder';
update public.activities set effects = effects || '{"bladder": -20}'::jsonb
 where id in ('club_night') and not effects ? 'bladder';
update public.activities set effects = effects || '{"bladder": -10}'::jsonb
 where id in ('watch_football', 'pepper_soup') and not effects ? 'bladder';

-- ---------------------------------------------------------------------
-- 4. players_online(): how many Sims were seen in the last time.presence_real_minutes (HUD pill)
-- ---------------------------------------------------------------------
create or replace function public.players_online() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_n bigint;
begin
  select count(*) into v_n from profiles
   where not banned and home_chosen
     and last_seen > bl_now() - make_interval(secs => (bl_cfg('time.presence_real_minutes') * 60)::double precision);
  return jsonb_build_object('count', v_n, 'minutes', bl_cfg('time.presence_real_minutes'));
end $$;

revoke execute on function public.players_online() from public, anon;
grant execute on function public.players_online() to authenticated;

-- Helpers stay internal.
revoke execute on function public.bl_decay_row(public.profiles, timestamptz) from public, anon, authenticated;
revoke execute on function public.bl_apply_needs(uuid) from public, anon, authenticated;
revoke execute on function public.bl_adjust_needs(uuid, jsonb) from public, anon, authenticated;
