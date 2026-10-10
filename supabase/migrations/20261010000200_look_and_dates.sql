-- Wardrobe follow-ups (user, 2026-10-10):
--   1. Edit look is identity-only. update_avatar keeps the Sim's current clothes (top, bottom, shoes, hat,
--      accent, accessories, preset): clothes come from the Benin Boutique (wardrobe_set_outfit), so the old
--      free editor can't hand out paid garments. Re-created from its live definition (20261005000400_creator).
--   2. Date night: two date activities ("Date night dinner" at hotels, "Movie date" at the cinema/mall). The
--      client switches to the Date night outfit while one of them runs (src/lib/outfit.ts).
-- Idempotent.

create or replace function public.update_avatar(p_avatar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles := bl_me_any(); v_old jsonb; v_new jsonb; k text;
begin
  if p_avatar is null or jsonb_typeof(p_avatar) <> 'object' or length(p_avatar::text) > 4000 then
    raise exception 'Your avatar data is not valid. Please try again.' using errcode = 'P0001';
  end if;
  v_old := coalesce(v_me.avatar, '{}'::jsonb);
  v_new := p_avatar;
  foreach k in array array['top', 'bottom', 'shoes', 'hat', 'accent', 'accessories', 'preset'] loop
    if v_old ? k then v_new := jsonb_set(v_new, array[k], v_old->k, true); else v_new := v_new - k; end if;
  end loop;
  update profiles set
    avatar = v_new,
    gender = case when p_avatar->>'gender' in ('male','female') then p_avatar->>'gender' else gender end
  where id = v_me.id;
  return jsonb_build_object('message', 'Your new look is saved. Looking good!');
end $$;
revoke execute on function public.update_avatar(jsonb) from public, anon;
grant execute on function public.update_avatar(jsonb) to authenticated;

insert into public.activities (id, name, scenes, home_only, cost, game_minutes, effects, night_only, sort, max_seconds, min_seconds, scale_by_need, location_ids, risky, rush, icon) values
('date_dinner', 'Date night dinner',  '{hotel}',        false, 25000, 90, '{"fun": 30, "social": 35, "stress": -15, "hunger": 40}', false, 323, 14, 7, false, '{}', false, '{}', '🕯️'),
('movie_date',  'Movie date',         '{cinema,mall}',  false, 7000, 120, '{"fun": 40, "social": 25, "stress": -12}', false, 311, 14, 8, false, '{}', false, '{}', '💞')
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select z || '.' || r, z, k, r, l, s from (values
  ('hotel.lounge', 'activity', 'date_dinner', null, 2),
  ('cinema.screen', 'activity', 'movie_date', null, 3),
  ('mall.cinema', 'activity', 'movie_date', null, 3)
) v(z, k, r, l, s)
where exists (select 1 from public.place_zones pz where pz.id = v.z)
on conflict (id) do nothing;
