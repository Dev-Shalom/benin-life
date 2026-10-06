-- P3 hype with aura (docs/SHIP_TODAY.md "P3", docs/PLACES.md "P3 hype aura").
-- * 18 more MC lines per kind (vip / bottles / spray / shoutout / shutdown) -> 20 per kind, in the voice of a
--   Benin club hype man (English + Pidgin, a touch of Edo). Seeded once per stable id (on conflict do nothing),
--   so admin edits in Content -> Hype lines are never overwritten. Each has a short ticker line for the app-wide
--   strip.
-- * No repeats: hype_template_recent remembers which lines a place has used per kind; bl_hype_announce picks at
--   random among the unused ones and starts a new cycle when the pool is used up (never the same line twice in a
--   row across the cycle edge). Server-only table (RLS on, no grants).
-- * place_announcements.place: the place's display name ("360 Signature"), so the full-screen takeover and the
--   app-wide strip can say "SHUT DOWN 360 SIGNATURE" without a lookup.
-- Re-created from its live definition (grants kept): bl_hype_announce.
-- Idempotent and safe on a non-empty DB.

-- ---------------------------------------------------------------------
-- 1. Display name on the announcement
-- ---------------------------------------------------------------------
alter table public.place_announcements add column if not exists place text;

-- ---------------------------------------------------------------------
-- 2. Which lines each place has used (no repeats until the pool cycles)
-- ---------------------------------------------------------------------
create table if not exists public.hype_template_recent (
  location_id text not null references public.locations(id) on delete cascade,
  kind        text not null,
  template_id text not null references public.hype_templates(id) on delete cascade,
  used_at     timestamptz not null default clock_timestamp(),
  primary key (location_id, template_id)
);
create index if not exists hype_template_recent_kind_idx on public.hype_template_recent (location_id, kind, used_at desc);
alter table public.hype_template_recent enable row level security;
revoke all on table public.hype_template_recent from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. MC lines (seeded once per id; the admin edits them in Content -> Hype lines)
-- ---------------------------------------------------------------------
insert into public.hype_templates (id, kind, line, ticker, sort) values
('vip.3', 'vip', 'Odogwu don land! @{name} don take VIP table for {place}. Security, open that rope!', '👑 @{name} just took VIP at {place}', 3),
('vip.4', 'vip', 'Who get money pass am for this club? @{name} just collect VIP. Ehen!', '🥂 @{name} is holding court at {place}', 4),
('vip.5', 'vip', 'Koyo, Benin City! Make una stand up for {name}, VIP table don get owner!', '✨ @{name} landed in VIP at {place}', 5),
('vip.6', 'vip', 'Hostess, carry the menu go meet @{name}! VIP table, no long story.', '🔥 VIP rope open for @{name} at {place}', 6),
('vip.7', 'vip', 'Na so e suppose be! @{name} don siddon for VIP like chairman. {place}, wave am!', '👑 Chairman @{name} is in VIP at {place}', 7),
('vip.8', 'vip', 'Rope don open, light don shine, @{name} don enter VIP. This one no be beans o!', '👑 @{name} just took VIP at {place}', 8),
('vip.9', 'vip', 'Obokhian! Welcome to VIP, @{name}. Na here the big boys and big girls dey sit.', '🥂 @{name} is holding court at {place}', 9),
('vip.10', 'vip', 'DJ Ekpen, drop that beat for @{name}! VIP table don confirm for {place}.', '✨ @{name} landed in VIP at {place}', 10),
('vip.11', 'vip', 'From Ring Road reach Sapele Road, dem don hear say @{name} dey VIP tonight!', '🔥 VIP rope open for @{name} at {place}', 11),
('vip.12', 'vip', 'If you no know @{name} before, look am well. VIP table, {amount} down, zero shaking.', '👑 Chairman @{name} is in VIP at {place}', 12),
('vip.13', 'vip', 'Edo no dey carry last! @{name} don book VIP, {place} don set!', '👑 @{name} just took VIP at {place}', 13),
('vip.14', 'vip', 'Make una clear road, VIP don land! @{name}, the table na your own till morning.', '🥂 @{name} is holding court at {place}', 14),
('vip.15', 'vip', 'E get why. @{name} no dey sit for floor, na VIP or nothing. Hail am!', '✨ @{name} landed in VIP at {place}', 15),
('vip.16', 'vip', 'Ladies and gentlemen, our new VIP: @{name}! {place}, give am small noise... no o, BIG noise!', '🔥 VIP rope open for @{name} at {place}', 16),
('vip.17', 'vip', 'Sparkler girls, una work don start. @{name} just take VIP table!', '👑 Chairman @{name} is in VIP at {place}', 17),
('vip.18', 'vip', 'Uyi! Honour to @{name}, VIP table don land. Today na today!', '👑 @{name} just took VIP at {place}', 18),
('vip.19', 'vip', 'Chairman of the night don sit down! @{name}, VIP section dey greet you.', '🥂 @{name} is holding court at {place}', 19),
('vip.20', 'vip', 'No be everybody fit pass that rope o. @{name} waka enter am like say na im house!', '✨ @{name} landed in VIP at {place}', 20),
('bottles.3', 'bottles', 'E no dey finish! {bottles} and counting for @{name}! {place}, shout!', '🍾 @{name} is popping bottles at {place}', 3),
('bottles.4', 'bottles', 'Waiter, run am! @{name} don call for {bottles}. Sparklers, rise up!', '🍾 {bottles} for @{name} at {place}', 4),
('bottles.5', 'bottles', 'Who dey pop like this? @{name}, {bottles} don land for table!', '✨ Sparklers up for @{name} at {place}', 5),
('bottles.6', 'bottles', 'Ice bucket don full! @{name} get {bottles} for table and e still dey order.', '🥂 @{name} has the champagne going at {place}', 6),
('bottles.7', 'bottles', 'Light am up! {bottles} dey parade go meet @{name}. Na celebration we dey!', '🍾 Bottle parade for @{name} at {place}', 7),
('bottles.8', 'bottles', 'DJ Ekpen, hold the beat! @{name} just pop {bottles}. Make una see sparkle!', '🍾 @{name} is popping bottles at {place}', 8),
('bottles.9', 'bottles', 'Na champagne shower tonight! @{name} don open {bottles} for {place}.', '🍾 {bottles} for @{name} at {place}', 9),
('bottles.10', 'bottles', 'If you dey find enjoyment, find @{name}. {bottles} don open already!', '✨ Sparklers up for @{name} at {place}', 10),
('bottles.11', 'bottles', 'Benin City, una dey see wetin I dey see? {bottles} for @{name} table!', '🥂 @{name} has the champagne going at {place}', 11),
('bottles.12', 'bottles', 'Bottle parade! @{name} don order {bottles}, the waiters no go rest tonight.', '🍾 Bottle parade for @{name} at {place}', 12),
('bottles.13', 'bottles', 'Pop! Pop! Pop! Na {bottles} from @{name} be that. {place}, make una hail!', '🍾 @{name} is popping bottles at {place}', 13),
('bottles.14', 'bottles', 'Omo, the cork dey fly! @{name} dey on {bottles} now. E sweet am die.', '🍾 {bottles} for @{name} at {place}', 14),
('bottles.15', 'bottles', 'Na so money dey talk! {bottles} for @{name} and the night still young.', '✨ Sparklers up for @{name} at {place}', 15),
('bottles.16', 'bottles', 'Ehen! @{name} say make e rain champagne. {bottles} don land. Gbas gbos!', '🥂 @{name} has the champagne going at {place}', 16),
('bottles.17', 'bottles', 'Hold your glass well! @{name} don pop {bottles}, the whole side go taste am.', '🍾 Bottle parade for @{name} at {place}', 17),
('bottles.18', 'bottles', 'Edo people, raise your hands! @{name} don carry {bottles} enter VIP!', '🍾 @{name} is popping bottles at {place}', 18),
('bottles.19', 'bottles', 'Sparklers up, phones up! {bottles} for @{name}. Na content be this!', '🍾 {bottles} for @{name} at {place}', 19),
('bottles.20', 'bottles', 'Champagne no dey vex anybody. @{name}, {bottles} don show. Correct!', '✨ Sparklers up for @{name} at {place}', 20),
('spray.3', 'spray', 'Money dey rain! @{name} dey spray {amount} for dance floor. Pick am with style o!', '💸 @{name} is spraying {amount} at {place}', 3),
('spray.4', 'spray', 'E be like say na ATM @{name} carry come! {amount} don fly!', '💸 Naira rain at {place}: @{name}', 4),
('spray.5', 'spray', 'Hands up, {place}! @{name} don spray {amount}. Na so Benin dey do am!', '💸 @{name} is making it rain at {place}', 5),
('spray.6', 'spray', 'Wetin be this? Na naira rain! @{name} dey spray {amount} and e never tire.', '💸 Money dey fly at {place}! @{name}', 6),
('spray.7', 'spray', 'DJ, no stop the music! @{name} still dey spray. {amount} don touch ground!', '💸 @{name} just sprayed {amount} at {place}', 7),
('spray.8', 'spray', 'Owambe vibes for club! @{name} dey spray like say na wedding. {amount}!', '💸 @{name} is spraying {amount} at {place}', 8),
('spray.9', 'spray', 'Mint naira dey fly for air! @{name}, you be correct person. {amount}!', '💸 Naira rain at {place}: @{name}', 9),
('spray.10', 'spray', 'Who send you, @{name}? {amount} for dance floor and e no even look back!', '💸 @{name} is making it rain at {place}', 10),
('spray.11', 'spray', 'Make una dance well well, @{name} dey spray! {amount} no be small thing.', '💸 Money dey fly at {place}! @{name}', 11),
('spray.12', 'spray', 'Na rain season for {place}! @{name} don release {amount}.', '💸 @{name} just sprayed {amount} at {place}', 12),
('spray.13', 'spray', 'Edo money no dey finish! @{name} don spray {amount}. Hail the giver!', '💸 @{name} is spraying {amount} at {place}', 13),
('spray.14', 'spray', 'Dancers, una see your oga? @{name} dey spray {amount}. Shake am!', '💸 Naira rain at {place}: @{name}', 14),
('spray.15', 'spray', 'From Uselu to GRA, dem go talk am tomorrow: @{name} sprayed {amount} for {place}!', '💸 @{name} is making it rain at {place}', 15),
('spray.16', 'spray', 'E dey rain, e dey pour! @{name} with {amount}. Abeg nobody slip o!', '💸 Money dey fly at {place}! @{name}', 16),
('spray.17', 'spray', 'Correct spender! @{name} just spray {amount}. Benin, una hear?', '💸 @{name} just sprayed {amount} at {place}', 17),
('spray.18', 'spray', 'Giver never lack! @{name} don spray {amount}. Ise!', '💸 @{name} is spraying {amount} at {place}', 18),
('spray.19', 'spray', 'Na so dem dey do am for Benin! @{name} dey spray {amount}, the floor don shine.', '💸 Naira rain at {place}: @{name}', 19),
('spray.20', 'spray', 'Money no be problem tonight! @{name} don open hand, {amount} dey fly!', '💸 @{name} is making it rain at {place}', 20),
('shoutout.3', 'shoutout', 'Special shout-out to the one and only @{name}! Odogwu don land!', '🎤 MC Lightning is hailing @{name} at {place}', 3),
('shoutout.4', 'shoutout', 'DJ Ekpen, drop that beat for @{name}! Tonight na your night!', '🎤 Shout-out to @{name} at {place}', 4),
('shoutout.5', 'shoutout', 'Benin City, make una stand up for {name}! Na person wey dey move correct.', '🎤 @{name} is the main character at {place}', 5),
('shoutout.6', 'shoutout', 'I dey hail you, @{name}! Big heart, clean vibes. {place}, scream!', '🎤 {place} is standing up for @{name}', 6),
('shoutout.7', 'shoutout', 'Mic check! This one na for @{name}. If you know am, shout! If you no know am, shout anyway!', '🎤 Big shout-out for @{name} at {place}', 7),
('shoutout.8', 'shoutout', 'Koyo! @{name}, MC Lightning dey greet you. You don make this night better.', '🎤 MC Lightning is hailing @{name} at {place}', 8),
('shoutout.9', 'shoutout', 'Make una hail the main character: @{name}! The energy don change for {place}.', '🎤 Shout-out to @{name} at {place}', 9),
('shoutout.10', 'shoutout', 'Na who dey hold the night? Na @{name}! Give am one loud EHEN!', '🎤 @{name} is the main character at {place}', 10),
('shoutout.11', 'shoutout', 'Edo no dey carry last and @{name} no dey carry last! Shout-out from the booth!', '🎤 {place} is standing up for @{name}', 11),
('shoutout.12', 'shoutout', 'Respect to @{name}! Person wey sabi enjoy, sabi share. {place}, wave am!', '🎤 Big shout-out for @{name} at {place}', 12),
('shoutout.13', 'shoutout', 'Hold the beat small... @{name}, this shout-out na for you. Correct person!', '🎤 MC Lightning is hailing @{name} at {place}', 13),
('shoutout.14', 'shoutout', 'Ladies, gentlemen, oga dem, aunty dem: put your hands together for @{name}!', '🎤 Shout-out to @{name} at {place}', 14),
('shoutout.15', 'shoutout', 'Uyi! Honour to @{name}. Tell your friends say MC Lightning call your name!', '🎤 @{name} is the main character at {place}', 15),
('shoutout.16', 'shoutout', 'From the booth with love: @{name}, the vibe na you! {place}, make noise!', '🎤 {place} is standing up for @{name}', 16),
('shoutout.17', 'shoutout', 'Big man energy, small man humility. Na @{name} be that. Hail am!', '🎤 Big shout-out for @{name} at {place}', 17),
('shoutout.18', 'shoutout', 'If enjoyment get face, e go resemble @{name}. Shout-out o!', '🎤 MC Lightning is hailing @{name} at {place}', 18),
('shoutout.19', 'shoutout', 'Obokhian, @{name}! {place} happy say you show face tonight.', '🎤 Shout-out to @{name} at {place}', 19),
('shoutout.20', 'shoutout', 'Una no hear me? I say make una hail @{name}! Louder!', '🎤 @{name} is the main character at {place}', 20),
('shutdown.3', 'shutdown', '{place} don close for everybody, na only @{name} dey inside tonight!', '🔥 @{name} is shutting down {place}', 3),
('shutdown.4', 'shutdown', 'STOP THE MUSIC! @{name} don shut down {place}! Every drink, every table, na on am!', '🔥 @{name} bought out {place}. Drinks on am!', 4),
('shutdown.5', 'shutdown', 'Odogwu of odogwus! @{name} just buy the whole {place}. Nobody go pay for anything!', '👑 @{name} just shut down {place}', 5),
('shutdown.6', 'shutdown', 'Benin City, history don happen! @{name} shut down {place}. Tell your children!', '🔥 {place} is closed for @{name} tonight', 6),
('shutdown.7', 'shutdown', 'Lock the door, nobody dey go home! @{name} don take over {place}!', '🔥 Odogwu alert: @{name} shut down {place}', 7),
('shutdown.8', 'shutdown', 'E don happen! @{name} don shut down the club. Waiters, carry drinks go every table!', '🔥 @{name} is shutting down {place}', 8),
('shutdown.9', 'shutdown', 'Who get money pass am for this club? NOBODY! @{name} don shut down {place}!', '🔥 @{name} bought out {place}. Drinks on am!', 9),
('shutdown.10', 'shutdown', 'DJ Ekpen, play the biggest song for @{name}! {place} na im own tonight!', '👑 @{name} just shut down {place}', 10),
('shutdown.11', 'shutdown', 'Make una stand up! The king of the night @{name} don shut down {place}!', '🔥 {place} is closed for @{name} tonight', 11),
('shutdown.12', 'shutdown', 'Omo, this one pass level! @{name} don close {place}. Round on the house, na @{name} pay!', '🔥 Odogwu alert: @{name} shut down {place}', 12),
('shutdown.13', 'shutdown', 'Edo no dey carry last! @{name} don shut down {place} like say na small thing!', '🔥 @{name} is shutting down {place}', 13),
('shutdown.14', 'shutdown', 'Light everything! Sparklers, fireworks, everything! @{name} don shut down {place}!', '🔥 @{name} bought out {place}. Drinks on am!', 14),
('shutdown.15', 'shutdown', 'This na the moment! @{name} don buy out {place}. Drinks for everybody till morning!', '👑 @{name} just shut down {place}', 15),
('shutdown.16', 'shutdown', 'From Ring Road reach Airport Road, everybody don hear: @{name} shut down {place}!', '🔥 {place} is closed for @{name} tonight', 16),
('shutdown.17', 'shutdown', 'Uyi! The whole club dey hail @{name}. {place} don shut down tonight!', '🔥 Odogwu alert: @{name} shut down {place}', 17),
('shutdown.18', 'shutdown', 'No more VIP, no more regular. Everybody na @{name} guest now! {place}, shout!', '🔥 @{name} is shutting down {place}', 18),
('shutdown.19', 'shutdown', '{amount} don talk! @{name} don shut down {place}. Na legend we dey look!', '🔥 @{name} bought out {place}. Drinks on am!', 19),
('shutdown.20', 'shutdown', 'Tonight go enter history book: @{name} shut down {place}! Make una hail!', '👑 @{name} just shut down {place}', 20)

on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 4. The announcer: random, no repeats per place until the pool is used up
-- ---------------------------------------------------------------------
create or replace function public.bl_hype_announce(p_user uuid, p_loc text, p_kind text, p_amount bigint, p_qty int, p_force boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  l        locations;
  v_name   text;
  t        hype_templates;
  v_last   text;
  v_place  text;
  v_text   text;
  v_ticker text;
  v_global boolean := false;
  v_row    place_announcements;
begin
  if p_kind is null or not coalesce(bl_cfg_bool('hype.enabled'), false) then return null; end if;
  select * into l from locations where id = p_loc;
  if not found or l.scene <> 'club' then return null; end if;
  -- per-player cooldown (Shut down the club always announces in the club)
  if not p_force and exists (select 1 from place_announcements
                              where user_id = p_user and created_at > now() - make_interval(secs => greatest(0, bl_cfg('hype.cooldown_s')))) then
    return null;
  end if;
  -- a line this place hasn't heard in this cycle
  select h.* into t from hype_templates h
   where h.kind = p_kind and h.active
     and not exists (select 1 from hype_template_recent r where r.location_id = l.id and r.template_id = h.id)
   order by random() limit 1;
  if not found then
    -- pool used up: new cycle, but not the line we just heard
    select r.template_id into v_last from hype_template_recent r
     where r.location_id = l.id and r.kind = p_kind order by r.used_at desc limit 1;
    delete from hype_template_recent where location_id = l.id and kind = p_kind;
    select h.* into t from hype_templates h
     where h.kind = p_kind and h.active and h.id is distinct from v_last order by random() limit 1;
    if not found then
      select h.* into t from hype_templates h where h.kind = p_kind and h.active order by random() limit 1;
    end if;
    if not found then return null; end if;
  end if;
  insert into hype_template_recent (location_id, kind, template_id, used_at)
  values (l.id, p_kind, t.id, clock_timestamp())
  on conflict (location_id, template_id) do update set used_at = excluded.used_at, kind = excluded.kind;
  select username into v_name from profiles where id = p_user;
  v_place := regexp_replace(l.name, '\s*\(.*\)\s*$', '');
  v_text := t.line;
  v_ticker := nullif(t.ticker, '');
  v_text := replace(replace(replace(replace(replace(v_text, '{name}', v_name), '{place}', v_place), '{count}', p_qty::text),
              '{bottles}', p_qty || case when p_qty = 1 then ' bottle' else ' bottles' end), '{amount}', bl_naira(p_amount));
  if p_amount >= bl_cfg('hype.global_min') and v_ticker is not null
     and not exists (select 1 from place_announcements
                      where global and created_at > now() - make_interval(secs => greatest(0, bl_cfg('hype.global_cooldown_s')))) then
    v_global := true;
    v_ticker := replace(replace(replace(replace(replace(v_ticker, '{name}', v_name), '{place}', v_place), '{count}', p_qty::text),
                  '{bottles}', p_qty || case when p_qty = 1 then ' bottle' else ' bottles' end), '{amount}', bl_naira(p_amount));
  else
    v_ticker := null;
  end if;
  insert into place_announcements (location_id, user_id, username, kind, amount, qty, text, ticker, global, place)
  values (l.id, p_user, v_name, p_kind, p_amount, greatest(1, p_qty), left(v_text, 400), left(v_ticker, 200), v_global, v_place)
  returning * into v_row;
  -- now and then, clean up old rows
  if random() < 0.05 then
    delete from place_announcements where created_at < now() - make_interval(hours => greatest(1, bl_cfg('hype.retention_hours'))::int);
  end if;
  return to_jsonb(v_row);
end $$;
revoke execute on function public.bl_hype_announce(uuid, text, text, bigint, int, boolean) from public, anon, authenticated;
