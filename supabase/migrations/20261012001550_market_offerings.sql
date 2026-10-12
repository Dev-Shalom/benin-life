-- Owner: show Baba's offerings at Oba Market (a stall you can see and buy from), and markets close at 8 PM.

-- 1. "Baba's offerings" stall at Oba Market (location-only zone; the shared market scene keeps its stalls)
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort, active)
values ('oba_market.offerings', null, 'oba_market', 'offerings', 'Offerings stall', '🌰', 'stall',
        13.5, 8.5, 3.2, 2.2, 0, 'Kola, schnapps, white cloth, animals: everything Baba asks for.', 7, true)
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, sort, active)
select 'oba_market.offerings.' || i.id, 'oba_market.offerings', 'shop', i.id, row_number() over (order by i.sort, i.id), true
  from public.items i
 where i.category = 'offering' and 'oba_market' = any (i.sold_at)
on conflict (id) do nothing;

-- 2. Markets open 6 AM and close 8 PM (only where no hours are set yet, so admin edits stay)
update public.locations set open_hour = 6, close_hour = 20
 where scene = 'market' and open_hour is null and close_hour is null;

notify pgrst, 'reload schema';
