-- Owner: trying for a baby is free (both must still say yes), and the baby arrives about a week later.
-- Moves the live settings only while they still hold the first defaults (an admin's own number is never overwritten). Idempotent.
update public.game_config set value = '0'::jsonb where key = 'kids.try_cost_each' and value in ('5000'::jsonb, '"5000"'::jsonb);
update public.game_config set value = '7'::jsonb where key = 'kids.pregnancy_days' and value in ('3'::jsonb, '"3"'::jsonb);
notify pgrst, 'reload schema';
