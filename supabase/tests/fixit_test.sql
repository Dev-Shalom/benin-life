-- "Fix it" update (migrations 20261110000100 and up). Rolled back. Run (migrations applied):
--   bash scripts/sql-test.sh -- supabase/tests/fixit_test.sql
-- One group per item with server logic (the numbers in the headers are the item numbers):
-- 3 club spray alert prefs · 4 beds · 5 gang boss hand-back · 6 land levy · 7 laptops · 8 delete account ·
-- 9 phone banking · 10 primary car · 11 balance guards · 12 money history
create or replace function pg_temp.fx_hint(p_sql text) returns text
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

create or replace function pg_temp.fx_make(p_name text, p_cash bigint default 1000000, p_bank bigint default 1000000) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@fx.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  update game_config set value = 'false' where key = 'stories.push_enabled';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'male', '{"gender":"male"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  update profiles set last_seen = now() - interval '1 hour', transfer_trusted = true, bank = p_bank, cash = p_cash,
         protected_until = null where id = v;
  return v;
end $$;

-- ---------- 3. Club spray alerts ----------
do $$
declare a uuid := pg_temp.fx_make('FxAda'); b uuid := pg_temp.fx_make('FxBayo'); r jsonb; v_club text; n int;
begin
  perform pg_temp.login(a);
  r := club_alert_prefs_get();
  perform pg_temp.assert((r->>'toasts')::boolean and not (r->>'strip')::boolean and not (r->>'push')::boolean, 'defaults: toasts on, strip off, push off');
  r := club_alert_prefs_set('{"push": true}');
  perform pg_temp.assert((r->>'push')::boolean and (r->>'toasts')::boolean, 'partial set');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"nope": true}')$q$) = 'bad_value', 'unknown switch refused');
  perform pg_temp.assert(pg_temp.fx_hint($q$select club_alert_prefs_set('{"push": 1}')$q$) = 'bad_value', 'non-boolean refused');
  -- B cannot see A's row
  perform pg_temp.login(b);
  perform pg_temp.assert((club_alert_prefs_get()->>'push')::boolean = false, 'B has own defaults');
  set local role authenticated;
  select count(*) into n from club_alert_prefs;
  reset role;
  perform pg_temp.assert(n = 0, 'RLS: B reads no other row');
  raise notice 'ok 3: club spray alert prefs';
end $$;
