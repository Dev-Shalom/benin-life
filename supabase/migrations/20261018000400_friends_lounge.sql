-- R7 Friends tab + Members' Lounge. docs/LOUNGE.md
-- Part A  Friends: ONE cheap read RPC friends_overview() (friends with online dot, where they are, join / invite flags, pending requests,
--         my privacy switch), friends_set_privacy(), friend_join_check(), friend_invite_place() (alert + push, friends category).
--         Built on the existing player_friendships / social_* RPCs: nothing is duplicated.
-- Part B  The Lounge: a new place type 'lounge' open all day, `lounge_tiers` (admin table), `lounge_members`, `lounge_guests`, membership
--         RPCs (lounge_status / lounge_buy / lounge_bring_guest), admin grant + revoke (audited), perks (drinks discount, VIP zone, gold tag,
--         free drink voucher, VIP guest), entry gate on travel + activities + shop, hype and music reuse.
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions
-- `create or replace`, live functions patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is missing,
-- skips when already applied; create or replace keeps the grants). Private bl_* helpers are revoked from anon/authenticated.

-- ---------------------------------------------------------------------------------------------
-- 0. Guarded patch helper (session-only)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.bl_patch1(p_sig text, p_done text, p_marker text, p_new text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_marker, ''))) / length(p_marker);
  if v_n = 0 then raise exception '% : marker not found: %', p_sig, p_marker; end if;
  if v_n > 1 then raise exception '% : marker not unique (% times): %', p_sig, v_n, p_marker; end if;
  execute replace(v_def, p_marker, p_new);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('friends.online_seconds', '120', 'social', 'Friend is online for (seconds)',
 'R7 Friends tab: a friend counts as online (green dot) when they were active in the game in the last this many seconds.', 'number', 20, 3600),
('friends.poll_seconds', '20', 'social', 'Friends tab refresh (seconds)',
 'R7: how often the Friends tab asks friends_overview() while it is open and the tab is visible. It never polls while closed.', 'number', 10, 300),
('friends.invite_cooldown_seconds', '60', 'social', 'Place invite cooldown (seconds)',
 'R7: a player can invite the same friend to a place only once per this many seconds.', 'number', 0, 86400),
('lounge.enabled', 'true', 'lounge', 'Lounge open',
 'R7 Members'' Lounge. Off = nobody can enter or buy a pass (the pin shows closed).', 'bool', null, null),
('lounge.requirements_enabled', 'true', 'lounge', 'Tier requirements on',
 'R7: tiers with a requirement (VIP: Charisma level or any certificate) can only be bought by players who meet it. Off = anyone can buy any tier.', 'bool', null, null),
('lounge.bank_first', 'true', 'lounge', 'Pay from the bank first',
 'R7: a pass is paid from the bank balance first, then cash. Off = cash only.', 'bool', null, null),
('lounge.max_stack_days', '90', 'lounge', 'Longest a membership can be stacked (days)',
 'R7: renewing the same tier adds its time on top of what is left, but never more than this many days from now.', 'number', 1, 3650),
('lounge.max_vouchers', '3', 'lounge', 'Most free-drink vouchers held',
 'R7: vouchers from several renewals stack, up to this number.', 'number', 0, 50),
('lounge.guest_pass_hours', '12', 'lounge', 'VIP guest pass lasts (hours)',
 'R7: a friend brought in by a VIP member can enter for this long.', 'number', 1, 720),
('lounge.guest_vip', 'false', 'lounge', 'Guests can use the VIP zone',
 'R7: on = a VIP''s guest may also use the VIP-only cards. Off = guests get the main lounge only.', 'bool', null, null),
('lounge.vip_activities', '"lounge_vip_suite,lounge_vip_network"', 'lounge', 'VIP-only activities',
 'R7: comma-separated activity ids only VIP members can do (the VIP zone). Edit the zone cards in Content -> Place zone actions.', 'text', null, null),
('lounge.vip_items', '""', 'lounge', 'VIP-only shop items',
 'R7: comma-separated item ids only VIP members can buy in the lounge.', 'text', null, null),
('lounge.voucher_activities', '"lounge_cocktail"', 'lounge', 'Activities a free-drink voucher covers',
 'R7: comma-separated activity ids. The first time a member does one, a voucher (if they have one) pays for it.', 'text', null, null),
('lounge.gold_tag', 'true', 'lounge', 'Gold name tag',
 'R7: members whose tier has the gold tag show a gold @name inside the lounge.', 'bool', null, null),
('lounge.hype', 'true', 'lounge', 'Lounge big-spend announcements',
 'R7: VIP suites and bottles bought in the lounge get the same hype-man announcement as the clubs (Settings -> Hype rules apply).', 'bool', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Part A: privacy switch
-- ---------------------------------------------------------------------------------------------
alter table public.profiles add column if not exists share_location_friends boolean not null default true;

-- ---------------------------------------------------------------------------------------------
-- 3. Part B tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.lounge_tiers (
  id                  text primary key,
  name                text not null,
  icon                text not null default '🛋️',
  blurb               text not null default '',
  price               bigint not null default 0 check (price >= 0),
  hours               integer not null default 24 check (hours > 0),
  discount_pct        integer not null default 0 check (discount_pct between 0 and 100),
  vip                 boolean not null default false,
  gold_tag            boolean not null default false,
  vouchers            integer not null default 0 check (vouchers >= 0),
  guests              integer not null default 0 check (guests >= 0),
  req_charisma_level  integer not null default 0 check (req_charisma_level >= 0),
  req_any_cert        boolean not null default false,
  sort                integer not null default 0,
  active              boolean not null default true
);

create table if not exists public.lounge_members (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  tier_id       text not null references public.lounge_tiers(id) on update cascade on delete restrict,
  started_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  vouchers_left integer not null default 0 check (vouchers_left >= 0),
  source        text not null default 'purchase' check (source in ('purchase', 'admin')),
  granted_by    uuid,
  paid_total    bigint not null default 0,
  updated_at    timestamptz not null default now()
);
create index if not exists lounge_members_expiry_idx on public.lounge_members (expires_at);

create table if not exists public.lounge_guests (
  id         bigserial primary key,
  host_id    uuid not null references public.profiles(id) on delete cascade,
  guest_id   uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists lounge_guests_guest_idx on public.lounge_guests (guest_id, expires_at desc);
create index if not exists lounge_guests_host_idx on public.lounge_guests (host_id, expires_at desc);

alter table public.lounge_tiers enable row level security;
alter table public.lounge_members enable row level security;
alter table public.lounge_guests enable row level security;
revoke all on public.lounge_tiers, public.lounge_members, public.lounge_guests from anon, authenticated;
grant select on public.lounge_tiers to authenticated;
grant select on public.lounge_members to authenticated;
grant select on public.lounge_guests to authenticated;
revoke all on sequence public.lounge_guests_id_seq from anon, authenticated;
drop policy if exists lounge_tiers_read on public.lounge_tiers;
create policy lounge_tiers_read on public.lounge_tiers for select to authenticated using (true);
drop policy if exists lounge_members_own on public.lounge_members;
create policy lounge_members_own on public.lounge_members for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists lounge_guests_own on public.lounge_guests;
create policy lounge_guests_own on public.lounge_guests for select to authenticated
  using (guest_id = (select auth.uid()) or host_id = (select auth.uid()));

-- Tiers (admin-tunable in Content -> Lounge tiers). Day pass 24 h, Monthly 30 days, VIP 30 days.
insert into public.lounge_tiers (id, name, icon, blurb, price, hours, discount_pct, vip, gold_tag, vouchers, guests, req_charisma_level, req_any_cert, sort) values
('day_pass', 'Day pass', '🎟️', 'Come in for 24 hours. Sofas, bar, pool table and gist.', 5000, 24, 0, false, false, 0, 0, 0, false, 10),
('monthly', 'Monthly Member', '🛋️', '30 days inside, 15% off drinks and bites, gold name tag and a free drink.', 150000, 720, 15, false, true, 1, 0, 0, false, 20),
('vip', 'VIP', '👑', '30 days, 30% off, the VIP cabana, gold name tag, a free drink and 1 free guest. Needs Charisma lvl 3 or any certificate.', 1000000, 720, 30, true, true, 1, 1, 3, true, 30)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. The place, its zones, cards, moods, crowd
-- ---------------------------------------------------------------------------------------------
insert into public.locations (id, name, district, scene, blurb, risk, night_risk_mult, cctv, keke_ok, congestion, remote_km, x, y, actions, sort, open_hour, close_hour, active) values
('members_lounge', 'The Lounge, GRA', 'gra', 'lounge',
 'Members'' lounge tucked off Ihama Road, GRA. Soft sofas, a proper bar, a pool table and big-man gist. Open all day. Pass at the door, abeg.',
 .05, 1.2, true, false, 1.1, 0, 412, 688, '{activities,shop}', 335, null, null, true)
on conflict (id) do nothing;

-- the bar sells Star and bottles like the clubs
update public.items set sold_at = sold_at || array['members_lounge']
 where id in ('club_bottle', 'star_beer') and not ('members_lounge' = any (sold_at));

-- restroom works in the lounge too
update public.activities set scenes = scenes || array['lounge']
 where id = 'ease_yourself' and not ('lounge' = any (scenes));

insert into public.activities (id, name, scenes, cost, game_minutes, effects, sort, max_seconds, min_seconds, icon) values
('lounge_cocktail', 'Signature cocktail', '{lounge}', 6000, 30, '{"fun": 14, "social": 12, "stress": -8, "bladder": -10}', 900, 8, 3, '🍸'),
('lounge_small_chops', 'Small chops platter', '{lounge}', 4500, 25, '{"hunger": 30, "fun": 6, "social": 6, "bladder": -6}', 901, 8, 3, '🍢'),
('lounge_pool', 'Shoot a game of pool', '{lounge}', 2000, 45, '{"fun": 22, "social": 20, "stress": -10, "energy": -4, "bladder": -5}', 902, 8, 3, '🎱'),
('lounge_network', 'Network with the big boys', '{lounge}', 2500, 60, '{"social": 25, "fun": 6, "stress": -4, "street_cred": 1}', 903, 8, 3, '🤝'),
('lounge_vip_suite', 'VIP cabana + bottle', '{lounge}', 120000, 90, '{"fun": 50, "social": 45, "stress": -22, "bladder": -15, "street_cred": 3}', 904, 8, 3, '🍾'),
('lounge_vip_network', 'VIP mixer', '{lounge}', 15000, 60, '{"social": 35, "fun": 8, "stress": -6, "street_cred": 2}', 905, 8, 3, '🥂')
on conflict (id) do nothing;

-- charisma XP (skills R3): networking trains charisma
insert into public.skill_sources (id, kind, ref, skill_id, xp, note) values
('activity:lounge_network:charisma', 'activity', 'lounge_network', 'charisma', 4, 'Network with the big boys'),
('activity:lounge_vip_network:charisma', 'activity', 'lounge_vip_network', 'charisma', 8, 'VIP mixer'),
('activity:lounge_cocktail:charisma', 'activity', 'lounge_cocktail', 'charisma', 1, 'Signature cocktail'),
('activity:lounge_pool:charisma', 'activity', 'lounge_pool', 'charisma', 1, 'Shoot a game of pool')
on conflict (id) do nothing;

insert into public.place_zones (id, scene, location_id, zone_key, label, icon, prop, x, z, w, d, rot, note, sort) values
('lounge.bar', 'lounge', null, 'bar', 'Bar', '🍸', 'bar', 3.2, 2.2, 4.6, 1.4, 0, 'Members drink cheaper. A free-drink voucher covers one cocktail.', 10),
('lounge.tables', 'lounge', null, 'tables', 'Network corner', '🤝', 'tables', 8.0, 2.6, 3.0, 2.4, 0, 'Meet people, build your name.', 20),
('lounge.sofas', 'lounge', null, 'sofas', 'Sofas', '🛋️', 'couches', 5.0, 6.6, 4.8, 2.2, 0, 'Sit, gist, and chat with everyone inside.', 30),
('lounge.pool', 'lounge', null, 'pool', 'Pool table', '🎱', 'pool_table', 10.4, 7.4, 3.4, 2.2, 0, null, 40),
('lounge.vip', 'lounge', null, 'vip', 'VIP cabana', '👑', 'vip', 12.6, 3.0, 3.2, 3.2, 3, 'VIP members only.', 50),
('lounge.restroom', 'lounge', null, 'restroom', 'Restroom', '🚻', 'restroom', 1.0, 6.4, 1.6, 1.6, 1, null, 60)
on conflict (id) do nothing;

insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
('lounge.bar.lounge_cocktail', 'lounge.bar', 'activity', 'lounge_cocktail', null, null, 10),
('lounge.bar.lounge_small_chops', 'lounge.bar', 'activity', 'lounge_small_chops', null, null, 20),
('lounge.bar.star_beer', 'lounge.bar', 'shop', 'star_beer', null, null, 30),
('lounge.bar.club_bottle', 'lounge.bar', 'shop', 'club_bottle', null, null, 40),
('lounge.tables.lounge_network', 'lounge.tables', 'activity', 'lounge_network', null, null, 10),
('lounge.sofas.chat', 'lounge.sofas', 'panel', 'chat', 'Lounge chat', '💬', 10),
('lounge.pool.lounge_pool', 'lounge.pool', 'activity', 'lounge_pool', null, null, 10),
('lounge.vip.lounge_vip_suite', 'lounge.vip', 'activity', 'lounge_vip_suite', null, null, 10),
('lounge.vip.lounge_vip_network', 'lounge.vip', 'activity', 'lounge_vip_network', null, null, 20),
('lounge.restroom.ease_yourself', 'lounge.restroom', 'activity', 'ease_yourself', null, null, 10)
on conflict (id) do nothing;

insert into public.place_moods (id, scene, location_id, part, icon, line, sort) values
('lounge.1', 'lounge', null, 'any', '🛋️', 'Soft sofas, low lights and a calm groove', 1),
('lounge.2', 'lounge', null, 'morning', '☕', 'Early members dey sip coffee and read the papers', 2),
('lounge.3', 'lounge', null, 'afternoon', '🎱', 'Pool balls clacking, deals being sealed quietly', 3),
('lounge.4', 'lounge', null, 'evening', '🍸', 'Cocktail hour: the big boys are in the house', 4),
('lounge.5', 'lounge', null, 'night', '🌙', 'Late-night gist under warm lamps', 5)
on conflict (id) do nothing;

insert into public.crowd_profiles (id, scene, days, from_hour, to_hour, npcs, sort) values
('lounge.all.0-24', 'lounge', 'all', 0, 24, 3, 0),
('lounge.all.12-18', 'lounge', 'all', 12, 18, 6, 0),
('lounge.all.18-24', 'lounge', 'all', 18, 24, 9, 0),
('lounge.weekend.18-24', 'lounge', 'weekend', 18, 24, 12, 0)
on conflict (id) do nothing;

insert into public.npc_roster (id, name, role, motion, avatar, lines, scenes, location_ids, zone_key, headliner, sort) values
('lounge_bartender', 'Ehi', 'Bartender', 'serve', '{"v": 2, "top": {"c": "#111111"}, "hair": "waves", "skin": "tone5", "gender": "male", "preset": "corporate"}',
 E'Cocktail or something stronger?\nMembers get the good ice.', '{lounge}', '{}', 'bar', false, 600),
('lounge_member_a', 'Chief Idemudia', 'Member', 'sit', '{"v": 2, "top": {"c": "#f3f0e8"}, "hair": "bald", "skin": "tone4", "gender": "male", "preset": "senator"}',
 E'This lounge is the only quiet place in GRA.\nMy people, we close deals here.', '{lounge}', '{}', 'sofas', false, 601),
('lounge_member_b', 'Aisosa', 'Member', 'phone', '{"v": 2, "top": {"c": "#111111"}, "hair": "waves", "skin": "tone5", "gender": "female", "preset": "corporate"}',
 E'One sec, let me finish this email.\nGold tag looks good on me.', '{lounge}', '{}', 'sofas', false, 602),
('lounge_member_c', 'Engr. Osarenren', 'Member', 'idle', '{"v": 2, "top": {"c": "#f3f0e8"}, "hair": "bald", "skin": "tone4", "gender": "male", "preset": "senator"}',
 E'Network, network, network.\nNa who you know.', '{lounge}', '{}', 'tables', false, 603),
('lounge_player_pool', 'Ede', 'Pool shark', 'idle', '{"v": 2, "top": {"c": "#111111"}, "hair": "waves", "skin": "tone5", "gender": "male", "preset": "corporate"}',
 E'Rack them up. Loser buys.\nI no miss easy shots.', '{lounge}', '{}', 'pool', false, 604)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 5. Private helpers (all revoked from clients at the end)
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_lounge_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('lounge.enabled'), true)
$$;

-- the active membership row, if any
create or replace function public.bl_lounge_member(p_uid uuid) returns public.lounge_members
language sql stable security definer set search_path = public as $$
  select m.* from lounge_members m where m.user_id = p_uid and m.expires_at > bl_now()
$$;

create or replace function public.bl_lounge_tier(p_uid uuid) returns public.lounge_tiers
language sql stable security definer set search_path = public as $$
  select t.* from lounge_members m join lounge_tiers t on t.id = m.tier_id
   where m.user_id = p_uid and m.expires_at > bl_now()
$$;

-- 'member', 'guest' (a VIP's pass) or null
create or replace function public.bl_lounge_access(p_uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from lounge_members m where m.user_id = p_uid and m.expires_at > bl_now()) then 'member'
              when exists (select 1 from lounge_guests g where g.guest_id = p_uid and g.expires_at > bl_now()) then 'guest'
              else null end
$$;

create or replace function public.bl_lounge_vip(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select t.vip from lounge_members m join lounge_tiers t on t.id = m.tier_id
                    where m.user_id = p_uid and m.expires_at > bl_now()), false)
      or (coalesce(bl_cfg_bool('lounge.guest_vip'), false)
          and exists (select 1 from lounge_guests g where g.guest_id = p_uid and g.expires_at > bl_now()))
$$;

create or replace function public.bl_lounge_gold(p_uid uuid, p_loc text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('lounge.gold_tag'), true)
     and exists (select 1 from locations l where l.id = p_loc and l.scene = 'lounge')
     and exists (select 1 from lounge_members m join lounge_tiers t on t.id = m.tier_id
                  where m.user_id = p_uid and m.expires_at > bl_now() and t.gold_tag)
$$;

create or replace function public.bl_lounge_hype_on() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(bl_cfg_bool('lounge.hype'), true)
$$;

-- Does the player meet a tier's requirement? (none set, or the switch is off = yes; else level OR any certificate)
create or replace function public.bl_lounge_req_ok(p_uid uuid, t public.lounge_tiers) returns boolean
language sql stable security definer set search_path = public as $$
  select not coalesce(bl_cfg_bool('lounge.requirements_enabled'), true)
      or (t.req_charisma_level <= 0 and not t.req_any_cert)
      or (t.req_charisma_level > 0 and bl_skill_level(p_uid, 'charisma') >= t.req_charisma_level)
      or (t.req_any_cert and exists (select 1 from player_certificates pc where pc.user_id = p_uid))
$$;

create or replace function public.bl_lounge_req_text(t public.lounge_tiers) returns text
language sql stable security definer set search_path = public as $$
  select case when t.req_charisma_level > 0 and t.req_any_cert then 'Charisma level ' || t.req_charisma_level || ' or any certificate'
              when t.req_charisma_level > 0 then 'Charisma level ' || t.req_charisma_level
              when t.req_any_cert then 'Any certificate'
              else null end
$$;

-- Entry: members and a VIP's guests only. Raises with a friendly message.
create or replace function public.bl_lounge_assert_entry(p_uid uuid, p_loc public.locations) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc.scene is distinct from 'lounge' then return; end if;
  if not bl_lounge_on() then
    raise exception '% is closed for now. Check back soon.', p_loc.name using errcode = 'P0001', hint = 'inactive';
  end if;
  if bl_lounge_access(p_uid) is null then
    raise exception '% is for members only. Get a day pass or a membership first.', p_loc.name using errcode = 'P0001', hint = 'no_membership';
  end if;
end $$;

-- Entry + the VIP-only cards / items.
create or replace function public.bl_lounge_assert(p_uid uuid, p_loc public.locations, p_ref text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc.scene is distinct from 'lounge' then return; end if;
  perform bl_lounge_assert_entry(p_uid, p_loc);
  if (bl_csv_has(bl_cfg_text('lounge.vip_activities'), p_ref) or bl_csv_has(bl_cfg_text('lounge.vip_items'), p_ref))
     and not bl_lounge_vip(p_uid) then
    raise exception 'The VIP cabana is for VIP members only.' using errcode = 'P0001', hint = 'vip_only';
  end if;
end $$;

-- why a card is locked (null = fine); used by place_interior
create or replace function public.bl_lounge_lock(p_uid uuid, p_loc public.locations, p_ref text) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc.scene is distinct from 'lounge' then return null; end if;
  if not bl_lounge_on() then return 'Closed for now'; end if;
  if bl_lounge_access(p_uid) is null then return 'Members only'; end if;
  if (bl_csv_has(bl_cfg_text('lounge.vip_activities'), p_ref) or bl_csv_has(bl_cfg_text('lounge.vip_items'), p_ref))
     and not bl_lounge_vip(p_uid) then
    return 'VIP only';
  end if;
  return null;
end $$;

-- member discount on everything priced in the lounge (the logged-in player)
create or replace function public.bl_lounge_price(p_loc public.locations, p_ref text, p_base bigint) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare d int; v numeric;
begin
  if coalesce(p_base, 0) <= 0 then return coalesce(p_base, 0); end if;
  select coalesce((bl_lounge_tier(auth.uid())).discount_pct, 0) into d;
  if d <= 0 then return p_base; end if;
  v := p_base * (100 - least(100, d)) / 100.0;
  if v < 1000 then return greatest(0, (round(v / 10.0) * 10)::bigint); end if;
  return (round(v / 50.0) * 50)::bigint;
end $$;

-- spend a free-drink voucher on this activity, if the player has one (true = it covers the price)
create or replace function public.bl_lounge_voucher(p_uid uuid, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not bl_csv_has(bl_cfg_text('lounge.voucher_activities'), p_ref) then return false; end if;
  update lounge_members set vouchers_left = vouchers_left - 1, updated_at = bl_now()
   where user_id = p_uid and expires_at > bl_now() and vouchers_left > 0;
  return found;
end $$;

-- what place_interior and the place card show about my access
create or replace function public.bl_lounge_card(p_uid uuid, p_loc public.locations) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m public.lounge_members; t public.lounge_tiers; v_acc text := bl_lounge_access(p_uid); g public.lounge_guests;
begin
  select * into m from lounge_members where user_id = p_uid;
  if m.user_id is not null then select * into t from lounge_tiers where id = m.tier_id; end if;
  select * into g from lounge_guests where guest_id = p_uid and expires_at > bl_now() order by expires_at desc limit 1;
  return jsonb_build_object(
    'on', bl_lounge_on(), 'access', v_acc, 'vip', bl_lounge_vip(p_uid),
    'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'name', t.name, 'icon', t.icon, 'vip', t.vip, 'gold', t.gold_tag, 'discount_pct', t.discount_pct) end,
    'expires_at', m.expires_at, 'expired', m.user_id is not null and m.expires_at <= bl_now(),
    'seconds_left', case when m.user_id is not null and m.expires_at > bl_now() then floor(extract(epoch from (m.expires_at - bl_now())))::bigint end,
    'vouchers_left', case when m.expires_at > bl_now() then m.vouchers_left else 0 end,
    'guest_until', g.expires_at);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Part B RPCs (players)
-- ---------------------------------------------------------------------------------------------
create or replace function public.lounge_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  v_me   profiles;
  m      public.lounge_members;
  cur    public.lounge_tiers;
  v_loc  locations;
  v_max  numeric := greatest(1, coalesce(bl_cfg('lounge.max_stack_days'), 90)) * 24;
begin
  select * into v_me from profiles where id = v_uid;
  select * into v_loc from locations where scene = 'lounge' order by sort limit 1;
  m := bl_lounge_member(v_uid);
  if m.user_id is not null then select * into cur from lounge_tiers where id = m.tier_id; end if;
  return jsonb_build_object(
    'enabled', bl_lounge_on(), 'location_id', v_loc.id, 'location_name', v_loc.name,
    'cash', v_me.cash, 'bank', v_me.bank, 'bank_first', coalesce(bl_cfg_bool('lounge.bank_first'), true),
    'access', bl_lounge_access(v_uid), 'vip', bl_lounge_vip(v_uid),
    'me', case when m.user_id is null then null else jsonb_build_object(
        'tier_id', cur.id, 'tier_name', cur.name, 'icon', cur.icon, 'vip', cur.vip, 'gold', cur.gold_tag, 'discount_pct', cur.discount_pct,
        'started_at', m.started_at, 'expires_at', m.expires_at,
        'seconds_left', floor(extract(epoch from (m.expires_at - bl_now())))::bigint,
        'vouchers_left', m.vouchers_left, 'source', m.source,
        'guest_slots', cur.guests,
        'guests_active', (select count(*) from lounge_guests g where g.host_id = v_uid and g.expires_at > bl_now())) end,
    'expired_tier', (select t.name from lounge_members x join lounge_tiers t on t.id = x.tier_id where x.user_id = v_uid and x.expires_at <= bl_now()),
    'guest_pass', (select jsonb_build_object('host', h.username, 'expires_at', g.expires_at)
                     from lounge_guests g join profiles h on h.id = g.host_id
                    where g.guest_id = v_uid and g.expires_at > bl_now() order by g.expires_at desc limit 1),
    'guest_hours', coalesce(bl_cfg('lounge.guest_pass_hours'), 12),
    'tiers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name', t.name, 'icon', t.icon, 'blurb', t.blurb, 'price', t.price, 'hours', t.hours,
               'discount_pct', t.discount_pct, 'vip', t.vip, 'gold_tag', t.gold_tag, 'vouchers', t.vouchers, 'guests', t.guests,
               'requirement', bl_lounge_req_text(t), 'requirement_ok', bl_lounge_req_ok(v_uid, t),
               'action', case
                 when not bl_lounge_req_ok(v_uid, t) then 'locked'
                 when cur.id is null then 'buy'
                 when cur.id = t.id then case when extract(epoch from (m.expires_at - bl_now())) / 3600.0 >= v_max then 'max' else 'renew' end
                 when t.price < cur.price then 'lower'
                 else 'upgrade' end)
             order by t.sort, t.price)
        from lounge_tiers t where t.active), '[]'::jsonb));
end $$;

create or replace function public.lounge_buy(p_tier text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  t       public.lounge_tiers;
  cur     public.lounge_tiers;
  m       public.lounge_members;
  v_bank  bigint := 0;
  v_cash  bigint;
  v_start timestamptz;
  v_exp   timestamptz;
  v_max   numeric := greatest(1, coalesce(bl_cfg('lounge.max_stack_days'), 90)) * 24;
  v_vmax  int := greatest(0, coalesce(bl_cfg('lounge.max_vouchers'), 3))::int;
  v_kind  text;
  v_msg   text;
begin
  if not bl_lounge_on() then
    raise exception 'The Lounge is closed for now. Check back soon.' using errcode = 'P0001', hint = 'inactive';
  end if;
  select * into t from lounge_tiers where id = p_tier and active;
  if not found then
    raise exception 'That pass is not on sale.' using errcode = 'P0001', hint = 'no_tier';
  end if;
  if not bl_lounge_req_ok(v_me.id, t) then
    raise exception '% needs %.', t.name, bl_lounge_req_text(t) using errcode = 'P0001', hint = 'requirement';
  end if;
  select * into m from lounge_members where user_id = v_me.id for update;
  if m.user_id is not null and m.expires_at > bl_now() then
    select * into cur from lounge_tiers where id = m.tier_id;
    if cur.id <> t.id and t.price < cur.price then
      raise exception 'You already hold % (better than %).', cur.name, t.name using errcode = 'P0001', hint = 'have_better';
    end if;
    if cur.id = t.id and extract(epoch from (m.expires_at - bl_now())) / 3600.0 >= v_max then
      raise exception 'Your % already runs the longest it can. Renew later.', t.name using errcode = 'P0001', hint = 'max_stack';
    end if;
  end if;
  -- pay: bank first (if on), then cash
  if coalesce(bl_cfg_bool('lounge.bank_first'), true) then v_bank := least(v_me.bank, t.price); end if;
  v_cash := t.price - v_bank;
  if v_cash > v_me.cash then
    raise exception 'Your money no reach. % costs % and you have % (bank % + cash %).', t.name, bl_naira(t.price),
      bl_naira(v_me.bank + v_me.cash), bl_naira(v_me.bank), bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  if v_bank > 0 then
    perform bl_add_money(v_me.id, 'bank', -v_bank, 'lounge', jsonb_build_object('tier', t.id, 'name', t.name, 'from', 'bank'));
  end if;
  if v_cash > 0 then
    perform bl_add_money(v_me.id, 'cash', -v_cash, 'lounge', jsonb_build_object('tier', t.id, 'name', t.name, 'from', 'cash'));
  end if;
  if cur.id = t.id then
    v_kind := 'renewed';
    v_start := m.started_at;
    v_exp := least(m.expires_at + make_interval(hours => t.hours), bl_now() + make_interval(hours => v_max::int));
  else
    v_kind := case when cur.id is null then 'bought' else 'upgraded' end;
    v_start := bl_now();
    v_exp := bl_now() + make_interval(hours => t.hours);
  end if;
  insert into lounge_members (user_id, tier_id, started_at, expires_at, vouchers_left, source, paid_total, updated_at)
  values (v_me.id, t.id, v_start, v_exp, least(v_vmax, t.vouchers), 'purchase', t.price, bl_now())
  on conflict (user_id) do update
    set tier_id = excluded.tier_id, started_at = excluded.started_at, expires_at = excluded.expires_at,
        vouchers_left = least(v_vmax, case when cur.id is null then 0 else lounge_members.vouchers_left end + t.vouchers),
        source = 'purchase', granted_by = null,
        paid_total = lounge_members.paid_total + t.price, updated_at = bl_now();
  v_msg := case v_kind when 'renewed' then t.name || ' renewed for ' || bl_naira(t.price) || '.'
                       when 'upgraded' then 'Upgraded to ' || t.name || ' for ' || bl_naira(t.price) || '.'
                       else 'Welcome to The Lounge. ' || t.name || ' for ' || bl_naira(t.price) || '.' end;
  perform bl_event(v_me.id, 'lounge_member', t.icon || ' ' || t.name || ' active', v_msg || ' Valid until ' || to_char(v_exp at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || '.',
                   jsonb_build_object('tier', t.id, 'expires_at', v_exp, 'settle', true));  -- settle: the app already toasts the result
  return jsonb_build_object('message', v_msg, 'kind', v_kind, 'tier', t.id, 'expires_at', v_exp, 'spent', t.price,
                            'from_bank', v_bank, 'from_cash', v_cash) || jsonb_build_object('status', lounge_status());
end $$;

-- A VIP brings a friend in free for lounge.guest_pass_hours.
create or replace function public.lounge_bring_guest(p_friend uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me   profiles := bl_me();
  t      public.lounge_tiers;
  o      profiles;
  v_loc  locations;
  v_exp  timestamptz;
  v_hrs  int := greatest(1, coalesce(bl_cfg('lounge.guest_pass_hours'), 12))::int;
begin
  t := bl_lounge_tier(v_me.id);
  if t.id is null or t.guests <= 0 then
    raise exception 'Only VIP members can bring a free guest.' using errcode = 'P0001', hint = 'not_vip';
  end if;
  select * into o from profiles where id = p_friend and not banned;
  if not found or p_friend = v_me.id then
    raise exception 'Pick a friend to bring.' using errcode = 'P0001', hint = 'bad_guest';
  end if;
  if not exists (select 1 from player_friendships f where f.user_a = least(v_me.id, p_friend) and f.user_b = greatest(v_me.id, p_friend) and f.status = 'accepted')
     or bl_social_blocked(v_me.id, p_friend) then
    raise exception 'You can only bring friends.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  if exists (select 1 from lounge_guests g where g.host_id = v_me.id and g.guest_id = p_friend and g.expires_at > bl_now()) then
    raise exception '@% already has your guest pass.', o.username using errcode = 'P0001', hint = 'already_guest';
  end if;
  if (select count(*) from lounge_guests g where g.host_id = v_me.id and g.expires_at > bl_now()) >= t.guests then
    raise exception 'Your guest pass is still in use. It frees up when it runs out.' using errcode = 'P0001', hint = 'no_slot';
  end if;
  select * into v_loc from locations where scene = 'lounge' order by sort limit 1;
  v_exp := bl_now() + make_interval(hours => v_hrs);
  insert into lounge_guests (host_id, guest_id, expires_at) values (v_me.id, p_friend, v_exp);
  perform bl_event(p_friend, 'lounge_guest', '@' || v_me.username || ' wants you at ' || v_loc.name,
                   'Free guest pass for ' || v_hrs || ' hours. Tap Go there to join them.',
                   jsonb_build_object('location_id', v_loc.id, 'from', v_me.id));
  perform bl_push_enqueue(p_friend, 'friends', 'lounge_guest', '@' || v_me.username || ' wants you at ' || v_loc.name,
                          'You are on the guest list. Tap to head there.', '/play?go=place:' || v_loc.id, v_me.id);
  return jsonb_build_object('message', '@' || o.username || ' is on your guest list for ' || v_hrs || ' hours.', 'expires_at', v_exp);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. Part B admin: look at, grant and revoke a membership (audited)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_lounge_get(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); m public.lounge_members;
begin
  select * into m from lounge_members where user_id = p_user;
  return jsonb_build_object(
    'member', case when m.user_id is null then null else jsonb_build_object(
        'tier_id', m.tier_id, 'tier_name', (select name from lounge_tiers where id = m.tier_id), 'started_at', m.started_at,
        'expires_at', m.expires_at, 'active', m.expires_at > bl_now(), 'vouchers_left', m.vouchers_left,
        'source', m.source, 'granted_by', m.granted_by, 'paid_total', m.paid_total) end,
    'guest_passes', coalesce((select jsonb_agg(jsonb_build_object('host', h.username, 'expires_at', g.expires_at) order by g.expires_at desc)
                                from lounge_guests g join profiles h on h.id = g.host_id
                               where g.guest_id = p_user and g.expires_at > bl_now()), '[]'::jsonb),
    'tiers', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'hours', t.hours) order by t.sort) from lounge_tiers t), '[]'::jsonb));
end $$;

create or replace function public.admin_lounge_grant(p_user uuid, p_tier text, p_hours integer default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  t       public.lounge_tiers;
  v_old   public.lounge_members;
  v_hrs   int;
  v_exp   timestamptz;
begin
  if not exists (select 1 from profiles where id = p_user) then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select * into t from lounge_tiers where id = p_tier;
  if not found then
    raise exception 'That tier doesn''t exist.' using errcode = 'P0001', hint = 'no_tier';
  end if;
  v_hrs := coalesce(p_hours, t.hours);
  if v_hrs < 1 or v_hrs > 24 * 3650 then
    raise exception 'Hours must be between 1 and 87600.' using errcode = 'P0001', hint = 'bad_value';
  end if;
  select * into v_old from lounge_members where user_id = p_user for update;
  v_exp := bl_now() + make_interval(hours => v_hrs);
  insert into lounge_members (user_id, tier_id, started_at, expires_at, vouchers_left, source, granted_by, paid_total, updated_at)
  values (p_user, t.id, bl_now(), v_exp, t.vouchers, 'admin', v_admin, 0, bl_now())
  on conflict (user_id) do update
    set tier_id = excluded.tier_id, started_at = excluded.started_at, expires_at = excluded.expires_at,
        vouchers_left = excluded.vouchers_left, source = 'admin', granted_by = v_admin, updated_at = bl_now();
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'lounge_grant', p_user, jsonb_build_object('tier', t.id, 'hours', v_hrs, 'expires_at', v_exp,
            'was_tier', v_old.tier_id, 'was_expires_at', v_old.expires_at));
  perform bl_event(p_user, 'lounge_member', t.icon || ' ' || t.name || ' from Benin Life',
                   'You have been given ' || t.name || ' for The Lounge. Valid until ' || to_char(v_exp at time zone 'Africa/Lagos', 'DD Mon HH24:MI') || '.',
                   jsonb_build_object('tier', t.id, 'expires_at', v_exp));
  return jsonb_build_object('message', t.name || ' granted until ' || to_char(v_exp at time zone 'Africa/Lagos', 'DD Mon YYYY HH24:MI') || '.',
                            'tier', t.id, 'expires_at', v_exp);
end $$;

create or replace function public.admin_lounge_revoke(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_old public.lounge_members;
begin
  select * into v_old from lounge_members where user_id = p_user for update;
  if not found then
    raise exception 'That player has no lounge membership.' using errcode = 'P0001', hint = 'no_member';
  end if;
  delete from lounge_members where user_id = p_user;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'lounge_revoke', p_user, jsonb_build_object('was_tier', v_old.tier_id, 'was_expires_at', v_old.expires_at));
  return jsonb_build_object('message', 'Membership removed.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Part A: friends
-- ---------------------------------------------------------------------------------------------
create or replace function public.bl_place_public(l public.locations) returns boolean
language sql stable security definer set search_path = public as $$
  select l.private_home_owner_id is null and l.scene not like 'home\_%'
$$;

-- Can p_me join friend o where they are right now? {ok, hint, message, dest, name}
create or replace function public.bl_friend_join_state(p_me profiles, o profiles, p_online boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l locations; v_hint text; v_msg text;
begin
  if not p_online then
    v_hint := 'offline'; v_msg := '@' || o.username || ' is offline right now.';
  elsif not o.share_location_friends then
    v_hint := 'hidden'; v_msg := '@' || o.username || ' keeps their location private.';
  elsif o.travel_to is not null then
    v_hint := 'travelling'; v_msg := '@' || o.username || ' is on the road right now.';
  else
    select * into l from locations where id = o.location_id;
    if not found then
      v_hint := 'nowhere'; v_msg := 'You cannot find @' || o.username || ' right now.';
    elsif not bl_place_public(l) then
      v_hint := 'private'; v_msg := '@' || o.username || ' is at home. Ask for a house invite.';
    elsif not coalesce(l.active, true) then
      v_hint := 'inactive'; v_msg := l.name || ' is closed for now. Check back soon.';
    elsif not bl_place_open(l) then
      v_hint := 'closed'; v_msg := l.name || ' is closed right now. It opens at ' || bl_hour_label(l.open_hour) || '.';
    elsif l.id = p_me.location_id and p_me.travel_to is null then
      v_hint := 'same'; v_msg := 'You are already at ' || l.name || '.';
    elsif l.scene = 'lounge' and (not bl_lounge_on() or bl_lounge_access(p_me.id) is null) then
      v_hint := 'no_membership'; v_msg := l.name || ' is for members only. Get a day pass first.';
    end if;
  end if;
  return jsonb_build_object('ok', v_hint is null, 'hint', v_hint, 'message', v_msg, 'dest', l.id, 'name', l.name);
end $$;

-- One friend card (everything but the chat bits)
create or replace function public.bl_friend_card(p_me profiles, o profiles, p_secs numeric, p_yahoo boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_online boolean := o.last_seen is not null and o.last_seen > bl_now() - make_interval(secs => p_secs::double precision);
  l        locations;
  v_loc    jsonb;
  v_join   jsonb;
  v_hid    boolean := not o.share_location_friends;
  v_yahoo  boolean := false;
begin
  if v_online and not v_hid then
    if o.travel_to is not null then
      v_loc := jsonb_build_object('id', null, 'name', 'On the road', 'private', false, 'traveling', true);
    else
      select * into l from locations where id = o.location_id;
      if found then
        v_loc := case when bl_place_public(l)
                      then jsonb_build_object('id', l.id, 'name', l.name, 'district', l.district, 'scene', l.scene, 'open', bl_place_open(l))
                      else jsonb_build_object('id', null, 'name', 'At home', 'private', true) end;
      end if;
    end if;
  end if;
  v_join := bl_friend_join_state(p_me, o, v_online);
  if p_yahoo and v_online then
    v_yahoo := bl_yahoo_laptop(o.id) is not null and coalesce((bl_yahoo_group_spot(o)->>'ok')::boolean, false)
               and not exists (select 1 from yahoo_group_members x join yahoo_groups g on g.id = x.group_id
                                where x.user_id = o.id and x.status = 'accepted' and g.status in ('inviting', 'running'));
  end if;
  return jsonb_build_object(
    'id', o.id, 'username', o.username, 'avatar', o.avatar, 'online', v_online, 'last_seen', o.last_seen,
    'location', v_loc, 'location_hidden', v_hid and v_online,
    'can_join', coalesce((v_join->>'ok')::boolean, false), 'join_hint', v_join->>'hint', 'join_reason', v_join->>'message',
    'join_to', v_join->>'dest',
    'yahoo_ready', v_yahoo,
    'house_invite', (select i.status from player_house_invites i
                      where i.host_id = p_me.id and i.guest_id = o.id and i.status in ('invited', 'knocking') and i.expires_at > bl_now() limit 1));
end $$;

create or replace function public.friends_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := bl_require_uid();
  v_me    profiles;
  v_secs  numeric := greatest(10, coalesce(bl_cfg('friends.online_seconds'), 120));
  v_yahoo boolean := coalesce(bl_cfg_bool('yahoo.enabled'), true) and coalesce(bl_cfg_bool('yahoo.group_enabled'), true);
  l       locations;
  v_place jsonb;
  v_fr    jsonb;
  v_req   jsonb;
  v_tier  public.lounge_tiers;
begin
  select * into v_me from profiles where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  -- where I am: can I invite a friend here?
  select * into l from locations where id = v_me.location_id;
  v_place := jsonb_build_object('id', l.id, 'name', l.name, 'scene', l.scene, 'can_invite',
    found and v_me.travel_to is null and bl_place_public(l) and coalesce(l.active, true) and bl_place_open(l)
      and (l.scene <> 'lounge' or (bl_lounge_on() and bl_lounge_access(v_uid) is not null)),
    'reason', case when not found or v_me.travel_to is not null then 'You are on the road.'
                   when not bl_place_public(l) then 'Invite to your house instead.'
                   when not coalesce(l.active, true) or not bl_place_open(l) then l.name || ' is closed right now.'
                   when l.scene = 'lounge' and (not bl_lounge_on() or bl_lounge_access(v_uid) is null) then 'You need a lounge pass first.'
                   else null end);
  v_tier := bl_lounge_tier(v_uid);

  select coalesce(jsonb_agg(c.card order by c.online desc, c.seen desc nulls last, c.uname), '[]'::jsonb) into v_fr
    from (
      select o.username as uname, o.last_seen as seen,
             (o.last_seen is not null and o.last_seen > bl_now() - make_interval(secs => v_secs::double precision)) as online,
             bl_friend_card(v_me, o, v_secs, v_yahoo)
               || jsonb_build_object('conversation_id', cv.id, 'unread', coalesce(u.n, 0), 'at_home', o.location_id = o.home_location_id) as card
        from player_friendships f
        join profiles o on o.id = case when f.user_a = v_uid then f.user_b else f.user_a end
        left join player_conversations cv on cv.user_a = f.user_a and cv.user_b = f.user_b
        left join lateral (select count(*)::int as n from player_messages pm
                            where pm.conversation_id = cv.id and pm.sender_id = o.id and pm.read_at is null) u on true
       where f.status = 'accepted' and v_uid in (f.user_a, f.user_b) and not o.banned
         and not bl_social_blocked(v_uid, o.id)
       limit 300
    ) c;

  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'username', o.username, 'avatar', o.avatar,
                                               'direction', case when f.requested_by = v_uid then 'outgoing' else 'incoming' end,
                                               'created_at', f.created_at)
                           order by (f.requested_by <> v_uid) desc, f.created_at desc), '[]'::jsonb) into v_req
    from player_friendships f
    join profiles o on o.id = case when f.user_a = v_uid then f.user_b else f.user_a end
   where f.status = 'pending' and v_uid in (f.user_a, f.user_b) and not o.banned and not bl_social_blocked(v_uid, o.id);

  return jsonb_build_object(
    'me', jsonb_build_object('share_location', v_me.share_location_friends, 'home_chosen', v_me.home_chosen,
                             'place', v_place, 'lounge_guest_slots', coalesce(v_tier.guests, 0),
                             'lounge_guests_active', (select count(*) from lounge_guests g where g.host_id = v_uid and g.expires_at > bl_now())),
    'online_seconds', v_secs,
    'poll_seconds', greatest(10, coalesce(bl_cfg('friends.poll_seconds'), 20)),
    'requests', v_req,
    'friends', v_fr);
end $$;

create or replace function public.friends_set_privacy(p_show boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  update profiles set share_location_friends = coalesce(p_show, true) where id = v_uid;
  if not found then
    raise exception 'You haven''t created your Sim yet. Create one first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  return jsonb_build_object('share_location', coalesce(p_show, true),
    'message', case when coalesce(p_show, true) then 'Friends can see where you are.' else 'Your location is hidden from friends.' end);
end $$;

-- Refuses (with a reason) unless the friend is online, shares their location, and is at a public, open place you may enter.
create or replace function public.friend_join_check(p_friend uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_me profiles := bl_me(); o profiles; v_s jsonb;
begin
  select * into o from profiles where id = p_friend and not banned;
  if not found or p_friend = v_me.id
     or not exists (select 1 from player_friendships f where f.user_a = least(v_me.id, p_friend) and f.user_b = greatest(v_me.id, p_friend) and f.status = 'accepted')
     or bl_social_blocked(v_me.id, p_friend) then
    raise exception 'That player is not in your friends list.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  v_s := bl_friend_join_state(v_me, o, o.last_seen is not null and o.last_seen > bl_now() - make_interval(secs => greatest(10, coalesce(bl_cfg('friends.online_seconds'), 120))::double precision));
  if not (v_s->>'ok')::boolean then
    raise exception '%', v_s->>'message' using errcode = 'P0001', hint = v_s->>'hint';
  end if;
  return jsonb_build_object('dest', v_s->>'dest', 'name', v_s->>'name');
end $$;

-- "@x wants you at 360 Signature": an alert + a push (friends category). Tapping goes to the place.
create or replace function public.friend_invite_place(p_friend uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me  profiles := bl_me();
  o     profiles;
  l     locations;
  v_cd  numeric := greatest(0, coalesce(bl_cfg('friends.invite_cooldown_seconds'), 60));
begin
  select * into o from profiles where id = p_friend and not banned;
  if not found or p_friend = v_me.id
     or not exists (select 1 from player_friendships f where f.user_a = least(v_me.id, p_friend) and f.user_b = greatest(v_me.id, p_friend) and f.status = 'accepted')
     or bl_social_blocked(v_me.id, p_friend) then
    raise exception 'You can invite friends only.' using errcode = 'P0001', hint = 'not_friend';
  end if;
  if v_me.travel_to is not null then
    raise exception 'You are on the road. Arrive first, then invite.' using errcode = 'P0001', hint = 'travelling';
  end if;
  select * into l from locations where id = v_me.location_id;
  if not found or not bl_place_public(l) then
    raise exception 'Invite friends to your house from their chat. Places need a public spot.' using errcode = 'P0001', hint = 'private';
  end if;
  if not coalesce(l.active, true) or not bl_place_open(l) then
    raise exception '% is closed right now.', l.name using errcode = 'P0001', hint = 'closed';
  end if;
  if l.scene = 'lounge' then
    perform bl_lounge_assert_entry(v_me.id, l);
  end if;
  if o.location_id = l.id and o.travel_to is null then
    raise exception '@% is already at %.', o.username, l.name using errcode = 'P0001', hint = 'same';
  end if;
  if v_cd > 0 and exists (select 1 from events e where e.user_id = p_friend and e.kind = 'place_invite'
                           and e.data->>'from' = v_me.id::text and e.created_at > now() - make_interval(secs => v_cd::double precision)) then
    raise exception 'You just invited @%. Give them a minute.', o.username using errcode = 'P0001', hint = 'cooldown';
  end if;
  perform bl_event(p_friend, 'place_invite', '@' || v_me.username || ' wants you at ' || l.name,
                   'Tap Go there to join them at ' || l.name || '.',
                   jsonb_build_object('location_id', l.id, 'from', v_me.id, 'from_username', v_me.username, 'place', l.name));
  perform bl_push_enqueue(p_friend, 'friends', 'place_invite', '@' || v_me.username || ' wants you at ' || l.name,
                          'Tap to head there.', '/play?go=place:' || l.id, v_me.id);
  return jsonb_build_object('message', 'Invite sent to @' || o.username || '.', 'place', l.name);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. Guarded edits of live functions
-- ---------------------------------------------------------------------------------------------
-- discount on everything priced in the lounge (do_activity, shop_buy, place_interior, shop_list all go through bl_club_price)
select pg_temp.bl_patch1('public.bl_club_price(public.locations, text, bigint)', 'bl_lounge_price',
  'if coalesce(p_base, 0) <= 0 then return coalesce(p_base, 0); end if;',
  E'if coalesce(p_base, 0) <= 0 then return coalesce(p_base, 0); end if;\n  if p_loc.scene = ''lounge'' then return bl_lounge_price(p_loc, p_ref, p_base); end if; /* R7 lounge */');

-- entry: travel to the lounge needs a membership or a guest pass
select pg_temp.bl_patch1('public.bl_travel_quote(public.profiles, text)', 'bl_lounge_assert_entry',
  E'  if dst.id = src.id then',
  E'  perform bl_lounge_assert_entry(p_me.id, dst); /* R7 lounge */\n  if dst.id = src.id then');

-- activities: entry + VIP gate, free-drink voucher, hype
select pg_temp.bl_patch1('public.do_activity(text)', 'v_voucher',
  E'  v_ev     jsonb;\nbegin',
  E'  v_ev     jsonb;\n  v_voucher boolean := false;\nbegin');
select pg_temp.bl_patch1('public.do_activity(text)', 'bl_lounge_assert(',
  E'  a.cost := bl_club_price(v_loc, a.id, a.cost);',
  E'  perform bl_lounge_assert(v_me.id, v_loc, a.id); /* R7 lounge: members only + VIP zone */\n  a.cost := bl_club_price(v_loc, a.id, a.cost);');
select pg_temp.bl_patch1('public.do_activity(text)', 'bl_lounge_voucher(',
  E'  if a.cost > 0 then\n    perform bl_add_money(v_me.id, ''cash'', -a.cost, ''activity'', jsonb_build_object(''activity'', a.id));',
  E'  if v_scene = ''lounge'' and a.cost > 0 and bl_lounge_voucher(v_me.id, a.id) then\n    a.cost := 0; v_voucher := true; /* R7 free drink voucher */\n  end if;\n  if a.cost > 0 then\n    perform bl_add_money(v_me.id, ''cash'', -a.cost, ''activity'', jsonb_build_object(''activity'', a.id));');
select pg_temp.bl_patch1('public.do_activity(text)', 'Free drink voucher used',
  E'  if cardinality(v_used) > 0 then\n    v_msg := v_msg || '' Used: ''',
  E'  if v_voucher then\n    v_msg := v_msg || '' Free drink voucher used.'';\n  end if;\n  if cardinality(v_used) > 0 then\n    v_msg := v_msg || '' Used: ''');
select pg_temp.bl_patch1('public.do_activity(text)', 'bl_lounge_hype_on',
  E'if v_scene = ''club'' and bl_hype_kind(a.id) is not null then',
  E'if (v_scene = ''club'' or (v_scene = ''lounge'' and bl_lounge_hype_on())) and bl_hype_kind(a.id) is not null then');

-- shop: entry + VIP items, bottles in the lounge are announced
select pg_temp.bl_patch1('public.shop_buy(text, integer)', 'bl_lounge_assert(',
  E'  perform bl_assert_place_open(l);\n  v_total := bl_club_price(',
  E'  perform bl_assert_place_open(l);\n  perform bl_lounge_assert(v_me.id, l, it.id); /* R7 lounge */\n  v_total := bl_club_price(');
select pg_temp.bl_patch1('public.shop_buy(text, integer)', 'bl_lounge_hype_on',
  E'if l.scene = ''club'' and bl_hype_kind(it.id) is not null then',
  E'if (l.scene = ''club'' or (l.scene = ''lounge'' and bl_lounge_hype_on())) and bl_hype_kind(it.id) is not null then');

-- hype: the lounge announces like a club; the VIP cabana is a "vip" spend
select pg_temp.bl_patch1('public.bl_hype_announce(uuid, text, text, bigint, integer, boolean)', 'not in (''club'', ''lounge'')',
  E'if not found or l.scene <> ''club'' then return null; end if;',
  E'if not found or l.scene not in (''club'', ''lounge'') then return null; end if;');
select pg_temp.bl_patch1('public.bl_hype_kind(text)', 'lounge_vip_suite',
  E'when ''big_boy_booth'' then ''vip''',
  E'when ''big_boy_booth'' then ''vip''\n    when ''lounge_vip_suite'' then ''vip''');

-- place_interior: "Members only" / "VIP only" locks and the lounge block for the card
select pg_temp.bl_patch1('public.place_interior(text)', 'bl_lounge_lock(',
  E'when a.home_only and not v_home then ''Only in your own home''',
  E'when bl_lounge_lock(v_uid, l, a.id) is not null then bl_lounge_lock(v_uid, l, a.id)\n                          when a.home_only and not v_home then ''Only in your own home''');
select pg_temp.bl_patch1('public.place_interior(text)', 'bl_lounge_lock(v_uid, l, it.id)',
  E'''locked'', case when not v_open then v_closed_for else null end)\n                 from zone_actions za join items it on it.id = za.ref',
  E'''locked'', case when bl_lounge_lock(v_uid, l, it.id) is not null then bl_lounge_lock(v_uid, l, it.id)\n                                   when not v_open then v_closed_for else null end)\n                 from zone_actions za join items it on it.id = za.ref');
select pg_temp.bl_patch1('public.place_interior(text)', 'bl_lounge_card(',
  E'''zones'', v_zones);',
  E'''zones'', v_zones,\n    ''lounge'', case when l.scene = ''lounge'' then bl_lounge_card(v_uid, l) end);');

-- gold name tag inside the lounge
select pg_temp.bl_patch1('public.players_here(text)', 'bl_lounge_gold',
  E'''street_cred'', p.street_cred, ''last_seen'', p.last_seen)',
  E'''street_cred'', p.street_cred, ''last_seen'', p.last_seen, ''gold'', public.bl_lounge_gold(p.id, p_location))');

-- the lounge can have a playlist like the clubs (Admin -> Music)
select pg_temp.bl_patch1('public.admin_music_assign(text, text, uuid)', 'in (''club'', ''lounge'')',
  E'where id = p_id and scene = ''club'' for update;',
  E'where id = p_id and scene in (''club'', ''lounge'') for update;');
select pg_temp.bl_patch1('public.admin_music_overview()', 'in (''club'', ''lounge'')',
  E'order by l.sort, l.name) from locations l where l.scene = ''club'')',
  E'order by l.sort, l.name) from locations l where l.scene in (''club'', ''lounge''))');

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''lounge'' then',
  E'when ''topup'' then',
  E'when ''lounge'' then return ''The Lounge: '' || coalesce(nullif(p_meta->>''name'', ''''), ''pass'');\n    when ''topup'' then');

-- admin Content editor: Lounge tiers
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''lounge_tiers'' then',
  E'when ''skill_sources'' then',
  E'when ''lounge_tiers'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","icon":"text","blurb":"text","price":"money","hours":"int","discount_pct":"int","vip":"bool","gold_tag":"bool","vouchers":"int","guests":"int","req_charisma_level":"int","req_any_cert":"bool","sort":"int","active":"bool"}}''\n    when ''skill_sources'' then');

-- ---------------------------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_lounge_on() from public, anon, authenticated;
revoke all on function public.bl_lounge_member(uuid) from public, anon, authenticated;
revoke all on function public.bl_lounge_tier(uuid) from public, anon, authenticated;
revoke all on function public.bl_lounge_access(uuid) from public, anon, authenticated;
revoke all on function public.bl_lounge_vip(uuid) from public, anon, authenticated;
revoke all on function public.bl_lounge_gold(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_lounge_hype_on() from public, anon, authenticated;
revoke all on function public.bl_lounge_req_ok(uuid, public.lounge_tiers) from public, anon, authenticated;
revoke all on function public.bl_lounge_req_text(public.lounge_tiers) from public, anon, authenticated;
revoke all on function public.bl_lounge_assert_entry(uuid, public.locations) from public, anon, authenticated;
revoke all on function public.bl_lounge_assert(uuid, public.locations, text) from public, anon, authenticated;
revoke all on function public.bl_lounge_lock(uuid, public.locations, text) from public, anon, authenticated;
revoke all on function public.bl_lounge_price(public.locations, text, bigint) from public, anon, authenticated;
revoke all on function public.bl_lounge_voucher(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_lounge_card(uuid, public.locations) from public, anon, authenticated;
revoke all on function public.bl_place_public(public.locations) from public, anon, authenticated;
revoke all on function public.bl_friend_join_state(profiles, profiles, boolean) from public, anon, authenticated;
revoke all on function public.bl_friend_card(profiles, profiles, numeric, boolean) from public, anon, authenticated;

revoke all on function public.friends_overview() from public, anon;
grant execute on function public.friends_overview() to authenticated, service_role;
revoke all on function public.friends_set_privacy(boolean) from public, anon;
grant execute on function public.friends_set_privacy(boolean) to authenticated, service_role;
revoke all on function public.friend_join_check(uuid) from public, anon;
grant execute on function public.friend_join_check(uuid) to authenticated, service_role;
revoke all on function public.friend_invite_place(uuid) from public, anon;
grant execute on function public.friend_invite_place(uuid) to authenticated, service_role;
revoke all on function public.lounge_status() from public, anon;
grant execute on function public.lounge_status() to authenticated, service_role;
revoke all on function public.lounge_buy(text) from public, anon;
grant execute on function public.lounge_buy(text) to authenticated, service_role;
revoke all on function public.lounge_bring_guest(uuid) from public, anon;
grant execute on function public.lounge_bring_guest(uuid) to authenticated, service_role;
revoke all on function public.admin_lounge_get(uuid) from public, anon;
grant execute on function public.admin_lounge_get(uuid) to authenticated, service_role;
revoke all on function public.admin_lounge_grant(uuid, text, integer) from public, anon;
grant execute on function public.admin_lounge_grant(uuid, text, integer) to authenticated, service_role;
revoke all on function public.admin_lounge_revoke(uuid) from public, anon;
grant execute on function public.admin_lounge_revoke(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
