-- E4 money sinks (20261019000400): this suite asserts exact balances and prices, so the new fees, tax, bills and VAT are pinned off here.
-- They are covered by money_sinks_test.sql.
update game_config set value = 'false' where key in ('economy.transfer_fees_enabled', 'economy.tax_enabled', 'economy.bills_enabled', 'economy.vat_enabled', 'economy.luxury_enabled');
-- W1 Wardrobe (20261010000100_wardrobe.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/wardrobe_test.sql
-- Groups: 1 brands + catalog · 2 buy charges once (bank first), ledger, ownership · 3 can't buy twice / no money
-- 4 outfits: unowned paid refused, free allowed, slots save + clear + default, everyday writes the avatar
-- 5 players can't write the tables directly · 6 wardrobe.enabled off refuses.
do $$
declare u uuid := pg_temp.new_user('wd_a@wardrobe.bl'); r jsonb; m text; v_bank bigint; v_cash bigint; n int;
begin
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(u);
  perform create_profile_v2('Wd_Ada', 'male', '{"gender":"male","v":2}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  perform set_config('wdtest.u', u::text, true);

  -- 1. brands
  perform pg_temp.assert(exists (select 1 from wardrobe_brands where id = 'benin_basics' and is_house and active), 'house brand exists');
  perform pg_temp.assert(not exists (select 1 from wardrobe_items i left join wardrobe_brands b on b.id = i.brand_id
                                     where i.active and (b.id is null or not b.active)), 'every active item has an active brand');
  perform pg_temp.assert((select count(*) from wardrobe_items where active) between 20 and 60, 'seeded catalog');
  r := wardrobe_state();
  perform pg_temp.assert((r->>'enabled')::boolean and jsonb_array_length(r->'brands') >= 4, 'state: enabled + brands');
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(r->'items') x where x->>'gender' = 'female'), 'state hides other-gender items');

  -- 2. buy: bank first, then cash; one ledger row per account; ownership recorded
  update profiles set bank = 10000, cash = 50000 where id = u;
  r := wardrobe_buy('bb_polo', '#2346a8');   -- 12,000: 10,000 bank + 2,000 cash
  select bank, cash into v_bank, v_cash from profiles where id = u;
  perform pg_temp.assert(v_bank = 0 and v_cash = 48000, 'charged bank then cash: ' || v_bank || '/' || v_cash);
  perform pg_temp.assert((select count(*) from ledger where user_id = u and reason = 'Boutique: Polo shirt') = 2, 'ledger rows');
  perform pg_temp.assert((select sum(delta) from ledger where user_id = u and reason = 'Boutique: Polo shirt') = -12000, 'ledger total');
  perform pg_temp.assert(exists (select 1 from player_wardrobe where user_id = u and item_id = 'bb_polo' and colour = '#2346a8'), 'owned');

  -- 3. can't buy twice; not enough money; wrong gender
  begin perform wardrobe_buy('bb_polo', null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'You already own%', 'no double buy: ' || coalesce(m, 'none'));
  perform pg_temp.assert((select cash from profiles where id = u) = 48000, 'not charged twice');
  begin perform wardrobe_buy('rr_agbada', null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'Not enough money%', 'too expensive: ' || coalesce(m, 'none'));
  begin perform wardrobe_buy('bo_heels', null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%isn''t made for your Sim%', 'gendered item: ' || coalesce(m, 'none'));

  -- 4. outfits
  begin perform wardrobe_set_outfit('party', '[{"item":"bo_agbada","colour":"#5aa7e0"}]'); m := null;
  exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'Buy the%', 'unowned paid item refused: ' || coalesce(m, 'none'));
  r := wardrobe_set_outfit('home', '[{"item":"bb_singlet","colour":"#7d828c"},{"item":"bb_joggers"},{"item":"bb_slippers"}]');
  perform pg_temp.assert(r->'patch'->'top'->>'s' = 'singlet' and r->'patch'->'top'->>'c' = '#7d828c'
                         and r->'patch'->'bottom'->>'c' = '#25232b' and r->'patch'->'shoes'->>'s' = 'slippers', 'free items allowed: ' || (r->>'patch'));
  r := wardrobe_set_outfit('work', '[{"item":"bb_polo","colour":"#f4f1ea"},{"item":"bb_jeans"}]');
  perform pg_temp.assert(r->'patch'->'top'->>'c' = '#f4f1ea', 'owned paid item allowed');
  begin perform wardrobe_set_outfit('work', '[{"item":"bb_tee"},{"item":"bb_polo"}]'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like 'One piece%', 'one per category');
  begin perform wardrobe_set_outfit('work', '[{"item":"bb_tee","colour":"#123456"}]'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%colour%', 'bad colour refused');
  begin perform wardrobe_set_outfit('club', '[]'); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%slot%', 'bad slot refused');
  r := wardrobe_set_outfit('sleep', null);
  perform pg_temp.assert(exists (select 1 from player_outfits where user_id = u and slot = 'sleep' and patch is null), 'default rule saved');
  perform pg_temp.assert((select count(*) from player_outfits where user_id = u) = 3, 'three slots saved');
  r := wardrobe_state();
  perform pg_temp.assert(r->'outfits'->'home'->'patch'->'top'->>'s' = 'singlet' and r->'outfits' ? 'sleep', 'state returns outfits');
  perform wardrobe_clear_slot('home');
  perform pg_temp.assert(not exists (select 1 from player_outfits where user_id = u and slot = 'home'), 'slot cleared');
  -- everyday is written into the avatar (portraits, chat); bags replace bags
  update profiles set avatar = avatar || '{"accessories":["watch","bag"]}' where id = u;
  perform wardrobe_buy('bb_backpack', null);
  perform wardrobe_set_outfit('everyday', '[{"item":"bb_polo","colour":"#1f8a55"},{"item":"bb_backpack","colour":"#7a1f33"}]');
  perform pg_temp.assert((select avatar->'top'->>'s' = 'polo' and avatar->'top'->>'c' = '#1f8a55' and avatar->>'accent' = '#7a1f33'
                                 and avatar->'accessories' = '["watch","backpack"]'::jsonb and avatar->>'gender' = 'male'
                          from profiles where id = u), 'everyday look written to avatar');
  begin perform wardrobe_set_outfit('everyday', null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m is not null, 'everyday has no default rule');

  -- 6. switch off
  update game_config set value = 'false' where key = 'wardrobe.enabled';
  begin perform wardrobe_buy('bb_wrapper', null); m := null; exception when others then m := sqlerrm; end;
  perform pg_temp.assert(m like '%boutique is closed%', 'off refuses buy');
  perform pg_temp.assert(not (wardrobe_state()->>'enabled')::boolean, 'state says off');
  update game_config set value = 'true' where key = 'wardrobe.enabled';
  raise notice 'ok: wardrobe rpcs';
end $$;

-- 5. Direct writes as the authenticated role are refused (reads are own-rows only).
do $$ begin perform pg_temp.login(current_setting('wdtest.u')::uuid); end $$;
set local role authenticated;
do $$
declare u uuid := current_setting('wdtest.u')::uuid; ok boolean;
begin
  perform pg_temp.assert((select count(*) from player_wardrobe) = 2, 'RLS: own wardrobe visible');
  ok := false; begin insert into player_wardrobe (user_id, item_id) values (u, 'rr_agbada'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'no direct insert into player_wardrobe');
  ok := false; begin insert into player_outfits (user_id, slot, items, patch) values (u, 'party', '[]', '{}'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'no direct insert into player_outfits');
  ok := false; begin update wardrobe_items set price = 0; exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'no direct update of wardrobe_items');
  ok := false; begin delete from player_outfits; exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'no direct delete of player_outfits');
  ok := false; begin perform bl_wardrobe_apply('{}', '{}'); exception when insufficient_privilege then ok := true; end;
  perform pg_temp.assert(ok, 'helpers not callable');
  raise notice 'ok: wardrobe direct writes refused';
end $$;
reset role;
