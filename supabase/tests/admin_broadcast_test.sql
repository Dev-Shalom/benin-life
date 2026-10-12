-- A2 admin broadcast + mass gift (20261012001100_admin_broadcast.sql). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/admin_broadcast_test.sql
-- Groups: 1 grants + non-admin refused · 2 broadcast audiences (everyone / lapo / nepo / joined_after / online frozen)
-- + inbox + seen/dismissed + reach counts · 3 RLS (audience, expired, ended, targeted) · 4 gift pays each target once,
-- ledger narration in bank_history, recipients alert · 5 idempotency key · 6 caps + validation · 7 5k-player gift timing.
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

-- ---------- setup ----------
do $$
declare
  adm uuid := pg_temp.new_user('a2_admin@bc.bl');
  a uuid := pg_temp.new_user('a2_lapo@bc.bl');
  b uuid := pg_temp.new_user('a2_nepo@bc.bl');
  c uuid := pg_temp.new_user('a2_late@bc.bl');
begin
  perform set_config('a2.adm', adm::text, true); perform set_config('a2.a', a::text, true);
  perform set_config('a2.b', b::text, true); perform set_config('a2.c', c::text, true);
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm);
  perform create_profile_v2('A2_Admin', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('A2_Lapo', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"nepo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('A2_Nepo', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(c);
  perform create_profile_v2('A2_Late', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  -- everyone else in the local DB is "long ago" and offline; A is online, C joined "later"
  update profiles set created_at = now() - interval '30 days', last_seen = now() - interval '2 days';
  update profiles set last_seen = now() where id = a;
  update profiles set created_at = now() - interval '1 day' where id = c;
  update profiles set cash = 1000, bank = 500 where id in (a, b, c);
  delete from broadcasts;  -- start clean (rolled back): live rows from manual testing would change the inbox lists
  update game_config set value = '1000000' where key = 'admin.gift_max';
  update game_config set value = '20000000000' where key = 'admin.gift_total_max';
end $$;

-- ---------- 1. grants + non-admin refused ----------
do $$
declare v_rpc text;
begin
  foreach v_rpc in array array['broadcast_inbox()', 'broadcast_mark(bigint[],boolean)', 'admin_broadcast_preview(text,timestamptz,bigint)',
                               'admin_broadcast_send(text,text,text,text,timestamptz,boolean,timestamptz)',
                               'admin_gift_send(text,bigint,text,text,text,timestamptz,boolean,timestamptz)',
                               'admin_broadcast_list(integer)', 'admin_broadcast_end(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'anon blocked ' || v_rpc);
    perform pg_temp.assert((select prosecdef from pg_proc where oid = ('public.' || v_rpc)::regprocedure), 'secdef ' || v_rpc);
  end loop;
  foreach v_rpc in array array['bl_broadcast_targets(text,timestamptz)', 'bl_broadcast_check(text,timestamptz,text,timestamptz)',
                               'bl_broadcast_bump(bigint)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || v_rpc)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || v_rpc)::regprocedure, 'execute'), 'helper private ' || v_rpc);
  end loop;
  perform pg_temp.login(current_setting('a2.a')::uuid);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_send('Hi', 'Hello all', 'info', 'everyone', null, true, null)$q$) = 'not_admin', 'send refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('key-000001', 5000, 'cash', 'Free money', 'everyone', null, true, null)$q$) = 'not_admin', 'gift refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_preview('everyone', null, 5000)$q$) = 'not_admin', 'preview refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_list(10)$q$) = 'not_admin', 'list refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_end(1)$q$) = 'not_admin', 'end refused');
  perform pg_temp.assert(not exists (select 1 from ledger where reason = 'admin_gift' and user_id = current_setting('a2.a')::uuid), 'nothing paid');
  raise notice 'ok 1: grants + non-admin refused';
end $$;

-- ---------- 2. audiences + inbox + seen/dismissed ----------
do $$
declare
  adm uuid := current_setting('a2.adm')::uuid; a uuid := current_setting('a2.a')::uuid;
  b uuid := current_setting('a2.b')::uuid; c uuid := current_setting('a2.c')::uuid;
  r jsonb; v_all bigint; v_lapo bigint; v_nepo bigint; v_late bigint; v_on bigint; n bigint; v_ids bigint[];
begin
  perform pg_temp.login(adm);
  r := admin_broadcast_preview('everyone', null, 5000);
  perform pg_temp.assert((r->>'count')::bigint = (select count(*) from profiles where home_chosen and not banned)
                         and (r->>'total')::numeric = (r->>'count')::numeric * 5000, 'preview everyone ' || r::text);
  perform pg_temp.assert((admin_broadcast_preview('online', null, null)->>'count')::int = 1, 'preview online = A only');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_preview('martians', null, null)$q$) = 'bad_audience', 'bad audience');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_preview('joined_after', null, null)$q$) = 'bad_audience', 'joined_after needs date');

  v_all := (admin_broadcast_send('Welcome', 'Benin Life don land!', 'celebration', 'everyone', null, true, null)->>'id')::bigint;
  perform pg_temp.assert((select value #>> '{}' from game_config where key = 'broadcast.last_id')::bigint = v_all, 'last_id bumped');
  v_lapo := (admin_broadcast_send('LAPO gist', 'For LAPO babies', 'info', 'lapo', null, false, null)->>'id')::bigint;
  v_nepo := (admin_broadcast_send('Nepo gist', 'For Nepo babies', 'warning', 'nepo', null, true, null)->>'id')::bigint;
  v_late := (admin_broadcast_send('New here?', 'For new players', 'info', 'joined_after', now() - interval '7 days', true, null)->>'id')::bigint;
  r := admin_broadcast_send('Online now', 'Only who dey online', 'info', 'online', null, true, null);
  v_on := (r->>'id')::bigint;
  perform pg_temp.assert((r->>'count')::int = 1 and (select targeted from broadcasts where id = v_on), 'online frozen: ' || r::text);
  perform pg_temp.assert((select count(*) from broadcasts) >= 5 and (select count(*) from broadcast_reads where broadcast_id <> v_on) = 0,
                         'open audiences insert no per-player rows');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'broadcast' and (data->>'broadcast_id')::bigint = v_all), 'audited');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'broadcast' and url = '/admin/broadcast'), 'admin notified');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_broadcast_send(%L, %L)', 'Long', repeat('x', 501))) = 'too_long', '500 chars');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_send('', 'x')$q$) = 'bad_title', 'title');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_broadcast_send('T', 'x', 'loud')$q$) = 'bad_style', 'style');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_broadcast_send(%L, %L, %L, %L, null, true, %L)', 'T', 'x', 'info', 'everyone', now() - interval '1 hour')) = 'bad_expiry', 'expiry past');

  -- A (lapo, online, old): everyone + lapo + online
  perform pg_temp.login(a);
  select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) into v_ids from jsonb_array_elements(broadcast_inbox()->'rows') x;
  perform pg_temp.assert(v_ids = array[v_all, v_lapo, v_on], 'A inbox ' || v_ids::text);
  -- B (nepo, offline, old): everyone + nepo
  perform pg_temp.login(b);
  select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) into v_ids from jsonb_array_elements(broadcast_inbox()->'rows') x;
  perform pg_temp.assert(v_ids = array[v_all, v_nepo], 'B inbox ' || v_ids::text);
  -- C (lapo, joined 1 day ago, offline): everyone + lapo + joined_after; coming online later does not add "online"
  update profiles set last_seen = now() where id = c;
  perform pg_temp.login(c);
  select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) into v_ids from jsonb_array_elements(broadcast_inbox()->'rows') x;
  perform pg_temp.assert(v_ids = array[v_all, v_lapo, v_late], 'C inbox ' || v_ids::text);

  -- seen / dismissed; can't mark what isn't mine
  r := broadcast_mark(array[v_all, v_nepo, v_late], false);
  perform pg_temp.assert((r->>'marked')::int = 2, 'C marks only own: ' || r::text);
  perform broadcast_mark(array[v_all], true);
  r := (select x from jsonb_array_elements(broadcast_inbox()->'rows') x where (x->>'id')::bigint = v_all);
  perform pg_temp.assert((r->>'seen')::boolean and (r->>'dismissed')::boolean, 'C seen+dismissed ' || r::text);
  perform pg_temp.login(a);
  perform broadcast_mark(array[v_all, v_on], false);
  perform pg_temp.login(adm);
  r := (select x from jsonb_array_elements(admin_broadcast_list(50)->'rows') x where (x->>'id')::bigint = v_all);
  perform pg_temp.assert((r->>'seen_count')::int = 2 and (r->>'dismissed_count')::int = 1 and (r->>'live')::boolean
                         and (r->>'target_count')::int = (select count(*) from profiles where home_chosen and not banned), 'reach ' || r::text);
  r := (select x from jsonb_array_elements(admin_broadcast_list(50)->'rows') x where (x->>'id')::bigint = v_on);
  perform pg_temp.assert((r->>'seen_count')::int = 1 and (r->>'target_count')::int = 1, 'online reach ' || r::text);
  perform set_config('a2.all', v_all::text, true); perform set_config('a2.nepo', v_nepo::text, true);
  perform set_config('a2.on', v_on::text, true); perform set_config('a2.lapo', v_lapo::text, true);
  raise notice 'ok 2: audiences, inbox, seen/dismissed, reach';
end $$;

-- ---------- 3. RLS ----------
do $$
declare
  adm uuid := current_setting('a2.adm')::uuid; a uuid := current_setting('a2.a')::uuid; b uuid := current_setting('a2.b')::uuid;
  v_exp bigint; v_ids bigint[]; n int;
begin
  perform pg_temp.login(adm);
  v_exp := (admin_broadcast_send('Soon gone', 'Expires', 'info', 'everyone', null, true, now() + interval '1 hour')->>'id')::bigint;
  update broadcasts set expires_at = now() - interval '1 minute' where id = v_exp;   -- expired
  perform admin_broadcast_end(current_setting('a2.lapo')::bigint);                    -- ended early
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_broadcast_end(%s)', current_setting('a2.lapo'))) = 'not_found', 'end twice');
  set local role authenticated;
  perform pg_temp.login(a);
  select array_agg(id order by id) into v_ids from broadcasts;
  perform pg_temp.assert(v_ids = array[current_setting('a2.all')::bigint, current_setting('a2.on')::bigint], 'A RLS ' || coalesce(v_ids::text, 'none'));
  select count(*) into n from broadcast_reads;
  perform pg_temp.assert(n = (select count(*) from broadcast_reads where user_id = a), 'A reads own rows only');
  perform pg_temp.login(b);
  select array_agg(id order by id) into v_ids from broadcasts;
  perform pg_temp.assert(v_ids = array[current_setting('a2.all')::bigint, current_setting('a2.nepo')::bigint], 'B RLS ' || coalesce(v_ids::text, 'none'));
  perform pg_temp.assert(pg_temp.hint_of($q$insert into broadcasts (title) values ('hack')$q$) <> 'ok', 'no insert');
  perform pg_temp.assert(pg_temp.hint_of($q$update broadcast_reads set seen_at = now()$q$) <> 'ok', 'no update');
  reset role;
  perform pg_temp.login(b);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(broadcast_inbox()->'rows') x where (x->>'id')::bigint = v_exp), 'expired not in inbox');
  raise notice 'ok 3: RLS audience / expired / ended / targeted';
end $$;
reset role;

-- ---------- 4 + 5 + 6. gift ----------
do $$
declare
  adm uuid := current_setting('a2.adm')::uuid; a uuid := current_setting('a2.a')::uuid;
  b uuid := current_setting('a2.b')::uuid; c uuid := current_setting('a2.c')::uuid;
  r jsonb; r2 jsonb; v_id bigint; n bigint; h jsonb;
begin
  perform pg_temp.login(adm);
  -- 6. validation + caps
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('short', 5000, 'cash', 'Hi there')$q$) = 'bad_key', 'key');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('gift-key-0001', 5000, 'gold', 'Hi there')$q$) = 'bad_value', 'account');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('gift-key-0001', 0, 'cash', 'Hi there')$q$) = 'bad_value', 'zero');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('gift-key-0001', 1000001, 'cash', 'Hi there')$q$) = 'too_big', 'per-player cap');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('gift-key-0001', 5000, 'cash', ' ')$q$) = 'bad_narration', 'narration');
  update game_config set value = '10000' where key = 'admin.gift_total_max';
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_gift_send('gift-key-0001', 5000, 'cash', 'Launch gift')$q$) = 'total_cap', 'total cap');
  update game_config set value = '20000000000' where key = 'admin.gift_total_max';
  perform pg_temp.assert(not exists (select 1 from broadcasts where gift_key = 'gift-key-0001'), 'refusals leave nothing');

  -- 4. lapo-only cash gift: A + C paid once, B not
  r := admin_gift_send('gift-key-0001', 5000, 'cash', 'Launch gift from the Oba 🎉', 'lapo', null, true, null);
  v_id := (r->>'id')::bigint;
  n := (select count(*) from profiles where home_chosen and not banned and origin = 'lapo');
  perform pg_temp.assert((r->>'count')::bigint = n and (r->>'total')::numeric = n * 5000 and not (r->>'duplicate')::boolean, 'gift result ' || r::text);
  perform pg_temp.assert((select cash from profiles where id = a) = 6000 and (select cash from profiles where id = c) = 6000
                         and (select cash from profiles where id = b) = 1000 and (select bank from profiles where id = a) = 500, 'balances');
  perform pg_temp.assert((select count(*) from ledger where reason = 'admin_gift' and (meta->>'broadcast_id')::bigint = v_id) = n, 'one ledger row each');
  perform pg_temp.assert((select count(*) from ledger where reason = 'admin_gift' and user_id = a) = 1
                         and (select balance_after from ledger where reason = 'admin_gift' and user_id = a) = 6000, 'A ledger row');
  perform pg_temp.assert((select count(*) from broadcast_reads where broadcast_id = v_id) = n, 'recipients frozen');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'mass_gift' and (data->>'broadcast_id')::bigint = v_id
                                   and (data->>'players')::bigint = n), 'gift audited');
  perform pg_temp.login(a);
  h := bank_history(5)->0;
  perform pg_temp.assert(h->>'label' = 'Launch gift from the Oba 🎉' and (h->>'delta')::bigint = 5000 and h->>'note' is null, 'bank history narration ' || h::text);
  r2 := (select x from jsonb_array_elements(broadcast_inbox()->'rows') x where (x->>'id')::bigint = v_id);
  perform pg_temp.assert(r2->>'kind' = 'gift' and r2->>'title' = 'You received ₦5,000 🎁' and r2->>'body' = 'Launch gift from the Oba 🎉'
                         and (r2->>'gift_amount')::bigint = 5000 and (r2->>'popup')::boolean, 'gift alert ' || coalesce(r2::text, 'missing'));
  perform pg_temp.login(b);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(broadcast_inbox()->'rows') x where (x->>'id')::bigint = v_id), 'B no gift alert');

  -- 5. idempotency: same key again pays nothing
  perform pg_temp.login(adm);
  r2 := admin_gift_send('gift-key-0001', 5000, 'cash', 'Launch gift from the Oba 🎉', 'lapo', null, true, null);
  perform pg_temp.assert((r2->>'duplicate')::boolean and (r2->>'id')::bigint = v_id, 'duplicate returns first ' || r2::text);
  perform pg_temp.assert((select cash from profiles where id = a) = 6000 and (select count(*) from ledger where reason = 'admin_gift' and user_id = a) = 1, 'no double pay');

  -- a new key, bank, joined_after: only C
  r := admin_gift_send('gift-key-0002', 2500, 'bank', 'Welcome bonus', 'joined_after', now() - interval '7 days', false, null);
  perform pg_temp.assert((r->>'count')::int = 1 and (select bank from profiles where id = c) = 3000 and (select bank from profiles where id = a) = 500, 'bank joined_after ' || r::text);
  -- ceiling: a player near ₦9Q is skipped, not overflowed
  update profiles set cash = 9000000000000000 - 100 where id = b;
  r := admin_gift_send('gift-key-0003', 1000, 'cash', 'Small dash', 'nepo', null, true, null);
  perform pg_temp.assert((r->>'skipped')::int >= 1 and (select cash from profiles where id = b) = 9000000000000000 - 100, 'ceiling skip ' || r::text);
  update profiles set cash = 1000 where id = b;
  raise notice 'ok 4-6: gift pays once with narration, idempotent, caps';
end $$;

-- ---------- 7. performance: 5,000 synthetic players ----------
do $$
declare
  adm uuid := current_setting('a2.adm')::uuid; tpl uuid := current_setting('a2.a')::uuid;
  t0 timestamptz; v_ms numeric; r jsonb; n bigint;
begin
  set local session_replication_role = replica;  -- skip per-row furnishing triggers while seeding
  create temp table a2_ids on commit drop as select gen_random_uuid() as id, g from generate_series(1, 5000) g;
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a2_syn' || g || '@bc.bl', '', '{}', '{}', now(), now() from a2_ids;
  insert into profiles
  select (jsonb_populate_record(null::profiles,
           to_jsonb(p) || jsonb_build_object('id', i.id, 'username', 'a2syn' || i.g, 'cash', 100, 'bank', 0, 'is_admin', false))).*
    from a2_ids i cross join (select * from profiles where id = tpl) p;
  set local session_replication_role = origin;
  perform pg_temp.login(adm);
  select count(*) into n from profiles where home_chosen and not banned;
  t0 := clock_timestamp();
  r := admin_gift_send('gift-key-perf-1', 1000, 'cash', 'Perf gift', 'everyone', null, true, null);
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice 'gift to % players took % ms', r->>'count', round(v_ms);
  perform pg_temp.assert((r->>'count')::bigint = n and n >= 5000, 'perf count ' || r::text);
  perform pg_temp.assert((select count(*) from ledger l join a2_ids i on i.id = l.user_id where l.reason = 'admin_gift') = 5000
                         and (select min(cash) = 1100 and max(cash) = 1100 from profiles p join a2_ids i on i.id = p.id), 'all synthetic paid once');
  perform pg_temp.assert(v_ms < 3000, 'gift too slow: ' || round(v_ms) || ' ms');
  t0 := clock_timestamp();
  perform admin_broadcast_list(50);
  perform pg_temp.login(tpl);
  perform broadcast_inbox();
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  perform pg_temp.assert(v_ms < 1000, 'list/inbox too slow: ' || round(v_ms) || ' ms');
  raise notice 'ok 7: 5k gift + list/inbox (% ms)', round(v_ms);
end $$;
