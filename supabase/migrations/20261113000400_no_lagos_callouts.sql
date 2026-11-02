-- Owner rule: Benin Life never sends players to "Lagos". Bus callouts, travellers and the airport talk about Edo and Delta
-- towns instead. Real Benin road names (Lagos Road, the Lagos-Benin expressway) stay: they are Benin streets.
-- Idempotent: each line only changes while it still holds the old wording.
update public.npc_roster set lines = replace(lines, 'Lagos bus is loading!', 'Auchi bus is loading!'),
       pidgin = replace(pidgin, 'Lagos! Lagos! E remain one!', 'Warri! Warri! E remain one!')
 where id = 'agbero_nosa';
update public.npc_roster set lines = replace(lines, 'Road is clear to Lagos today.', 'Road is clear to Auchi today.') where id = 'driver_ehigie';
update public.npc_roster set lines = replace(lines, 'I am going to Lagos for business.', 'I am going to Warri for business.'),
       pidgin = replace(pidgin, 'which motor dey go Lagos?', 'which motor dey go Ekpoma?')
 where id = 'traveller_ikpomwosa';
update public.npc_roster set lines = replace(lines, 'Lagos in forty minutes', 'Abuja in fifty minutes') where id = 'airport_pilot';
update public.npc_roster set lines = replace(lines, 'The Lagos flight is boarding.', 'The Abuja flight is boarding.') where id = 'airport_porter';
update public.locations set blurb = replace(blurb, '"Lagos! Lagos! One chance remain!"', '"Auchi! Auchi! One chance remain!"') where id = 'uselu_park';
update public.locations set blurb = replace(blurb, 'Flights to Lagos and Abuja are coming soon.', 'Flights to Abuja and beyond are coming soon.') where id = 'benin_airport';
update public.place_zones set label = replace(label, 'Conductor: "Lagos! One chance remaining!"', 'Conductor: "Auchi! One chance remaining!"')
 where label like '%Lagos! One chance remaining!%';
notify pgrst, 'reload schema';
