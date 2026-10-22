-- Owner: Godfather ticket prices up (Councillor 5B, Chairman 25B, Governor 50B) and a lower EFCC probe chance (25 % -> 10 %).
-- Both stay editable: Content -> Offices and Settings -> Politics. Idempotent.
update public.offices set ticket_price = 5000000000  where id = 'councillor';
update public.offices set ticket_price = 25000000000 where id = 'chairman';
update public.offices set ticket_price = 50000000000 where id = 'governor';
update public.game_config set value = '10'::jsonb where key = 'pol.ticket_probe_pct';
notify pgrst, 'reload schema';
