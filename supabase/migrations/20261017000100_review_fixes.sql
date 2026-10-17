-- Review fixes (2026-10-17), all data-only and idempotent:
--   1. GRA duplex: the dining set (and the ceiling fan that hangs over it) stood 0.55 m from the guest bedroom
--      door, leaving a ~0.27 m squeeze. They move 0.6 m west (x 8.8 -> 8.2) so the guest bed is easy to reach.
--      Owners who still have those pieces at the old default spot are moved too; pieces they moved are untouched.
--   2. Billboards: the legs of seven city boards stood on the road (the Ugbowo screen right at the Wi-Fi Joint
--      junction). They move to the roadside; only rows still at their old seed position are touched.
-- No functions are changed here, so there is nothing to patch with pg_get_functiondef.

-- ---------------------------------------------------------------- 1. duplex dining set
do $mig$
declare v_inc jsonb; v_new jsonb;
begin
  select included into v_inc from public.home_layouts where id = 'duplex';
  if v_inc is null then raise exception 'review_fixes: home_layouts.duplex is missing'; end if;
  if not (v_inc @> '[{"id":"dining"}]'::jsonb and v_inc @> '[{"id":"cfan"}]'::jsonb) then
    raise exception 'review_fixes: duplex included pieces dining/cfan not found (marker missing)';
  end if;
  select jsonb_agg(case when e->>'id' in ('dining', 'cfan') and (e->>'x')::numeric = 8.8
                        then jsonb_set(e, '{x}', '8.2'::jsonb) else e end order by ord)
    into v_new
    from jsonb_array_elements(v_inc) with ordinality as t(e, ord);
  if v_new is distinct from v_inc then
    update public.home_layouts set included = v_new where id = 'duplex';
  end if;
end $mig$;

-- owners: copies still standing at the old spot of the layout move with it
update public.player_house_furniture
   set x = 8.2, updated_at = now()
 where layout = 'duplex'
   and furniture_key ~ '^own_(dining_6|fan_ceiling)(-[0-9]+)?$'
   and not stored
   and x = 8.8 and z = 6.4;

-- ---------------------------------------------------------------- 2. billboards off the road
update public.billboards b
   set x = v.nx, y = v.ny
  from (values
    ('ring_road',   557::numeric, 468::numeric, 582.5::numeric, 460::numeric),
    ('ramat_park',  694, 398, 689, 387.5),
    ('sapele_road', 557, 672, 566.5, 673),
    ('ugbowo',      470, 148, 484, 170.5),
    ('akpakpava',   596, 425, 594, 421.5),
    ('uselu',       448, 250, 442.5, 259),
    ('new_benin',   608, 343, 615.5, 350.5)
  ) as v(id, ox, oy, nx, ny)
 where b.id = v.id and b.x = v.ox and b.y = v.oy;

notify pgrst, 'reload schema';
