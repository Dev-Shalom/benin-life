-- Owner: a pair becomes a couple at flirt level 75, not 30 (it should take real effort). Idempotent.
-- Only moves the value while it is still the old default, so an admin's own number is never overwritten.
update public.game_config set value = '75'::jsonb where key = 'love.couple_level' and value in ('30'::jsonb, '"30"'::jsonb);
notify pgrst, 'reload schema';
