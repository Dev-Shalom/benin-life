-- PAY: Paystack top-ups (server-verified), leaderboards (Rich list + VIP) and VIP arrival announcements.
-- docs/PAYMENTS.md. Idempotent and safe on a non-empty DB (create if not exists, on conflict do nothing,
-- create or replace). Re-created from their live definitions (grants kept): bl_ledger_label, travel_arrive,
-- bl_admin_table_spec.
--
-- Money flow: client -> payment_init (pending row + reference) -> Paystack Inline checkout -> Edge Function
-- paystack-verify (or the paystack-webhook backup) asks Paystack, then calls bl_payment_credit with the
-- service role. Only that function credits naira, only once per reference, only for the exact amount.

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('payments.enabled', 'false', 'payments', 'Top-ups live',
 'Real-money top-ups with Paystack. Off = the Wallet says "Coming soon" and nobody can start a payment. Turn on only after the Paystack keys are set (docs/PAYMENTS.md).', 'bool', null, null),
('payments.currency', '"NGN"', 'payments', 'Currency',
 'Currency of every pack price. Paystack verification checks it. Leave NGN.', 'text', null, null),
('leaderboard.hide_admins', 'true', 'leaderboard', 'Hide admins from the ranks',
 'Admins (who can grant themselves money) never show on the Rich list or VIP list.', 'bool', null, null),
('leaderboard.vip_show_amounts', 'false', 'leaderboard', 'VIP list: show ₦ spent',
 'Off = the VIP list shows only ranks and tier names. On = it also shows how much real money each player has spent.', 'bool', null, null),
('leaderboard.rich_tiers', '"Hustler:0, Big Boy:1000000, Oga:10000000, Chairman:100000000, Billionaire:1000000000"',
 'leaderboard', 'Rich list tiers',
 'Name:minimum pairs, comma separated. The minimum is game money (cash + bank, ₦) needed for the tier.', 'text', null, null),
('leaderboard.vip_tiers', '"Bronze:0, Silver:5000, Gold:20000, Platinum:100000, Odogwu:500000"',
 'leaderboard', 'VIP tiers',
 'Name:minimum pairs, comma separated. The minimum is real money spent on top-ups (₦, not kobo) needed for the tier.', 'text', null, null),
('vip.arrivals_enabled', 'true', 'vip', 'VIP arrival announcements',
 'When one of the top VIPs arrives at a place, everyone there sees "VIP #1 @name just walked into …".', 'bool', null, null),
('vip.arrival_cooldown_min', '30', 'vip', 'Arrival cooldown (real minutes)',
 'At most one arrival announcement per VIP in this many real minutes.', 'minutes', 0, 1440),
('vip.arrival_top', '3', 'vip', 'Announce the top … VIPs',
 'Only players ranked this high on the VIP list get an arrival announcement.', 'number', 1, 20)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.topup_packs (
  id          text primary key,
  label       text not null,
  game_naira  bigint not null check (game_naira > 0),
  price_kobo  bigint not null check (price_kobo >= 10000),
  bonus_tag   text,
  active      boolean not null default true,
  sort        int not null default 0
);
alter table public.topup_packs enable row level security;
revoke all on table public.topup_packs from public, anon, authenticated;
grant select on table public.topup_packs to authenticated;
grant select on table public.topup_packs to service_role;
drop policy if exists topup_packs_read on public.topup_packs;
create policy topup_packs_read on public.topup_packs for select to authenticated using (active);

insert into public.topup_packs (id, label, game_naira, price_kobo, bonus_tag, active, sort) values
('small',  'Small chops',   20000,   20000,   null,          true, 10),
('medium', 'Correct money', 120000,  100000,  '+20% bonus',  true, 20),
('big',    'Big boy pack',  650000,  500000,  '+30% bonus',  true, 30),
('oga',    'Oga pack',      1500000, 1000000, '+50% bonus',  true, 40),
('odogwu', 'Odogwu pack',   3500000, 2000000, '+75% bonus',  true, 50)
on conflict (id) do nothing;

create table if not exists public.payments (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete set null,
  pack_id     text references public.topup_packs(id),
  reference   text not null unique,
  amount_kobo bigint not null check (amount_kobo > 0),
  game_naira  bigint not null check (game_naira > 0),
  status      text not null default 'pending' check (status in ('pending', 'success', 'failed')),
  provider    text not null default 'paystack',
  created_at  timestamptz not null default now(),
  paid_at     timestamptz,
  raw         jsonb not null default '{}'::jsonb
);
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);
create index if not exists payments_status_idx on public.payments (status, created_at desc);
alter table public.payments enable row level security;
revoke all on table public.payments from public, anon, authenticated;
revoke all on sequence public.payments_id_seq from public, anon, authenticated;
grant select (id, user_id, pack_id, reference, amount_kobo, game_naira, status, provider, created_at, paid_at)
  on table public.payments to authenticated;
grant select on table public.payments to service_role;
drop policy if exists payments_read_own on public.payments;
create policy payments_read_own on public.payments for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Ledger label (live definition + "Top-up via Paystack")
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bl_ledger_label(p_reason text, p_meta jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  case p_reason
    when 'salary' then
      select 'Salary · ' || title into v from career_levels
       where track_id = p_meta->>'track' and level = (p_meta->>'level')::int;
      return coalesce(v, 'Salary');
    when 'shop' then
      select name into v from items where id = p_meta->>'item';
      return 'Bought ' || coalesce(v, 'something');
    when 'shop_sell' then
      select name into v from items where id = p_meta->>'item';
      return 'Sold ' || coalesce(v, 'something');
    when 'food_delivery' then
      select name into v from items where id = p_meta->>'item';
      return 'Chowdeck · ' || coalesce(v, 'food');
    when 'activity' then
      select name into v from activities where id = p_meta->>'activity';
      return coalesce(v, 'Activity');
    when 'travel' then
      return 'Transport · ' || case p_meta->>'mode' when 'keke' then 'keke' when 'bus' then 'bus'
                                    when 'drop' then 'drop taxi' when 'car' then 'fuel' else 'fare' end;
    when 'rent' then return case when (p_meta->>'settle')::boolean then 'Rent paid (owed)' else 'Rent' end;
    when 'street_robbery' then return 'Robbed on the street';
    when 'start_bonus' then return 'Starting money';
    when 'allowance' then return 'Dad''s allowance';
    when 'admin_origin' then return 'Account adjustment';
    when 'bank_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'Deposit · ' || coalesce(v, 'bank');
    when 'bank_withdraw' then
      select name into v from locations where id = p_meta->>'location';
      return 'Withdrawal · ' || coalesce(v, 'bank');
    when 'pos_cashout' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS cash-out' || coalesce(' · ' || v, '');
    when 'pos_deposit' then
      select name into v from locations where id = p_meta->>'location';
      return 'PoS deposit' || coalesce(' · ' || v, '');
    when 'pos_fee' then return 'PoS charge';
    when 'transfer_out' then return 'Sent to @' || coalesce(p_meta->>'to_username', 'player');
    when 'transfer_in' then return 'From @' || coalesce(p_meta->>'from_username', 'player');
    when 'transfer_fee' then return 'Transfer fee';
    when 'topup' then return 'Top-up via ' || coalesce(initcap(p_meta->>'provider'), 'Paystack');
    else return initcap(replace(coalesce(p_reason, 'money'), '_', ' '));
  end case;
end $function$;
revoke execute on function public.bl_ledger_label(text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. payment_init (players) and bl_payment_credit (service role only)
-- ---------------------------------------------------------------------
create or replace function public.payment_init(p_pack text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  k       topup_packs;
  v_email text;
  v_ref   text;
  v_ban   boolean;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  if not coalesce(bl_cfg_bool('payments.enabled'), false) then
    raise exception 'Top-ups are coming soon. Hold on to your naira for now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  select banned into v_ban from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_ban then
    raise exception 'This account can''t buy top-ups.' using errcode = 'P0001', hint = 'banned';
  end if;
  select * into k from topup_packs where id = p_pack and active;
  if not found then
    raise exception 'That pack is not on sale right now.' using errcode = 'P0001', hint = 'bad_pack';
  end if;
  select email into v_email from auth.users where id = v_uid;
  if coalesce(v_email, '') = '' then
    raise exception 'Your account needs an email address to pay.' using errcode = 'P0001', hint = 'no_email';
  end if;
  if (select count(*) from payments where user_id = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Too many payment attempts. Try again in a little while.' using errcode = 'P0001', hint = 'limit';
  end if;
  v_ref := 'BL-' || replace(gen_random_uuid()::text, '-', '');
  insert into payments (user_id, pack_id, reference, amount_kobo, game_naira, status, provider)
  values (v_uid, k.id, v_ref, k.price_kobo, k.game_naira, 'pending', 'paystack');
  return jsonb_build_object('reference', v_ref, 'amount_kobo', k.price_kobo, 'game_naira', k.game_naira,
                            'email', v_email, 'currency', coalesce(bl_cfg_text('payments.currency'), 'NGN'),
                            'pack', k.id, 'label', k.label);
end $$;
revoke execute on function public.payment_init(text) from public, anon;
grant execute on function public.payment_init(text) to authenticated;

create or replace function public.bl_payment_credit(p_reference text, p_amount_kobo bigint, p_raw jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v      payments;
  v_bank bigint;
begin
  select * into v from payments where reference = p_reference for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_reference');
  end if;
  if v.status = 'success' then
    return jsonb_build_object('ok', true, 'credited', false, 'already', true, 'user_id', v.user_id,
                              'game_naira', v.game_naira, 'bank', (select bank from profiles where id = v.user_id));
  end if;
  if v.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'not_pending', 'status', v.status);
  end if;
  if p_amount_kobo is distinct from v.amount_kobo then
    update payments set status = 'failed',
                        raw = coalesce(p_raw, '{}'::jsonb) || jsonb_build_object('bl_error', 'amount_mismatch', 'bl_paid_kobo', p_amount_kobo)
     where id = v.id;
    return jsonb_build_object('ok', false, 'error', 'amount_mismatch', 'expected', v.amount_kobo, 'got', p_amount_kobo);
  end if;
  if v.user_id is null or not exists (select 1 from profiles where id = v.user_id) then
    -- paid, but no Sim to credit right now: stays pending, a later verify / webhook retry credits it
    update payments set raw = coalesce(p_raw, '{}'::jsonb) where id = v.id;
    return jsonb_build_object('ok', false, 'error', 'no_profile');
  end if;
  v_bank := bl_add_money(v.user_id, 'bank', v.game_naira, 'topup',
                         jsonb_build_object('provider', v.provider, 'reference', v.reference, 'pack', v.pack_id));
  update payments set status = 'success', paid_at = now(), raw = coalesce(p_raw, '{}'::jsonb) where id = v.id;
  perform bl_event(v.user_id, 'topup', 'Top-up received',
                   bl_naira(v.game_naira) || ' landed in your bank. Thank you for supporting Benin Life!',
                   jsonb_build_object('reference', v.reference, 'game_naira', v.game_naira));
  return jsonb_build_object('ok', true, 'credited', true, 'user_id', v.user_id, 'game_naira', v.game_naira, 'bank', v_bank);
end $$;
revoke execute on function public.bl_payment_credit(text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.bl_payment_credit(text, bigint, jsonb) to service_role;

-- ---------------------------------------------------------------------
-- 5. Leaderboards
-- ---------------------------------------------------------------------
-- "Name:min, Name:min" -> [{name, min}] lowest first (bad pieces are skipped)
create or replace function public.bl_lb_tiers(p_key text) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'min', t.min) order by t.min), '[]'::jsonb)
    from (select trim(split_part(piece, ':', 1)) as name,
                 nullif(regexp_replace(split_part(piece, ':', 2), '[^0-9.]', '', 'g'), '')::numeric as min
            from regexp_split_to_table(coalesce(bl_cfg_text(p_key), ''), ',') piece) t
   where t.name <> '' and t.min is not null
$$;
revoke execute on function public.bl_lb_tiers(text) from public, anon, authenticated;

create or replace function public.bl_lb_tier(p_key text, p_amount numeric) returns text
language sql stable set search_path = public as $$
  select e->>'name' from jsonb_array_elements(bl_lb_tiers(p_key)) e
   where (e->>'min')::numeric <= coalesce(p_amount, 0)
   order by (e->>'min')::numeric desc limit 1
$$;
revoke execute on function public.bl_lb_tier(text, numeric) from public, anon, authenticated;

create or replace function public.bl_rich_ranked()
returns table (id uuid, username text, avatar jsonb, origin text, total bigint, rank bigint)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.avatar, p.origin, (p.cash + p.bank)::bigint,
         row_number() over (order by p.cash + p.bank desc, p.created_at, p.id)
    from profiles p
   where not p.banned and (not coalesce(bl_cfg_bool('leaderboard.hide_admins'), true) or not p.is_admin)
$$;
revoke execute on function public.bl_rich_ranked() from public, anon, authenticated;

create or replace function public.bl_vip_ranked()
returns table (id uuid, username text, avatar jsonb, origin text, kobo bigint, rank bigint)
language sql stable security definer set search_path = public as $$
  with s as (
    select user_id, sum(amount_kobo)::bigint as kobo, max(paid_at) as last_paid
      from payments where status = 'success' and user_id is not null group by user_id
  )
  select p.id, p.username, p.avatar, p.origin, s.kobo,
         row_number() over (order by s.kobo desc, s.last_paid, p.id)
    from s join profiles p on p.id = s.user_id
   where not p.banned and (not coalesce(bl_cfg_bool('leaderboard.hide_admins'), true) or not p.is_admin)
$$;
revoke execute on function public.bl_vip_ranked() from public, anon, authenticated;

create or replace function public.bl_vip_rank(p_uid uuid) returns int
language sql stable security definer set search_path = public as $$
  select rank::int from bl_vip_ranked() where id = p_uid
$$;
revoke execute on function public.bl_vip_rank(uuid) from public, anon, authenticated;

create or replace function public.leaderboard_rich(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  select count(*) into v_n from bl_rich_ranked();
  select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                               'origin', r.origin, 'total', r.total,
                                               'tier', bl_lb_tier('leaderboard.rich_tiers', r.total), 'me', r.id = v_uid)
                            order by r.rank), '[]'::jsonb)
    into v_rows from bl_rich_ranked() r where r.rank <= v_lim;
  select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                            'total', p.cash + p.bank, 'tier', bl_lb_tier('leaderboard.rich_tiers', p.cash + p.bank))
    into v_me from profiles p left join bl_rich_ranked() r on r.id = p.id where p.id = v_uid;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n,
                            'tiers', bl_lb_tiers('leaderboard.rich_tiers'));
end $$;
revoke execute on function public.leaderboard_rich(int) from public, anon;
grant execute on function public.leaderboard_rich(int) to authenticated;

create or replace function public.leaderboard_vip(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  v_lim  int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_show boolean := coalesce(bl_cfg_bool('leaderboard.vip_show_amounts'), false);
  v_rows jsonb;
  v_me   jsonb;
  v_n    bigint;
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  select count(*) into v_n from bl_vip_ranked();
  select coalesce(jsonb_agg(jsonb_build_object('rank', r.rank, 'id', r.id, 'username', r.username, 'avatar', r.avatar,
                                               'origin', r.origin, 'tier', bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0),
                                               'amount', case when v_show then r.kobo / 100 end, 'me', r.id = v_uid)
                            order by r.rank), '[]'::jsonb)
    into v_rows from bl_vip_ranked() r where r.rank <= v_lim;
  -- your own row: your amount is always shown to you
  select jsonb_build_object('rank', r.rank, 'id', p.id, 'username', p.username, 'avatar', p.avatar, 'origin', p.origin,
                            'tier', case when r.id is not null then bl_lb_tier('leaderboard.vip_tiers', r.kobo / 100.0) end,
                            'amount', coalesce(r.kobo, 0) / 100)
    into v_me from profiles p left join bl_vip_ranked() r on r.id = p.id where p.id = v_uid;
  return jsonb_build_object('rows', v_rows, 'me', v_me, 'players', v_n, 'show_amounts', v_show,
                            'tiers', bl_lb_tiers('leaderboard.vip_tiers'));
end $$;
revoke execute on function public.leaderboard_vip(int) from public, anon;
grant execute on function public.leaderboard_vip(int) to authenticated;

-- ---------------------------------------------------------------------
-- 6. VIP arrival announcements (place_announcements kind 'vip_arrival', the P2 realtime channel)
-- ---------------------------------------------------------------------
create or replace function public.bl_vip_arrival(p_uid uuid, p_loc text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_rank  int;
  v_name  text;
  v_home  text;
  l       locations;
  v_row   place_announcements;
begin
  if not coalesce(bl_cfg_bool('vip.arrivals_enabled'), true) then return null; end if;
  select username, home_location_id into v_name, v_home from profiles where id = p_uid;
  if not found or p_loc is null or p_loc = v_home then return null; end if;
  select * into l from locations where id = p_loc;
  if not found then return null; end if;
  v_rank := bl_vip_rank(p_uid);
  if v_rank is null or v_rank > greatest(1, coalesce(bl_cfg('vip.arrival_top'), 3)) then return null; end if;
  if exists (select 1 from place_announcements
              where user_id = p_uid and kind = 'vip_arrival'
                and created_at > now() - make_interval(mins => greatest(0, coalesce(bl_cfg('vip.arrival_cooldown_min'), 30))::int)) then
    return null;
  end if;
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, ticker, global)
  values (l.id, p_uid, v_name, 'vip_arrival', 0, v_rank,
          left(format('VIP #%s @%s just walked into %s!', v_rank, v_name, regexp_replace(l.name, '\s*\(.*\)\s*$', '')), 400),
          null, false)
  returning * into v_row;
  return to_jsonb(v_row);
exception when others then
  -- an announcement must never break arriving somewhere
  return null;
end $$;
revoke execute on function public.bl_vip_arrival(uuid, text) from public, anon, authenticated;

-- travel_arrive: live definition + the VIP arrival announcement
CREATE OR REPLACE FUNCTION public.travel_arrive()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_me      profiles := bl_me();
  v_now     timestamptz := bl_now();
  v_from    text;
  v_dest    text;
  v_mode    text;
  v_traffic numeric;
  v_robbed  jsonb;
  v_name    text;
  v_msg     text;
begin
  if v_me.travel_to is null then
    raise exception 'You are not travelling right now.' using errcode = 'P0001';
  end if;
  if v_now < v_me.travel_arrives_at then
    raise exception 'You haven''t arrived yet! About % sec left.',
      ceil(extract(epoch from v_me.travel_arrives_at - v_now)) using errcode = 'P0001';
  end if;
  v_from := v_me.location_id; v_dest := v_me.travel_to; v_mode := v_me.travel_mode;
  v_traffic := case when v_mode = 'walk' then 1 else bl_traffic(v_from, v_dest, v_me.travel_started_at) end;

  update profiles set location_id = v_dest, travel_to = null, travel_mode = null,
                      travel_started_at = null, travel_arrives_at = null, last_seen = v_now
  where id = v_me.id;

  -- PAY: a top VIP walking in is announced to everyone there
  perform bl_vip_arrival(v_me.id, v_dest);

  v_robbed := bl_roll_street_robbery(v_me.id, v_dest, v_mode, v_traffic);
  select name into v_name from locations where id = v_dest;

  if v_robbed is null then
    v_msg := 'You have arrived at ' || v_name || '.';
    return jsonb_build_object('message', v_msg, 'location', v_dest);
  end if;
  -- street moment: Pidgin stays
  v_msg := 'Omo! You reached ' || v_name || ' but some boys took '
           || bl_naira((v_robbed->>'amount')::bigint) || ' from you. You can report it to the Police.'
           || case when (v_robbed->>'injured')::boolean
                   then ' Dem wound you small. Go to UBTH or a clinic quick.' else '' end;
  return jsonb_build_object('message', v_msg, 'location', v_dest, 'robbed', v_robbed);
end $function$;
revoke execute on function public.travel_arrive() from public, anon;
grant execute on function public.travel_arrive() to authenticated;

-- ---------------------------------------------------------------------
-- 7. Admin: Content -> Top-up packs (whitelisted table) and the Payments view
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bl_admin_table_spec(p_table text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_table
    when 'origin_tiers' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","tagline":"text","welcome":"text","sort":"int","perks":"obj"}}'
    when 'traits' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","effects":"obj","sort":"int","active":"bool"}}'
    when 'dreams' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","goal":"obj","sort":"int","active":"bool"}}'
    when 'start_homes' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","location_id":"text","district":"text","tag":"text","description":"text",
              "weekly_rent":"money","start_cash":"obj","allowed_origins":"arr","locked_quip":"text","housing_id":"text",
              "sort":"int","active":"bool"}}'
    when 'career_tracks' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","description":"text","location_ids":"arr","skill":"text_null","sort":"int","active":"bool"}}'
    when 'career_levels' then '{"pk":["track_id","level"],"insert":true,"order":"track_id, level",
      "cols":{"title":"text","pay_per_shift":"money","shift_game_minutes":"int","energy_cost":"int","effects":"obj",
              "xp_per_shift":"int","xp_to_next":"int_null","requirements":"obj","perks":"obj"}}'
    when 'items' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","category":"text","price":"money","description":"text","effects":"obj","sold_at":"arr",
              "sellable":"bool","resale_pct":"num","icon":"text_null","sort":"int"}}'
    when 'activities' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","scenes":"arr","home_only":"bool","night_only":"bool","cost":"money","game_minutes":"int",
              "max_seconds":"num","min_seconds":"num","scale_by_need":"bool","needs_furniture":"bool","effects":"obj","sort":"int",
              "location_ids":"arr","risky":"bool","rush":"obj","icon":"text_null","requires_event":"text_null"}}'
    when 'locations' then '{"pk":["id"],"insert":false,"order":"sort, id",
      "cols":{"name":"text","blurb":"text","risk":"num","night_risk_mult":"num","cctv":"bool","keke_ok":"bool",
              "congestion":"num","remote_km":"num","actions":"arr","sort":"int","open_hour":"num_null","close_hour":"num_null","active":"bool"}}'
    when 'chat_banned_words' then '{"pk":["word"],"insert":true,"order":"word","cols":{"active":"bool"}}'
    when 'furniture' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","emoji":"text","kind":"text","slot":"text","activities":"arr","rest_pct":"int",
              "color":"text_null","description":"text","sort":"int","active":"bool"}}'
    when 'starter_furniture' then '{"pk":["id"],"insert":true,"order":"origin, sort, id",
      "cols":{"origin":"text","start_home":"text_null","furniture_id":"text","slot":"text_null","sort":"int","active":"bool"}}'
    when 'place_zones' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","zone_key":"text","label":"text","icon":"text","prop":"text",
              "x":"num","z":"num","w":"num","d":"num","rot":"int","note":"text_null","sort":"int","active":"bool"}}'
    when 'zone_actions' then '{"pk":["id"],"insert":true,"order":"zone_id, sort, id",
      "cols":{"zone_id":"text","kind":"text","ref":"text","label":"text_null","icon":"text_null","sort":"int","active":"bool"}}'
    when 'place_moods' then '{"pk":["id"],"insert":true,"order":"coalesce(scene, location_id), part, sort, id",
      "cols":{"scene":"text_null","location_id":"text_null","part":"text","icon":"text","line":"text","sort":"int","active":"bool"}}'
    when 'npc_roster' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","role":"text","motion":"text","avatar":"obj","lines":"text","pidgin":"text","scenes":"arr",
              "location_ids":"arr","zone_key":"text_null","headliner":"bool","sort":"int","active":"bool"}}'
    when 'crowd_profiles' then '{"pk":["id"],"insert":true,"order":"scene, from_hour, days, id",
      "cols":{"scene":"text","days":"text","from_hour":"int","to_hour":"int","npcs":"int","sort":"int","active":"bool"}}'
    when 'hype_templates' then '{"pk":["id"],"insert":true,"order":"kind, sort, id",
      "cols":{"kind":"text","line":"text","ticker":"text","sort":"int","active":"bool"}}'
    when 'place_events' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"location_id":"text","title":"text","description":"text","kind":"text","icon":"text","recurrence":"text",
              "weekday":"int_null","start_time":"num_null","end_time":"num_null","starts_at":"ts_null","ends_at":"ts_null",
              "ticket_price":"money","capacity":"int_null","perks":"obj","variants":"text","sort":"int","active":"bool"}}'
    when 'topup_packs' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"label":"text","game_naira":"money","price_kobo":"money","bonus_tag":"text_null","sort":"int","active":"bool"}}'
  end::jsonb;
$function$;
revoke execute on function public.bl_admin_table_spec(text) from public, anon, authenticated;

-- Payments view: recent payments (newest first, filter by status / username / reference) + revenue totals.
-- "Today" starts at midnight WAT, like admin_stats.
create or replace function public.admin_payments(p_status text default null, p_search text default null, p_limit int default 100)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today timestamptz := (date_trunc('day', now() at time zone 'Africa/Lagos')) at time zone 'Africa/Lagos';
  v_lim   int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_q     text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_rows  jsonb;
  v_tot   jsonb;
begin
  perform bl_admin_guard();
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into v_rows from (
    select pay.id, pay.reference, pay.user_id, p.username, pay.pack_id, k.label as pack_label, pay.amount_kobo, pay.game_naira,
           pay.status, pay.provider, pay.created_at, pay.paid_at,
           nullif(coalesce(pay.raw->>'bl_error', pay.raw->'data'->>'gateway_response', ''), '') as note
      from payments pay
      left join profiles p on p.id = pay.user_id
      left join topup_packs k on k.id = pay.pack_id
     where (p_status is null or p_status = '' or p_status = 'all' or pay.status = p_status)
       and (v_q is null or lower(coalesce(p.username, '')) like '%' || v_q || '%' or lower(pay.reference) like '%' || v_q || '%')
     order by pay.created_at desc
     limit v_lim) x;
  select jsonb_build_object(
    'today_kobo', coalesce(sum(amount_kobo) filter (where status = 'success' and paid_at >= v_today), 0),
    'today_count', count(*) filter (where status = 'success' and paid_at >= v_today),
    'd7_kobo', coalesce(sum(amount_kobo) filter (where status = 'success' and paid_at >= now() - interval '7 days'), 0),
    'd7_count', count(*) filter (where status = 'success' and paid_at >= now() - interval '7 days'),
    'all_kobo', coalesce(sum(amount_kobo) filter (where status = 'success'), 0),
    'all_count', count(*) filter (where status = 'success'),
    'payers', count(distinct user_id) filter (where status = 'success'),
    'pending', count(*) filter (where status = 'pending'),
    'failed', count(*) filter (where status = 'failed'),
    'naira_sold', coalesce(sum(game_naira) filter (where status = 'success'), 0))
    into v_tot from payments;
  return jsonb_build_object('rows', v_rows, 'totals', v_tot, 'enabled', coalesce(bl_cfg_bool('payments.enabled'), false));
end $$;
revoke execute on function public.admin_payments(text, text, int) from public, anon;
grant execute on function public.admin_payments(text, text, int) to authenticated;
