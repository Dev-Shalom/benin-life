-- P1-MAP geography tests. Run:
--   bash scripts/sql-test.sh supabase/migrations/20261004000100_core.sql supabase/migrations/20261004000200_core_seed.sql \
--     supabase/migrations/20261005000100_map_geo.sql -- supabase/tests/map_geo_test.sql
-- Checks every pin position from docs/MAP_GEO.md plus a few real-world sanity relations.

do $$
declare r record; n int;
begin
  -- 1. every location sits at its MAP_GEO.md position
  for r in select * from (values
    ('national_museum',500,500),
    ('oba_market',448,452),
    ('oba_palace',432,512),
    ('ring_road_pos',540,452),
    ('igun_street',580,470),
    ('mama_osas_buka',480,565),
    ('mission_rd_flats',530,405),
    ('mercy_clinic',560,365),
    ('new_benin_market',595,350),
    ('new_benin_pos',645,375),
    ('uselu_park',450,270),
    ('uselu_market',480,235),
    ('fresh_cut_salon',515,290),
    ('ubth',440,165),
    ('uniben',480,125),
    ('wifi_joint',400,135),
    ('back_gate_joint',455,75),
    ('oluku_park',390,40),
    ('ramat_park',680,415),
    ('oregbeni_market',700,465),
    ('aduwawa_park',820,335),
    ('aduwawa_room',860,385),
    ('third_east',665,520),
    ('ekiosa_market',595,575),
    ('baba_shrine',640,615),
    ('upper_sakponba',700,665),
    ('police_hq',510,604),
    ('bronze_bank',470,625),
    ('kingdom_lounge',420,650),
    ('gra_duplex',450,690),
    ('sapele_pos',545,640),
    ('santana_market',560,700),
    ('bronze_lounge',560,770),
    ('benin_airport',330,615),
    ('ekenwan_room',298,562),
    ('siluko_rd',378,378),
    ('iguobazuwa_farm',40,300),
    ('uniben_hostel',522,140),   -- R3a start home (UNIBEN hall, east side of campus)
    ('uselu_selfcon',420,228),   -- R3a start home (Uselu, west of Lagos Rd)
    ('bronze_tech_hub',535,190)  -- V1-3 workplace (Ugbowo tech cluster near UNIBEN, fictional)
  ) v(id, x, y) loop
    perform pg_temp.assert(exists (select 1 from locations l where l.id = r.id and l.x = r.x and l.y = r.y),
      format('%s should be at (%s,%s)', r.id, r.x, r.y));
  end loop;
  select count(*) into n from locations;
  perform pg_temp.assert(n = 40, format('expected 40 seeded locations, got %s', n));
  raise notice 'ok 1: all % pins at MAP_GEO.md positions', n;

  -- 2. real-world relations (north is up: smaller y = further north)
  perform pg_temp.assert((select y from locations where id = 'uniben') < (select y from locations where id = 'national_museum'), 'UNIBEN north of museum');
  perform pg_temp.assert((select y from locations where id = 'ubth') < (select y from locations where id = 'uselu_market'), 'UBTH north of Uselu');
  perform pg_temp.assert((select y from locations where id = 'oluku_park') < (select y from locations where id = 'uniben'), 'Oluku north of UNIBEN');
  perform pg_temp.assert((select x from locations where id = 'oba_palace') < 500, 'palace west of King''s Square');
  perform pg_temp.assert((select x from locations where id = 'siluko_rd') < 500 and (select y from locations where id = 'siluko_rd') < 500, 'Siluko Rd NW');
  perform pg_temp.assert((select x from locations where id = 'igun_street') > 500 and (select y from locations where id = 'igun_street') < 500, 'Igun Street ENE');
  perform pg_temp.assert((select x from locations where id = 'ramat_park') > (select x from locations where id = 'third_east'), 'Ramat east of Third East');
  perform pg_temp.assert((select x from locations where id = 'benin_airport') < 500 and (select y from locations where id = 'benin_airport') > 500, 'airport SW');
  perform pg_temp.assert((select y from locations where id = 'police_hq') > 500, 'police HQ south (GRA)');
  perform pg_temp.assert((select y from locations where id = 'santana_market') > (select y from locations where id = 'sapele_pos'), 'Santana further S on Sapele Rd');
  perform pg_temp.assert((select remote_km from locations where id = 'iguobazuwa_farm') = 22, 'farm remote_km unchanged');
  raise notice 'ok 2: real-world direction checks';

  -- 3. pins stay at least ~35 units apart so they never overlap on the map
  select count(*) into n from locations a join locations b on a.id < b.id
   where sqrt((a.x - b.x)^2 + (a.y - b.y)^2) < 34;
  perform pg_temp.assert(n = 0, format('%s pin pairs closer than 34 units', n));
  raise notice 'ok 3: no overlapping pins';

  -- 4. distances follow the new coordinates (km = dist/1000 * city_km_across)
  perform pg_temp.assert(abs(bl_distance_km('ekenwan_room', 'mama_osas_buka') - sqrt(182^2 + 3^2) / 1000 * 18) < 0.01, 'ekenwan -> buka km');
  perform pg_temp.assert(bl_distance_km('national_museum', 'uniben') > bl_distance_km('national_museum', 'uselu_market'), 'UNIBEN further than Uselu');
  perform pg_temp.assert(bl_distance_km('national_museum', 'iguobazuwa_farm') > 22, 'farm adds remote km');
  raise notice 'ok 4: distances';
  raise notice 'ALL MAP GEO TESTS PASSED';
end $$;
