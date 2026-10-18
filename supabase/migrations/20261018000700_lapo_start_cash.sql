-- Owner request (18 Oct 2026): every new LAPO baby lands with ₦85,000 cash (was ₦5,000).
-- Only new players are affected; existing balances are untouched. Still editable in Admin → Settings → Origin.
update public.game_config set value = '85000'::jsonb where key = 'origin.lapo.start_cash';
notify pgrst, 'reload schema';
