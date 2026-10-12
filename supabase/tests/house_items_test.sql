-- H4 everything that comes with a house is movable + sellable (20261012001400_house_items_movable.sql). Rolled back.
-- Run (migrations applied):  bash scripts/sql-test.sh -- supabase/tests/house_items_test.sql
-- Groups: 1 an existing duplex player gets owned copies of the built-ins at valid spots (backfill) · 2 move / rotate /
-- store them · 3 sell: included % for came-with-house copies, resale % for bought ones, key renumbering, cap ·
-- 4 starter pieces sell too · 5 a new home's pieces once per move, no re-grant, move -> sell never profits (every
-- tier) · 6 architecture stays fixed, server validation unchanged · 7 a sold / stored piece stops giving its bonus.
create or replace function pg_temp.hint_of(p_sql text) returns text
language plpgsql as $$
declare v_h text;
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  get stacked diagnostics v_h = pg_exception_hint;
  return coalesce(nullif(v_h, ''), sqlerrm);
end $$;

create or replace function pg_temp.all_valid(p_uid uuid) returns boolean
language sql as $$
  select coalesce(bool_and(bl_furniture_check(h.owner_id, h.layout, h.furniture_key, h.x, h.z, h.rotation) is null), true)
    from player_house_furniture h where h.owner_id = p_uid and not h.stored
$$;

create or replace function pg_temp.resale(p_id text, p_pct numeric) returns bigint
language sql as $$ select (floor(price * p_pct / 100.0 / 100) * 100)::bigint from furniture where id = p_id $$;

-- included value of a layout at p_pct
create or replace function pg_temp.layout_value(p_layout text, p_pct numeric) returns bigint
language sql as $$
  select coalesce(sum(pg_temp.resale(i->>'furniture', p_pct)), 0)::bigint
    from home_layouts hl, jsonb_array_elements(hl.included) i where hl.id = p_layout
$$;

do $$
declare n uuid := pg_temp.new_user('h4_nepo@house.bl'); l uuid := pg_temp.new_user('h4_lapo@house.bl');
begin
  perform set_config('h4.n', n::text, true); perform set_config('h4.l', l::text, true);
  update game_config set value = 'true' where key in ('furniture.sell_enabled', 'house.move_enabled');
  update game_config set value = '45' where key = 'furniture.resale_pct';
  update game_config set value = '25' where key = 'furniture.included_resale_pct';
  update game_config set value = '75' where key = 'furniture.included_move_cap_pct';
  update game_config set value = '4' where key = 'house.move_in_weeks';
  update game_config set value = '1000000000' where key = 'receipts.min_amount';
  update furniture set active = true
   where id in (select i->>'furniture' from home_layouts, jsonb_array_elements(included) i);
  update furniture set active = true, buyable = true, max_qty = 4 where id = 'ac_split';
  update start_homes set weekly_rent = 8000 where id = 'mission_rd_mini_flat';
  update start_homes set weekly_rent = 25000 where id = 'gra_duplex';
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform pg_temp.login(n);
  perform create_profile_v2('H4_Nepo', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('gra_duplex');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(l);
  perform create_profile_v2('H4_Lapo', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set rent_owed = 0, busy_until = null, travel_to = null, location_id = home_location_id where id in (n, l);
end $$;

-- ---------- 1. existing duplex player: owned copies of the built-ins at valid spots ----------
do $$
declare n uuid := current_setting('h4.n')::uuid; v_inc int; it jsonb;
begin
  perform pg_temp.login(n);
  select jsonb_array_length(included) into v_inc from home_layouts where id = 'duplex';
  perform pg_temp.assert(v_inc = 14, 'duplex comes with 14 movable pieces: ' || v_inc);
  -- choosing the duplex as the first home gave them already
  perform pg_temp.assert((select jsonb_array_length(items) from player_house_grants where user_id = n and home_key = 'gra_duplex') = 14,
                         'first home grant on choose_start_home');
  -- simulate a player from before H4: no grant, no copies; then the migration's backfill call
  update player_furniture set qty = qty - house_qty, house_qty = 0
   where user_id = n and source <> 'starter' and qty > house_qty;
  delete from player_furniture where user_id = n and source = 'came_with_house' and qty = house_qty;
  update player_furniture set qty = 1, house_qty = 1 where user_id = n and source = 'starter';
  delete from player_house_furniture where owner_id = n;
  delete from player_house_grants where user_id = n;
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = n and furniture_id = 'chandelier'), 'pre-H4 state: no chandelier');
  perform pg_temp.assert(bl_house_items_grant(n, null) = 14, 'backfill gives 14 pieces');
  perform pg_temp.assert(bl_house_items_grant(n, null) = 0, 'second call gives nothing');
  perform bl_furniture_materialize(n);
  -- each included piece is a real owned copy that came with the house, standing where the house had it
  for it in select * from jsonb_array_elements((select included from home_layouts where id = 'duplex')) loop
    perform pg_temp.assert(exists (select 1 from player_furniture where user_id = n and furniture_id = it->>'furniture' and house_qty >= 1),
                           'owned + came with house: ' || (it->>'furniture'));
    perform pg_temp.assert(exists (select 1 from player_house_furniture h
                                    where h.owner_id = n and bl_furniture_id_of(h.furniture_key) = it->>'furniture' and not h.stored
                                      and h.layout = 'duplex' and h.x = (it->>'x')::numeric and h.z = (it->>'z')::numeric
                                      and h.rotation = (it->>'rot')::int),
                           'standing at its default spot: ' || it::text);
  end loop;
  perform pg_temp.assert((select qty from player_furniture where user_id = n and furniture_id = 'ac_split') = 2
                         and (select house_qty from player_furniture where user_id = n and furniture_id = 'ac_split') = 2, 'two ACs');
  perform pg_temp.assert((select source from player_furniture where user_id = n and furniture_id = 'chandelier') = 'came_with_house', 'source flag');
  -- the Nepo starter bed + the guest bed: both came with the house
  perform pg_temp.assert((select qty = 2 and house_qty = 2 from player_furniture where user_id = n and furniture_id = 'bed_double'), 'starter bed + guest bed');
  perform pg_temp.assert(pg_temp.all_valid(n), 'every standing piece passes the server check');
  -- allowance: first home = at most 75% of its move-in fee (4 x 25,000)
  perform pg_temp.assert((select allowance from player_house_grants where user_id = n and home_key = 'gra_duplex') = 75000,
                         'duplex allowance 75,000: ' || (select allowance from player_house_grants where user_id = n and home_key = 'gra_duplex'));
  perform pg_temp.assert((select value from player_house_grants where user_id = n and home_key = 'gra_duplex') = pg_temp.layout_value('duplex', 25), 'value recorded');
  raise notice 'ok 1: existing duplex player owns the built-ins at valid spots';
end $$;

-- ---------- 2. move / rotate / store ----------
do $$
declare n uuid := current_setting('h4.n')::uuid; r jsonb;
begin
  perform pg_temp.login(n);
  r := furniture_place('own_chandelier', 2.2, 5.0, 0);
  perform pg_temp.assert((select x = 2.2 and z = 5.0 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_chandelier'), 'chandelier moved');
  -- the dining set: nudge + quarter turn (2.1 x 1.7 -> 1.7 x 2.1)
  r := furniture_place('own_dining_6', 8.75, 6.5, 1);
  perform pg_temp.assert((r->>'rotation')::int = 1, 'dining rotated');
  r := furniture_store('own_washing_machine');
  perform pg_temp.assert((select stored from player_house_furniture where owner_id = n and furniture_key = 'own_washing_machine'), 'washer stored');
  r := furniture_place('own_washing_machine', 12.3, 0.4, 0);
  perform pg_temp.assert(not (select stored from player_house_furniture where owner_id = n and furniture_key = 'own_washing_machine'), 'washer back');
  -- the guest bed (copy 2 of bed_double) moves like any piece
  r := furniture_place('own_bed_double-2', 12.9, 8.6, 3);
  perform pg_temp.assert(r->>'furniture_key' = 'own_bed_double-2', 'guest bed moved');
  -- server validation unchanged: overlaps and doors are refused
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_place('own_dining_6', 6.0, 8.9, 0) $q$) = 'blocks_door', 'door zone refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_place('own_wardrobe_big', 6.9, 2.3, 0) $q$) = 'overlap', 'kitchen island refused');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_place('own_gen_firman', 5, 5, 0) $q$) = 'outside_home', 'generator stays outside');
  perform pg_temp.assert(pg_temp.all_valid(n), 'still valid');
  raise notice 'ok 2: move / rotate / store';
end $$;

-- ---------- 3. sell ----------
do $$
declare n uuid := current_setting('h4.n')::uuid; r jsonb; q jsonb; c0 bigint; v_left bigint;
begin
  perform pg_temp.login(n);
  update profiles set cash = 0, bank = 5000000 where id = n;
  -- quote: came with the house -> 25%, capped by what is left
  q := furniture_sell_quote('own_chandelier');
  perform pg_temp.assert((q->>'included')::boolean and (q->>'pct')::numeric = 25, 'included quote: ' || q::text);
  perform pg_temp.assert((q->>'full')::bigint = pg_temp.resale('chandelier', 25), 'full = 25% of the price');
  v_left := bl_house_resale_left(n);
  perform pg_temp.assert((q->>'payout')::bigint = least(pg_temp.resale('chandelier', 25), v_left), 'payout = min(full, left)');
  -- a bought extra AC is a normal copy: it takes key 1, the first came-with-house AC moves to the end with its spot
  r := furniture_buy('ac_split');
  perform pg_temp.assert(r->>'furniture_key' = 'own_ac_split', 'bought copy takes key 1: ' || r::text);
  perform pg_temp.assert((select x = 1.4 and z = 0.15 and not stored from player_house_furniture where owner_id = n and furniture_key = 'own_ac_split-3'),
                         'came-with AC moved to key 3 with its spot');
  perform pg_temp.assert((select stored from player_house_furniture where owner_id = n and furniture_key = 'own_ac_split'), 'bought AC in My items');
  perform pg_temp.assert(not (furniture_sell_quote('own_ac_split')->>'included')::boolean
                         and (furniture_sell_quote('own_ac_split')->>'pct')::numeric = 45, 'bought copy: 45%');
  perform pg_temp.assert((furniture_sell_quote('own_ac_split-2')->>'included')::boolean, 'copy 2 came with the house');
  -- sell the bought one: 45%, no allowance used, the last copy takes key 1 back
  select cash into c0 from profiles where id = n;
  r := furniture_sell('own_ac_split');
  perform pg_temp.assert((r->>'earned')::bigint = pg_temp.resale('ac_split', 45) and not (r->>'included')::boolean, 'bought AC 45%: ' || r::text);
  perform pg_temp.assert(bl_house_resale_left(n) = v_left, 'allowance untouched by a bought sale');
  perform pg_temp.assert((select qty = 2 and house_qty = 2 from player_furniture where user_id = n and furniture_id = 'ac_split'), 'two came-with ACs left');
  perform pg_temp.assert((select x = 1.4 and z = 0.15 from player_house_furniture where owner_id = n and furniture_key = 'own_ac_split'), 'AC back on key 1');
  -- sell the chandelier (came with the house)
  select cash into c0 from profiles where id = n;
  r := furniture_sell('own_chandelier');
  perform pg_temp.assert((r->>'included')::boolean and (r->>'earned')::bigint = (q->>'payout')::bigint, 'included sale pays the quote: ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = n) = c0 + (q->>'payout')::bigint, 'paid in cash');
  perform pg_temp.assert(not exists (select 1 from player_furniture where user_id = n and furniture_id = 'chandelier'), 'chandelier gone');
  perform pg_temp.assert(not exists (select 1 from player_house_furniture where owner_id = n and furniture_key = 'own_chandelier'), 'its row gone');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = n and reason = 'furniture_sell' and meta->>'included' = 'true'
                                   and meta->>'furniture' = 'chandelier'), 'ledger marks the included sale');
  perform pg_temp.assert(bl_house_resale_left(n) = v_left - (q->>'payout')::bigint, 'allowance used');
  -- sell came-with pieces until the allowance is used up, then the next one is refused
  while bl_house_resale_left(n) > 0 loop
    perform furniture_sell('own_dining_6');
    exit;
  end loop;
  while bl_house_resale_left(n) > 0 loop
    perform furniture_sell((select furniture_key from player_house_furniture h join player_furniture pf
                              on pf.user_id = h.owner_id and pf.furniture_id = bl_furniture_id_of(h.furniture_key)
                             where h.owner_id = n and bl_furniture_copy_of(h.furniture_key) > pf.qty - pf.house_qty
                             order by h.furniture_key limit 1));
  end loop;
  perform pg_temp.assert(bl_house_resale_left(n) = 0, 'allowance used up');
  perform pg_temp.assert((select sum(paid) from player_house_grants where user_id = n) = (select sum(allowance) from player_house_grants where user_id = n),
                         'paid = allowance');
  perform pg_temp.assert((select coalesce(sum(delta), 0) from ledger where user_id = n and reason = 'furniture_sell' and meta->>'included' = 'true')
                         = (select sum(allowance) from player_house_grants where user_id = n), 'never more than the allowances');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('own_washing_machine') $q$) = 'house_resale_used', 'used up -> refused');
  perform pg_temp.assert((furniture_sell_quote('own_washing_machine')->>'payout')::bigint = 0
                         and (furniture_sell_quote('own_washing_machine')->>'capped')::boolean, 'quote shows 0, capped');
  -- refused sales change nothing; the piece can still be stored
  perform furniture_store('own_washing_machine');
  raise notice 'ok 3: sell (included %%, bought %%, renumbering, cap)';
end $$;

-- ---------- 4. starter pieces sell too ----------
do $$
declare l uuid := current_setting('h4.l')::uuid; r jsonb; q jsonb;
begin
  perform pg_temp.login(l);
  perform bl_furniture_materialize(l);
  perform pg_temp.assert((select house_qty from player_furniture where user_id = l and furniture_id = 'foam_mat') = 1, 'starter mat came with the house');
  perform pg_temp.assert(exists (select 1 from player_house_grants where user_id = l and home_key = 'starter'
                                   and allowance = (select sum(pg_temp.resale(pf.furniture_id, 25)) from player_furniture pf
                                                     where pf.user_id = l and pf.source = 'starter')), 'starter allowance once per life');
  perform pg_temp.assert((select jsonb_array_length(items) from player_house_grants where user_id = l and home_key = 'ekenwan_face_me') = 0,
                         'face-me comes with nothing movable (shared compound)');
  q := furniture_sell_quote('own_foam_mat');
  perform pg_temp.assert((q->>'included')::boolean and (q->>'payout')::bigint = pg_temp.resale('foam_mat', 25), 'starter quote 25%: ' || q::text);
  r := furniture_sell('own_foam_mat');
  perform pg_temp.assert((r->>'earned')::bigint = pg_temp.resale('foam_mat', 25), 'no starter_piece refusal any more: ' || r::text);
  -- a bought extra stool + the starter stool: the starter is the highest copy
  update profiles set cash = 100000 where id = l;
  r := furniture_buy('stool');
  perform pg_temp.assert(r->>'furniture_key' = 'own_stool', 'bought stool takes key 1');
  perform pg_temp.assert((furniture_sell_quote('own_stool-2')->>'included')::boolean
                         and not (furniture_sell_quote('own_stool')->>'included')::boolean, 'starter stool is copy 2');
  raise notice 'ok 4: starter pieces sell';
end $$;

-- ---------- 5. moving: a new home's pieces once, no re-grant, never a profit ----------
do $$
declare l uuid := current_setting('h4.l')::uuid; r jsonb; v_q0 int; c0 bigint; b0 bigint; v_earn bigint := 0; v_k text; h record;
        v_pct numeric := 25; v_cap numeric := 75; v_weeks numeric := 4;
begin
  perform pg_temp.login(l);
  update profiles set cash = 0, bank = 1000000, rent_owed = 0 where id = l;
  select cash + bank into b0 from profiles where id = l;
  r := house_move('mission_rd_mini_flat');
  perform pg_temp.assert((r->>'came_with')::int = 5, 'the mini-flat comes with 5 pieces: ' || r::text);
  perform pg_temp.assert(pg_temp.all_valid(l), 'all valid after the move');
  perform pg_temp.assert((select allowance from player_house_grants where user_id = l and home_key = 'mission_rd_mini_flat')
                         = least(pg_temp.layout_value('flat', v_pct), floor(32000 * v_cap / 100)::bigint), 'flat allowance capped at 75% of 32,000');
  perform pg_temp.assert(exists (select 1 from player_house_furniture where owner_id = l and furniture_key = 'own_dining_4'
                                   and x = 7.6 and z = 4.7 and not stored), 'dining set at its spot');
  -- no re-grant: calling again (or any furniture action) gives nothing more
  select qty into v_q0 from player_furniture where user_id = l and furniture_id = 'ac_split';
  perform pg_temp.assert(bl_house_items_grant(l, 32000) = 0, 'no second grant');
  perform bl_furniture_materialize(l);
  perform pg_temp.assert((select qty from player_furniture where user_id = l and furniture_id = 'ac_split') = v_q0, 'qty unchanged');
  -- sell everything that came with the flat: the move-in fee is never earned back
  for v_k in select h2.furniture_key from player_house_furniture h2 join player_furniture pf
               on pf.user_id = h2.owner_id and pf.furniture_id = bl_furniture_id_of(h2.furniture_key)
              where h2.owner_id = l and pf.source = 'came_with_house' loop
    begin
      r := furniture_sell(v_k);
      v_earn := v_earn + (r->>'earned')::bigint;
    exception when others then
      perform pg_temp.assert(sqlerrm not like 'TEST FAILED%', sqlerrm);
    end;
  end loop;
  -- (the starter allowance left from group 4 may top this up once per life; the flat itself adds at most 24,000)
  perform pg_temp.assert(v_earn <= 24000 + (select allowance - 0 from player_house_grants where user_id = l and home_key = 'starter'),
                         'earned from the flat: ' || v_earn);
  perform pg_temp.assert((select sum(paid) from player_house_grants where user_id = l and home_key = 'mission_rd_mini_flat') <= 24000, 'flat pays <= 24,000');
  -- can't go back to the face-me (no second chance at its pieces), and the flat grant can't repeat
  perform pg_temp.assert(pg_temp.hint_of($q$ select house_move('ekenwan_face_me') $q$) = 'old_home', 'no going back');
  -- move on to the duplex: its pieces once, allowance capped at 75% of 100,000
  update profiles set rent_owed = 0 where id = l;
  r := house_move('gra_duplex');
  perform pg_temp.assert((r->>'came_with')::int = 14, 'duplex: 14 pieces');
  perform pg_temp.assert((select allowance from player_house_grants where user_id = l and home_key = 'gra_duplex') = 75000, 'duplex allowance 75,000');
  perform pg_temp.assert((select count(*) from player_house_grants where user_id = l and home_key <> 'starter') = 3, 'one grant per home');
  perform pg_temp.assert(pg_temp.all_valid(l), 'all valid in the duplex');

  -- the rule for every tier: what moving in can add to the allowance is below the move-in fee
  for h in select s.id, s.weekly_rent, bl_home_layout_id(s.housing_id) as layout from start_homes s where s.active loop
    perform pg_temp.assert(least(pg_temp.layout_value(h.layout, v_pct), floor(h.weekly_rent * v_weeks * v_cap / 100)::bigint)
                           - (h.weekly_rent * v_weeks)::bigint < 0 or (h.weekly_rent = 0),
                           format('move -> sell must lose money at %s: value %s, fee %s', h.id, pg_temp.layout_value(h.layout, v_pct), h.weekly_rent * v_weeks));
    raise notice 'profit check %: fee %, pieces worth % at 25%%, max from them %, net %', h.id, (h.weekly_rent * v_weeks)::bigint,
      pg_temp.layout_value(h.layout, v_pct), least(pg_temp.layout_value(h.layout, v_pct), floor(h.weekly_rent * v_weeks * v_cap / 100)::bigint),
      least(pg_temp.layout_value(h.layout, v_pct), floor(h.weekly_rent * v_weeks * v_cap / 100)::bigint) - (h.weekly_rent * v_weeks)::bigint;
  end loop;
  -- and in practice: flat + duplex moves cost 132,000; everything sold from both homes paid back less
  for v_k in select h2.furniture_key from player_house_furniture h2 join player_furniture pf
               on pf.user_id = h2.owner_id and pf.furniture_id = bl_furniture_id_of(h2.furniture_key)
              where h2.owner_id = l and pf.source = 'came_with_house' order by h2.furniture_key desc loop
    begin
      r := furniture_sell(v_k);
      v_earn := v_earn + (r->>'earned')::bigint;
    exception when others then
      perform pg_temp.assert(sqlerrm not like 'TEST FAILED%', sqlerrm);
    end;
  end loop;
  perform pg_temp.assert((select sum(paid) from player_house_grants where user_id = l and home_key in ('mission_rd_mini_flat', 'gra_duplex')) < 132000,
                         'two moves never pay for themselves');
  raise notice 'ok 5: moving grants once, never profitable (earned %, moves cost 132000)', v_earn;
end $$;

-- ---------- 6. architecture stays fixed ----------
do $$
declare n uuid := current_setting('h4.n')::uuid;
begin
  perform pg_temp.login(n);
  perform pg_temp.assert(not exists (select 1 from home_layouts hl, jsonb_array_elements(hl.included) i
                                      where i->>'kind' in ('kitchen', 'island', 'stairs', 'toilet', 'sink', 'shower', 'bathtub',
                                                           'pit_toilet', 'bucket_bath', 'clothesline', 'stall', 'drum')), 'architecture never included');
  perform pg_temp.assert((select blocks @> '[[13.3,0.2,14.3,2.8]]'::jsonb and blocks @> '[[6.1,1.9,7.7,2.7]]'::jsonb
                                 and blocks @> '[[5.65,0.04,7.85,0.66]]'::jsonb from home_layouts where id = 'duplex'),
                         'staircase, island and fitted kitchen still block');
  perform pg_temp.assert(not (select blocks @> '[[7.75,5.55,9.85,7.25]]'::jsonb from home_layouts where id = 'duplex'), 'the dining set no longer blocks');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_place('stairs', 5, 5, 0) $q$) = 'fixed_furniture', 'staircase not movable');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_sell('island') $q$) = 'fixed_furniture', 'island not sellable');
  perform pg_temp.assert(pg_temp.hint_of($q$ select furniture_place('own_wardrobe_big', 13.8, 1.5, 1) $q$) = 'overlap', 'nothing on the stairs');
  -- shared compound things in the small homes stay part of the house
  perform pg_temp.assert((select included = '[]'::jsonb from home_layouts where id = 'face_me')
                         and (select included = '[]'::jsonb from home_layouts where id = 'hostel')
                         and (select included = '[]'::jsonb from home_layouts where id = 'self_contain'), 'small homes: nothing included');
  raise notice 'ok 6: architecture fixed';
end $$;

-- ---------- 7. a sold or stored piece stops giving its bonus ----------
do $$
declare m uuid := pg_temp.new_user('h4_bonus@house.bl'); v jsonb;
begin
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform pg_temp.login(m);
  perform create_profile_v2('H4_Bonus', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('gra_duplex');
  update profiles set rent_owed = 0, busy_until = null, travel_to = null, location_id = home_location_id where id = m;
  perform bl_furniture_materialize(m);
  v := bl_furniture_for(m, 'bathe');
  perform pg_temp.assert((v->'bonus'->>'hygiene')::numeric = 8, 'water heater gives bath +8: ' || v::text);
  v := bl_furniture_for(m, 'sleep');
  perform pg_temp.assert((v->'bonus'->>'energy')::numeric = 8, 'ACs give sleep +8: ' || v::text);
  -- sell the heater (allowance 75,000 covers its 40,000): the washer's +4 is what is left
  perform furniture_sell('own_water_heater');
  v := bl_furniture_for(m, 'bathe');
  perform pg_temp.assert((v->'bonus'->>'hygiene')::numeric = 4, 'heater sold -> washer +4: ' || v::text);
  -- store the washer: no bath bonus at all
  perform furniture_store('own_washing_machine');
  v := bl_furniture_for(m, 'bathe');
  perform pg_temp.assert(v->'bonus'->>'hygiene' is null, 'washer stored -> no bonus: ' || v::text);
  -- store both ACs: the ceiling fan's +3 is what is left for sleep
  perform furniture_store('own_ac_split');
  perform furniture_store('own_ac_split-2');
  v := bl_furniture_for(m, 'sleep');
  perform pg_temp.assert((v->'bonus'->>'energy')::numeric = 3, 'ACs stored -> fan +3: ' || v::text);
  raise notice 'ok 7: bonuses follow the pieces';
end $$;

do $$ begin raise notice 'house_items_test: all groups passed'; end $$;
