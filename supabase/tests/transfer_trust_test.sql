-- Admin "allow to send money now": trusted new accounts skip the transfer wait.
create or replace function pg_temp.tt_make(p_name text) returns uuid
language plpgsql as $$
declare v uuid := pg_temp.new_user(lower(p_name) || '@tt.bl');
begin
  perform pg_temp.login(v);
  update game_config set value = '""' where key = 'origin.force_next';
  perform set_config('bl.test_rand', '0.99', true);
  perform create_profile_v2(p_name, 'female', '{"gender":"female"}', '{hustler,bini_pride}', 'oga_at_the_top');
  perform set_config('bl.test_rand', '', true);
  perform choose_start_home('ekenwan_face_me');
  return v;
end $$;

do $$
declare a uuid; b uuid; c uuid; r jsonb; v_rcv bigint;
begin
  a := pg_temp.tt_make('TtAdmin'); b := pg_temp.tt_make('TtNew'); c := pg_temp.tt_make('TtRcv');
  update profiles set is_admin = true where id = a;
  update profiles set bank = 50000, created_at = bl_now() where id = b;
  perform pg_temp.login(b);
  begin perform bank_transfer('TtRcv', 1000); raise exception 'should wait'; exception when others then
    perform pg_temp.assert(sqlerrm like 'New accounts%', 'new account waits: ' || sqlerrm); end;
  begin perform admin_set_transfer_trusted(b, true); raise exception 'player allowed'; exception when others then
    perform pg_temp.assert(sqlerrm <> 'player allowed', 'non-admin refused'); end;
  perform pg_temp.login(a);
  r := admin_set_transfer_trusted(b, true);
  perform pg_temp.login(b);
  perform pg_temp.assert(coalesce((bank_info()->>'new_account_wait_real_seconds')::numeric, 0) = 0, 'bank_info shows no wait');
  select bank into v_rcv from profiles where id = c;
  r := bank_transfer('TtRcv', 1000);
  perform pg_temp.assert((select bank from profiles where id = c) = v_rcv + 1000, 'trusted new account sent money');
  perform pg_temp.assert(exists(select 1 from admin_audit where action = 'transfer_allow' and target_user = b), 'audited');
  perform pg_temp.login(a);
  r := admin_set_transfer_trusted(b, false);
  perform pg_temp.login(b);
  begin perform bank_transfer('TtRcv', 1000); raise exception 'should wait again'; exception when others then
    perform pg_temp.assert(sqlerrm like 'New accounts%', 'waits again after removal: ' || sqlerrm); end;
  raise notice 'transfer trust OK';
end $$;
