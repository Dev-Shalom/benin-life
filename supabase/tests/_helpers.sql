-- Test helpers (session-scoped). Loaded by scripts/sql-test.sh before each test file.
-- pg_temp.new_user(email) -> uuid : creates an auth user
-- pg_temp.login(uid)              : impersonates that user for auth.uid()
-- pg_temp.assert(cond, msg)       : raises msg when cond is not true

create or replace function pg_temp.new_user(p_email text) returns uuid
language plpgsql as $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at, email_confirmed_at)
  values (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', p_email, '',
          '{"provider":"email","providers":["email"]}', '{}', now(), now(), now());
  return u;
end $$;

create or replace function pg_temp.login(p uuid) returns void
language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p::text, true);
$$;

create or replace function pg_temp.assert(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'TEST FAILED: %', p_msg;
  end if;
end $$;
