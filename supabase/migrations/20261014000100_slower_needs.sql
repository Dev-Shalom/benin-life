-- Owner (2026-10-14): needs still drop too fast. Halve the global needs speed (every need: hunger, energy,
-- fun, social, hygiene, bladder, stress). needs.decay_speed 1 -> 0.5: hunger now empties in ~50 real hours.
-- Guarded: only changes the row if it is still at the previous default, so an admin's own value is kept.
update public.game_config set value = '0.5'::jsonb
 where key = 'needs.decay_speed' and value = '1'::jsonb;
update public.game_config
   set description = 'Need hours per real hour (real clock). 0.5 = every need drops at half speed; lower = slower.'
 where key = 'needs.decay_speed';
notify pgrst, 'reload schema';
