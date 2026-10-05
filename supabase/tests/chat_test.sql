-- Chat tests (V1-6): config + privileges (no direct writes), chat_send at a place (refused while
-- travelling / banned / muted / brand new / too fast / burst / too long / empty / duplicate),
-- profanity masking + control-character cleanup, chat_recent only for the current place, RLS
-- (select only at your place, minus blocked players, minus hidden), report + auto-hide, block /
-- unblock, lazy retention delete, admin_chat_hide guard. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/chat_test.sql
-- Rolled back at the end. Time with bl.test_offset_seconds.

create or replace function pg_temp.ch_advance(p_seconds numeric) returns void
language plpgsql as $$
declare v numeric := coalesce(nullif(current_setting('bl.test_offset_seconds', true), '')::numeric, 0) + p_seconds;
begin
  perform set_config('bl.test_offset_seconds', v::text, true);
end $$;

create or replace function pg_temp.ch_hint(p_sql text, p_hint text) returns text
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

-- user ids live in GUCs (readable after `set role authenticated`, unlike a temp table)
create or replace function pg_temp.ch_u(p_name text) returns uuid
language sql as $$ select current_setting('chtest.' || p_name)::uuid $$;

create or replace function pg_temp.ch_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@chat.bl');
begin
  perform set_config('chtest.' || lower(p_name), v::text, true);
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set created_at = bl_now() - interval '1 day' where id = v;
  return v;
end $$;

create or replace function pg_temp.ch_at(p_uid uuid, p_loc text) returns void
language sql as $$
  update profiles set location_id = p_loc, travel_to = null, travel_mode = null, busy_until = null, busy_label = null,
                      jailed_until = null, hospitalized_until = null, banned = false, chat_muted_until = null
   where id = p_uid;
$$;

-- send as a user, then step past the rate limit
create or replace function pg_temp.ch_say(p_uid uuid, p_body text) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.login(p_uid);
  r := chat_send(p_body);
  perform pg_temp.ch_advance(4);
  return r;
end $$;

do $$ begin
  perform set_config('bl.test_offset_seconds', '', true);
  perform set_config('bl.test_rand', '', true);
  update game_config set value = 'true' where key = 'chat.enabled';
  update game_config set value = '200' where key = 'chat.max_len';
  update game_config set value = '3' where key = 'chat.rate_seconds';
  update game_config set value = '8' where key = 'chat.burst_per_minute';
  update game_config set value = '120' where key = 'chat.duplicate_window_seconds';
  update game_config set value = '5' where key = 'chat.min_account_real_minutes';
  update game_config set value = '30' where key = 'chat.recent_limit';
  update game_config set value = '3' where key = 'chat.report_hide_count';
  update game_config set value = '48' where key = 'chat.retention_hours';
  update game_config set value = 'false' where key = 'rent.enabled';
  -- start from an empty chat (rolled back)
  delete from chat_messages;
end $$;

-- ---------- 0. config + privileges ----------
do $$
declare k text;
begin
  foreach k in array array['chat.enabled','chat.max_len','chat.rate_seconds','chat.burst_per_minute','chat.duplicate_window_seconds',
                           'chat.min_account_real_minutes','chat.recent_limit','chat.report_hide_count','chat.retention_hours','chat.max_blocks'] loop
    perform pg_temp.assert(exists (select 1 from game_config where key = k and category = 'chat' and label <> '' and description <> ''),
                           'config ' || k);
  end loop;
  foreach k in array array['chat_messages','chat_reports','chat_blocks','chat_banned_words'] loop
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'insert'), 'no client insert: ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'update'), 'no client update: ' || k);
    perform pg_temp.assert(not has_table_privilege('authenticated', 'public.' || k, 'delete'), 'no client delete: ' || k);
    perform pg_temp.assert(not has_table_privilege('anon', 'public.' || k, 'select'), 'no anon select: ' || k);
    perform pg_temp.assert((select relrowsecurity from pg_class where oid = ('public.' || k)::regclass), 'RLS on: ' || k);
  end loop;
  perform pg_temp.assert(has_table_privilege('authenticated', 'public.chat_messages', 'select'), 'select chat_messages');
  perform pg_temp.assert(not has_table_privilege('authenticated', 'public.chat_reports', 'select'), 'reports are private');
  perform pg_temp.assert(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'chat_messages'),
                         'chat_messages in realtime');
  foreach k in array array['bl_chat_clean(text)','bl_chat_mask(text)','bl_chat_me()','bl_chat_row(chat_messages,jsonb,uuid)'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', 'public.' || k, 'execute'), 'helper revoked: ' || k);
  end loop;
  foreach k in array array['chat_send(text)','chat_recent(text,integer)','chat_report(bigint,text)','chat_block(uuid)',
                           'chat_unblock(uuid)','chat_blocked()','admin_chat_hide(bigint,boolean)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', 'public.' || k, 'execute'), 'rpc granted: ' || k);
    perform pg_temp.assert(not has_function_privilege('anon', 'public.' || k, 'execute'), 'rpc not for anon: ' || k);
  end loop;
  raise notice 'ok 0: config, privileges';
end $$;

-- ---------- 1. send + mask + clean ----------
do $$
declare a uuid := pg_temp.ch_make('ChatAda'); b uuid := pg_temp.ch_make('ChatBen'); c uuid := pg_temp.ch_make('ChatCy');
        r jsonb;
begin
  perform pg_temp.ch_at(a, 'oba_market'); perform pg_temp.ch_at(b, 'oba_market'); perform pg_temp.ch_at(c, 'uselu_market');
  r := pg_temp.ch_say(a, '  Hello   Oba Market!  ');
  perform pg_temp.assert(r->>'body' = 'Hello Oba Market!', 'trimmed + squeezed: ' || (r->>'body'));
  perform pg_temp.assert(r->>'location_id' = 'oba_market' and r->>'username' = 'ChatAda' and (r->>'mine')::boolean, 'row fields');
  perform pg_temp.assert(not (r->>'masked')::boolean, 'clean message not masked');
  r := pg_temp.ch_say(b, E'Who be this ashawo?\nFUCK off,\tshitty  fuckers');
  perform pg_temp.assert(r->>'body' = 'Who be this ******? **** off, ****** *******', 'masked: ' || (r->>'body'));
  perform pg_temp.assert((r->>'masked')::boolean, 'masked flag');
  r := pg_temp.ch_say(b, 'I assume Dickens wrote that, a classic');
  perform pg_temp.assert(r->>'body' = 'I assume Dickens wrote that, a classic', 'no false positives: ' || (r->>'body'));
  r := pg_temp.ch_say(a, E'zero​width\x01 ok');
  perform pg_temp.assert(r->>'body' = 'zerowidth ok', 'control chars stripped: ' || (r->>'body'));
  -- admin switches a word off
  update chat_banned_words set active = false where word = 'werey';
  r := pg_temp.ch_say(a, 'you be werey');
  perform pg_temp.assert(r->>'body' = 'you be werey', 'inactive word not masked');
  update chat_banned_words set active = true where word = 'werey';
  perform pg_temp.assert((select count(*) from chat_messages where location_id = 'oba_market') = 5, '5 rows at oba_market');
  raise notice 'ok 1: send, mask, clean';
end $$;

-- ---------- 2. refusals ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); i int;
begin
  perform pg_temp.login(a);
  perform pg_temp.ch_hint($q$select chat_send('   ')$q$, 'empty');
  perform pg_temp.ch_hint(format('select chat_send(%L)', repeat('a', 201)), 'too_long');
  perform chat_send(repeat('b', 200));                                   -- exactly the limit is fine
  perform pg_temp.ch_hint($q$select chat_send('again so soon')$q$, 'too_fast');
  perform pg_temp.ch_advance(4);
  perform pg_temp.ch_hint(format('select chat_send(%L)', repeat('B', 200)), 'duplicate');  -- same text, any case
  perform pg_temp.ch_advance(121);
  perform chat_send(repeat('b', 200));                                   -- window passed
  perform pg_temp.ch_advance(4);
  -- travelling
  update profiles set travel_to = 'uselu_market' where id = a;
  perform pg_temp.ch_hint($q$select chat_send('on the bus')$q$, 'traveling');
  perform pg_temp.ch_hint($q$select chat_recent('oba_market', 30)$q$, 'not_here');
  perform pg_temp.ch_at(a, 'oba_market');
  -- banned / muted
  update profiles set banned = true where id = a;
  perform pg_temp.ch_hint($q$select chat_send('hi')$q$, 'banned');
  update profiles set banned = false, chat_muted_until = bl_now() + interval '10 minutes' where id = a;
  perform pg_temp.ch_hint($q$select chat_send('hi')$q$, 'muted');
  update profiles set chat_muted_until = null where id = a;
  -- chat off
  update game_config set value = 'false' where key = 'chat.enabled';
  perform pg_temp.ch_hint($q$select chat_send('hi')$q$, 'chat_off');
  update game_config set value = 'true' where key = 'chat.enabled';
  -- brand-new account
  update profiles set created_at = bl_now() - interval '1 minute' where id = a;
  perform pg_temp.ch_hint($q$select chat_send('first post')$q$, 'too_new');
  update profiles set created_at = bl_now() - interval '1 day' where id = a;
  -- burst: 8 per minute even when spaced past the 3 s wait
  update game_config set value = '1' where key = 'chat.rate_seconds';
  perform pg_temp.ch_advance(120);
  for i in 1..8 loop
    perform chat_send('burst ' || i);
    perform pg_temp.ch_advance(1.1);
  end loop;
  perform pg_temp.ch_hint($q$select chat_send('burst 9')$q$, 'too_fast');
  update game_config set value = '3' where key = 'chat.rate_seconds';
  perform pg_temp.ch_advance(61);
  raise notice 'ok 2: refusals';
end $$;

-- ---------- 3. recent + RLS ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); c uuid := pg_temp.ch_u('chatcy'); r jsonb;
begin
  perform pg_temp.login(a);
  update game_config set value = '10' where key = 'chat.recent_limit';
  r := chat_recent('oba_market', 100);
  perform pg_temp.assert(jsonb_array_length(r) = 10, 'capped at chat.recent_limit: ' || jsonb_array_length(r));
  perform pg_temp.assert((r->9->>'id')::bigint > (r->0->>'id')::bigint, 'oldest first');
  perform pg_temp.assert(r->9->>'body' = 'burst 8' and (r->9->>'mine')::boolean and r->9->'avatar' is not null, 'last row');
  perform pg_temp.assert(jsonb_array_length(chat_recent('oba_market', 3)) = 3, 'p_limit honoured');
  update game_config set value = '30' where key = 'chat.recent_limit';
  perform pg_temp.ch_hint($q$select chat_recent('uselu_market', 30)$q$, 'not_here');
  perform pg_temp.login(c);
  perform pg_temp.ch_say(c, 'Uselu market dey hot');
  r := chat_recent('uselu_market', 30);
  perform pg_temp.assert(jsonb_array_length(r) = 1 and (r->0->>'mine')::boolean, 'uselu has 1 (mine)');
  raise notice 'ok 3: recent';
end $$;

-- RLS as the authenticated role: Cy (uselu) sees only uselu rows; Ada (ring road) only ring road rows.
do $$ begin perform pg_temp.login(pg_temp.ch_u('chatcy')); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from chat_messages) = 1, 'RLS: Cy sees only uselu');
  perform pg_temp.assert((select count(*) from chat_messages where location_id = 'oba_market') = 0, 'RLS: no ring road for Cy');
  perform pg_temp.assert((select count(*) from chat_blocks) = 0, 'RLS: no blocks');
end $$;
reset role;
do $$ begin perform pg_temp.login(pg_temp.ch_u('chatada')); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from chat_messages where location_id = 'uselu_market') = 0, 'RLS: no uselu for Ada');
  perform pg_temp.assert((select count(*) from chat_messages) > 10, 'RLS: Ada sees ring road');
end $$;
reset role;
-- a direct insert is refused even if someone tries
do $$ begin perform pg_temp.login(pg_temp.ch_u('chatada')); end $$;
set local role authenticated;
do $$ begin
  begin
    insert into chat_messages (location_id, user_id, username, body)
    values ('oba_market', current_setting('chtest.chatada')::uuid, 'x', 'sneaky');
    raise exception 'TEST FAILED: direct insert worked';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ---------- 4. block / unblock ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); b uuid := pg_temp.ch_u('chatben'); r jsonb; n_before int; n_after int;
begin
  perform pg_temp.login(a);
  select count(*) into n_before from jsonb_array_elements(chat_recent('oba_market', 30)) e where e->>'user_id' = b::text;
  perform pg_temp.ch_hint(format('select chat_block(%L)', a), 'self');
  perform pg_temp.ch_hint(format('select chat_block(%L)', gen_random_uuid()), 'unknown_player');
  r := chat_block(b);
  perform pg_temp.assert(r->>'username' = 'ChatBen', 'block returns name');
  perform chat_block(b);                                         -- idempotent
  r := chat_blocked();
  perform pg_temp.assert(jsonb_array_length(r) = 1 and r->0->>'username' = 'ChatBen', 'blocked list');
  perform pg_temp.ch_say(b, 'can Ada see me?');
  perform pg_temp.login(a);
  select count(*) into n_after from jsonb_array_elements(chat_recent('oba_market', 30)) e where e->>'user_id' = b::text;
  perform pg_temp.assert(n_after = 0, 'blocked user filtered from recent');
  -- Ben still sees Ada
  perform pg_temp.login(b);
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(chat_recent('oba_market', 30)) e where e->>'user_id' = a::text),
                         'block is one-way');
  raise notice 'ok 4a: block (n_before=%)', n_before;
end $$;
do $$ begin perform pg_temp.login(pg_temp.ch_u('chatada')); end $$;
set local role authenticated;
do $$ begin
  perform pg_temp.assert((select count(*) from chat_messages where user_id = current_setting('chtest.chatben')::uuid) = 0, 'RLS hides blocked');
  perform pg_temp.assert((select count(*) from chat_blocks) = 1, 'own block row visible');
end $$;
reset role;
do $$
declare a uuid := pg_temp.ch_u('chatada'); b uuid := pg_temp.ch_u('chatben');
begin
  perform pg_temp.login(a);
  perform chat_unblock(b);
  perform pg_temp.assert(jsonb_array_length(chat_blocked()) = 0, 'unblocked');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(chat_recent('oba_market', 30)) e where e->>'user_id' = b::text),
                         'visible again after unblock');
  raise notice 'ok 4: block / unblock';
end $$;

-- ---------- 5. report + auto-hide ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); b uuid := pg_temp.ch_u('chatben'); c uuid := pg_temp.ch_u('chatcy');
        d uuid := pg_temp.ch_make('ChatDee'); mid bigint; r jsonb;
begin
  perform pg_temp.ch_at(c, 'oba_market'); perform pg_temp.ch_at(d, 'oba_market');
  mid := (pg_temp.ch_say(b, 'buy my fake watch o')->>'id')::bigint;
  perform pg_temp.login(b);
  perform pg_temp.ch_hint(format('select chat_report(%s, null)', mid), 'own_message');
  perform pg_temp.ch_hint('select chat_report(-1, null)', 'not_found');
  perform pg_temp.login(a);
  r := chat_report(mid, E'spam\n');
  perform pg_temp.assert((r->>'reports')::int = 1 and not (r->>'hidden')::boolean, 'one report');
  r := chat_report(mid, 'again');                                  -- same reporter twice counts once
  perform pg_temp.assert((r->>'reports')::int = 1, 'one per reporter');
  perform pg_temp.login(c);
  r := chat_report(mid, 'spam');
  perform pg_temp.assert(not (r->>'hidden')::boolean, 'two reports: still visible');
  perform pg_temp.login(d);
  r := chat_report(mid, 'scam');
  perform pg_temp.assert((r->>'reports')::int = 3 and (r->>'hidden')::boolean, 'third report hides');
  perform pg_temp.assert((select hidden from chat_messages where id = mid), 'row hidden');
  perform pg_temp.login(a);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(chat_recent('oba_market', 30)) e where (e->>'id')::bigint = mid),
                         'hidden not in recent');
  perform pg_temp.assert((select reason from chat_reports where message_id = mid and reporter_id = a) = 'spam', 'reason cleaned');
  perform set_config('chtest.hidden_mid', mid::text, true);
  raise notice 'ok 5: report + auto-hide';
end $$;

-- ---------- 6. admin hide guard ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); b uuid := pg_temp.ch_u('chatben'); mid bigint; r jsonb;
begin
  mid := (pg_temp.ch_say(b, 'admin please look')->>'id')::bigint;
  perform pg_temp.login(a);
  perform pg_temp.ch_hint(format('select admin_chat_hide(%s, true)', mid), 'not_admin');
  update profiles set is_admin = true where id = a;
  r := admin_chat_hide(mid, true);
  perform pg_temp.assert((r->>'hidden')::boolean and (select hidden from chat_messages where id = mid), 'admin hid it');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'chat_hide' and target_user = b and admin_id = a), 'audited');
  r := admin_chat_hide(current_setting('chtest.hidden_mid')::bigint, false);
  perform pg_temp.assert(not (r->>'hidden')::boolean, 'admin un-hides');
  perform pg_temp.ch_hint('select admin_chat_hide(-5, true)', 'not_found');
  update profiles set is_admin = false where id = a;
  raise notice 'ok 6: admin hide';
end $$;

-- ---------- 7. retention ----------
do $$
declare a uuid := pg_temp.ch_u('chatada'); n_old int; v_cut timestamptz;
begin
  perform pg_temp.ch_advance(49 * 3600);                           -- everything so far is now > 48 h old
  v_cut := bl_now() - interval '48 hours';
  select count(*) into n_old from chat_messages where created_at < v_cut;
  perform pg_temp.assert(n_old > 10, 'old rows exist: ' || n_old);
  perform pg_temp.ch_say(a, 'fresh start');
  perform pg_temp.assert(not exists (select 1 from chat_messages where created_at < v_cut), 'old rows deleted lazily');
  perform pg_temp.assert(not exists (select 1 from chat_reports r left join chat_messages m on m.id = r.message_id where m.id is null),
                         'reports cascade');
  perform pg_temp.assert((select count(*) from chat_messages) = 1, 'only the fresh message left');
  raise notice 'ok 7: retention';
end $$;
