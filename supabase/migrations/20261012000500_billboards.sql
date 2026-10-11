-- H3 billboards (docs/BILLBOARDS.md): digital boards on the 3D city map that rotate player ads bought with
-- real money (Paystack), owner approval with automatic refunds, admin Web Push notifications.
-- Also: the Tokunbo Lot shows only the cars it sells (no luxury line-up), and a friendly check for
-- Admin -> Content -> Car dealers new rows.
--
-- Idempotent and safe on a non-empty DB: create ... if not exists, on conflict do nothing, create or replace,
-- guarded patches of live function definitions (bl_admin_table_spec). Grants are kept explicit.
--
-- Money flow (ads): billboard_ad_create (row 'awaiting_payment' + reference BLAD-<hex>, price from the board)
--   -> Paystack Inline checkout (metadata purpose 'billboard_ad', ad_id)
--   -> Edge Function paystack-verify (or the paystack-webhook backup) asks Paystack, then calls
--      bl_billboard_paid with the service role: 'pending_review' only when the paid amount = the stored price.
--   -> admin approves (live now .. now + days) or rejects (refund through the billboard-refund Edge Function).

-- ---------------------------------------------------------------------
-- 1. Config
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('billboards.enabled', 'true', 'billboards', 'Billboards on the map',
 'Digital billboards on the 3D city map. Off = no boards, nobody can buy an ad. Buying also needs payments.enabled.', 'bool', null, null),
('billboards.max_ads', '50', 'billboards', 'Ads per board',
 'Most live ads one board holds (they take turns). New ads are refused while a board is full (live + waiting for review).', 'number', 1, 200),
('billboards.rotate_seconds', '15', 'billboards', 'Seconds per ad',
 'Each ad shows this long before the next one fades in. Everyone sees the same ad at the same time (wall clock).', 'number', 5, 120),
('billboards.max_active_per_player', '3', 'billboards', 'Active ads per player',
 'Most ads one player can have waiting for review or live at the same time.', 'number', 1, 50),
('billboards.report_alert', '1', 'billboards', 'Notify after … reports',
 'Admins get a notification when an ad reaches this many player reports (and again each time it doubles).', 'number', 1, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------
create table if not exists public.billboards (
  id            text primary key,
  name          text not null,
  area          text not null default '',
  kind          text not null default 'standard' check (kind in ('mega', 'standard', 'local')),
  x             numeric not null check (x between 0 and 1000),
  y             numeric not null check (y between 0 and 1000),
  yaw           numeric not null default 0 check (yaw between -3.2 and 3.2),
  price_1d_kobo bigint not null check (price_1d_kobo >= 10000),
  price_3d_kobo bigint not null check (price_3d_kobo >= 10000),
  price_7d_kobo bigint not null check (price_7d_kobo >= 10000),
  sort          int not null default 100,
  active        boolean not null default true
);
alter table public.billboards enable row level security;
revoke all on table public.billboards from public, anon, authenticated;
grant select on table public.billboards to anon, authenticated;
grant select on table public.billboards to service_role;
drop policy if exists billboards_read on public.billboards;
create policy billboards_read on public.billboards for select to anon, authenticated using (active);

-- Prices in kobo (₦1 = 100 kobo). Busier boards cost more. Edit in Admin -> Content -> Billboards.
insert into public.billboards (id, name, area, kind, x, y, yaw, price_1d_kobo, price_3d_kobo, price_7d_kobo, sort) values
('ring_road',    'Ring Road mega screen',     'King''s Square · mega screen · digital', 'mega',     557, 468,  0.10, 5000000, 13000000, 25000000, 10),
('ramat_park',   'Ramat Park mega screen',    'Ramat Park junction · mega screen · digital', 'mega', 694, 398, -0.15, 4000000, 10000000, 20000000, 20),
('sapele_road',  'Sapele Rd screen',          'Sapele Rd by the Mall · digital',       'standard', 557, 672,  0.05, 2000000,  5000000, 10000000, 30),
('ugbowo',       'Ugbowo screen',             'UNIBEN main gate · digital',            'standard', 470, 148,  0.10, 2000000,  5000000, 10000000, 40),
('club_strip',   'GRA nightlife screen',      '360 Signature · Golden Tulip · digital','standard', 505, 690, -0.05, 1800000,  4500000,  9000000, 50),
('oba_market',   'Oba Market screen',         'Oba Market · Ring Road · digital',      'standard', 462, 436,  0.12, 1500000,  4000000,  8000000, 60),
('akpakpava',    'Akpakpava Rd screen',       'Akpakpava Rd · Ikpoba bridge · digital','standard', 596, 425, -0.10, 1200000,  3200000,  6500000, 70),
('uselu',        'Uselu Market screen',       'Uselu Market · Ugbowo Rd · digital',    'local',    448, 250,  0.10,  600000,  1500000,  3000000, 80),
('airport_road', 'Airport Rd screen',         'Airport Rd · GRA · digital',            'local',    398, 566,  0.20,  500000,  1300000,  2500000, 90),
('new_benin',    'New Benin screen',          'Mission Rd · New Benin Market · digital','local',   608, 343, -0.10,  500000,  1300000,  2500000, 100)
on conflict (id) do nothing;

create table if not exists public.billboard_ads (
  id            uuid primary key default gen_random_uuid(),
  board_id      text not null references public.billboards(id) on update cascade,
  user_id       uuid references auth.users(id) on delete set null,
  kind          text not null default 'paid' check (kind in ('paid', 'sponsor')),
  image_path    text not null,
  link_url      text,
  title         text not null default '',
  days          int not null default 1 check (days between 1 and 366),
  price_kobo    bigint not null default 0 check (price_kobo >= 0),
  status        text not null default 'awaiting_payment'
                check (status in ('awaiting_payment', 'pending_review', 'live', 'rejected', 'removed', 'expired', 'cancelled')),
  reference     text unique,
  paid_kobo     bigint,
  paid_at       timestamptz,
  pay_raw       jsonb not null default '{}'::jsonb,
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  reject_reason text,
  starts_at     timestamptz,
  ends_at       timestamptz,
  refund_status text not null default 'none' check (refund_status in ('none', 'pending', 'processing', 'refunded', 'refund_failed')),
  refund_kobo   bigint,
  refund_at     timestamptz,
  refund_error  text,
  refund_raw    jsonb not null default '{}'::jsonb,
  views         bigint not null default 0,
  taps          bigint not null default 0,
  reports       int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists billboard_ads_board_live_idx on public.billboard_ads (board_id, status, starts_at);
create index if not exists billboard_ads_user_idx on public.billboard_ads (user_id, created_at desc);
create index if not exists billboard_ads_status_idx on public.billboard_ads (status, created_at desc);
alter table public.billboard_ads enable row level security;
revoke all on table public.billboard_ads from public, anon, authenticated;
-- players read only their own ads (never the payment JSON); everything else goes through RPCs
grant select (id, board_id, user_id, kind, image_path, link_url, title, days, price_kobo, status, reference, paid_kobo, paid_at,
              reviewed_at, reject_reason, starts_at, ends_at, refund_status, refund_kobo, refund_at, views, taps, created_at)
  on table public.billboard_ads to authenticated;
grant select, insert, update on table public.billboard_ads to service_role;
drop policy if exists billboard_ads_read_own on public.billboard_ads;
create policy billboard_ads_read_own on public.billboard_ads for select to authenticated using (user_id = auth.uid());

create table if not exists public.billboard_reports (
  ad_id      uuid not null references public.billboard_ads(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  reason     text not null default '',
  created_at timestamptz not null default now(),
  primary key (ad_id, user_id)
);
alter table public.billboard_reports enable row level security;
revoke all on table public.billboard_reports from public, anon, authenticated;

-- rate limits for the view / tap counters
create table if not exists public.billboard_counter_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  ad_id   uuid not null,  -- '00000000-…' = the batched view counter
  kind    text not null check (kind in ('view', 'tap')),
  at      timestamptz not null default now(),
  primary key (user_id, ad_id, kind)
);
alter table public.billboard_counter_log enable row level security;
revoke all on table public.billboard_counter_log from public, anon, authenticated;

-- admin notifications: outbox for Web Push + the in-page inbox (unread badge fallback)
create table if not exists public.admin_notifications (
  id         bigserial primary key,
  kind       text not null,
  title      text not null,
  body       text not null default '',
  url        text not null default '/admin/ads',
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  pushed_at  timestamptz
);
create index if not exists admin_notifications_unpushed_idx on public.admin_notifications (id) where pushed_at is null;
alter table public.admin_notifications enable row level security;
revoke all on table public.admin_notifications from public, anon, authenticated;
revoke all on sequence public.admin_notifications_id_seq from public, anon, authenticated;
grant select, update on table public.admin_notifications to service_role;

create table if not exists public.admin_notify_seen (
  admin_id uuid primary key references auth.users(id) on delete cascade,
  last_id  bigint not null default 0
);
alter table public.admin_notify_seen enable row level security;
revoke all on table public.admin_notify_seen from public, anon, authenticated;

create table if not exists public.push_subscriptions (
  id         bigserial primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  last_ok_at timestamptz,
  fail_count int not null default 0
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
revoke all on table public.push_subscriptions from public, anon, authenticated;
revoke all on sequence public.push_subscriptions_id_seq from public, anon, authenticated;
grant select, update, delete on table public.push_subscriptions to service_role;

-- ---------------------------------------------------------------------
-- 3. Storage: public-read bucket, players upload only into their own folder
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('billboard-ads', 'billboard-ads', true, 1572864, array['image/jpeg', 'image/png', 'image/webp']::text[])
on conflict (id) do update set
  name = excluded.name,
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists billboard_ads_upload_own on storage.objects;
create policy billboard_ads_upload_own on storage.objects for insert to authenticated
  with check (
    bucket_id = 'billboard-ads'
    and (storage.foldername(name))[1] = auth.uid()::text
    and array_length(storage.foldername(name), 1) = 1
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
  );
drop policy if exists billboard_ads_read_own on storage.objects;
create policy billboard_ads_read_own on storage.objects for select to authenticated
  using (bucket_id = 'billboard-ads' and (storage.foldername(name))[1] = auth.uid()::text);
-- a player may delete an upload that no paid / live ad uses (e.g. a cancelled checkout)
drop policy if exists billboard_ads_delete_unused on storage.objects;
create policy billboard_ads_delete_unused on storage.objects for delete to authenticated
  using (
    bucket_id = 'billboard-ads'
    and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (select 1 from public.billboard_ads a
                     where a.image_path = storage.objects.name
                       and a.status in ('pending_review', 'live'))
  );

-- ---------------------------------------------------------------------
-- 4. Private helpers (service / definer use only)
-- ---------------------------------------------------------------------
create or replace function public.bl_billboard_link_ok(p_url text) returns boolean
language sql immutable set search_path = public as $$
  select p_url is not null and length(p_url) between 12 and 300
     and p_url ~ '^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}(:[0-9]{2,5})?([/?#][^[:space:]<>"''`\\]*)?$'
     and p_url !~ '@'
$$;

create or replace function public.bl_billboard_price(p_board public.billboards, p_days int) returns bigint
language sql immutable set search_path = public as $$
  select case p_days when 1 then p_board.price_1d_kobo when 3 then p_board.price_3d_kobo when 7 then p_board.price_7d_kobo end
$$;

create or replace function public.bl_admin_notify(p_kind text, p_title text, p_body text, p_data jsonb default '{}'::jsonb,
                                                  p_url text default '/admin/ads') returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into admin_notifications (kind, title, body, data, url)
  values (p_kind, left(p_title, 120), left(coalesce(p_body, ''), 300), coalesce(p_data, '{}'::jsonb), coalesce(p_url, '/admin/ads'))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.bl_board_name(p_board text) returns text
language sql stable set search_path = public as $$
  select coalesce((select name from billboards where id = p_board), p_board)
$$;

-- End finished ads (and stale unpaid checkouts). Called by billboard_list and the admin-push function.
create or replace function public.bl_billboard_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in update billboard_ads set status = 'expired', updated_at = now()
            where status = 'live' and ends_at <= now()
            returning id, board_id, user_id, kind, title loop
    n := n + 1;
    perform bl_admin_notify('ad_ended', 'Ad ended · ' || bl_board_name(r.board_id),
      case when r.kind = 'sponsor' then 'Sponsor ad' || coalesce(nullif(' "' || r.title || '"', ' ""'), '') || ' finished its run.'
           else coalesce('@' || (select username from profiles where id = r.user_id), 'A player') || '''s ad finished its run.' end,
      jsonb_build_object('ad_id', r.id, 'board', r.board_id));
    if r.user_id is not null and exists (select 1 from profiles where id = r.user_id) then
      perform bl_event(r.user_id, 'billboard_ended', 'Your billboard ad ended',
                       'Your ad on ' || bl_board_name(r.board_id) || ' finished its run. Book another one any time.',
                       jsonb_build_object('ad_id', r.id, 'board', r.board_id));
    end if;
  end loop;
  update billboard_ads set status = 'cancelled', updated_at = now()
   where status = 'awaiting_payment' and created_at < now() - interval '1 day';
  delete from admin_notifications where created_at < now() - interval '45 days';
  delete from billboard_counter_log where at < now() - interval '2 days';
  return n;
end $$;

-- Called by the Edge Functions (service role) after Paystack says the payment succeeded. Idempotent.
create or replace function public.bl_billboard_paid(p_reference text, p_amount_kobo bigint, p_raw jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare a billboard_ads; v_user text;
begin
  select * into a from billboard_ads where reference = p_reference for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_reference');
  end if;
  if a.paid_at is not null then
    return jsonb_build_object('ok', true, 'marked', false, 'already', true, 'ad_id', a.id, 'status', a.status, 'user_id', a.user_id);
  end if;
  if a.status not in ('awaiting_payment', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'not_awaiting', 'status', a.status);
  end if;
  v_user := coalesce('@' || (select username from profiles where id = a.user_id), 'A player');
  if p_amount_kobo is distinct from a.price_kobo then
    -- wrong amount: never goes on review; the money is refunded from the admin Ads page
    update billboard_ads set status = 'rejected', paid_kobo = p_amount_kobo, paid_at = now(),
                             reject_reason = 'The amount paid did not match the price.',
                             refund_status = case when coalesce(p_amount_kobo, 0) > 0 then 'pending' else 'none' end,
                             pay_raw = coalesce(p_raw, '{}'::jsonb) || jsonb_build_object('bl_error', 'amount_mismatch'),
                             updated_at = now()
     where id = a.id;
    perform bl_admin_notify('refund_needed', 'Refund needed · wrong amount',
      v_user || ' paid ' || bl_naira(coalesce(p_amount_kobo, 0) / 100) || ' instead of ' || bl_naira(a.price_kobo / 100)
      || ' for ' || bl_board_name(a.board_id) || '. Open Ads → Refunds.', jsonb_build_object('ad_id', a.id));
    return jsonb_build_object('ok', false, 'error', 'amount_mismatch', 'expected', a.price_kobo, 'got', p_amount_kobo, 'ad_id', a.id);
  end if;
  update billboard_ads set status = 'pending_review', paid_kobo = p_amount_kobo, paid_at = now(),
                           pay_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now()
   where id = a.id;
  perform bl_admin_notify('ad_paid', 'New ad to approve · ' || bl_naira(p_amount_kobo / 100),
    v_user || ' paid for ' || a.days || (case when a.days = 1 then ' day' else ' days' end) || ' on ' || bl_board_name(a.board_id) || '.',
    jsonb_build_object('ad_id', a.id, 'board', a.board_id));
  if a.user_id is not null and exists (select 1 from profiles where id = a.user_id) then
    perform bl_event(a.user_id, 'billboard_paid', 'Billboard ad paid',
                     'We got your payment. Your ad goes live on ' || bl_board_name(a.board_id) || ' as soon as it is checked (usually within a few hours).',
                     jsonb_build_object('ad_id', a.id, 'board', a.board_id));
  end if;
  return jsonb_build_object('ok', true, 'marked', true, 'ad_id', a.id, 'status', 'pending_review', 'user_id', a.user_id);
end $$;

-- billboard-refund Edge Function (service role): claim the refund so two clicks can't refund twice.
create or replace function public.bl_billboard_refund_claim(p_ad uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a billboard_ads;
begin
  select * into a from billboard_ads where id = p_ad for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_ad'); end if;
  if a.refund_status = 'refunded' then return jsonb_build_object('ok', false, 'error', 'already_refunded'); end if;
  if not (a.refund_status in ('pending', 'refund_failed')
          or (a.refund_status = 'processing' and a.updated_at < now() - interval '10 minutes')) then
    return jsonb_build_object('ok', false, 'error', 'no_refund_due', 'refund_status', a.refund_status);
  end if;
  if a.reference is null or coalesce(a.paid_kobo, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'not_paid');
  end if;
  update billboard_ads set refund_status = 'processing', updated_at = now() where id = a.id;
  return jsonb_build_object('ok', true, 'reference', a.reference, 'amount_kobo', coalesce(a.refund_kobo, a.paid_kobo));
end $$;

create or replace function public.bl_billboard_refund_result(p_ad uuid, p_ok boolean, p_error text default null,
                                                             p_raw jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a billboard_ads;
begin
  select * into a from billboard_ads where id = p_ad for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_ad'); end if;
  if a.refund_status <> 'processing' then
    return jsonb_build_object('ok', false, 'error', 'not_processing', 'refund_status', a.refund_status);
  end if;
  if p_ok then
    update billboard_ads set refund_status = 'refunded', refund_at = now(), refund_error = null,
                             refund_kobo = coalesce(refund_kobo, paid_kobo), refund_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now()
     where id = a.id;
    if a.user_id is not null and exists (select 1 from profiles where id = a.user_id) then
      perform bl_event(a.user_id, 'billboard_refund', 'Billboard refund sent',
                       bl_naira(coalesce(a.refund_kobo, a.paid_kobo) / 100) || ' is on its way back to your card or bank (Paystack takes a few days).',
                       jsonb_build_object('ad_id', a.id));
    end if;
  else
    update billboard_ads set refund_status = 'refund_failed', refund_error = left(coalesce(p_error, 'unknown error'), 300),
                             refund_raw = coalesce(p_raw, '{}'::jsonb), updated_at = now()
     where id = a.id;
    perform bl_admin_notify('refund_failed', 'Refund failed · ' || bl_naira(coalesce(a.refund_kobo, a.paid_kobo) / 100),
      'Paystack refused the refund for ' || coalesce(a.reference, '?') || ': ' || left(coalesce(p_error, 'unknown error'), 120)
      || '. Retry from Ads → Refunds or refund in the Paystack dashboard.', jsonb_build_object('ad_id', a.id));
  end if;
  return jsonb_build_object('ok', true, 'refund_status', case when p_ok then 'refunded' else 'refund_failed' end);
end $$;

-- admin-push Edge Function (service role): take the unsent notifications once (skip locked = no doubles)
create or replace function public.bl_push_outbox_claim(p_limit int default 20) returns setof public.admin_notifications
language sql security definer set search_path = public as $$
  update admin_notifications n set pushed_at = now()
   where n.id in (select id from admin_notifications where pushed_at is null
                   order by id limit greatest(1, least(coalesce(p_limit, 20), 100)) for update skip locked)
  returning n.*
$$;

revoke all on function public.bl_billboard_link_ok(text) from public, anon, authenticated;
revoke all on function public.bl_billboard_price(public.billboards, int) from public, anon, authenticated;
revoke all on function public.bl_admin_notify(text, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.bl_board_name(text) from public, anon, authenticated;
revoke all on function public.bl_billboard_sweep() from public, anon, authenticated;
revoke all on function public.bl_billboard_paid(text, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.bl_billboard_refund_claim(uuid) from public, anon, authenticated;
revoke all on function public.bl_billboard_refund_result(uuid, boolean, text, jsonb) from public, anon, authenticated;
revoke all on function public.bl_push_outbox_claim(int) from public, anon, authenticated;
grant execute on function public.bl_billboard_sweep() to service_role;
grant execute on function public.bl_billboard_paid(text, bigint, jsonb) to service_role;
grant execute on function public.bl_billboard_refund_claim(uuid) to service_role;
grant execute on function public.bl_billboard_refund_result(uuid, boolean, text, jsonb) to service_role;
grant execute on function public.bl_push_outbox_claim(int) to service_role;

-- ---------------------------------------------------------------------
-- 5. Player RPCs
-- ---------------------------------------------------------------------
-- Boards + the live rotation (same order for everyone, so the wall clock picks the same ad everywhere).
create or replace function public.billboard_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_max int := greatest(1, coalesce(bl_cfg('billboards.max_ads'), 50)::int);
begin
  if auth.uid() is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  perform bl_billboard_sweep();
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('billboards.enabled'), false),
    'buy_enabled', coalesce(bl_cfg_bool('billboards.enabled'), false) and coalesce(bl_cfg_bool('payments.enabled'), false),
    'rotate_seconds', coalesce(bl_cfg('billboards.rotate_seconds'), 15),
    'max_ads', v_max,
    'now', now(),
    -- admin notifications waiting for Web Push: the client then pokes the admin-push function once
    'pending_push', exists (select 1 from admin_notifications where pushed_at is null and created_at > now() - interval '1 day'),
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', b.id, 'name', b.name, 'area', b.area, 'kind', b.kind, 'x', b.x, 'y', b.y, 'yaw', b.yaw,
               'prices', jsonb_build_object('1', b.price_1d_kobo, '3', b.price_3d_kobo, '7', b.price_7d_kobo),
               'queued', (select count(*) from billboard_ads q where q.board_id = b.id and q.status = 'pending_review'),
               'ads', coalesce((
                 select jsonb_agg(jsonb_build_object('id', t.id, 'image', t.image_path, 'link', t.link_url, 'ends_at', t.ends_at,
                                                     'sponsor', t.kind = 'sponsor', 'mine', t.user_id = auth.uid())
                                  order by t.starts_at, t.id)
                   from (select a.* from billboard_ads a
                          where a.board_id = b.id and a.status = 'live' and a.starts_at <= now() and a.ends_at > now()
                          order by a.starts_at, a.id limit v_max) t), '[]'::jsonb))
             order by b.sort, b.id)
        from billboards b where b.active), '[]'::jsonb));
end $$;

create or replace function public.billboard_ad_create(p_board text, p_days int, p_image_path text, p_link text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  b       billboards;
  v_ban   boolean;
  v_email text;
  v_price bigint;
  v_ref   text;
  v_id    uuid;
  v_max   int := greatest(1, coalesce(bl_cfg('billboards.max_ads'), 50)::int);
  v_lim   int := greatest(1, coalesce(bl_cfg('billboards.max_active_per_player'), 3)::int);
  v_link  text := btrim(coalesce(p_link, ''));
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  if not coalesce(bl_cfg_bool('billboards.enabled'), false) then
    raise exception 'Billboards are off right now.' using errcode = 'P0001', hint = 'disabled';
  end if;
  if not coalesce(bl_cfg_bool('payments.enabled'), false) then
    raise exception 'Ad payments are coming soon.' using errcode = 'P0001', hint = 'payments_off';
  end if;
  select banned into v_ban from profiles where id = v_uid;
  if not found then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  if v_ban then
    raise exception 'This account can''t buy ads.' using errcode = 'P0001', hint = 'banned';
  end if;
  select * into b from billboards where id = p_board and active;
  if not found then
    raise exception 'That billboard is not available.' using errcode = 'P0001', hint = 'bad_board';
  end if;
  if p_days is null or p_days not in (1, 3, 7) then
    raise exception 'Pick 1, 3 or 7 days.' using errcode = 'P0001', hint = 'bad_days';
  end if;
  if not bl_billboard_link_ok(v_link) then
    raise exception 'Add a full link that starts with https:// (for example https://wa.me/234…).' using errcode = 'P0001', hint = 'bad_link';
  end if;
  if p_image_path is null
     or p_image_path !~ ('^' || v_uid::text || '/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$')
     or not exists (select 1 from storage.objects o where o.bucket_id = 'billboard-ads' and o.name = p_image_path) then
    raise exception 'Upload your image first.' using errcode = 'P0001', hint = 'bad_image';
  end if;
  select email into v_email from auth.users where id = v_uid;
  if coalesce(v_email, '') = '' then
    raise exception 'Your account needs an email address to pay.' using errcode = 'P0001', hint = 'no_email';
  end if;
  perform 1 from profiles where id = v_uid for update; -- one create at a time per player (limit check below)
  if (select count(*) from billboard_ads
       where user_id = v_uid
         and (status = 'pending_review' or (status = 'live' and ends_at > now())
              or (status = 'awaiting_payment' and created_at > now() - interval '1 hour'))) >= v_lim then
    raise exception 'You already have % ads running or waiting. Wait for one to end.', v_lim using errcode = 'P0001', hint = 'limit';
  end if;
  if (select count(*) from billboard_ads where user_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Too many tries. Wait a little and try again.' using errcode = 'P0001', hint = 'rate';
  end if;
  if (select count(*) from billboard_ads where board_id = b.id
        and (status = 'pending_review' or (status = 'live' and ends_at > now()))) >= v_max then
    raise exception 'This board is full right now. Try another board.' using errcode = 'P0001', hint = 'board_full';
  end if;
  v_price := bl_billboard_price(b, p_days);
  v_ref := 'BLAD-' || replace(gen_random_uuid()::text, '-', '');
  insert into billboard_ads (board_id, user_id, kind, image_path, link_url, days, price_kobo, status, reference)
  values (b.id, v_uid, 'paid', p_image_path, v_link, p_days, v_price, 'awaiting_payment', v_ref)
  returning id into v_id;
  return jsonb_build_object('ad_id', v_id, 'reference', v_ref, 'amount_kobo', v_price, 'email', v_email,
                            'currency', coalesce(bl_cfg_text('payments.currency'), 'NGN'), 'board', b.id, 'days', p_days);
end $$;

create or replace function public.billboard_ad_cancel(p_ad uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update billboard_ads set status = 'cancelled', updated_at = now()
   where id = p_ad and user_id = auth.uid() and status = 'awaiting_payment' and paid_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('cancelled', n > 0);
end $$;

create or replace function public.billboard_my_ads() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'board_id', a.board_id, 'board', b.name, 'area', b.area, 'image', a.image_path, 'link', a.link_url,
           'days', a.days, 'price_kobo', a.price_kobo, 'paid_kobo', a.paid_kobo,
           'status', case when a.status = 'live' and a.ends_at <= now() then 'expired' else a.status end,
           'starts_at', a.starts_at, 'ends_at', a.ends_at, 'created_at', a.created_at, 'reject_reason', a.reject_reason,
           'refund_status', a.refund_status, 'views', a.views, 'taps', a.taps, 'reference', a.reference)
           order by a.created_at desc), '[]'::jsonb)
    from billboard_ads a join billboards b on b.id = a.board_id
   where a.user_id = auth.uid() and a.status <> 'cancelled' and auth.uid() is not null
$$;

create or replace function public.billboard_report(p_ad uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); a billboard_ads; n int; v_alert int := greatest(1, coalesce(bl_cfg('billboards.report_alert'), 1)::int);
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = 'P0001', hint = 'auth';
  end if;
  select * into a from billboard_ads where id = p_ad and status = 'live' for update;
  if not found then
    raise exception 'That ad is not showing any more.' using errcode = 'P0001', hint = 'not_live';
  end if;
  if a.user_id = v_uid then
    raise exception 'You can''t report your own ad.' using errcode = 'P0001', hint = 'own_ad';
  end if;
  insert into billboard_reports (ad_id, user_id, reason) values (a.id, v_uid, left(btrim(coalesce(p_reason, '')), 200))
  on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('reported', false, 'already', true, 'message', 'You already reported this ad. Thanks!');
  end if;
  update billboard_ads set reports = reports + 1 where id = a.id returning reports into n;
  -- notify at the threshold, then every time the count doubles
  if n >= v_alert and (n = v_alert or (n % v_alert = 0 and ((n / v_alert) & ((n / v_alert) - 1)) = 0)) then
    perform bl_admin_notify('ad_reported', 'Ad reported · ' || bl_board_name(a.board_id),
      n || (case when n = 1 then ' report' else ' reports' end) || ' on '
      || coalesce('@' || (select username from profiles where id = a.user_id) || '''s ad', 'a sponsor ad')
      || coalesce(': "' || nullif(left(btrim(coalesce(p_reason, '')), 80), '') || '"', '') || '.',
      jsonb_build_object('ad_id', a.id, 'reports', n));
  end if;
  return jsonb_build_object('reported', true, 'message', 'Thanks. The Benin Life team will check this ad.');
end $$;

create or replace function public.billboard_tap(p_ad uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); n int;
begin
  if v_uid is null then return jsonb_build_object('counted', false); end if;
  if not exists (select 1 from billboard_ads where id = p_ad and status = 'live') then return jsonb_build_object('counted', false); end if;
  insert into billboard_counter_log (user_id, ad_id, kind, at) values (v_uid, p_ad, 'tap', now())
  on conflict (user_id, ad_id, kind) do update set at = excluded.at
   where billboard_counter_log.at < now() - interval '1 hour';
  get diagnostics n = row_count;
  if n > 0 then update billboard_ads set taps = taps + 1 where id = p_ad; end if;
  return jsonb_build_object('counted', n > 0);
end $$;

-- Batched views from the map ({"<ad uuid>": count}); at most one batch per player per 50 s, 10 per ad per batch.
create or replace function public.billboard_track(p_views jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); n int; k text; c int; v_total int := 0;
begin
  if v_uid is null or jsonb_typeof(p_views) is distinct from 'object' then return jsonb_build_object('counted', 0); end if;
  insert into billboard_counter_log (user_id, ad_id, kind, at) values (v_uid, '00000000-0000-0000-0000-000000000000', 'view', now())
  on conflict (user_id, ad_id, kind) do update set at = excluded.at
   where billboard_counter_log.at < now() - interval '50 seconds';
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('counted', 0, 'throttled', true); end if;
  for k in select jsonb_object_keys(p_views) limit 60 loop
    continue when k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    c := case when (p_views->>k) ~ '^[0-9]{1,6}$' then least(10, (p_views->>k)::int) else 0 end;
    continue when c = 0;
    update billboard_ads set views = views + c where id = k::uuid and status = 'live';
    if found then v_total := v_total + c; end if;
  end loop;
  return jsonb_build_object('counted', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 6. Admin RPCs (bl_admin_guard + admin_audit)
-- ---------------------------------------------------------------------
create or replace function public.admin_billboard_queue(p_filter text default 'review', p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_filter text := coalesce(p_filter, 'review');
begin
  perform bl_billboard_sweep();
  return jsonb_build_object(
    'counts', jsonb_build_object(
      'review',   (select count(*) from billboard_ads where status = 'pending_review'),
      'live',     (select count(*) from billboard_ads where status = 'live'),
      'reported', (select count(*) from billboard_ads where status = 'live' and reports > 0),
      'refunds',  (select count(*) from billboard_ads where refund_status in ('pending', 'processing', 'refund_failed')),
      'ended',    (select count(*) from billboard_ads where status in ('expired', 'removed', 'rejected'))),
    'payments_enabled', coalesce(bl_cfg_bool('payments.enabled'), false),
    'boards', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'area', area,
                         'live', (select count(*) from billboard_ads a where a.board_id = b.id and a.status = 'live')) order by sort, id)
                          from billboards b), '[]'::jsonb),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'board_id', a.board_id, 'board', b.name, 'kind', a.kind, 'status', a.status,
               'image', a.image_path, 'link', a.link_url, 'title', a.title, 'days', a.days, 'price_kobo', a.price_kobo,
               'paid_kobo', a.paid_kobo, 'paid_at', a.paid_at, 'created_at', a.created_at, 'starts_at', a.starts_at, 'ends_at', a.ends_at,
               'reviewed_at', a.reviewed_at, 'reviewer', (select username from profiles where id = a.reviewed_by),
               'reject_reason', a.reject_reason, 'refund_status', a.refund_status, 'refund_kobo', a.refund_kobo,
               'refund_error', a.refund_error, 'reference', a.reference, 'user_id', a.user_id,
               'username', p.username, 'email', u.email, 'views', a.views, 'taps', a.taps, 'reports', a.reports,
               'report_reasons', (select coalesce(jsonb_agg(r.reason order by r.created_at desc), '[]'::jsonb)
                                    from (select reason, created_at from billboard_reports where ad_id = a.id and reason <> ''
                                           order by created_at desc limit 5) r))
             order by case when v_filter = 'review' then a.paid_at end asc nulls last, a.created_at desc)
        from (select * from billboard_ads x
               where case v_filter
                       when 'review' then x.status = 'pending_review'
                       when 'live' then x.status = 'live'
                       when 'reported' then x.status = 'live' and x.reports > 0
                       when 'refunds' then x.refund_status in ('pending', 'processing', 'refund_failed')
                       when 'ended' then x.status in ('expired', 'removed', 'rejected')
                       else x.status not in ('awaiting_payment', 'cancelled') end
               order by x.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 300))) a
        join billboards b on b.id = a.board_id
        left join profiles p on p.id = a.user_id
        left join auth.users u on u.id = a.user_id), '[]'::jsonb));
end $$;

create or replace function public.admin_billboard_approve(p_ad uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a billboard_ads; v_max int := greatest(1, coalesce(bl_cfg('billboards.max_ads'), 50)::int);
begin
  select * into a from billboard_ads where id = p_ad for update;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001', hint = 'unknown_ad';
  end if;
  if a.status <> 'pending_review' or a.paid_at is null then
    raise exception 'Only paid ads waiting for review can be approved (this one is %).', a.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  if (select count(*) from billboard_ads where board_id = a.board_id and status = 'live' and ends_at > now()) >= v_max then
    raise exception 'This board already shows % ads. Remove one or raise billboards.max_ads.', v_max using errcode = 'P0001', hint = 'board_full';
  end if;
  update billboard_ads set status = 'live', reviewed_by = v_admin, reviewed_at = now(), starts_at = now(),
                           ends_at = now() + make_interval(days => a.days), updated_at = now()
   where id = a.id returning * into a;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'billboard_approve', a.user_id, jsonb_build_object('ad_id', a.id, 'board', a.board_id, 'days', a.days,
          'paid_kobo', a.paid_kobo, 'ends_at', a.ends_at));
  perform bl_admin_notify('ad_live', 'Ad live · ' || bl_board_name(a.board_id),
    coalesce('@' || (select username from profiles where id = a.user_id), 'A player') || '''s ad is on air until '
    || to_char(a.ends_at at time zone 'Africa/Lagos', 'Dy DD Mon, HH24:MI') || ' (WAT).', jsonb_build_object('ad_id', a.id));
  if a.user_id is not null and exists (select 1 from profiles where id = a.user_id) then
    perform bl_event(a.user_id, 'billboard_approved', 'Your billboard ad is live!',
                     'Your ad is on ' || bl_board_name(a.board_id) || ' now, until '
                     || to_char(a.ends_at at time zone 'Africa/Lagos', 'Dy DD Mon') || '. See views and taps in Phone → Billboards.',
                     jsonb_build_object('ad_id', a.id, 'board', a.board_id));
  end if;
  return jsonb_build_object('message', 'Approved. The ad is live now.', 'ad_id', a.id, 'ends_at', a.ends_at);
end $$;

create or replace function public.admin_billboard_reject(p_ad uuid, p_reason text, p_refund boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a billboard_ads; v_reason text := left(btrim(coalesce(p_reason, '')), 300); v_refund boolean;
begin
  if v_reason = '' then
    raise exception 'Write a short reason (the player sees it).' using errcode = 'P0001', hint = 'reason';
  end if;
  select * into a from billboard_ads where id = p_ad for update;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001', hint = 'unknown_ad';
  end if;
  if a.status <> 'pending_review' then
    raise exception 'Only ads waiting for review can be rejected (this one is %).', a.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  v_refund := coalesce(p_refund, true) and coalesce(a.paid_kobo, 0) > 0 and a.reference is not null;
  update billboard_ads set status = 'rejected', reviewed_by = v_admin, reviewed_at = now(), reject_reason = v_reason,
                           refund_status = case when v_refund then 'pending' else refund_status end,
                           refund_kobo = case when v_refund then a.paid_kobo else refund_kobo end, updated_at = now()
   where id = a.id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'billboard_reject', a.user_id, jsonb_build_object('ad_id', a.id, 'board', a.board_id, 'reason', v_reason,
          'refund', v_refund, 'paid_kobo', a.paid_kobo));
  if a.user_id is not null and exists (select 1 from profiles where id = a.user_id) then
    perform bl_event(a.user_id, 'billboard_rejected', 'Billboard ad not approved',
                     'Reason: ' || v_reason || case when v_refund then ' Your money is being refunded.' else '' end,
                     jsonb_build_object('ad_id', a.id, 'board', a.board_id));
  end if;
  return jsonb_build_object('message', case when v_refund then 'Rejected. Refunding now…' else 'Rejected.' end,
                            'ad_id', a.id, 'refund', v_refund);
end $$;

create or replace function public.admin_billboard_remove(p_ad uuid, p_reason text, p_refund boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a billboard_ads; v_reason text := left(btrim(coalesce(p_reason, '')), 300); v_refund boolean;
begin
  select * into a from billboard_ads where id = p_ad for update;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001', hint = 'unknown_ad';
  end if;
  if a.status <> 'live' then
    raise exception 'Only live ads can be removed (this one is %).', a.status using errcode = 'P0001', hint = 'bad_status';
  end if;
  v_refund := coalesce(p_refund, false) and a.kind = 'paid' and coalesce(a.paid_kobo, 0) > 0 and a.reference is not null;
  update billboard_ads set status = 'removed', ends_at = least(ends_at, now()), reviewed_by = v_admin, reviewed_at = now(),
                           reject_reason = nullif(v_reason, ''),
                           refund_status = case when v_refund then 'pending' else refund_status end,
                           refund_kobo = case when v_refund then a.paid_kobo else refund_kobo end, updated_at = now()
   where id = a.id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'billboard_remove', a.user_id, jsonb_build_object('ad_id', a.id, 'board', a.board_id, 'reason', v_reason,
          'refund', v_refund, 'kind', a.kind));
  if a.user_id is not null and exists (select 1 from profiles where id = a.user_id) then
    perform bl_event(a.user_id, 'billboard_removed', 'Billboard ad taken down',
                     coalesce('Reason: ' || nullif(v_reason, '') || ' ', '') || case when v_refund then 'Your money is being refunded.'
                       else 'Ads that break the rules are removed without a refund.' end,
                     jsonb_build_object('ad_id', a.id, 'board', a.board_id));
  end if;
  return jsonb_build_object('message', case when v_refund then 'Removed. Refunding now…' else 'Removed.' end, 'ad_id', a.id, 'refund', v_refund);
end $$;

-- billboard-refund Edge Function calls this with the admin's JWT first (admin check + audit), then refunds.
create or replace function public.admin_billboard_refund_start(p_ad uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); a billboard_ads;
begin
  select * into a from billboard_ads where id = p_ad;
  if not found then
    raise exception 'No such ad.' using errcode = 'P0001', hint = 'unknown_ad';
  end if;
  if a.refund_status not in ('pending', 'processing', 'refund_failed') then
    raise exception 'No refund is due on this ad (%).', a.refund_status using errcode = 'P0001', hint = 'no_refund_due';
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'billboard_refund', a.user_id, jsonb_build_object('ad_id', a.id, 'reference', a.reference,
          'amount_kobo', coalesce(a.refund_kobo, a.paid_kobo), 'retry', a.refund_status = 'refund_failed'));
  return jsonb_build_object('ok', true, 'ad_id', a.id);
end $$;

-- A free sponsor ad on any board for any period (real-life sponsors). p_image: a billboard-ads path or an https URL.
create or replace function public.admin_billboard_sponsor(p_board text, p_image text, p_link text, p_starts timestamptz,
                                                          p_ends timestamptz, p_title text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_id uuid; v_starts timestamptz := coalesce(p_starts, now()); v_link text := nullif(btrim(coalesce(p_link, '')), '');
begin
  if not exists (select 1 from billboards where id = p_board) then
    raise exception 'Pick a board.' using errcode = 'P0001', hint = 'bad_board';
  end if;
  if p_image is null or not ((p_image ~ '^https://[^[:space:]]{8,}$' and length(p_image) <= 500)
       or exists (select 1 from storage.objects o where o.bucket_id = 'billboard-ads' and o.name = p_image)) then
    raise exception 'Upload the sponsor image first (or paste an https image link).' using errcode = 'P0001', hint = 'bad_image';
  end if;
  if v_link is not null and not bl_billboard_link_ok(v_link) then
    raise exception 'The link must start with https://' using errcode = 'P0001', hint = 'bad_link';
  end if;
  if p_ends is null or p_ends <= v_starts or p_ends <= now() then
    raise exception 'The end must be after the start and in the future.' using errcode = 'P0001', hint = 'bad_dates';
  end if;
  insert into billboard_ads (board_id, user_id, kind, image_path, link_url, title, days, price_kobo, status,
                             reviewed_by, reviewed_at, starts_at, ends_at)
  values (p_board, null, 'sponsor', p_image, v_link, left(btrim(coalesce(p_title, '')), 80),
          greatest(1, least(366, ceil(extract(epoch from (p_ends - v_starts)) / 86400)::int)), 0, 'live',
          v_admin, now(), v_starts, p_ends)
  returning id into v_id;
  insert into admin_audit (admin_id, action, data)
  values (v_admin, 'billboard_sponsor', jsonb_build_object('ad_id', v_id, 'board', p_board, 'title', p_title,
          'starts_at', v_starts, 'ends_at', p_ends, 'link', v_link));
  return jsonb_build_object('message', 'Sponsor ad placed.', 'ad_id', v_id);
end $$;

-- Notifications inbox (unread badge + sound when Web Push is unavailable) and push subscriptions
create or replace function public.admin_notifications(p_limit int default 30) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_seen bigint;
begin
  select last_id into v_seen from admin_notify_seen where admin_id = v_admin;
  v_seen := coalesce(v_seen, 0);
  return jsonb_build_object(
    'unread', (select count(*) from admin_notifications where id > v_seen),
    'last_id', coalesce((select max(id) from admin_notifications), 0),
    'seen_id', v_seen,
    'subscriptions', (select count(*) from push_subscriptions where user_id = v_admin),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'title', title, 'body', body, 'url', url,
                                                          'created_at', created_at, 'unread', id > v_seen) order by id desc)
                        from (select * from admin_notifications order by id desc
                               limit greatest(1, least(coalesce(p_limit, 30), 100))) n), '[]'::jsonb));
end $$;

create or replace function public.admin_notifications_seen(p_last_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_id bigint := coalesce(p_last_id, (select max(id) from admin_notifications), 0);
begin
  insert into admin_notify_seen (admin_id, last_id) values (v_admin, v_id)
  on conflict (admin_id) do update set last_id = greatest(admin_notify_seen.last_id, excluded.last_id);
  return jsonb_build_object('seen_id', v_id);
end $$;

create or replace function public.admin_push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  if p_endpoint is null or p_endpoint !~ '^https://[^[:space:]]{10,}$' or length(p_endpoint) > 1000
     or coalesce(p_p256dh, '') !~ '^[A-Za-z0-9_=-]{60,120}$' or coalesce(p_auth, '') !~ '^[A-Za-z0-9_=-]{16,40}$' then
    raise exception 'That push subscription looks wrong.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (v_admin, p_endpoint, p_p256dh, p_auth, left(coalesce(p_user_agent, ''), 200))
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
                                       user_agent = excluded.user_agent, fail_count = 0;
  insert into admin_audit (admin_id, action, data) values (v_admin, 'push_subscribe', jsonb_build_object('ua', left(coalesce(p_user_agent, ''), 120)));
  return jsonb_build_object('message', 'Notifications are on for this device.',
                            'subscriptions', (select count(*) from push_subscriptions where user_id = v_admin));
end $$;

create or replace function public.admin_push_unsubscribe(p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard();
begin
  delete from push_subscriptions where user_id = v_admin and endpoint = p_endpoint;
  return jsonb_build_object('message', 'Notifications are off for this device.',
                            'subscriptions', (select count(*) from push_subscriptions where user_id = v_admin));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'billboard_list()', 'billboard_ad_create(text,int,text,text)', 'billboard_ad_cancel(uuid)', 'billboard_my_ads()',
    'billboard_report(uuid,text)', 'billboard_tap(uuid)', 'billboard_track(jsonb)',
    'admin_billboard_queue(text,int)', 'admin_billboard_approve(uuid)', 'admin_billboard_reject(uuid,text,boolean)',
    'admin_billboard_remove(uuid,text,boolean)', 'admin_billboard_refund_start(uuid)',
    'admin_billboard_sponsor(text,text,text,timestamptz,timestamptz,text)',
    'admin_notifications(int)', 'admin_notifications_seen(bigint)', 'admin_push_subscribe(text,text,text,text)',
    'admin_push_unsubscribe(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 7. Admin Content -> Billboards (prices per board) via admin_row_upsert
-- ---------------------------------------------------------------------
create or replace function pg_temp.h3_patch(p_fn text, p_guard text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  v_def := pg_get_functiondef(p_fn::regprocedure);
  if position(p_guard in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / greatest(length(p_marker), 1);
  if v_n <> 1 then
    raise exception 'H3: marker for % found % times: %', p_fn, v_n, p_marker;
  end if;
  execute replace(v_def, p_marker, p_new);
end $$;

do $mig$
begin
  perform pg_temp.h3_patch('public.bl_admin_table_spec(text)', $g$'billboards'$g$,
    $m$    when 'car_dealers' then$m$,
    $m$    when 'billboards' then '{"pk":["id"],"insert":true,"order":"sort, id",
      "cols":{"name":"text","area":"text","kind":"text","x":"num","y":"num","yaw":"num","price_1d_kobo":"int",
              "price_3d_kobo":"int","price_7d_kobo":"int","sort":"int","active":"bool"}}'
    when 'car_dealers' then$m$);
end $mig$;

-- ---------------------------------------------------------------------
-- 8. Car dealers: friendly check for new rows (Admin -> Content -> Car dealers -> Add)
-- ---------------------------------------------------------------------
create or replace function public.bl_car_dealer_check() returns trigger
language plpgsql set search_path = public as $$
declare v_scene text;
begin
  select scene into v_scene from locations where id = new.location_id;
  if not found then
    raise exception 'No place has the id "%". Use the id of a car dealer place (Content → Places, type car_dealer).', new.location_id
      using errcode = 'P0001', hint = 'bad_value';
  end if;
  if v_scene is distinct from 'car_dealer' then
    raise exception 'Place "%" is a % place. A dealer row needs a place of type car_dealer.', new.location_id, coalesce(v_scene, '?')
      using errcode = 'P0001', hint = 'bad_value';
  end if;
  return new;
end $$;
revoke all on function public.bl_car_dealer_check() from public, anon, authenticated;
drop trigger if exists car_dealers_check on public.car_dealers;
create trigger car_dealers_check before insert or update of location_id on public.car_dealers
  for each row execute function public.bl_car_dealer_check();

-- ---------------------------------------------------------------------
-- 9. Tokunbo Lot: show only what it sells (no luxury display cars)
-- ---------------------------------------------------------------------
update public.place_zones set prop = 'tokunbo_cars', label = 'Tokunbo row', icon = '🚙',
       note = 'Belgium-used cars, cleaned and polished. Price na negotiation.'
 where id = 'tokunbo_lot.showroom' and prop = 'lux_cars';
delete from public.zone_actions
 where zone_id = 'tokunbo_lot.showroom' and kind = 'shop'
   and ref in ('lambo_urus', 'gwagon_g63', 'tesla_cybertruck', 'gle63_coupe');
-- its own front lot replaces the shared dealer lot (Escalade, C300, new Camry are not sold here)
insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort)
select 'tokunbo_lot.lot', null, 'tokunbo_lot', 'lot', 'Bikes & budget cars', '🏍️', 'tokunbo_yard', 5.5, 8.6, 9.0, 3.2, 0,
       'Okada, bicycles and small cars for first-time owners.', 2
 where exists (select 1 from public.locations where id = 'tokunbo_lot')
on conflict do nothing;
insert into public.zone_actions (id, zone_id, kind, ref, label, sort)
select z || '.' || r, z, 'shop', r, null, s from (values
  ('tokunbo_lot.showroom', 'camry_muscle', 6), ('tokunbo_lot.showroom', 'lexus_rx350', 7),
  ('tokunbo_lot.lot', 'kia_rio_used', 1), ('tokunbo_lot.lot', 'bajaj_boxer', 2), ('tokunbo_lot.lot', 'bicycle', 3)
) as v(z, r, s)
where exists (select 1 from public.place_zones pz where pz.id = v.z) and exists (select 1 from public.items i where i.id = v.r)
on conflict do nothing;

notify pgrst, 'reload schema';
