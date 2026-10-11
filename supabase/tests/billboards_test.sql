-- H3 billboards (20261012000500_billboards.sql). Rolled back. Run:
--   bash scripts/sql-test.sh -- supabase/tests/billboards_test.sql
-- Groups: 1 grants + helpers private · 2 create ad (validation, price from the board, switches) · 3 no self-approve,
-- no skipping payment · 4 payment: pending_review only on the exact amount, idempotent, wrong amount -> refund due ·
-- 5 admin approve / reject (+refund claim/result) / remove / sponsor + audit + events + notifications ·
-- 6 rotation list (live, not expired, <= max, order) + sweep · 7 per-player limit + board full · 8 report, tap, track ·
-- 9 RLS (others can't see unpaid/pending ads, nobody writes directly) · 10 storage policies · 11 push + inbox ·
-- 12 Tokunbo Lot zones + car dealer check · 13 admin Content -> Billboards.
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

create or replace function pg_temp.err_of(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  return sqlerrm;
end $$;

-- a stored upload for user p (storage API not needed: the row is what the RPC checks)
create or replace function pg_temp.bb_upload(p uuid, p_file text) returns text
language plpgsql as $$
declare v text := p::text || '/' || p_file;
begin
  insert into storage.objects (bucket_id, name, owner) values ('billboard-ads', v, p);
  return v;
end $$;

do $$
declare a uuid := pg_temp.new_user('h3_a@bb.bl'); b uuid := pg_temp.new_user('h3_b@bb.bl'); adm uuid := pg_temp.new_user('h3_admin@bb.bl');
begin
  perform set_config('h3.a', a::text, true); perform set_config('h3.b', b::text, true); perform set_config('h3.adm', adm::text, true);
  update game_config set value = 'true' where key in ('billboards.enabled', 'payments.enabled');
  update game_config set value = '3' where key = 'billboards.max_active_per_player';
  update game_config set value = '50' where key = 'billboards.max_ads';
  update game_config set value = '1' where key = 'billboards.report_alert';
  update billboards set active = true;
  update billboards set price_1d_kobo = 500000, price_3d_kobo = 1300000, price_7d_kobo = 2500000 where id = 'uselu';
  update billboards set price_7d_kobo = 25000000 where id = 'ring_road';
  update billboard_ads set status = 'expired' where status in ('live', 'pending_review'); -- start from an empty rotation
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(a);
  perform create_profile_v2('H3_Ada', 'female', '{"gender":"female"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(b);
  perform create_profile_v2('H3_Bode', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update game_config set value = '"lapo"' where key = 'origin.force_next';
  perform pg_temp.login(adm);
  perform create_profile_v2('H3_Boss', 'male', '{"gender":"male"}', '{hustler,foodie}', 'oga_at_the_top');
  perform choose_start_home('ekenwan_face_me');
  update profiles set is_admin = true where id = adm;
end $$;

-- ---------- 1. grants: helpers private, RPCs for players, service functions for service_role only ----------
do $$
declare f text;
begin
  foreach f in array array['bl_billboard_paid(text,bigint,jsonb)', 'bl_billboard_sweep()', 'bl_billboard_refund_claim(uuid)',
                           'bl_billboard_refund_result(uuid,boolean,text,jsonb)', 'bl_push_outbox_claim(integer)',
                           'bl_admin_notify(text,text,text,jsonb,text)', 'bl_billboard_link_ok(text)', 'bl_board_name(text)',
                           'bl_car_dealer_check()'] loop
    perform pg_temp.assert(not has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'execute')
                           and not has_function_privilege('anon', ('public.' || f)::regprocedure, 'execute'), 'helper private: ' || f);
  end loop;
  foreach f in array array['bl_billboard_paid(text,bigint,jsonb)', 'bl_billboard_sweep()', 'bl_billboard_refund_claim(uuid)',
                           'bl_billboard_refund_result(uuid,boolean,text,jsonb)', 'bl_push_outbox_claim(integer)'] loop
    perform pg_temp.assert(has_function_privilege('service_role', ('public.' || f)::regprocedure, 'execute'), 'service can: ' || f);
  end loop;
  foreach f in array array['billboard_list()', 'billboard_ad_create(text,integer,text,text)', 'billboard_ad_cancel(uuid)',
                           'billboard_my_ads()', 'billboard_report(uuid,text)', 'billboard_tap(uuid)', 'billboard_track(jsonb)',
                           'admin_billboard_queue(text,integer)', 'admin_billboard_approve(uuid)', 'admin_billboard_reject(uuid,text,boolean)',
                           'admin_billboard_remove(uuid,text,boolean)', 'admin_billboard_refund_start(uuid)',
                           'admin_billboard_sponsor(text,text,text,timestamp with time zone,timestamp with time zone,text)',
                           'admin_notifications(integer)', 'admin_notifications_seen(bigint)',
                           'admin_push_subscribe(text,text,text,text)', 'admin_push_unsubscribe(text)'] loop
    perform pg_temp.assert(has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'execute'), 'rpc granted: ' || f);
    perform pg_temp.assert(not has_function_privilege('anon', ('public.' || f)::regprocedure, 'execute'), 'rpc not anon: ' || f);
  end loop;
  perform pg_temp.assert((select count(*) from billboards) >= 10, 'ten boards seeded');
  perform pg_temp.assert((select min(price_7d_kobo) from billboards) >= 2500000 and (select max(price_7d_kobo) from billboards) <= 25000000,
                         '7-day prices between ₦25k and ₦250k');
  perform pg_temp.assert(not exists (select 1 from billboards where not (price_1d_kobo < price_3d_kobo and price_3d_kobo < price_7d_kobo)),
                         'longer runs cost more');
  perform pg_temp.assert((select public and file_size_limit = 1572864 from storage.buckets where id = 'billboard-ads'), 'bucket public, 1.5 MB');
end $$;

-- ---------- 2. create ad ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; r jsonb; img text;
begin
  perform pg_temp.login(a);
  img := pg_temp.bb_upload(a, 'ad1.webp');
  perform set_config('h3.img_a', img, true);
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 2, %L, 'https://wa.me/2348000000000')$q$, img)) = 'bad_days', 'days 1/3/7 only');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('nope', 1, %L, 'https://wa.me/2348000000000')$q$, img)) = 'bad_board', 'unknown board');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'http://wa.me/x')$q$, img)) = 'bad_link', 'http refused');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'javascript:alert(1)')$q$, img)) = 'bad_link', 'js refused');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'https://user@evil.com/')$q$, img)) = 'bad_link', 'userinfo refused');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'https://localhost/')$q$, img)) = 'bad_link', 'needs a real domain');
  perform pg_temp.assert(pg_temp.hint_of($q$select billboard_ad_create('uselu', 1, 'someone/else.webp', 'https://wa.me/234')$q$) = 'bad_image', 'other folder refused');
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'https://wa.me/234')$q$, a::text || '/missing.webp')) = 'bad_image', 'upload must exist');
  update game_config set value = 'false' where key = 'payments.enabled';
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'https://wa.me/234')$q$, img)) = 'payments_off', 'respects payments.enabled');
  update game_config set value = 'true' where key = 'payments.enabled';
  update game_config set value = 'false' where key = 'billboards.enabled';
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('uselu', 1, %L, 'https://wa.me/234')$q$, img)) = 'disabled', 'respects billboards.enabled');
  update game_config set value = 'true' where key = 'billboards.enabled';

  r := billboard_ad_create('uselu', 7, img, '  https://shop.example.com.ng/p?x=1#top ');
  perform pg_temp.assert((r->>'amount_kobo')::bigint = 2500000, 'price from the board (7 days uselu = ₦25,000): ' || r::text);
  perform pg_temp.assert(r->>'reference' ~ '^BLAD-[a-f0-9]{32}$', 'BLAD reference');
  perform pg_temp.assert(r->>'email' = 'h3_a@bb.bl' and r->>'currency' = 'NGN', 'email + currency for checkout');
  perform pg_temp.assert((select status = 'awaiting_payment' and link_url = 'https://shop.example.com.ng/p?x=1#top' and paid_at is null
                            from billboard_ads where id = (r->>'ad_id')::uuid), 'row awaiting payment, link trimmed');
  perform set_config('h3.ad1', r->>'ad_id', true);
  perform set_config('h3.ref1', r->>'reference', true);
end $$;

-- ---------- 3. cannot self-approve / skip payment ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; ad uuid := current_setting('h3.ad1')::uuid; adm uuid := current_setting('h3.adm')::uuid;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_approve(%L)', ad)) = 'not_admin', 'player cannot approve');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_sponsor(''uselu'', %L, null, now(), now() + interval ''1 day'')',
                         current_setting('h3.img_a'))) = 'not_admin', 'player cannot place sponsor ads');
  perform pg_temp.assert(pg_temp.hint_of('select admin_billboard_queue()') = 'not_admin', 'player cannot read the queue');
  set local role authenticated;
  perform pg_temp.assert(pg_temp.err_of(format('update billboard_ads set status = ''live'' where id = %L', ad)) like '%permission denied%', 'no direct update');
  perform pg_temp.assert(pg_temp.err_of(format('select bl_billboard_paid(%L, 2500000, ''{}'')', current_setting('h3.ref1'))) like '%permission denied%', 'cannot mark own payment');
  perform pg_temp.assert(pg_temp.err_of($q$insert into billboard_ads (board_id, image_path, status) values ('uselu', 'x', 'live')$q$) like '%permission denied%', 'no direct insert');
  reset role;
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_approve(%L)', ad)) = 'bad_status', 'admin cannot approve an unpaid ad');
  perform pg_temp.login(a);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(billboard_list()->'boards') bd, jsonb_array_elements(bd->'ads') x
                                      where x->>'id' = ad::text), 'unpaid ad is not on the board');
end $$;

-- ---------- 4. payment ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; r jsonb; r2 jsonb; img text; bad jsonb;
begin
  -- wrong amount: never on review, refund due, admins told
  perform pg_temp.login(a);
  img := pg_temp.bb_upload(a, 'ad2.png');
  bad := billboard_ad_create('uselu', 1, img, 'https://wa.me/2348000000001');
  r := bl_billboard_paid(bad->>'reference', 100, '{"data":{"amount":100}}');
  perform pg_temp.assert(not (r->>'ok')::boolean and r->>'error' = 'amount_mismatch', 'mismatch refused: ' || r::text);
  perform pg_temp.assert((select status = 'rejected' and refund_status = 'pending' and paid_kobo = 100 from billboard_ads where id = (bad->>'ad_id')::uuid),
                         'wrong amount -> rejected, refund pending');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'refund_needed' and data->>'ad_id' = bad->>'ad_id'), 'admins told about the refund');
  r := bl_billboard_paid(bad->>'reference', 500000, '{}');
  perform pg_temp.assert((r->>'already')::boolean and (select status from billboard_ads where id = (bad->>'ad_id')::uuid) = 'rejected',
                         'a later correct callback cannot revive it');
  perform set_config('h3.bad', bad->>'ad_id', true);
  -- unknown reference
  perform pg_temp.assert(bl_billboard_paid('BLAD-00000000000000000000000000000000', 1, '{}')->>'error' = 'unknown_reference', 'unknown ref');
  -- exact amount
  r := bl_billboard_paid(current_setting('h3.ref1'), 2500000, '{"data":{"amount":2500000}}');
  perform pg_temp.assert((r->>'ok')::boolean and (r->>'marked')::boolean and r->>'status' = 'pending_review', 'paid -> pending_review: ' || r::text);
  perform pg_temp.assert((select status = 'pending_review' and paid_kobo = 2500000 and paid_at is not null and starts_at is null
                            from billboard_ads where id = current_setting('h3.ad1')::uuid), 'row pending review, not live');
  r2 := bl_billboard_paid(current_setting('h3.ref1'), 2500000, '{}');
  perform pg_temp.assert((r2->>'already')::boolean and not (r2->>'marked')::boolean, 'idempotent');
  perform pg_temp.assert((select count(*) from admin_notifications where kind = 'ad_paid' and data->>'ad_id' = current_setting('h3.ad1')) = 1, 'one ad_paid notification');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'billboard_paid'), 'player told payment arrived');
  -- paid while the checkout row was cancelled (closed tab): still counts
  r := billboard_ad_create('uselu', 1, img, 'https://wa.me/2348000000002');
  perform billboard_ad_cancel((r->>'ad_id')::uuid);
  perform pg_temp.assert((select status from billboard_ads where id = (r->>'ad_id')::uuid) = 'cancelled', 'cancel own checkout');
  perform pg_temp.assert(bl_billboard_paid(r->>'reference', 500000, '{}')->>'status' = 'pending_review', 'late payment after cancel still reviewed');
  perform set_config('h3.ad3', r->>'ad_id', true);
end $$;

-- ---------- 5. admin approve / reject / remove / sponsor ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; adm uuid := current_setting('h3.adm')::uuid; r jsonb; q jsonb; sp uuid; c jsonb;
begin
  perform pg_temp.login(adm);
  q := admin_billboard_queue('review');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(q->'rows') x where x->>'id' = current_setting('h3.ad1')
                                    and x->>'username' = 'H3_Ada' and (x->>'paid_kobo')::bigint = 2500000 and x->>'board' = 'Uselu Market screen'
                                    and x->>'email' = 'h3_a@bb.bl'), 'queue shows buyer, board, paid: ' || q::text);
  perform pg_temp.assert((q->'counts'->>'review')::int >= 2 and (q->'counts'->>'refunds')::int >= 1, 'counts');
  -- approve
  r := admin_billboard_approve(current_setting('h3.ad1')::uuid);
  perform pg_temp.assert((select status = 'live' and reviewed_by = adm and starts_at <= now() and ends_at = starts_at + interval '7 days'
                            from billboard_ads where id = current_setting('h3.ad1')::uuid), 'live now for 7 days');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'billboard_approve' and admin_id = adm and data->>'ad_id' = current_setting('h3.ad1')), 'approve audited');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'billboard_approved'), 'player event approved');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'ad_live'), 'ad_live notification');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_approve(%L)', current_setting('h3.ad1'))) = 'bad_status', 'no double approve');
  -- reject with reason -> refund pending; the refund claim / result path
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_reject(%L, '''')', current_setting('h3.ad3'))) = 'reason', 'reason required');
  r := admin_billboard_reject(current_setting('h3.ad3')::uuid, 'Image is blurry', true);
  perform pg_temp.assert((r->>'refund')::boolean, 'reject refunds by default');
  perform pg_temp.assert((select status = 'rejected' and refund_status = 'pending' and refund_kobo = 500000 and reject_reason = 'Image is blurry'
                            from billboard_ads where id = current_setting('h3.ad3')::uuid), 'rejected + refund pending');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'billboard_rejected' and body like '%blurry%'), 'player event rejected');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'billboard_reject' and data->>'ad_id' = current_setting('h3.ad3')), 'reject audited');
  r := admin_billboard_refund_start(current_setting('h3.ad3')::uuid);
  perform pg_temp.assert((r->>'ok')::boolean and exists (select 1 from admin_audit where action = 'billboard_refund'), 'refund start audited');
  c := bl_billboard_refund_claim(current_setting('h3.ad3')::uuid);
  perform pg_temp.assert((c->>'ok')::boolean and (c->>'amount_kobo')::bigint = 500000 and c->>'reference' like 'BLAD-%', 'claim: ' || c::text);
  perform pg_temp.assert(bl_billboard_refund_claim(current_setting('h3.ad3')::uuid)->>'error' = 'no_refund_due', 'no double claim while processing');
  perform bl_billboard_refund_result(current_setting('h3.ad3')::uuid, false, 'Transaction has been fully reversed', '{}');
  perform pg_temp.assert((select refund_status = 'refund_failed' and refund_error like '%reversed%' from billboard_ads where id = current_setting('h3.ad3')::uuid), 'refund_failed marked');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'refund_failed'), 'refund_failed notification');
  perform pg_temp.assert(bl_billboard_refund_claim(current_setting('h3.ad3')::uuid)->>'ok' = 'true', 'retry after failure');
  perform bl_billboard_refund_result(current_setting('h3.ad3')::uuid, true, null, '{"status":true}');
  perform pg_temp.assert((select refund_status = 'refunded' and refund_at is not null from billboard_ads where id = current_setting('h3.ad3')::uuid), 'refunded');
  perform pg_temp.assert(bl_billboard_refund_claim(current_setting('h3.ad3')::uuid)->>'error' = 'already_refunded', 'never refund twice');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_refund_start(%L)', current_setting('h3.ad3'))) = 'no_refund_due', 'start refuses when refunded');
  -- sponsor ad on any board for any period
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_billboard_sponsor('ring_road', 'https://cdn.example.com/a.png', null, now(), now() - interval '1 day')$q$) = 'bad_dates', 'sponsor dates');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_billboard_sponsor('ring_road', 'http://x.y/a.png', null, now(), now() + interval '1 day')$q$) = 'bad_image', 'sponsor image');
  r := admin_billboard_sponsor('ring_road', 'https://cdn.example.com/sponsor.png', 'https://sponsor.example.com', now(), now() + interval '30 days', 'Bronze Bank');
  sp := (r->>'ad_id')::uuid;
  perform pg_temp.assert((select status = 'live' and kind = 'sponsor' and price_kobo = 0 and user_id is null and days = 30 from billboard_ads where id = sp), 'sponsor live, free');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'billboard_sponsor' and data->>'ad_id' = sp::text), 'sponsor audited');
  perform set_config('h3.sp', sp::text, true);
  -- remove live ad: no refund by default
  r := admin_billboard_remove(sp, 'Contract ended', false);
  perform pg_temp.assert(not (r->>'refund')::boolean and (select status = 'removed' and refund_status = 'none' from billboard_ads where id = sp), 'removed, no refund');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'billboard_remove' and data->>'ad_id' = sp::text), 'remove audited');
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_remove(%L, ''x'')', sp)) = 'bad_status', 'remove only live');
end $$;

-- remove with the optional refund toggle
do $$
declare a uuid := current_setting('h3.a')::uuid; adm uuid := current_setting('h3.adm')::uuid; r jsonb; img text;
begin
  perform pg_temp.login(a);
  img := pg_temp.bb_upload(a, 'ad4.jpg');
  r := billboard_ad_create('airport_road', 3, img, 'https://wa.me/2348000000004');
  perform bl_billboard_paid(r->>'reference', 1300000, '{}');
  perform pg_temp.login(adm);
  perform admin_billboard_approve((r->>'ad_id')::uuid);
  perform admin_billboard_remove((r->>'ad_id')::uuid, 'Broken link', true);
  perform pg_temp.assert((select status = 'removed' and refund_status = 'pending' and refund_kobo = 1300000 and ends_at <= now()
                            from billboard_ads where id = (r->>'ad_id')::uuid), 'remove with refund toggle');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'billboard_removed'), 'player told about removal');
end $$;

-- ---------- 6. rotation list + sweep ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; b uuid := current_setting('h3.b')::uuid; adm uuid := current_setting('h3.adm')::uuid;
        l jsonb; bd jsonb; i int; ids text[];
begin
  perform pg_temp.login(adm);
  -- five sponsor ads on new_benin with a max of 3: only the 3 oldest-started show, in a stable order
  update game_config set value = '3' where key = 'billboards.max_ads';
  for i in 1..5 loop
    perform admin_billboard_sponsor('new_benin', 'https://cdn.example.com/s' || i || '.png', null, now() - make_interval(mins => 10 - i), now() + interval '2 days', 'S' || i);
  end loop;
  -- one already over, one not started yet
  perform admin_billboard_sponsor('new_benin', 'https://cdn.example.com/old.png', null, now() - interval '3 days', now() + interval '1 second', 'old');
  update billboard_ads set ends_at = now() - interval '1 minute' where title = 'old';
  perform admin_billboard_sponsor('new_benin', 'https://cdn.example.com/later.png', null, now() + interval '1 day', now() + interval '3 days', 'later');
  perform pg_temp.login(b);
  l := billboard_list();
  perform pg_temp.assert((l->>'rotate_seconds')::int = 15 and (l->>'max_ads')::int = 3 and (l->>'enabled')::boolean and (l->>'buy_enabled')::boolean, 'list header: ' || (l - 'boards')::text);
  select x into bd from jsonb_array_elements(l->'boards') x where x->>'id' = 'new_benin';
  perform pg_temp.assert(jsonb_array_length(bd->'ads') = 3, 'max 3 ads per board: ' || bd::text);
  select array_agg(x->>'image' order by o) into ids from jsonb_array_elements(bd->'ads') with ordinality t(x, o);
  perform pg_temp.assert(ids = array['https://cdn.example.com/s1.png', 'https://cdn.example.com/s2.png', 'https://cdn.example.com/s3.png'], 'oldest first, stable: ' || ids::text);
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(l->'boards') x, jsonb_array_elements(x->'ads') y
                                      where y->>'image' like '%old.png' or y->>'image' like '%later.png'), 'expired and future ads hidden');
  perform pg_temp.assert((select status from billboard_ads where title = 'old') = 'expired', 'list sweeps ended ads');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'ad_ended'), 'ad_ended notification');
  select x into bd from jsonb_array_elements(l->'boards') x where x->>'id' = 'uselu';
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(bd->'ads') y where y->>'id' = current_setting('h3.ad1') and not (y->>'mine')::boolean
                                  and y->>'link' like 'https://shop.example.com.ng%'), 'paid live ad on its board for others');
  perform pg_temp.assert((bd->'prices'->>'7')::bigint = 2500000, 'prices in the list');
  -- the player's own ad ends -> event
  update billboard_ads set ends_at = now() - interval '1 second' where id = current_setting('h3.ad1')::uuid;
  perform billboard_list();
  perform pg_temp.assert((select status from billboard_ads where id = current_setting('h3.ad1')::uuid) = 'expired', 'expired');
  perform pg_temp.assert(exists (select 1 from events where user_id = a and kind = 'billboard_ended'), 'owner told the ad ended');
  update game_config set value = '50' where key = 'billboards.max_ads';
  -- stale unpaid checkouts are cancelled
  update billboard_ads set created_at = now() - interval '2 days' where status = 'awaiting_payment';
  perform billboard_list();
  perform pg_temp.assert(not exists (select 1 from billboard_ads where status = 'awaiting_payment' and created_at < now() - interval '1 day'), 'stale checkout cancelled');
end $$;

-- ---------- 7. per-player limit + board full ----------
do $$
declare b uuid := current_setting('h3.b')::uuid; adm uuid := current_setting('h3.adm')::uuid; img text; i int; r jsonb;
begin
  perform pg_temp.login(b);
  img := pg_temp.bb_upload(b, 'b1.webp');
  update game_config set value = '2' where key = 'billboards.max_active_per_player';
  for i in 1..2 loop
    r := billboard_ad_create('akpakpava', 1, img, 'https://wa.me/2348111111111');
    perform bl_billboard_paid(r->>'reference', (r->>'amount_kobo')::bigint, '{}');
  end loop;
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('akpakpava', 1, %L, 'https://wa.me/2348111111111')$q$, img)) = 'limit', 'per-player limit');
  update game_config set value = '3' where key = 'billboards.max_active_per_player';
  update game_config set value = '2' where key = 'billboards.max_ads';
  perform pg_temp.assert(pg_temp.hint_of(format($q$select billboard_ad_create('akpakpava', 1, %L, 'https://wa.me/2348111111111')$q$, img)) = 'board_full', 'board full');
  perform pg_temp.login(adm);
  update game_config set value = '0' where key = 'billboards.max_ads'; -- clamps to 1
  perform admin_billboard_approve((select id from billboard_ads where user_id = b and status = 'pending_review' order by created_at limit 1));
  perform pg_temp.assert(pg_temp.hint_of(format('select admin_billboard_approve(%L)',
                         (select id from billboard_ads where user_id = b and status = 'pending_review' limit 1))) = 'board_full', 'approve refuses when the board is full');
  update game_config set value = '50' where key = 'billboards.max_ads';
end $$;

-- ---------- 8. report, tap, track ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; b uuid := current_setting('h3.b')::uuid; ad uuid; r jsonb;
begin
  ad := (select id from billboard_ads where user_id = b and status = 'live' limit 1);
  perform pg_temp.login(b);
  perform pg_temp.assert(pg_temp.hint_of(format('select billboard_report(%L, ''x'')', ad)) = 'own_ad', 'cannot report own ad');
  perform pg_temp.login(a);
  r := billboard_report(ad, 'Looks like a scam');
  perform pg_temp.assert((r->>'reported')::boolean and (select reports from billboard_ads where id = ad) = 1, 'reported');
  perform pg_temp.assert((billboard_report(ad, 'again')->>'already')::boolean and (select reports from billboard_ads where id = ad) = 1, 'one report per player');
  perform pg_temp.assert(exists (select 1 from admin_notifications where kind = 'ad_reported' and body like '%scam%'), 'admins notified of report');
  perform pg_temp.assert(pg_temp.hint_of(format('select billboard_report(%L, ''x'')', current_setting('h3.ad3'))) = 'not_live', 'report only live ads');
  perform pg_temp.assert((billboard_tap(ad)->>'counted')::boolean, 'tap counted');
  perform pg_temp.assert(not (billboard_tap(ad)->>'counted')::boolean, 'one tap per hour per player');
  perform pg_temp.assert((select taps from billboard_ads where id = ad) = 1, 'taps = 1');
  r := billboard_track(jsonb_build_object(ad::text, 500, 'junk', 3, current_setting('h3.ad3'), 4));
  perform pg_temp.assert((r->>'counted')::int = 10 and (select views from billboard_ads where id = ad) = 10, 'views capped at 10 per batch, only live: ' || r::text);
  perform pg_temp.assert((billboard_track(jsonb_build_object(ad::text, 5))->>'throttled')::boolean, 'one batch per 50 s');
  perform pg_temp.assert((select views from billboard_ads where id = ad) = 10, 'throttled batch not counted');
end $$;

-- ---------- 9. RLS ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; b uuid := current_setting('h3.b')::uuid; n int; img text; r jsonb; my jsonb;
begin
  -- b has a pending ad and an unpaid checkout; a must not see them
  perform pg_temp.login(b);
  img := pg_temp.bb_upload(b, 'b2.webp');
  r := billboard_ad_create('oba_market', 1, img, 'https://wa.me/2348222222222');
  my := billboard_my_ads();
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(my) x where x->>'id' = r->>'ad_id' and x->>'status' = 'awaiting_payment'), 'my ads lists own checkout');
  perform pg_temp.assert(exists (select 1 from jsonb_array_elements(my) x where x->>'status' = 'live' and (x->>'views')::int = 10 and (x->>'taps')::int = 1),
                         'my ads shows stats');
  set local role authenticated;
  select count(*) into n from billboard_ads where user_id = b;
  perform pg_temp.assert(n >= 3, 'b reads own ads');
  perform pg_temp.assert(pg_temp.err_of('select pay_raw from billboard_ads limit 1') like '%permission denied%', 'payment JSON hidden');
  reset role;
  perform pg_temp.login(a);
  set local role authenticated;
  select count(*) into n from billboard_ads where user_id = b;
  perform pg_temp.assert(n = 0, 'others see none of b''s rows (unpaid, pending or live)');
  perform pg_temp.assert(pg_temp.err_of('select * from billboard_reports') like '%permission denied%', 'reports private');
  perform pg_temp.assert(pg_temp.err_of('select * from admin_notifications') like '%permission denied%', 'notifications private');
  perform pg_temp.assert(pg_temp.err_of('select * from push_subscriptions') like '%permission denied%', 'subscriptions private');
  perform pg_temp.assert(pg_temp.err_of($q$update billboards set price_7d_kobo = 10000$q$) like '%permission denied%', 'boards read-only');
  perform pg_temp.assert(pg_temp.err_of(format('delete from billboard_ads where user_id = %L', a)) like '%permission denied%', 'no deletes');
  reset role;
  perform pg_temp.assert(not exists (select 1 from jsonb_array_elements(billboard_list()->'boards') x, jsonb_array_elements(x->'ads') y
                                      where y->>'id' = r->>'ad_id'), 'unpaid ad not in the public rotation');
  set local role anon;
  perform pg_temp.assert(pg_temp.err_of('select billboard_list()') like '%permission denied%', 'anon cannot list');
  reset role;
end $$;

-- ---------- 10. storage policies ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; b uuid := current_setting('h3.b')::uuid; n int;
begin
  perform pg_temp.login(a);
  set local role authenticated;
  perform pg_temp.assert(pg_temp.err_of(format($q$insert into storage.objects (bucket_id, name, owner) values ('billboard-ads', %L, %L)$q$,
                         a::text || '/mine.webp', a)) = 'ok', 'upload into own folder');
  perform pg_temp.assert(pg_temp.hint_of(format($q$insert into storage.objects (bucket_id, name, owner) values ('billboard-ads', %L, %L)$q$,
                         b::text || '/theirs.webp', a)) like '%row-level security%', 'not into someone else''s folder');
  perform pg_temp.assert(pg_temp.hint_of(format($q$insert into storage.objects (bucket_id, name, owner) values ('billboard-ads', %L, %L)$q$,
                         a::text || '/x.svg', a)) like '%row-level security%', 'only jpg/png/webp');
  perform pg_temp.assert(pg_temp.hint_of(format($q$insert into storage.objects (bucket_id, name, owner) values ('billboard-ads', %L, %L)$q$,
                         a::text || '/deep/x.png', a)) like '%row-level security%', 'no sub folders');
  -- reads: own folder only (the public URL serves everyone; the API list is private)
  select count(*) into n from storage.objects where bucket_id = 'billboard-ads' and name like b::text || '/%';
  perform pg_temp.assert(n = 0, 'cannot list someone else''s uploads');
  select count(*) into n from storage.objects where bucket_id = 'billboard-ads' and name = a::text || '/mine.webp';
  perform pg_temp.assert(n = 1, 'reads own upload');
  reset role;
  -- deletes go through the Storage API (direct SQL deletes are blocked); the policy keeps used images
  perform pg_temp.assert((select qual from pg_policies where schemaname = 'storage' and policyname = 'billboard_ads_delete_unused')
                         like '%pending_review%live%', 'delete policy protects images of paid / live ads');
  set local role authenticated;
  reset role;
end $$;

-- ---------- 11. push subscriptions + inbox ----------
do $$
declare a uuid := current_setting('h3.a')::uuid; adm uuid := current_setting('h3.adm')::uuid; r jsonb; n int;
begin
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_push_subscribe('https://fcm.googleapis.com/fcm/send/x', repeat('B', 87), repeat('a', 22))$q$) = 'not_admin', 'players cannot subscribe');
  perform pg_temp.assert(pg_temp.hint_of('select admin_notifications()') = 'not_admin', 'players cannot read the inbox');
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_push_subscribe('http://bad', 'x', 'y')$q$) = 'bad_value', 'bad subscription refused');
  r := admin_push_subscribe('https://fcm.googleapis.com/fcm/send/abc123', repeat('B', 87), repeat('a', 22), 'test');
  r := admin_push_subscribe('https://fcm.googleapis.com/fcm/send/abc123', repeat('C', 87), repeat('b', 22), 'test');
  perform pg_temp.assert((r->>'subscriptions')::int = 1 and (select p256dh from push_subscriptions where endpoint like '%abc123') = repeat('C', 87), 'upsert by endpoint');
  r := admin_notifications(10);
  perform pg_temp.assert((r->>'unread')::int > 0 and jsonb_array_length(r->'rows') between 1 and 10, 'inbox unread');
  perform admin_notifications_seen(null);
  perform pg_temp.assert((admin_notifications(10)->>'unread')::int = 0, 'seen clears unread');
  perform bl_admin_notify('ad_paid', 'x', 'y');
  perform pg_temp.assert((admin_notifications(10)->>'unread')::int = 1, 'new one unread');
  -- outbox claim takes each row once
  select count(*) into n from bl_push_outbox_claim(1000);
  perform pg_temp.assert(n > 0 and not exists (select 1 from admin_notifications where pushed_at is null), 'outbox drained');
  select count(*) into n from bl_push_outbox_claim(10);
  perform pg_temp.assert(n = 0, 'nothing twice');
  r := admin_push_unsubscribe('https://fcm.googleapis.com/fcm/send/abc123');
  perform pg_temp.assert((r->>'subscriptions')::int = 0, 'unsubscribed');
end $$;

-- ---------- 12. Tokunbo Lot zones + car dealer row check ----------
do $$
declare adm uuid := current_setting('h3.adm')::uuid;
begin
  perform pg_temp.assert((select prop from place_zones where id = 'tokunbo_lot.showroom') <> 'lux_cars', 'no luxury corner at the Tokunbo Lot');
  perform pg_temp.assert(not exists (select 1 from zone_actions za join items i on i.id = za.ref
                                      where za.zone_id like 'tokunbo_lot.%' and za.kind = 'shop' and not ('tokunbo_lot' = any(i.sold_at))),
                         'every Tokunbo Lot shop action is something it sells');
  perform pg_temp.assert(exists (select 1 from place_zones where location_id = 'tokunbo_lot' and zone_key = 'lot' and prop = 'tokunbo_yard'),
                         'own front lot replaces the dealer lot (no Escalade / C300 / new Camry)');
  perform pg_temp.login(adm);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('car_dealers', '{"location_id":"new_dealer","tier":"mid","multiplier":1,"label":"x","blurb":"","sort":100,"active":false}')$q$) = 'bad_value', 'unknown place refused');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('car_dealers', '{"location_id":"oba_market","tier":"mid","multiplier":1,"label":"x","blurb":"","sort":100,"active":false}')$q$) = 'bad_value', 'non-dealer place refused');
  delete from car_dealers where location_id = 'ighodalo_cars';
  perform pg_temp.assert(admin_row_upsert('car_dealers', '{"location_id":"ighodalo_cars","tier":"mid","multiplier":1.05,"label":"Car dealer","blurb":"","sort":20,"active":true}')->>'message' = 'Added.', 'add row works');
  perform pg_temp.assert((select multiplier from car_dealers where location_id = 'ighodalo_cars') = 1.05, 'row saved');
  perform pg_temp.assert(exists (select 1 from admin_audit where action = 'row_insert' and data->>'table' = 'car_dealers'), 'insert audited');
end $$;

-- ---------- 13. admin Content -> Billboards ----------
do $$
declare adm uuid := current_setting('h3.adm')::uuid; a uuid := current_setting('h3.a')::uuid;
begin
  perform pg_temp.login(adm);
  perform admin_row_upsert('billboards', '{"id":"uselu","price_7d_kobo":3500000}');
  perform pg_temp.assert((select price_7d_kobo from billboards where id = 'uselu') = 3500000, 'admin edits prices');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('billboards', '{"id":"uselu","price_7d_kobo":"lots"}')$q$) = 'bad_value', 'typed');
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('billboards', '{"id":"uselu","price_1d_kobo":5}')$q$) = 'bad_value', 'minimum ₦100');
  perform pg_temp.login(a);
  perform pg_temp.assert(pg_temp.hint_of($q$select admin_row_upsert('billboards', '{"id":"uselu","price_7d_kobo":10000}')$q$) = 'not_admin', 'players cannot');
end $$;

select 'billboards_test: all groups passed' as result;
