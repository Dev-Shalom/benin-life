-- P1-MAP: move every location pin to match real Benin City geography.
-- Source of truth: docs/MAP_GEO.md ("Corrected map positions"; OSM + Wikipedia, 2026-10-05).
-- Map space 1000x1000, north up, King's Square at (500,500), distances compressed radially.
-- bronze_tech_hub (535,190) is created by its Phase 2 owner, so it is not updated here.
-- Two small nudges from the MAP_GEO.md table so pins and labels never collide on phones:
--   ring_road_pos 520,440 -> 540,452 (still on the ring, NE side between Mission and Akpakpava Rd);
--   police_hq     510,600 -> 510,604.
-- iguobazuwa_farm keeps remote_km = 22 (now off-map NW via Upper Siluko Rd).

update public.locations set x = 500, y = 500 where id = 'national_museum';
update public.locations set x = 448, y = 452 where id = 'oba_market';
update public.locations set x = 432, y = 512 where id = 'oba_palace';
update public.locations set x = 540, y = 452 where id = 'ring_road_pos';
update public.locations set x = 580, y = 470 where id = 'igun_street';
update public.locations set x = 480, y = 565 where id = 'mama_osas_buka';
update public.locations set x = 530, y = 405 where id = 'mission_rd_flats';
update public.locations set x = 560, y = 365 where id = 'mercy_clinic';
update public.locations set x = 595, y = 350 where id = 'new_benin_market';
update public.locations set x = 645, y = 375 where id = 'new_benin_pos';
update public.locations set x = 450, y = 270 where id = 'uselu_park';
update public.locations set x = 480, y = 235 where id = 'uselu_market';
update public.locations set x = 515, y = 290 where id = 'fresh_cut_salon';
update public.locations set x = 440, y = 165 where id = 'ubth';
update public.locations set x = 480, y = 125 where id = 'uniben';
update public.locations set x = 400, y = 135 where id = 'wifi_joint';
update public.locations set x = 455, y = 75 where id = 'back_gate_joint';
update public.locations set x = 390, y = 40 where id = 'oluku_park';
update public.locations set x = 680, y = 415 where id = 'ramat_park';
update public.locations set x = 700, y = 465 where id = 'oregbeni_market';
update public.locations set x = 820, y = 335 where id = 'aduwawa_park';
update public.locations set x = 860, y = 385 where id = 'aduwawa_room';
update public.locations set x = 665, y = 520 where id = 'third_east';
update public.locations set x = 595, y = 575 where id = 'ekiosa_market';
update public.locations set x = 640, y = 615 where id = 'baba_shrine';
update public.locations set x = 700, y = 665 where id = 'upper_sakponba';
update public.locations set x = 510, y = 604 where id = 'police_hq';
update public.locations set x = 470, y = 625 where id = 'bronze_bank';
update public.locations set x = 420, y = 650 where id = 'kingdom_lounge';
update public.locations set x = 450, y = 690 where id = 'gra_duplex';
update public.locations set x = 545, y = 640 where id = 'sapele_pos';
update public.locations set x = 560, y = 700 where id = 'santana_market';
update public.locations set x = 560, y = 770 where id = 'bronze_lounge';
update public.locations set x = 330, y = 615 where id = 'benin_airport';
update public.locations set x = 298, y = 562 where id = 'ekenwan_room';
update public.locations set x = 378, y = 378 where id = 'siluko_rd';
update public.locations set x = 40, y = 300 where id = 'iguobazuwa_farm';
