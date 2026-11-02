-- Power (NEPA) Managing Director (docs/OFFICES.md, docs/POWER.md): the office waited for `power.*` levers. Now it has them, and it is switched on.
--   * One lever per area: that area's outage chance (power.outage_pct.<area>), a tight rail of 75 to 125 percent of the default (whole percent),
--     24 hours between moves, the office's usual cap on changes per day and total drift.
--   * The rail is the lever band, the same machinery as every other industry office (ind_set_lever checks the band, the cooldown, the
--     drift, the daily change cap and the freeze switches). The MD can never touch the blackout control, the fuel scarcity, fuel prices or
--     the black market: those stay with the admin.
--   * Nothing here touches profiles or loops over players. Idempotent (on conflict do nothing; the activation is a one-time update).

insert into public.ind_levers (id, office_id, config_key, label, blurb, unit, band_min, band_max, step, cooldown_hours, direction, effect, sort)
select 'power.' || substr(g.key, length('power.outage_pct.') + 1), 'nepa_md', g.key,
       'Outage chance, ' || coalesce(nullif(btrim(regexp_replace(g.label, '^Outage % - ', '')), ''), substr(g.key, length('power.outage_pct.') + 1)),
       'How much of the time NEPA takes light in this area. A cut lasts 15 to 60 real minutes.', 'percent',
       greatest(coalesce(g.min, 0), floor((g.value #>> '{}')::numeric * 0.75)), least(coalesce(g.max, 100), ceil((g.value #>> '{}')::numeric * 1.25)), 1, 24,
       'Lower means more light. Higher means more cuts, and more generators and inverters sold.',
       'The light will be off about {new} of the time in this area instead of {old}.',
       10 + row_number() over (order by g.key)::int
  from public.game_config g
 where g.key like 'power.outage\_pct.%' and jsonb_typeof(g.value) = 'number'
on conflict (id) do nothing;

update public.ind_offices
   set active = true,
       blurb = 'Runs the lights: how often each area of Benin loses power, inside a narrow band set by the owner. The blackout button, fuel scarcity and the black market are not yours.'
 where id = 'nepa_md' and not active and blurb like 'Runs the lights: how often each area has an outage.%';

notify pgrst, 'reload schema';
