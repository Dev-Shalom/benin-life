-- SP1 custom spray (docs/SPRAY.md). In every club, the player chooses exactly how much cash to spray.
-- * spray_custom(p_location, p_amount, p_vip): the player must stand in an OPEN club (any place whose scene is
--   'club'), spray CASH in hand only (no bank: "Withdraw at the PoS first"), whole naira between club.spray_min
--   (₦1,000; club.vip_spray_min ₦100,000 for a VIP spray) and min(cash, club.spray_max = ₦10T). Takes numeric so a
--   giant number is refused cleanly instead of overflowing bigint. Per-player cooldown club.spray_cooldown_s (10 s),
--   row-locked (profiles + player_spray) so two taps can never both pass. The money leaves the economy; ledger
--   reason 'spray' ("Sprayed at <club>"). Works while dancing (busy) but not on the road / in jail / in hospital.
-- * Tier by the amount (club.spray_tier_* thresholds): small < nice ₦50k < big ₦500k < huge ₦5M < oga ₦50M <
--   billionaire ₦1B < trillionaire ₦1T. Each tier has its own MC pool in hype_templates (kind spray_<tier>, 8+ lines,
--   no repeats per place via bl_hype_pick) with {name} {place} {amount} (₦2,000,000,000,000) and {short}
--   (₦2 TRILLION). The announcement goes through place_announcements (kind 'spray', new columns tier / vip / points),
--   so every player in the club sees the full-screen hype live (or by the F1 poll fallback). Billionaire+ always
--   reach the app-wide strip (the global cooldown is skipped for them).
-- * Hype points: round(club.spray_points_scale * log10(1 + hype_amount / 1000)), hype_amount = amount x fame bath x
--   Yahoo rank / iPhone (the same helpers as bl_hype_announce) x (1 + club.vip_hype_bonus_pct) for VIP. Log-scale: ₦1k ~ 30,
--   ₦1M ~ 300, ₦1T ~ 900 points. Totals in player_spray (server-only).
-- * VIP: its own MC pool (spray_vip) and a gold-and-black takeover on the client. Spraying from the VIP section needs a VIP booking at a club in the last club.vip_spray_window_h hours (any of
--   club.vip_spray_activities: VIP table, Big Boys' VIP booth, VIP at Amapiano Night) unless club.vip_spray_needs_booking
--   is off. Min club.vip_spray_min, +club.vip_hype_bonus_pct hype, 'VIP' tag on the shout-out.
-- * get_spray_status(p_location): the sheet's numbers (cash, min/max, chips, cooldown left, VIP ok, points).
-- * New "Spray money" cards on the DJ booth and in the VIP section (the dance-floor card already exists); the client
--   opens the spray sheet from all three.
-- Guarded replacements of live functions (pg_get_functiondef): bl_ledger_label. Idempotent, safe on a non-empty DB.

-- ---------------------------------------------------------------------
-- 1. Config (Admin -> Settings -> Clubs)
-- ---------------------------------------------------------------------
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('club.spray_enabled', 'true', 'club', 'Custom spray',
 'SP1: players choose how much cash to spray in any club (the Spray money sheet).', 'bool', null, null),
('club.spray_min', '1000', 'club', 'Spray: minimum',
 'SP1: the smallest spray (cash).', 'naira', 1, null),
('club.spray_max', '10000000000000', 'club', 'Spray: maximum',
 'SP1: the biggest single spray (default ₦10 trillion). Never more than the player''s cash.', 'naira', 1, 1000000000000000),
('club.spray_cooldown_s', '10', 'club', 'Spray: cooldown (seconds)',
 'SP1: a player can spray once every this many seconds.', 'number', 0, 3600),
('club.spray_points_scale', '100', 'club', 'Spray: hype points scale',
 'SP1: hype points = scale x log10(1 + hype amount / 1000). 100 gives ₦1k ~30, ₦1M ~300, ₦1T ~900 points.', 'number', 0, 10000),
('club.spray_chips', '"5000,20000,100000,500000,1000000,10000000,100000000,1000000000"', 'club', 'Spray: quick chips',
 'SP1: comma-separated amounts for the quick chips in the spray sheet ("All my cash" is always added).', 'text', null, null),
('club.spray_tier_nice', '50000', 'club', 'Spray tier: Nice from',
 'SP1: sprays from this amount get the "Nice" MC lines (below it: Small).', 'naira', 1, null),
('club.spray_tier_big', '500000', 'club', 'Spray tier: Big from',
 'SP1: sprays from this amount get the "Big" MC lines and a bigger takeover.', 'naira', 1, null),
('club.spray_tier_huge', '5000000', 'club', 'Spray tier: Huge from',
 'SP1: sprays from this amount get the "Huge" MC lines.', 'naira', 1, null),
('club.spray_tier_oga', '50000000', 'club', 'Spray tier: Oga from',
 'SP1: sprays from this amount get the "Oga" MC lines and the crown.', 'naira', 1, null),
('club.spray_tier_billionaire', '1000000000', 'club', 'Spray tier: Billionaire from',
 'SP1: sprays from this amount get the "Billionaire" lines, the gold rain and always reach the app-wide strip.', 'naira', 1, null),
('club.spray_tier_trillionaire', '1000000000000', 'club', 'Spray tier: Trillionaire from',
 'SP1: sprays from this amount get the "Trillionaire" lines and the biggest takeover.', 'naira', 1, null),
('club.vip_spray_min', '100000', 'club', 'VIP spray: minimum',
 'SP1: the smallest spray from the VIP section.', 'naira', 1, null),
('club.vip_hype_bonus_pct', '25', 'club', 'VIP spray: + hype %',
 'SP1: VIP sprays get this much more hype (points) and a VIP tag on the shout-out.', 'percent', 0, 500),
('club.vip_spray_chips', '"100000,1000000,10000000,100000000,1000000000,10000000000"', 'club', 'VIP spray: quick chips',
 'SP1: comma-separated amounts for the VIP spray chips.', 'text', null, null),
('club.vip_spray_needs_booking', 'true', 'club', 'VIP spray needs a VIP booking',
 'SP1: on = only players who booked a VIP table / Big Boys'' VIP booth / VIP night at a club in the last club.vip_spray_window_h hours can VIP spray.', 'bool', null, null),
('club.vip_spray_window_h', '8', 'club', 'VIP spray: booking lasts (hours)',
 'SP1: how long a VIP booking lets the player VIP spray.', 'number', 1, 72),
('club.vip_spray_activities', '"vip_table,big_boy_booth,amapiano_vip"', 'club', 'VIP spray: booking activities',
 'SP1: comma-separated activity ids that count as a VIP booking.', 'text', null, null)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 2. Announcement columns + the per-tier MC pools
-- ---------------------------------------------------------------------
alter table public.place_announcements add column if not exists tier text;
alter table public.place_announcements add column if not exists vip boolean not null default false;
alter table public.place_announcements add column if not exists points int not null default 0;

do $$
declare v_kinds text[];
begin
  select array_agg(distinct k order by k) into v_kinds from unnest(
    array['vip', 'bottles', 'spray', 'shoutout', 'shutdown', 'vip_arrival',
          'spray_small', 'spray_nice', 'spray_big', 'spray_huge', 'spray_oga', 'spray_billionaire', 'spray_trillionaire', 'spray_vip']
    || coalesce((select array_agg(distinct kind) from public.hype_templates), '{}'::text[])) k;
  alter table public.hype_templates drop constraint if exists hype_templates_kind_chk;
  execute format('alter table public.hype_templates add constraint hype_templates_kind_chk check (kind = any (%L::text[]))', v_kinds);
end $$;

insert into public.hype_templates (id, kind, line, ticker, sort) values
-- Small (< ₦50k)
('spray_small.1', 'spray_small', 'Small small, na so e dey start! @{name} don spray {amount}. Thank you o!', '💸 @{name} sprayed {amount} at {place}', 1),
('spray_small.2', 'spray_small', 'I see you, @{name}! {amount} for the dancers. Every kobo count for {place}.', '💸 @{name} sprayed {amount} at {place}', 2),
('spray_small.3', 'spray_small', 'Giver no dey small! @{name} just drop {amount}. Make una dance am well.', '💸 @{name} sprayed {amount} at {place}', 3),
('spray_small.4', 'spray_small', 'Na from small dem dey grow! @{name} spray {amount}. Next one go big, abi?', '💸 @{name} sprayed {amount} at {place}', 4),
('spray_small.5', 'spray_small', 'Correct starter pack! @{name} don open hand with {amount}. Hands up for am!', '💸 @{name} sprayed {amount} at {place}', 5),
('spray_small.6', 'spray_small', 'Ehen, @{name}! {amount} don touch floor. Na the spirit we dey celebrate.', '💸 @{name} sprayed {amount} at {place}', 6),
('spray_small.7', 'spray_small', 'Who say e small? @{name} sprayed {amount}, the dancer don smile already!', '💸 @{name} sprayed {amount} at {place}', 7),
('spray_small.8', 'spray_small', 'Warm-up spray from @{name}! {amount} for {place}. The night still young o.', '💸 @{name} sprayed {amount} at {place}', 8),
('spray_small.9', 'spray_small', 'Respect the hustle! @{name} drop {amount}. Benin, clap for your person.', '💸 @{name} sprayed {amount} at {place}', 9),
-- Nice (₦50k+)
('spray_nice.1', 'spray_nice', 'Now we dey talk! @{name} don spray {amount}. {place}, make una shout!', '💸 Nice one: @{name} sprayed {short} at {place}', 1),
('spray_nice.2', 'spray_nice', 'That one sweet me! @{name} with {amount} for dance floor. Correct!', '💸 Nice one: @{name} sprayed {short} at {place}', 2),
('spray_nice.3', 'spray_nice', 'E don dey heat up! @{name} release {amount}. Dancers, una see am?', '💸 Nice one: @{name} sprayed {short} at {place}', 3),
('spray_nice.4', 'spray_nice', 'Nice one, @{name}! {amount} don land. The DJ go play your song next.', '💸 Nice one: @{name} sprayed {short} at {place}', 4),
('spray_nice.5', 'spray_nice', 'Hands up, {place}! @{name} don spray {amount}, no shaking at all.', '💸 Nice one: @{name} sprayed {short} at {place}', 5),
('spray_nice.6', 'spray_nice', 'Who dey find enjoyment? @{name} dey here with {amount}! Gbe body e!', '💸 Nice one: @{name} sprayed {short} at {place}', 6),
('spray_nice.7', 'spray_nice', 'Steady giver! @{name} don drop {amount}. Na so Edo people dey do am.', '💸 Nice one: @{name} sprayed {short} at {place}', 7),
('spray_nice.8', 'spray_nice', 'I hail you, @{name}! {amount} for the floor. Make the vibe no stop!', '💸 Nice one: @{name} sprayed {short} at {place}', 8),
('spray_nice.9', 'spray_nice', 'E get as e be! @{name} just spray {amount}. {place}, scream am name!', '💸 Nice one: @{name} sprayed {short} at {place}', 9),
-- Big (₦500k+)
('spray_big.1', 'spray_big', 'Big spray alert! @{name} don rain {amount} for {place}. Pick am with style!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 1),
('spray_big.2', 'spray_big', 'Omo! {amount} dey fly! @{name}, you no dey carry last at all.', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 2),
('spray_big.3', 'spray_big', 'DJ, hold that beat! @{name} just release {amount}. The floor don shine!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 3),
('spray_big.4', 'spray_big', 'Na money rain season! @{name} with {amount}. Dancers, una salary don land!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 4),
('spray_big.5', 'spray_big', 'From Ring Road reach Uselu, dem go hear am: @{name} sprayed {amount} for {place}!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 5),
('spray_big.6', 'spray_big', 'Wetin be this? Bundle by bundle! @{name} don spray {amount}. Ise!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 6),
('spray_big.7', 'spray_big', 'Big boy things! @{name} drop {amount} like say na pure water money.', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 7),
('spray_big.8', 'spray_big', 'Everybody, phones up! @{name} don spray {amount}. This one na content!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 8),
('spray_big.9', 'spray_big', 'Correct spender don land! {amount} from @{name}. {place}, hail your person!', '💸 BIG SPRAY: @{name} dropped {short} at {place}', 9),
-- Huge (₦5M+)
('spray_huge.1', 'spray_huge', 'HUGE! @{name} don spray {amount}! Abeg who get broom? Naira don cover floor!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 1),
('spray_huge.2', 'spray_huge', 'Stop everything! @{name} just rain {short} for {place}. Benin go remember today!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 2),
('spray_huge.3', 'spray_huge', 'E be like say na Central Bank @{name} carry come! {amount} don fly!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 3),
('spray_huge.4', 'spray_huge', 'Security, guard the floor! @{name} don pour {amount}. This one no be beans!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 4),
('spray_huge.5', 'spray_huge', 'Who send you, @{name}?! {short} for dance floor and e no even look back!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 5),
('spray_huge.6', 'spray_huge', 'Na owambe level be this! @{name} don spray {amount}. Edo, stand up!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 6),
('spray_huge.7', 'spray_huge', 'Mint naira dey rain like August! @{name} with {short}. Odogwu!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 7),
('spray_huge.8', 'spray_huge', 'Make una no slip o! @{name} don flood {place} with {amount}!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 8),
('spray_huge.9', 'spray_huge', 'Chairman of the floor! @{name} spray {short}. MC Lightning dey bow for you!', '🔥 HUGE SPRAY: @{name} rained {short} at {place}', 9),
-- Oga (₦50M+)
('spray_oga.1', 'spray_oga', 'OGA AT THE TOP! @{name} don spray {amount}! {place}, bow down!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 1),
('spray_oga.2', 'spray_oga', 'Na oga be this! @{name} just release {short}. Who get money pass am for Benin?', '👑 OGA SPRAY: @{name} rained {short} at {place}', 2),
('spray_oga.3', 'spray_oga', 'Close the gate, nobody comot! @{name} don rain {amount} for {place}!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 3),
('spray_oga.4', 'spray_oga', 'Uyi! Uyi! @{name} don spray {short}! The whole of Ring Road don hear!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 4),
('spray_oga.5', 'spray_oga', 'Crown am! @{name} with {amount}. This na oga matter, small boys siddon!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 5),
('spray_oga.6', 'spray_oga', 'Wahala for who no dey {place} tonight! @{name} don spray {short}!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 6),
('spray_oga.7', 'spray_oga', 'The money too much, the floor no fit carry am! @{name} sprayed {amount}!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 7),
('spray_oga.8', 'spray_oga', 'Odogwu of odogwus! @{name} don drop {short}. Make una hail the oga!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 8),
('spray_oga.9', 'spray_oga', 'Na bank vault @{name} carry enter club? {amount} don rain! Oga, we greet!', '👑 OGA SPRAY: @{name} rained {short} at {place}', 9),
-- Billionaire (₦1B+)
('spray_billionaire.1', 'spray_billionaire', 'BILLIONAIRE ON THE FLOOR! @{name} don spray {amount}! {place}, una dey see this?!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 1),
('spray_billionaire.2', 'spray_billionaire', 'Stop the music! @{name} just spray {short}! This one go enter news!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 2),
('spray_billionaire.3', 'spray_billionaire', 'Na billion we dey count now! @{name} don rain {amount}. Benin City, stand up!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 3),
('spray_billionaire.4', 'spray_billionaire', 'Omo, the CBN go call! @{name} don spray {short} for {place}!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 4),
('spray_billionaire.5', 'spray_billionaire', 'Make the whole club kneel down! @{name} sprayed {amount}. Billionaire things!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 5),
('spray_billionaire.6', 'spray_billionaire', 'Wetin my eye see today?! {short} from @{name}! Even the DJ don faint!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 6),
('spray_billionaire.7', 'spray_billionaire', 'From Oba Market reach GRA, dem go talk am for years: @{name} sprayed {short}!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 7),
('spray_billionaire.8', 'spray_billionaire', 'Na Dangote cousin be this?! @{name} don rain {amount} for {place}!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 8),
('spray_billionaire.9', 'spray_billionaire', 'Bring the money counter! @{name} just release {short}. Billionaire don land!', '💎 BILLIONAIRE SPRAY: @{name} rained {short} at {place}', 9),
-- Trillionaire (₦1T+)
('spray_trillionaire.1', 'spray_trillionaire', 'TRILLIONAIRE!!! @{name} don spray {amount}! {place}, history don happen tonight!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 1),
('spray_trillionaire.2', 'spray_trillionaire', 'Everybody freeze! @{name} just spray {short}! Nigeria economy don shake!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 2),
('spray_trillionaire.3', 'spray_trillionaire', 'Na trillion o, no be billion! @{name} don rain {amount}. Make una bow!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 3),
('spray_trillionaire.4', 'spray_trillionaire', 'Close Benin City! @{name} don spray {short} for {place}. Nobody fit pass this one!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 4),
('spray_trillionaire.5', 'spray_trillionaire', 'Na the richest person for the whole Edo be this! @{name} sprayed {amount}!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 5),
('spray_trillionaire.6', 'spray_trillionaire', 'MC Lightning don lose voice! @{name} with {short}! Wetin I go even talk?!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 6),
('spray_trillionaire.7', 'spray_trillionaire', 'Crown, throne and palace! @{name} don rain {amount}. Kabiyesi of the floor!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 7),
('spray_trillionaire.8', 'spray_trillionaire', 'Call the news, call the radio! @{name} sprayed {short} for {place}! E don cast!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 8),
('spray_trillionaire.9', 'spray_trillionaire', 'The naira no fit finish tonight! @{name} don pour {amount}. Legend!', '🌍 TRILLIONAIRE SPRAY: @{name} rained {short} at {place}', 9),
-- VIP (sprayed from the VIP section; its own pool, gold-and-black takeover)
('spray_vip.1', 'spray_vip', 'VIP in the building! @{name} don spray {amount} from the VIP section. Gold rain for {place}!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 1),
('spray_vip.2', 'spray_vip', 'From the VIP rope, @{name} don open the vault! {short} dey fly. Make una bow!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 2),
('spray_vip.3', 'spray_vip', 'Na VIP money be this, e get gold smell! @{name} sprayed {amount}. {place}, hail the VIP!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 3),
('spray_vip.4', 'spray_vip', 'Sparkler girls, follow am! VIP @{name} just release {short} from the high table!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 4),
('spray_vip.5', 'spray_vip', 'Big table, bigger hand! @{name} don rain {amount} from VIP. Odogwu don show!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 5),
('spray_vip.6', 'spray_vip', 'Gold standard! VIP @{name} don spray {short}. Obokhian, chairman of the night!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 6),
('spray_vip.7', 'spray_vip', 'Light am up, DJ! The VIP section dey talk: @{name} with {amount}!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 7),
('spray_vip.8', 'spray_vip', 'When VIP spray, the whole club go feel am! @{name} don pour {short} for {place}!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 8),
('spray_vip.9', 'spray_vip', 'No be every hand fit spray from that rope o! VIP @{name} don drop {amount}. Uyi!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 9),
('spray_vip.10', 'spray_vip', 'Crown don shine for VIP! @{name} sprayed {short}. {place}, scream am name!', '👑 VIP SPRAY: @{name} rained {short} at {place}', 10)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Per-player spray state (server only)
-- ---------------------------------------------------------------------
create table if not exists public.player_spray (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  last_spray_at timestamptz,
  sprays        int not null default 0,
  total_sprayed numeric not null default 0,
  best_spray    bigint not null default 0,
  hype_points   bigint not null default 0,
  updated_at    timestamptz not null default now()
);
alter table public.player_spray enable row level security;
revoke all on table public.player_spray from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Helpers (server only)
-- ---------------------------------------------------------------------
create or replace function public.bl_spray_num(p_key text, p_default numeric) returns numeric
language sql stable set search_path = public as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then (value #>> '{}')::numeric
                               when jsonb_typeof(value) = 'string' and (value #>> '{}') ~ '^\s*-?\d+(\.\d+)?\s*$' then (value #>> '{}')::numeric
                          end from game_config where key = p_key), p_default);
$$;

-- tier id for an amount
create or replace function public.bl_spray_tier(p_amount numeric) returns text
language sql stable set search_path = public as $$
  select case
    when p_amount >= bl_spray_num('club.spray_tier_trillionaire', 1000000000000) then 'trillionaire'
    when p_amount >= bl_spray_num('club.spray_tier_billionaire', 1000000000) then 'billionaire'
    when p_amount >= bl_spray_num('club.spray_tier_oga', 50000000) then 'oga'
    when p_amount >= bl_spray_num('club.spray_tier_huge', 5000000) then 'huge'
    when p_amount >= bl_spray_num('club.spray_tier_big', 500000) then 'big'
    when p_amount >= bl_spray_num('club.spray_tier_nice', 50000) then 'nice'
    else 'small' end;
$$;

create or replace function public.bl_spray_tier_rank(p_tier text) returns int
language sql immutable as $$
  select coalesce(array_position(array['small', 'nice', 'big', 'huge', 'oga', 'billionaire', 'trillionaire'], p_tier), 1) - 1;
$$;

-- ₦2 TRILLION / ₦1.5 BILLION / ₦250 MILLION / ₦50 THOUSAND / ₦900 (one decimal, truncated, never rounds up)
create or replace function public.bl_spray_short(p_amount numeric) returns text
language sql immutable as $$
  select case
    when v >= 1e12 then '₦' || trim_scale(trunc(v / 1e12, case when v >= 1e14 then 0 else 1 end)) || ' TRILLION'
    when v >= 1e9  then '₦' || trim_scale(trunc(v / 1e9,  case when v >= 1e11 then 0 else 1 end)) || ' BILLION'
    when v >= 1e6  then '₦' || trim_scale(trunc(v / 1e6,  case when v >= 1e8  then 0 else 1 end)) || ' MILLION'
    when v >= 1e3  then '₦' || trim_scale(trunc(v / 1e3,  case when v >= 1e5  then 0 else 1 end)) || ' THOUSAND'
    else '₦' || v::text end
  from (select round(abs(coalesce(p_amount, 0))) as v) x;
$$;

create or replace function public.bl_spray_points(p_hype_amount numeric) returns int
language sql stable set search_path = public as $$
  select greatest(0, round(greatest(0, bl_spray_num('club.spray_points_scale', 100))
                           * log(10, 1 + greatest(0, coalesce(p_hype_amount, 0)) / 1000.0)))::int;
$$;

-- csv of amounts -> jsonb array of positive integers
create or replace function public.bl_spray_chips(p_key text, p_default text) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(v order by o), '[]'::jsonb)
    from (select btrim(x)::numeric as v, o
            from unnest(string_to_array(coalesce(nullif(btrim(coalesce(
                   (select value #>> '{}' from game_config where key = p_key), '')), ''), p_default), ',')) with ordinality as t(x, o)
           where btrim(x) ~ '^\d+$' and btrim(x)::numeric > 0) s;
$$;

-- The player booked VIP (table / Big Boys' booth / VIP night) recently enough to spray from the VIP section.
create or replace function public.bl_spray_vip_ok(p_uid uuid) returns boolean
language sql stable set search_path = public as $$
  select not coalesce(bl_cfg_bool('club.vip_spray_needs_booking'), true)
      or exists (select 1 from ledger g
                  where g.user_id = p_uid and g.reason = 'activity'
                    and g.created_at > bl_now() - make_interval(hours => greatest(1, bl_spray_num('club.vip_spray_window_h', 8))::int)
                    and bl_csv_has(coalesce(bl_cfg_text('club.vip_spray_activities'), 'vip_table,big_boy_booth,amapiano_vip'),
                                   g.meta->>'activity'));
$$;

revoke all on function public.bl_spray_num(text, numeric) from public, anon, authenticated;
revoke all on function public.bl_spray_tier(numeric) from public, anon, authenticated;
revoke all on function public.bl_spray_tier_rank(text) from public, anon, authenticated;
revoke all on function public.bl_spray_short(numeric) from public, anon, authenticated;
revoke all on function public.bl_spray_points(numeric) from public, anon, authenticated;
revoke all on function public.bl_spray_chips(text, text) from public, anon, authenticated;
revoke all on function public.bl_spray_vip_ok(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. The sheet's numbers
-- ---------------------------------------------------------------------
create or replace function public.get_spray_status(p_location text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid  uuid := bl_require_uid();
  p      profiles;
  l      locations;
  s      player_spray;
  v_cd   numeric := greatest(0, bl_spray_num('club.spray_cooldown_s', 10));
  v_left int := 0;
begin
  select * into p from profiles where id = v_uid;
  if not found then
    raise exception 'Make your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  select * into l from locations where id = coalesce(p_location, p.location_id);
  select * into s from player_spray where user_id = v_uid;
  if s.last_spray_at is not null then
    v_left := greatest(0, ceil(extract(epoch from s.last_spray_at + make_interval(secs => v_cd) - bl_now())))::int;
  end if;
  return jsonb_build_object(
    'enabled', coalesce(bl_cfg_bool('club.spray_enabled'), true),
    'location', l.id, 'place', regexp_replace(coalesce(l.name, ''), '\s*\(.*\)\s*$', ''),
    'in_club', l.id is not null and l.scene = 'club' and p.location_id = l.id and p.travel_to is null,
    'open', l.id is not null and bl_place_open(l),
    'cash', p.cash, 'bank', p.bank,
    'min', greatest(1, bl_spray_num('club.spray_min', 1000)),
    'max', greatest(1, bl_spray_num('club.spray_max', 10000000000000)),
    'vip_min', greatest(1, bl_spray_num('club.vip_spray_min', 100000)),
    'vip_pct', greatest(0, bl_spray_num('club.vip_hype_bonus_pct', 25)),
    'vip_ok', bl_spray_vip_ok(v_uid),
    'cooldown_s', v_cd, 'cooldown_left', v_left,
    'chips', bl_spray_chips('club.spray_chips', '5000,20000,100000,500000,1000000,10000000,100000000,1000000000'),
    'vip_chips', bl_spray_chips('club.vip_spray_chips', '100000,1000000,10000000,100000000,1000000000,10000000000'),
    'tiers', jsonb_build_array(
      jsonb_build_object('id', 'small', 'label', 'Small', 'min', 0),
      jsonb_build_object('id', 'nice', 'label', 'Nice', 'min', bl_spray_num('club.spray_tier_nice', 50000)),
      jsonb_build_object('id', 'big', 'label', 'Big', 'min', bl_spray_num('club.spray_tier_big', 500000)),
      jsonb_build_object('id', 'huge', 'label', 'Huge', 'min', bl_spray_num('club.spray_tier_huge', 5000000)),
      jsonb_build_object('id', 'oga', 'label', 'Oga', 'min', bl_spray_num('club.spray_tier_oga', 50000000)),
      jsonb_build_object('id', 'billionaire', 'label', 'Billionaire', 'min', bl_spray_num('club.spray_tier_billionaire', 1000000000)),
      jsonb_build_object('id', 'trillionaire', 'label', 'Trillionaire', 'min', bl_spray_num('club.spray_tier_trillionaire', 1000000000000))),
    'points', coalesce(s.hype_points, 0), 'sprays', coalesce(s.sprays, 0), 'total_sprayed', coalesce(s.total_sprayed, 0),
    'best', coalesce(s.best_spray, 0));
end $$;
revoke all on function public.get_spray_status(text) from public, anon;
grant execute on function public.get_spray_status(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 6. Spray
-- ---------------------------------------------------------------------
create or replace function public.spray_custom(p_location text, p_amount numeric, p_vip boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles := bl_me();
  l        locations;
  s        player_spray;
  t        hype_templates;
  v_now    timestamptz := bl_now();
  v_vip    boolean := coalesce(p_vip, false);
  v_min    numeric;
  v_max    numeric := greatest(1, bl_spray_num('club.spray_max', 10000000000000));
  v_cd     numeric := greatest(0, bl_spray_num('club.spray_cooldown_s', 10));
  v_amt    bigint;
  v_cash   bigint;
  v_tier   text;
  v_rank   int;
  v_place  text;
  v_short  text;
  v_hype   numeric;
  v_points int;
  v_text   text;
  v_ticker text;
  v_global boolean := false;
  v_row    place_announcements;
  v_left   int;
  v_eff    jsonb;
begin
  if not coalesce(bl_cfg_bool('club.spray_enabled'), true) then
    raise exception 'Spraying is paused right now. Try again later.' using errcode = 'P0001', hint = 'disabled';
  end if;
  -- lock my row first: two taps at once never both pass
  select * into v_me from profiles where id = v_me.id for update;
  -- on the road / in jail / in hospital: no (dancing is fine)
  if v_me.jailed_until is not null and v_me.jailed_until > v_now then
    raise exception 'You are in a police cell. No spraying from there.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.hospitalized_until is not null and v_me.hospitalized_until > v_now then
    raise exception 'You are still admitted in hospital.' using errcode = 'P0001', hint = 'hospitalized';
  end if;
  if v_me.travel_to is not null then
    raise exception 'You are still on the road. Wait until you arrive.' using errcode = 'P0001', hint = 'traveling';
  end if;
  select * into l from locations where id = coalesce(p_location, v_me.location_id);
  if not found or l.scene <> 'club' then
    raise exception 'You can only spray money in a club.' using errcode = 'P0001', hint = 'not_club';
  end if;
  if v_me.location_id is distinct from l.id then
    raise exception 'You are not at % right now.', l.name using errcode = 'P0001', hint = 'wrong_place';
  end if;
  perform bl_assert_place_open(l);
  -- the amount: whole naira, between the min and the max (numeric in, so a giant number never overflows)
  v_min := case when v_vip then greatest(1, bl_spray_num('club.vip_spray_min', 100000)) else greatest(1, bl_spray_num('club.spray_min', 1000)) end;
  if p_amount is null or p_amount <> trunc(p_amount) or p_amount <= 0 then
    raise exception 'Enter a whole naira amount.' using errcode = 'P0001', hint = 'bad_amount';
  end if;
  if p_amount < v_min then
    raise exception '% spray starts from %.', case when v_vip then 'VIP' else 'A' end, bl_naira(v_min)
      using errcode = 'P0001', hint = 'too_small';
  end if;
  if p_amount > v_max then
    raise exception 'Easy, oga! The most you can spray at once is %.', bl_naira(v_max) using errcode = 'P0001', hint = 'too_much';
  end if;
  v_amt := p_amount::bigint;
  if v_vip and not bl_spray_vip_ok(v_me.id) then
    raise exception 'VIP spray is for VIP guests. Book a VIP table first.' using errcode = 'P0001', hint = 'not_vip';
  end if;
  if v_amt > v_me.cash then
    raise exception 'You only have % cash on you. Withdraw at the PoS first.', bl_naira(v_me.cash)
      using errcode = 'P0001', hint = 'no_cash';
  end if;
  -- cooldown (row-locked)
  insert into player_spray (user_id) values (v_me.id) on conflict (user_id) do nothing;
  select * into s from player_spray where user_id = v_me.id for update;
  if s.last_spray_at is not null and s.last_spray_at > v_now - make_interval(secs => v_cd) then
    v_left := greatest(1, ceil(extract(epoch from s.last_spray_at + make_interval(secs => v_cd) - v_now)))::int;
    raise exception 'Hold small, the dancers are still picking the last one. Spray again in % s.', v_left
      using errcode = 'P0001', hint = 'cooldown';
  end if;

  -- the money leaves the economy
  v_cash := bl_add_money(v_me.id, 'cash', -v_amt, 'spray',
              jsonb_build_object('location', l.id, 'place', regexp_replace(l.name, '\s*\(.*\)\s*$', ''), 'vip', v_vip));

  v_tier := bl_spray_tier(v_amt);
  v_rank := bl_spray_tier_rank(v_tier);
  -- hype: fame bath + Yahoo rank / iPhone (as bl_hype_announce) + VIP
  v_hype := bl_yahoo_hype_amount(v_me.id, bl_charm_hype_amount(v_me.id, v_amt))::numeric;
  if v_vip then
    v_hype := v_hype * (1 + greatest(0, bl_spray_num('club.vip_hype_bonus_pct', 25)) / 100.0);
  end if;
  v_points := bl_spray_points(v_hype);

  update player_spray set last_spray_at = v_now, sprays = sprays + 1, total_sprayed = total_sprayed + v_amt,
         best_spray = greatest(best_spray, v_amt), hype_points = hype_points + v_points, updated_at = now()
   where user_id = v_me.id
   returning * into s;

  -- a little joy (bigger tiers, more)
  v_eff := jsonb_build_object('fun', 6 + 4 * v_rank, 'social', 5 + 3 * v_rank);
  perform bl_adjust_needs(v_me.id, v_eff);
  if v_rank > 0 then
    update profiles set street_cred = street_cred + v_rank where id = v_me.id;
  end if;

  -- the hype man's shout-out for everyone in the club
  if coalesce(bl_cfg_bool('hype.enabled'), false) then
    v_place := regexp_replace(l.name, '\s*\(.*\)\s*$', '');
    v_short := bl_spray_short(v_amt);
    -- VIP sprays have their own pool; the rest by tier; the old spray pool as the last resort
    if v_vip then t := bl_hype_pick(l.id, 'spray_vip'); end if;
    if t.id is null then t := bl_hype_pick(l.id, 'spray_' || v_tier); end if;
    if t.id is null then t := bl_hype_pick(l.id, 'spray'); end if;
    v_text := coalesce(bl_hype_render(replace(t.line, '{short}', v_short), v_me.username, v_place, 1, v_amt),
                       format('@%s don spray %s for %s!', v_me.username, bl_naira(v_amt), v_place));
    v_ticker := nullif(coalesce(t.ticker, ''), '');
    if v_ticker is not null and v_amt >= bl_cfg('hype.global_min')
       and (v_rank >= bl_spray_tier_rank('billionaire')
            or not exists (select 1 from place_announcements
                            where global and created_at > now() - make_interval(secs => greatest(0, bl_cfg('hype.global_cooldown_s'))))) then
      v_global := true;
      v_ticker := bl_hype_render(replace(v_ticker, '{short}', v_short), v_me.username, v_place, 1, v_amt);
    else
      v_ticker := null;
    end if;
    insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, ticker, global, place, tier, vip, points)
    values (l.id, v_me.id, v_me.username, 'spray', v_amt, 1, left(v_text, 400), left(v_ticker, 200), v_global, v_place, v_tier, v_vip, v_points)
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'message', 'You sprayed ' || bl_naira(v_amt) || ' at ' || regexp_replace(l.name, '\s*\(.*\)\s*$', '') || '. The MC dey hail you!',
    'amount', v_amt, 'cash_after', v_cash, 'tier', v_tier, 'vip', v_vip,
    'hype_amount', round(v_hype), 'points', v_points, 'total_points', s.hype_points,
    'cooldown_s', v_cd, 'effects', v_eff, 'hype', case when v_row.id is null then null else to_jsonb(v_row) end);
end $$;
revoke all on function public.spray_custom(text, numeric, boolean) from public, anon;
grant execute on function public.spray_custom(text, numeric, boolean) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 7. Ledger label "Sprayed at <club>" (guarded replacement of the live function)
-- ---------------------------------------------------------------------
do $$
declare v_def text; v_anchor text := '    when ''yahoo_cashout'' then';
begin
  select pg_get_functiondef('public.bl_ledger_label(text,jsonb)'::regprocedure) into v_def;
  if position('Sprayed at' in v_def) > 0 then
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'SP1: bl_ledger_label() changed; update the custom spray migration anchor.';
  end if;
  v_def := replace(v_def, v_anchor,
    '    when ''spray'' then return ''Sprayed at '' || coalesce(nullif(p_meta->>''place'', ''''), ''the club'');' || chr(10) || v_anchor);
  execute v_def;
end $$;

-- ---------------------------------------------------------------------
-- 8. Spray cards on the DJ booth and in the VIP section (the dance floor has one)
-- ---------------------------------------------------------------------
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort) values
  ('club.dj.spray_money',  'club.dj',  'activity', 'spray_money', 'Spray money', '💸', 3),
  ('club.vip.spray_money', 'club.vip', 'activity', 'spray_money', 'VIP spray', '💸', 3)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
