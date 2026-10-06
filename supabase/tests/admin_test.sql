-- L1 (20261006000100_real_time.sql): this file pins the pre-L1 behaviour (accelerated clock +
-- game-minute durations); time_test.sql covers the real clock and short actions. Rolled back.
update game_config set value = '"accelerated"' where key = 'clock.mode';
update game_config set value = '"game_minutes"' where key = 'action.mode';

-- Admin tests (V1-7): every admin RPC refuses non-admins; config set validates kind/min/max,
-- writes config_audit, keeps the game_config triggers (epoch, force_next); set_many is atomic;
-- revert; table upserts whitelist columns/types and audit; grant/take money via the ledger;
-- ban / mute / admin toggles incl. last-admin guard; stats shape; audit list; chat reports;
-- admin_claim (listed vs unlisted email); admin.* config hidden from players.
-- Run (migrations applied): bash scripts/sql-test.sh -- supabase/tests/admin_test.sql
-- Rolled back at the end.

create or replace function pg_temp.ad_hint(p_sql text, p_hint text) returns text
language plpgsql as $$
declare v_h text; v_m text;
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    get stacked diagnostics v_h = pg_exception_hint, v_m = message_text;
    if v_h is distinct from p_hint then
      raise exception 'TEST FAILED: [%] expected hint "%", got "%" (%)', p_sql, p_hint, v_h, sqlerrm;
    end if;
    return v_m;
  end;
  raise exception 'TEST FAILED: [%] expected hint "%" but it succeeded', p_sql, p_hint;
end $$;

create or replace function pg_temp.ad_u(p_name text) returns uuid
language sql as $$ select current_setting('adtest.' || p_name)::uuid $$;

create or replace function pg_temp.ad_make(p_name text, p_email text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(p_email);
begin
  perform set_config('adtest.' || lower(p_name), v::text, true);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  return v;
end $$;

-- Setup: demote every existing admin inside this rolled-back transaction so counts are exact.
do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  update profiles set is_admin = false where is_admin;
  update game_config set value = '"boss@admin.bl, Owner2@Admin.bl"' where key = 'admin.bootstrap_emails';
  perform pg_temp.ad_make('AdBoss', 'boss@admin.bl');
  perform pg_temp.ad_make('AdPlayer', 'player@admin.bl');
  perform pg_temp.ad_make('AdOther', 'other@admin.bl');
end $$;

-- 1. config seed + privileges -------------------------------------------------------------
do $$ begin
  perform pg_temp.assert((select kind from game_config where key = 'admin.bootstrap_emails') = 'text', 'bootstrap key seeded');
  perform pg_temp.assert(not has_function_privilege('anon', 'public.admin_config_set(text, jsonb)', 'execute'), 'anon cannot call');
  perform pg_temp.assert(has_function_privilege('authenticated', 'public.admin_stats()', 'execute'), 'authenticated may call (guarded)');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_admin_guard()', 'execute'), 'helper revoked');
  perform pg_temp.assert(not has_function_privilege('authenticated', 'public.bl_admin_config_apply(uuid, text, jsonb)', 'execute'), 'apply revoked');
  raise notice 'admin 1 OK: seed + privileges';
end $$;

-- 2. admin.* config is hidden from players (RLS) -------------------------------------------
do $$ begin perform pg_temp.login(pg_temp.ad_u('adplayer')); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert(not exists (select 1 from game_config where key like 'admin.%'), 'players cannot read admin.* keys');
  perform pg_temp.assert(exists (select 1 from game_config where key = 'origin.nepo_pct'), 'players still read normal keys');
end $$;
reset role;
set local role anon;
do $$ begin
  perform pg_temp.assert(not exists (select 1 from game_config where key like 'admin.%'), 'anon cannot read admin.* keys');
  perform pg_temp.assert((select count(*) from game_config) > 100, 'anon reads the rest');
end $$;
reset role;
do $$ begin raise notice 'admin 2 OK: admin.* hidden'; end $$;

-- 3. every admin RPC refuses non-admins ---------------------------------------------------
do $$
declare s text; v_other uuid := pg_temp.ad_u('adother');
begin
  perform pg_temp.login(pg_temp.ad_u('adplayer'));
  foreach s in array array[
    'select admin_config_list()',
    'select admin_config_set(''origin.nepo_pct'', ''50'')',
    'select admin_config_set_many(''{"origin.nepo_pct": 50}'')',
    'select admin_config_revert(1)',
    'select admin_table_rows(''items'')',
    'select admin_row_upsert(''items'', ''{"id":"laptop","price":1}'')',
    'select admin_players('''', 10, 0)',
    format('select admin_player_detail(%L)', v_other),
    format('select admin_grant_money(%L, ''cash'', 1000, ''x'')', v_other),
    format('select admin_ban(%L, true, ''x'')', v_other),
    format('select admin_mute(%L, 10)', v_other),
    format('select admin_set_admin(%L, true)', v_other),
    format('select admin_set_origin(%L, ''nepo'', false)', v_other),
    'select admin_stats()',
    'select admin_audit_list(10)',
    'select admin_chat_reports(true)',
    'select admin_chat_hide(1, true)'
  ] loop
    perform pg_temp.ad_hint(s, 'not_admin');
  end loop;
  raise notice 'admin 3 OK: non-admins refused (17 RPCs)';
end $$;

-- 4. admin_claim ---------------------------------------------------------------------------
do $$
declare r jsonb; m text;
begin
  -- unlisted email
  perform pg_temp.login(pg_temp.ad_u('adplayer'));
  m := pg_temp.ad_hint('select admin_claim()', 'not_listed');
  perform pg_temp.assert(not (select is_admin from profiles where id = pg_temp.ad_u('adplayer')), 'unlisted stays non-admin');
  -- no profile yet
  perform pg_temp.login(pg_temp.new_user('owner2@admin.bl'));
  perform pg_temp.ad_hint('select admin_claim()', 'no_profile');
  -- listed email (list compare is case/space-insensitive)
  perform pg_temp.login(pg_temp.ad_u('adboss'));
  r := admin_claim();
  perform pg_temp.assert((r->>'is_admin')::boolean, 'claim ok');
  perform pg_temp.assert((select is_admin from profiles where id = pg_temp.ad_u('adboss')), 'boss is admin');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'admin_claim' and target_user = pg_temp.ad_u('adboss')), 'claim audited');
  r := admin_claim();
  perform pg_temp.assert(r->>'message' like 'You are already%', 'second claim is a no-op');
  -- a banned listed player cannot claim
  update profiles set banned = true where id = pg_temp.ad_u('adother');
  update game_config set value = '"boss@admin.bl,other@admin.bl"' where key = 'admin.bootstrap_emails';
  perform pg_temp.login(pg_temp.ad_u('adother'));
  perform pg_temp.ad_hint('select admin_claim()', 'banned');
  update profiles set banned = false where id = pg_temp.ad_u('adother');
  update game_config set value = '"boss@admin.bl"' where key = 'admin.bootstrap_emails';
  raise notice 'admin 4 OK: admin_claim';
end $$;

-- 5. config set: kinds, ranges, audit, triggers --------------------------------------------
do $$
declare r jsonb; v_old jsonb; v_aud bigint; v_list jsonb;
begin
  perform pg_temp.login(pg_temp.ad_u('adboss'));
  v_list := admin_config_list();
  perform pg_temp.assert(jsonb_array_length(v_list) = (select count(*) from game_config), 'list has every row');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(v_list) e where e->>'key' = 'admin.bootstrap_emails'), 'admins see admin.*');
  perform pg_temp.assert((select e ? 'kind' and e ? 'min' and e ? 'max' and e ? 'label' and e ? 'prev_value'
                            from jsonb_array_elements(v_list) e where e->>'key' = 'origin.nepo_pct'), 'list metadata');

  v_old := (select value from game_config where key = 'origin.nepo_pct');
  r := admin_config_set('origin.nepo_pct', '25');
  perform pg_temp.assert((r->>'changed')::boolean and (select value from game_config where key = 'origin.nepo_pct') = '25', 'percent saved');
  perform pg_temp.assert((select updated_by from game_config where key = 'origin.nepo_pct') = pg_temp.ad_u('adboss'), 'updated_by set');
  select id into v_aud from config_audit where key = 'origin.nepo_pct' order by id desc limit 1;
  perform pg_temp.assert((select old_value = v_old and new_value = '25' and admin_id = pg_temp.ad_u('adboss')
                            from config_audit where id = v_aud), 'config audit row');
  r := admin_config_set('origin.nepo_pct', '25');
  perform pg_temp.assert(not (r->>'changed')::boolean, 'same value = no change');
  perform pg_temp.assert((select count(*) from config_audit where key = 'origin.nepo_pct' and id > v_aud) = 0, 'no audit for no-op');

  perform pg_temp.ad_hint('select admin_config_set(''origin.nepo_pct'', ''101'')', 'out_of_range');
  perform pg_temp.ad_hint('select admin_config_set(''origin.nepo_pct'', ''-1'')', 'out_of_range');
  perform pg_temp.ad_hint('select admin_config_set(''origin.nepo_pct'', ''"10"'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_config_set(''origin.nepo_pct'', ''null'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_config_set(''time.real_seconds_per_game_minute'', ''0.05'')', 'out_of_range');
  perform pg_temp.ad_hint('select admin_config_set(''bank.transfer_fee'', ''50.5'')', 'bad_value');   -- naira = whole
  perform pg_temp.ad_hint('select admin_config_set(''rent.enabled'', ''1'')', 'bad_value');           -- bool
  perform pg_temp.ad_hint('select admin_config_set(''clock.epoch'', ''5'')', 'bad_value');             -- text
  perform pg_temp.ad_hint('select admin_config_set(''nope.key'', ''5'')', 'no_key');
  r := admin_config_set('time.real_seconds_per_game_minute', '1.5');
  perform pg_temp.assert((select value from game_config where key = 'time.real_seconds_per_game_minute') = '1.5', 'decimal number saved');
  r := admin_config_set('rent.enabled', 'false');
  r := admin_config_set('rent.enabled', 'true');                -- rent switch trigger runs fine
  perform pg_temp.assert((select value from game_config where key = 'rent.enabled') = 'true', 'bool saved');

  -- existing triggers still enforced
  begin
    perform admin_config_set('clock.epoch', '"not a date"');
    raise exception 'TEST FAILED: bad epoch accepted';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    perform pg_temp.assert(sqlerrm like 'Clock epoch must be%', 'epoch trigger: ' || sqlerrm);
  end;
  begin
    perform admin_config_set('origin.force_next', '"royal"');
    raise exception 'TEST FAILED: bad force_next accepted';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
    perform pg_temp.assert(sqlerrm like 'origin.force_next must be%', 'force_next trigger: ' || sqlerrm);
  end;
  r := admin_config_set('origin.force_next', '"nepo"');
  perform pg_temp.assert((select value from game_config where key = 'origin.force_next') = '"nepo"', 'force_next ok');

  -- set_many is all-or-nothing
  begin
    perform admin_config_set_many('{"origin.nepo_pct": 30, "crime.npc_base_pct": 500}');
    raise exception 'TEST FAILED: set_many accepted a bad value';
  exception when others then
    if sqlerrm like 'TEST FAILED%' then raise; end if;
  end;
  perform pg_temp.assert((select value from game_config where key = 'origin.nepo_pct') = '25', 'set_many rolled back');
  r := admin_config_set_many('{"origin.nepo_pct": 30, "crime.npc_base_pct": 7}');
  perform pg_temp.assert((r->>'changed')::int = 2, 'set_many saved 2');

  -- revert to previous via audit
  select id into v_aud from config_audit where key = 'origin.nepo_pct' order by id desc limit 1;
  r := admin_config_revert(v_aud);
  perform pg_temp.assert((select value from game_config where key = 'origin.nepo_pct') = '25', 'reverted to 25');
  perform pg_temp.assert((select prev_value from jsonb_to_recordset(admin_config_list()) as x(key text, prev_value jsonb)
                           where key = 'origin.nepo_pct') = '30', 'prev_value from audit');
  raise notice 'admin 5 OK: config set, validation, triggers, set_many, revert';
end $$;

-- 6. content tables -----------------------------------------------------------------------
do $$
declare r jsonb; v_price bigint; n int;
begin
  perform pg_temp.login(pg_temp.ad_u('adboss'));
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('items')) = (select count(*) from items), 'items rows');
  perform pg_temp.assert(jsonb_array_length(admin_table_rows('chat_banned_words')) > 0, 'banned words readable for admins');
  perform pg_temp.ad_hint('select admin_table_rows(''profiles'')', 'bad_table');
  perform pg_temp.ad_hint('select admin_row_upsert(''profiles'', ''{"id":"x","cash":1}'')', 'bad_table');

  -- update
  n := (select count(*) from admin_audit);
  r := admin_row_upsert('items', '{"id":"laptop","price":47000,"sold_at":["wifi_joint"],"effects":{}}');
  perform pg_temp.assert((select price from items where id = 'laptop') = 47000, 'price updated');
  perform pg_temp.assert((select sold_at from items where id = 'laptop') = '{wifi_joint}', 'sold_at updated');
  perform pg_temp.assert((r->'row'->>'price')::bigint = 47000, 'returns row');
  perform pg_temp.assert((select count(*) from admin_audit) = n + 1
                         and (select action from admin_audit order by id desc limit 1) = 'row_update', 'upsert audited');
  perform pg_temp.assert((select data->'old'->>'price' from admin_audit order by id desc limit 1) is not null, 'old row in audit');

  -- whitelist + types
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","bogus":1}'')', 'bad_column');
  perform pg_temp.ad_hint('select admin_row_upsert(''locations'', ''{"id":"oba_market","x":1}'')', 'bad_column');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","price":"cheap"}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","price":-5}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","price":5.5}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","effects":[1]}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","sold_at":["mars"]}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"id":"laptop","resale_pct":150}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''items'', ''{"price":5}'')', 'bad_value');            -- no pk
  perform pg_temp.ad_hint('select admin_row_upsert(''locations'', ''{"id":"oba_market","risk":2}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''start_homes'', ''{"id":"uniben_hostel","allowed_origins":["royal"]}'')', 'bad_value');
  perform pg_temp.ad_hint('select admin_row_upsert(''start_homes'', ''{"id":"uniben_hostel","location_id":"mars"}'')', 'bad_value'); -- FK
  perform pg_temp.assert((select price from items where id = 'laptop') = 47000, 'bad writes changed nothing');

  -- no insert where not allowed
  perform pg_temp.ad_hint('select admin_row_upsert(''locations'', ''{"id":"new_place","name":"X"}'')', 'no_insert');
  perform pg_temp.ad_hint('select admin_row_upsert(''origin_tiers'', ''{"id":"royal","name":"Royal"}'')', 'no_insert');

  -- inserts
  r := admin_row_upsert('traits', '{"id":"night_owl","name":"Night owl","emoji":"🦉","description":"Loves the night.","effects":{},"sort":99,"active":true}');
  perform pg_temp.assert(exists (select 1 from traits where id = 'night_owl'), 'trait inserted');
  perform pg_temp.assert((select action from admin_audit order by id desc limit 1) = 'row_insert', 'insert audited');
  r := admin_row_upsert('traits', '{"id":"night_owl","active":false}');
  perform pg_temp.assert(not (select active from traits where id = 'night_owl'), 'soft-disabled');
  r := admin_row_upsert('career_levels', '{"track_id":"tech","level":2,"title":"Junior Developer","pay_per_shift":9000,"requirements":{"item":"laptop"}}');
  perform pg_temp.assert((select title || pay_per_shift from career_levels where track_id = 'tech' and level = 2) = 'Junior Developer9000', 'level updated');
  r := admin_row_upsert('career_levels', '{"track_id":"tech","level":2,"xp_to_next":null}');
  perform pg_temp.assert((select xp_to_next from career_levels where track_id = 'tech' and level = 2) is null, 'nullable int ok');
  perform pg_temp.ad_hint('select admin_row_upsert(''career_levels'', ''{"track_id":"tech","level":2,"title":null}'')', 'bad_value');
  r := admin_row_upsert('chat_banned_words', '{"word":"zzbadword","active":true}');
  perform pg_temp.assert(exists (select 1 from chat_banned_words where word = 'zzbadword'), 'banned word added');
  perform pg_temp.ad_hint('select admin_row_upsert(''chat_banned_words'', ''{"word":"BAD WORD!"}'')', 'bad_value'); -- check constraint
  r := admin_row_upsert('locations', '{"id":"oba_market","risk":0.3,"cctv":true,"actions":["shop","chat"]}');
  perform pg_temp.assert((select risk from locations where id = 'oba_market') = 0.3, 'location risk');
  r := admin_row_upsert('activities', '{"id":"sleep","cost":0,"game_minutes":480,"effects":{"energy":90}}');
  perform pg_temp.assert((select game_minutes from activities where id = 'sleep') = 480, 'activity');
  r := admin_row_upsert('origin_tiers', '{"id":"nepo","tagline":"Dad dey.","perks":{"papa_allowance":true}}');
  perform pg_temp.assert((select tagline from origin_tiers where id = 'nepo') = 'Dad dey.', 'origin tier');
  raise notice 'admin 6 OK: content tables';
end $$;

-- 7. players: list, detail, money, ban, mute, admin --------------------------------------
do $$
declare r jsonb; v_p uuid := pg_temp.ad_u('adplayer'); v_b uuid := pg_temp.ad_u('adboss'); v_cash bigint;
begin
  perform pg_temp.login(v_b);
  r := admin_players('adplay', 10, 0);
  perform pg_temp.assert((r->>'total')::int = 1 and r->'rows'->0->>'username' = 'AdPlayer', 'search by name');
  perform pg_temp.assert((r->'rows'->0) ?& array['cash','bank','origin','job_id','location_id','created_at','last_seen','banned','is_admin','chat_muted_until'], 'row shape');
  r := admin_players('player@admin', 10, 0);
  perform pg_temp.assert((r->>'total')::int = 1, 'search by email');
  r := admin_players('', 2, 0);
  perform pg_temp.assert(jsonb_array_length(r->'rows') <= 2, 'limit');

  v_cash := (select cash from profiles where id = v_p);
  r := admin_grant_money(v_p, 'cash', 10000, 'launch gift');
  perform pg_temp.assert((select cash from profiles where id = v_p) = v_cash + 10000, 'grant added');
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v_p and reason = 'admin_grant' and delta = 10000
                                  and meta->>'note' = 'launch gift'), 'ledger admin_grant');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'grant_money' and target_user = v_p), 'grant audited');
  perform pg_temp.assert(exists (select 1 from events where user_id = v_p and kind = 'admin_money'), 'player notified');
  r := admin_grant_money(v_p, 'cash', -10000, 'oops');
  perform pg_temp.assert((select cash from profiles where id = v_p) = v_cash, 'take back');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''bank'', -999999999, '''')', v_p), 'insufficient_funds');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''wallet'', 5, '''')', v_p), 'bad_value');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''cash'', 0, '''')', v_p), 'bad_value');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''cash'', 5, '''')', gen_random_uuid()), 'no_player');

  -- Money format (20261006000300): trillion-scale grants, exact balance math, caps, formatting.
  v_cash := (select bank from profiles where id = v_p);
  r := admin_grant_money(v_p, 'bank', 1000000000000, 'one trillion');
  perform pg_temp.assert((select bank from profiles where id = v_p) = v_cash + 1000000000000, '₦1T grant added to bank');
  perform pg_temp.assert((r->>'balance')::bigint = v_cash + 1000000000000, '₦1T grant returns new balance');
  perform pg_temp.assert(r->>'message' like 'Added ₦1,000,000,000,000 (bank).%', '₦1T message full amount: ' || (r->>'message'));
  perform pg_temp.assert(exists (select 1 from ledger where user_id = v_p and account = 'bank' and delta = 1000000000000
                                  and balance_after = v_cash + 1000000000000), '₦1T ledger row + balance_after');
  r := admin_grant_money(v_p, 'bank', 500000000000, '');
  r := admin_grant_money(v_p, 'bank', -250000000001, '');
  perform pg_temp.assert((select bank from profiles where id = v_p) = v_cash + 1249999999999, '1T + 0.5T - 250,000,000,001 exact');
  r := admin_grant_money(v_p, 'bank', -1249999999999, '');
  perform pg_temp.assert((select bank from profiles where id = v_p) = v_cash, 'taken back to the start balance');
  r := admin_grant_money(v_p, 'cash', 1000000000000000, 'max grant');   -- ₦1Q default cap is allowed
  r := admin_grant_money(v_p, 'cash', -1000000000000000, '');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''cash'', 1000000000000001, '''')', v_p), 'too_big');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''cash'', -1000000000000001, '''')', v_p), 'too_big');
  update game_config set value = '9000000000000000' where key = 'admin.grant_max';
  r := admin_grant_money(v_p, 'cash', 8000000000000000, '');
  perform pg_temp.ad_hint(format('select admin_grant_money(%L, ''cash'', 1000000000000000, '''')', v_p), 'too_big'); -- past ₦9Q
  r := admin_grant_money(v_p, 'cash', -8000000000000000, '');
  update game_config set value = '1000000000000000' where key = 'admin.grant_max';
  perform pg_temp.assert(bl_naira(1250000000000) = '₦1,250,000,000,000', 'bl_naira trillions');
  perform pg_temp.assert(bl_naira(2500000000000000000) = '₦2,500,000,000,000,000,000', 'bl_naira past quadrillion (old mask printed #)');
  perform pg_temp.assert(bl_naira(-500) = '-₦500' and bl_naira(0) = '₦0' and bl_naira(999) = '₦999', 'bl_naira small + negative');
  perform pg_temp.assert(bl_naira_short(950) = '₦950' and bl_naira_short(12500) = '₦12.5K' and bl_naira_short(1234567) = '₦1.2M'
                         and bl_naira_short(3400000000) = '₦3.4B' and bl_naira_short(1100000000000) = '₦1.1T'
                         and bl_naira_short(2000000000000000) = '₦2Q' and bl_naira_short(999999) = '₦999K'
                         and bl_naira_short(2500000000000000000) = '₦2,500Q' and bl_naira_short(-12500) = '-₦12.5K', 'bl_naira_short scale');

  r := admin_player_detail(v_p);
  perform pg_temp.assert(r ?& array['profile','ledger','inventory','audit'], 'detail shape');
  perform pg_temp.assert(r->'profile'->>'email' = 'player@admin.bl', 'detail email');
  perform pg_temp.assert(jsonb_array_length(r->'ledger') >= 2 and r->'ledger'->0->>'reason' = 'admin_grant', 'recent ledger newest first');

  -- ban
  r := admin_ban(v_p, true, 'spam');
  perform pg_temp.assert((select banned from profiles where id = v_p), 'banned');
  perform pg_temp.ad_hint(format('select admin_ban(%L, true, '''')', v_b), 'self');
  perform pg_temp.login(v_p);
  perform pg_temp.ad_hint('select chat_send(''hello'')', 'banned');
  perform pg_temp.login(v_b);
  r := admin_ban(v_p, false, '');
  perform pg_temp.assert(not (select banned from profiles where id = v_p), 'unbanned');
  perform pg_temp.assert((select count(*) from admin_audit where target_user = v_p and action in ('ban','unban')) = 2, 'ban audited');

  -- mute
  r := admin_mute(v_p, 30);
  perform pg_temp.assert((select chat_muted_until from profiles where id = v_p) > bl_now() + interval '29 minutes', 'muted 30 min');
  r := admin_mute(v_p, 0);
  perform pg_temp.assert((select chat_muted_until from profiles where id = v_p) is null, 'unmuted');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'mute' and target_user = v_p)
                         and exists (select 1 from admin_audit where action = 'unmute' and target_user = v_p), 'mute audited');

  -- admin toggles + last-admin guard
  perform pg_temp.ad_hint(format('select admin_set_admin(%L, false)', v_b), 'last_admin');
  r := admin_set_admin(v_p, true);
  perform pg_temp.assert((select is_admin from profiles where id = v_p), 'made admin');
  r := admin_set_admin(v_b, false);                -- not last any more: may step down
  perform pg_temp.assert(not (select is_admin from profiles where id = v_b), 'stepped down');
  perform pg_temp.ad_hint('select admin_stats()', 'not_admin');   -- and lost access at once
  perform pg_temp.login(v_p);
  r := admin_set_admin(v_b, true);
  perform pg_temp.login(v_b);
  r := admin_set_admin(v_p, false);
  perform pg_temp.assert((select count(*) from profiles where is_admin) = 1, 'one admin left');
  -- a banned admin is not an admin
  update profiles set is_admin = true, banned = true where id = v_p;
  perform pg_temp.login(v_p);
  perform pg_temp.ad_hint('select admin_stats()', 'not_admin');
  update profiles set is_admin = false, banned = false where id = v_p;

  -- set origin (reused RPC) works for admins
  perform pg_temp.login(v_b);
  r := admin_set_origin(v_p, 'nepo', true);
  perform pg_temp.assert((select origin from profiles where id = v_p) = 'nepo', 'origin set');
  raise notice 'admin 7 OK: players';
end $$;

-- 8. stats, audit list, chat reports ------------------------------------------------------
do $$
declare r jsonb; v_msg bigint; v_p uuid := pg_temp.ad_u('adplayer'); v_o uuid := pg_temp.ad_u('adother');
begin
  -- a reported chat message
  update profiles set location_id = 'oba_market', created_at = bl_now() - interval '1 day' where id in (v_p, v_o);
  perform pg_temp.login(v_p);
  v_msg := (chat_send('buy my fake watches')->>'id')::bigint;
  perform pg_temp.login(v_o);
  perform chat_report(v_msg, 'spam');

  perform pg_temp.login(pg_temp.ad_u('adboss'));
  r := admin_stats();
  perform pg_temp.assert(r ?& array['players','online','new_today','cash_total','bank_total','money_today','created_today',
                                    'destroyed_today','jobs','origins','richest','chat_today','reports_pending'], 'stats shape');
  perform pg_temp.assert((r->>'players')::int = (select count(*) from profiles), 'player count');
  perform pg_temp.assert((r->>'cash_total')::bigint = (select sum(cash) from profiles), 'cash total');
  perform pg_temp.assert(jsonb_array_length(r->'richest') <= 10, 'top 10');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r->'money_today') e where e->>'reason' = 'admin_grant'
                                  and (e->>'created')::bigint >= 10000 and (e->>'destroyed')::bigint >= 10000), 'money by reason');
  perform pg_temp.assert((r->>'reports_pending')::int >= 1, 'reports pending');
  perform pg_temp.assert((r->>'chat_today')::int >= 1, 'chat today');

  r := admin_chat_reports(true);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r) e where (e->>'id')::bigint = v_msg
                                  and (e->>'reports')::int = 1 and e->>'username' = 'AdPlayer'), 'report listed');
  perform admin_chat_hide(v_msg, true);
  r := admin_stats();
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(admin_chat_reports(false)) e where (e->>'id')::bigint = v_msg), 'hidden filtered');

  r := admin_audit_list(50);
  perform pg_temp.assert(jsonb_array_length(r) between 1 and 50, 'audit list size');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r) e where e->>'type' = 'config' and e->>'key' = 'origin.nepo_pct'), 'config rows merged');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(r) e where e->>'type' = 'admin' and e->>'action' = 'chat_hide'), 'admin rows merged');
  perform pg_temp.assert((r->0->>'created_at')::timestamptz = (select max((e->>'created_at')::timestamptz) from jsonb_array_elements(r) e), 'newest first');
  perform pg_temp.assert(jsonb_array_length(admin_audit_list(3)) = 3, 'limit');
  raise notice 'admin 8 OK: stats, audit list, chat reports';
end $$;

-- L1: back to the shipped defaults (real clock, short actions) for the next test file.
update game_config set value = '"real"' where key = 'clock.mode';
update game_config set value = '"short"' where key = 'action.mode';
