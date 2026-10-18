-- R8 House upgrades: expand the home you live in instead of buying a new one. docs/HOUSE_UPGRADES.md
--  * house_upgrades (admin table, Content -> House upgrades): per home type, a list of upgrades: extension rooms, boys' quarters,
--    garage / +car space, generator house, solar, borehole, compound wall + gate, finish levels (paint, POP + tiles, premium)
--    and "upgrade to the next tier in place". Each has price, build minutes (0 = instant), a requirement and an effect jsonb.
--  * player_house_upgrades: what a player bought. Building takes real minutes ("builders working"); when the timer ends the
--    upgrade is settled LAZILY on the next read (no cron): garage / car space / tier change run then, bonuses apply.
--  * Every home is rented in this game, so the tenant pays for the works plus a landlord's consent fee (house.upgrade_landlord_fee_pct);
--    only your own current home (not the UNIBEN hostel, not a house you are visiting, no rent owed).
--  * Moving out gives back house.upgrade_resale_pct of what you paid (100% of unfinished builds): the old home is released for good.
--  * Server-side furniture check (bl_furniture_check) sees the extension rooms and yard buildings (bl_home_ext).
-- Idempotent and safe on a non-empty DB: tables `if not exists`, seeds `on conflict do nothing` (admin edits survive), functions
-- `create or replace`, live functions patched ONLY through a guarded replace on pg_get_functiondef (raises when the marker is
-- missing, skips when already applied; create or replace keeps the grants). Private bl_* helpers are revoked from anon/authenticated.

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
('house.upgrades_enabled', 'true', 'rent', 'House upgrades on',
 'R8 (docs/HOUSE_UPGRADES.md): players can extend and upgrade the home they live in from the phone''s Houses app. Off = the list shows but buying is refused. Prices and times: Content -> House upgrades.', 'bool', null, null),
('house.upgrade_resale_pct', '50', 'rent', 'Upgrades: % given back when you move',
 'R8: moving house gives back this % of what the player paid for upgrades (a build still in progress is refunded in full). The old home is released for good.', 'percent', 0, 100),
('house.upgrade_landlord_fee_pct', '10', 'rent', 'Upgrades: landlord consent fee %',
 'R8: every home is rented, so the landlord must agree to works. Fee = this % of the upgrade price, added on top (not given back when moving).', 'percent', 0, 100),
('house.upgrade_max_builds', '1', 'rent', 'Upgrades: builds at the same time',
 'R8: how many upgrades the builders can work on together (1 = one at a time).', 'number', 1, 10),
('house.upgrade_time_pct', '100', 'rent', 'Upgrades: build time %',
 'R8: scales every upgrade''s build minutes. 100 = as listed, 50 = twice as fast, 0 = all upgrades finish at once (handy for testing).', 'percent', 0, 1000),
('house.upgrade_bonus_cap', '12', 'rent', 'Upgrades: biggest bonus on one need',
 'R8: the upgrade bonuses (generator, solar, borehole, security, finish ...) added to one home activity never go above this for one need.', 'number', 1, 100)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------------------------
create table if not exists public.house_upgrades (
  id           text primary key,
  name         text not null,
  emoji        text not null default '🏗️',
  category     text not null default 'extension'
               check (category in ('extension', 'quarters', 'garage', 'power', 'water', 'security', 'finish', 'tier')),
  description  text not null default '',
  preview      text not null default '',
  -- housing kinds (bl_housing_kind) that can buy it: face_me, self_contain, mini_flat, duplex (hostel rooms are never upgradable)
  tiers        text[] not null default '{}',
  price        bigint not null default 0 check (price >= 0),
  tier_prices  jsonb not null default '{}'::jsonb,   -- {"duplex": 9000000} overrides price for one home type
  build_minutes int not null default 60 check (build_minutes >= 0),
  requires     text references public.house_upgrades(id) on update cascade on delete set null,
  -- {"geom": {layout: {room|struct}}, "bonus": {activity: {need: n}}, "finish": 1..3, "security": 1..2,
  --  "garage_type": id, "garage_space": n, "requires_garage": bool, "requires_no_garage": bool, "to_home": start_home id}
  effect       jsonb not null default '{}'::jsonb,
  sort         int not null default 100,
  active       boolean not null default true
);

create table if not exists public.player_house_upgrades (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  upgrade_id  text not null references public.house_upgrades(id) on update cascade on delete restrict,
  start_home  text,
  price_paid  bigint not null default 0,
  fee_paid    bigint not null default 0,
  bought_at   timestamptz not null default now(),
  ready_at    timestamptz not null default now(),
  done_at     timestamptz,
  notified    boolean not null default false,
  source      text not null default 'buy' check (source in ('buy', 'admin')),
  granted_by  uuid,
  primary key (user_id, upgrade_id)
);
create index if not exists player_house_upgrades_building_idx on public.player_house_upgrades (user_id) where done_at is null;

alter table public.player_garages add column if not exists extra_capacity int not null default 0 check (extra_capacity between 0 and 4);

alter table public.house_upgrades enable row level security;
alter table public.player_house_upgrades enable row level security;
revoke all on public.house_upgrades, public.player_house_upgrades from anon, authenticated;
grant select on public.house_upgrades, public.player_house_upgrades to authenticated;
drop policy if exists house_upgrades_read on public.house_upgrades;
create policy house_upgrades_read on public.house_upgrades for select to authenticated using (true);
drop policy if exists player_house_upgrades_own on public.player_house_upgrades;
create policy player_house_upgrades_own on public.player_house_upgrades for select to authenticated
  using (user_id = (select auth.uid()));

insert into public.house_upgrades (id, name, emoji, category, description, preview, tiers, price, tier_prices, build_minutes, requires, effect, sort) values
('ext_bedroom', 'Extra bedroom', '🛏️', 'extension', 'Block a new bedroom onto the back of your home, with its own door to the main house.', 'A new room joins the south side of your home and the floor plan grows. Furniture stays where it is: use Buy and Arrange to fill the new room.', '{face_me,self_contain,mini_flat}'::text[], 2400000, '{"face_me": 1800000, "self_contain": 2600000, "mini_flat": 3800000}'::jsonb, 120, null, '{"bonus":{"sleep":{"stress":-2},"nap":{"stress":-1}},"geom":{"face_me":{"room":{"rect":[0,3.8,4.2,6.6],"door":[2.6,3.4]}},"self_contain":{"room":{"rect":[0,4.8,6,7.6],"door":[3.9,4.9]}},"flat":{"room":{"rect":[0,7.2,6,10],"door":[3,4]}}}}'::jsonb, 10),
('ext_guest_wing', 'Guest wing', '🏡', 'extension', 'A proper guest wing along the back of the duplex: parlour side door, own windows and a wide room to furnish.', 'A big new wing joins the south side of the duplex and the floor plan grows. Furniture stays where it is.', '{duplex}'::text[], 9000000, '{}'::jsonb, 240, null, '{"bonus":{"sleep":{"stress":-2},"nap":{"stress":-1}},"geom":{"duplex":{"room":{"rect":[7.4,10,14.4,13.4],"door":[8,9]}}}}'::jsonb, 20),
('boys_quarters', 'Boys quarters', '🏚️', 'quarters', 'A block of boys quarters at the back of the compound, the GRA way. Somebody to run the small errands.', 'A small block building with its own door stands in the compound. It takes yard space, so plan where the cars and furniture go.', '{duplex}'::text[], 5500000, '{}'::jsonb, 150, null, '{"bonus":{"relax_sofa":{"stress":-3},"sit_rest":{"stress":-2}},"geom":{"duplex":{"struct":{"kind":"bq","rect":[15,7,18.2,9.4]}}}}'::jsonb, 30),
('garage_carport', 'Carport', '🚗', 'garage', 'Steel posts, long-span roof and a concrete pad for one car. Added to your home.', 'A carport appears at the gate and your car parks under it.', '{face_me,self_contain,mini_flat,duplex}'::text[], 1500000, '{}'::jsonb, 60, null, '{"garage_type":"carport","requires_no_garage":true}'::jsonb, 40),
('garage_standard', 'Standard garage', '🏠', 'garage', 'Single-car blockwork garage with a roller door. Added to your home.', 'A blockwork garage appears at the gate and your car parks inside.', '{self_contain,mini_flat,duplex}'::text[], 5000000, '{}'::jsonb, 150, null, '{"garage_type":"garage_standard","requires_no_garage":true}'::jsonb, 41),
('garage_luxury', 'Luxury double garage', '🏎️', 'garage', 'Two-car garage with a tiled floor and an automatic door. Added to your home.', 'A two-car garage appears at the gate.', '{duplex}'::text[], 12000000, '{}'::jsonb, 240, null, '{"garage_type":"garage_luxury","requires_no_garage":true}'::jsonb, 42),
('garage_space_1', 'Extra car space', '🅿️', 'garage', 'Widen your garage by one more car space.', 'The garage grows by one bay. One more car can park inside.', '{face_me,self_contain,mini_flat,duplex}'::text[], 3000000, '{}'::jsonb, 120, null, '{"garage_space":1,"requires_garage":true}'::jsonb, 43),
('garage_space_2', 'Another car space', '🅿️', 'garage', 'One more bay, for the oga with many cars.', 'The garage grows by one more bay.', '{face_me,self_contain,mini_flat,duplex}'::text[], 4500000, '{}'::jsonb, 150, 'garage_space_1', '{"garage_space":1,"requires_garage":true}'::jsonb, 44),
('gen_house', 'Generator house', '⚡', 'power', 'A soundproof block house for the generator. When NEPA take light, you still dey enjoy.', 'A small generator house stands in the compound. Home comfort goes up: better sleep, TV time and rest.', '{face_me,self_contain,mini_flat,duplex}'::text[], 650000, '{"face_me": 450000}'::jsonb, 45, null, '{"bonus":{"sleep":{"energy":2},"nap":{"energy":1},"watch_tv":{"fun":2}},"geom":{"face_me":{"struct":{"kind":"genhouse","rect":[7.15,0.4,8.45,1.4]}},"self_contain":{"struct":{"kind":"genhouse","rect":[7.4,0.4,8.7,1.4]}},"flat":{"struct":{"kind":"genhouse","rect":[11.15,0.4,12.45,1.4]}},"duplex":{"struct":{"kind":"genhouse","rect":[17.4,-0.1,18.7,0.9]}}}}'::jsonb, 50),
('solar_system', 'Solar and inverter', '☀️', 'power', 'Solar panels, batteries and an inverter. Quiet power, no fuel queue.', 'A solar rack and inverter stand in the compound. Home comfort goes up a lot: sleep, TV and the sofa.', '{self_contain,mini_flat,duplex}'::text[], 3200000, '{"self_contain": 2200000, "duplex": 5500000}'::jsonb, 120, null, '{"bonus":{"sleep":{"energy":3},"nap":{"energy":2},"watch_tv":{"fun":3},"relax_sofa":{"fun":1}},"geom":{"face_me":{"struct":{"kind":"solar","rect":[7.15,3.9,9.15,5]}},"self_contain":{"struct":{"kind":"solar","rect":[7.4,4.65,9.4,5.75]}},"flat":{"struct":{"kind":"solar","rect":[9.9,7.15,11.9,8.25]}},"duplex":{"struct":{"kind":"solar","rect":[18.65,8.4,20.65,9.5]}}}}'::jsonb, 51),
('borehole', 'Borehole and tank', '💧', 'water', 'Your own borehole, pump and overhead tank. Clean water all day.', 'A pump house and an overhead tank stand in the compound. Bathing leaves you cleaner.', '{face_me,self_contain,mini_flat,duplex}'::text[], 1100000, '{"face_me": 900000}'::jsonb, 90, null, '{"bonus":{"bathe":{"hygiene":6},"use_toilet":{"hygiene":2}},"geom":{"face_me":{"struct":{"kind":"borehole","rect":[7.9,1.9,9.5,3.1]}},"self_contain":{"struct":{"kind":"borehole","rect":[7.9,2.15,9.5,3.35]}},"flat":{"struct":{"kind":"borehole","rect":[9.9,2.15,11.5,3.35]}},"duplex":{"struct":{"kind":"borehole","rect":[15.65,5.4,17.25,6.6]}}}}'::jsonb, 60),
('fence_wall', 'Compound wall', '🧱', 'security', 'A block fence round the whole compound. Neighbours stop peeping.', 'A compound wall goes up round the lot, with a gap for the path.', '{face_me,self_contain,mini_flat,duplex}'::text[], 800000, '{"face_me": 500000}'::jsonb, 60, null, '{"security":1,"bonus":{"sleep":{"stress":-1}}}'::jsonb, 70),
('gate_security', 'Gate, CCTV and gateman', '🔒', 'security', 'Sliding steel gate, CCTV and a gatemans light. Sleep with both eyes closed.', 'Gate pillars, a sliding gate and a CCTV mast appear at the entrance. You sleep calmer.', '{face_me,self_contain,mini_flat,duplex}'::text[], 2200000, '{}'::jsonb, 90, 'fence_wall', '{"security":2,"bonus":{"sleep":{"stress":-3},"nap":{"stress":-1}}}'::jsonb, 71),
('paint_fresh', 'Fresh paint', '🎨', 'finish', 'Fresh emulsion on every wall. The room brightens up.', 'Walls change to a fresh, lighter paint.', '{face_me,self_contain,mini_flat,duplex}'::text[], 1200000, '{"face_me": 150000, "self_contain": 250000, "mini_flat": 450000}'::jsonb, 30, null, '{"finish":1,"bonus":{"relax_sofa":{"fun":1}}}'::jsonb, 80),
('finish_pop', 'POP ceiling and tiles', '🪞', 'finish', 'Plaster-of-Paris ceiling with a cornice, and porcelain tiles on the floor.', 'Floors become porcelain tiles, the ceiling gets a POP cornice and the house takes the finished look.', '{face_me,self_contain,mini_flat,duplex}'::text[], 3500000, '{"face_me": 450000, "self_contain": 700000, "mini_flat": 1400000}'::jsonb, 90, 'paint_fresh', '{"finish":2,"bonus":{"relax_sofa":{"fun":1},"sleep":{"stress":-1}}}'::jsonb, 81),
('finish_premium', 'Premium finish', '💎', 'finish', 'Marble-look floors, gold skirting and the best paint. Na big man house.', 'Marble-look floors, bright walls and gold skirting.', '{self_contain,mini_flat,duplex}'::text[], 8000000, '{"self_contain": 1500000, "mini_flat": 3000000}'::jsonb, 150, 'finish_pop', '{"finish":3,"bonus":{"relax_sofa":{"fun":2},"sleep":{"stress":-1}}}'::jsonb, 82),
('tier_face_to_selfcon', 'Upgrade to a self-contain', '🏗️', 'tier', 'Turn your face-me-I-face-you into a self-contain at the same address: your own kitchenette and bathroom. Furniture and garage stay.', 'Same address, bigger plan: you get a self-contain. Everything you own is placed again, and the garage stays.', '{face_me}'::text[], 3500000, '{}'::jsonb, 240, null, '{"to_home":"uselu_self_contain"}'::jsonb, 90),
('tier_selfcon_to_flat', 'Upgrade to a mini-flat', '🏗️', 'tier', 'Turn your self-contain into a mini-flat at the same address: bedroom, kitchen, bathroom and parlour. Furniture and garage stay.', 'Same address, much bigger plan: you get a mini-flat with separate rooms. Everything you own is placed again.', '{self_contain}'::text[], 8000000, '{}'::jsonb, 360, null, '{"to_home":"mission_rd_mini_flat"}'::jsonb, 91),
('tier_flat_to_duplex', 'Upgrade to a duplex', '🏗️', 'tier', 'Turn your mini-flat into a GRA-style duplex at the same address. Furniture and garage stay.', 'Same address, the biggest plan: you get a duplex with a guest bedroom and a staircase.', '{mini_flat}'::text[], 22000000, '{}'::jsonb, 720, null, '{"to_home":"gra_duplex"}'::jsonb, 92)
on conflict (id) do nothing;

-- the geometry (extension rooms, yard buildings) is code: re-seed it on every run so the server's furniture check always
-- matches the client (scripts/home-upgrade-check.mjs --sql prints this); every other column stays as the admin set it
update public.house_upgrades u set effect = jsonb_set(u.effect, '{geom}', g.geom, true)
  from (values
    ('ext_bedroom', '{"face_me":{"room":{"rect":[0,3.8,4.2,6.6],"door":[2.6,3.4]}},"self_contain":{"room":{"rect":[0,4.8,6,7.6],"door":[3.9,4.9]}},"flat":{"room":{"rect":[0,7.2,6,10],"door":[3,4]}}}'::jsonb),
    ('ext_guest_wing', '{"duplex":{"room":{"rect":[7.4,10,14.4,13.4],"door":[8,9]}}}'::jsonb),
    ('boys_quarters', '{"duplex":{"struct":{"kind":"bq","rect":[15,7,18.2,9.4]}}}'::jsonb),
    ('gen_house', '{"face_me":{"struct":{"kind":"genhouse","rect":[7.15,0.4,8.45,1.4]}},"self_contain":{"struct":{"kind":"genhouse","rect":[7.4,0.4,8.7,1.4]}},"flat":{"struct":{"kind":"genhouse","rect":[11.15,0.4,12.45,1.4]}},"duplex":{"struct":{"kind":"genhouse","rect":[17.4,-0.1,18.7,0.9]}}}'::jsonb),
    ('solar_system', '{"face_me":{"struct":{"kind":"solar","rect":[7.15,3.9,9.15,5]}},"self_contain":{"struct":{"kind":"solar","rect":[7.4,4.65,9.4,5.75]}},"flat":{"struct":{"kind":"solar","rect":[9.9,7.15,11.9,8.25]}},"duplex":{"struct":{"kind":"solar","rect":[18.65,8.4,20.65,9.5]}}}'::jsonb),
    ('borehole', '{"face_me":{"struct":{"kind":"borehole","rect":[7.9,1.9,9.5,3.1]}},"self_contain":{"struct":{"kind":"borehole","rect":[7.9,2.15,9.5,3.35]}},"flat":{"struct":{"kind":"borehole","rect":[9.9,2.15,11.5,3.35]}},"duplex":{"struct":{"kind":"borehole","rect":[15.65,5.4,17.25,6.6]}}}'::jsonb)
  ) as g(id, geom) where u.id = g.id;

-- ---------------------------------------------------------------------------------------------
-- 3. Private helpers
-- ---------------------------------------------------------------------------------------------
-- price of an upgrade for a home type
create or replace function public.bl_house_upgrade_price(u public.house_upgrades, p_kind text) returns bigint
language sql immutable set search_path = public as $$
  select coalesce(nullif(u.tier_prices ->> p_kind, '')::bigint, u.price)
$$;

-- build minutes after the admin dial (house.upgrade_time_pct)
create or replace function public.bl_house_upgrade_minutes(u public.house_upgrades) returns int
language sql stable set search_path = public as $$
  select greatest(0, round(u.build_minutes * coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_time_pct'), 100) / 100.0))::int
$$;

-- The extension rooms and yard buildings of p_uid's FINISHED upgrades for the layout they live in:
-- {"rooms": [{"rect": [x0,z0,x1,z1], "door": [a,b]}], "structs": [{"kind", "rect"}]}
create or replace function public.bl_home_ext(p_uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with me as (select bl_home_layout_id(housing_id) as lay from profiles where id = p_uid)
  select jsonb_build_object(
    'rooms', coalesce(jsonb_agg(u.effect -> 'geom' -> me.lay -> 'room') filter (where u.effect -> 'geom' -> me.lay ? 'room'), '[]'::jsonb),
    'structs', coalesce(jsonb_agg(u.effect -> 'geom' -> me.lay -> 'struct') filter (where u.effect -> 'geom' -> me.lay ? 'struct'), '[]'::jsonb))
    from me
    join player_house_upgrades p on p.user_id = p_uid and p.done_at is not null
    join house_upgrades u on u.id = p.upgrade_id
$$;

-- Where a footprint stands once extensions exist: {in: inside the house or an extension room, yard: in the (grown) yard and
-- clear of the house and the rooms}. With no upgrades this is exactly the plain layout rule (same maths as bl_furniture_check).
create or replace function public.bl_home_ext_flags(p_uid uuid, p_layout text, x0 numeric, z0 numeric, x1 numeric, z1 numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hl home_layouts;
  e constant numeric := 0.02;
  t constant numeric := 0.000001;
  v_ext jsonb := bl_home_ext(p_uid);
  rm jsonb; r numeric[];
  lx0 numeric; lz0 numeric; lx1 numeric; lz1 numeric;
  v_in boolean := false; v_room boolean := false; v_yard boolean;
begin
  select * into hl from home_layouts where id = p_layout;
  lx0 := (hl.lot->>0)::numeric; lz0 := (hl.lot->>1)::numeric; lx1 := (hl.lot->>2)::numeric; lz1 := (hl.lot->>3)::numeric;
  for rm in select * from jsonb_array_elements(v_ext->'rooms') loop
    r := array[(rm->'rect'->>0)::numeric, (rm->'rect'->>1)::numeric, (rm->'rect'->>2)::numeric, (rm->'rect'->>3)::numeric];
    if x0 >= r[1] - t and z0 >= r[2] - t and x1 <= r[3] + t and z1 <= r[4] + t then v_in := true; end if;
    if least(x1, r[3]) - greatest(x0, r[1]) > e and least(z1, r[4]) - greatest(z0, r[2]) > e then v_room := true; end if;
    lx0 := least(lx0, r[1]); lz0 := least(lz0, r[2]); lx1 := greatest(lx1, r[3] + 0.6); lz1 := greatest(lz1, r[4] + 0.6);
  end loop;
  for rm in select * from jsonb_array_elements(v_ext->'structs') loop
    lx1 := greatest(lx1, (rm->'rect'->>2)::numeric + 0.6); lz1 := greatest(lz1, (rm->'rect'->>3)::numeric + 0.6);
  end loop;
  v_yard := x0 >= lx0 - t and z0 >= lz0 - t and x1 <= lx1 + t and z1 <= lz1 + t
        and not (least(x1, hl.w) - greatest(x0, 0) > e and least(z1, hl.d) - greatest(z0, 0) > e)
        and not v_room;
  return jsonb_build_object('in', v_in, 'yard', v_yard);
end $$;

-- The doorway clear zones, the wall between the house and a room, and the yard buildings: why a SOLID piece
-- can't stand there ('hint|message'), null = fine.
create or replace function public.bl_home_ext_block(p_uid uuid, p_layout text, x0 numeric, z0 numeric, x1 numeric, z1 numeric)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  e constant numeric := 0.02;
  v_ext jsonb := bl_home_ext(p_uid);
  rm jsonb;
  rx0 numeric; rz0 numeric; rx1 numeric; da numeric; db numeric;
begin
  for rm in select * from jsonb_array_elements(v_ext->'rooms') loop
    rx0 := (rm->'rect'->>0)::numeric; rz0 := (rm->'rect'->>1)::numeric; rx1 := (rm->'rect'->>2)::numeric;
    da := (rm->'door'->>0)::numeric; db := (rm->'door'->>1)::numeric;
    if least(x1, db) - greatest(x0, da) > e and least(z1, rz0 + 0.8) - greatest(z0, rz0 - 0.8) > e then
      return 'blocks_door|You are blocking the door.';
    end if;
  end loop;
  for rm in select * from jsonb_array_elements(v_ext->'rooms') loop
    rx0 := (rm->'rect'->>0)::numeric; rz0 := (rm->'rect'->>1)::numeric; rx1 := (rm->'rect'->>2)::numeric;
    da := (rm->'door'->>0)::numeric; db := (rm->'door'->>1)::numeric;
    if da > rx0 and least(x1, da) - greatest(x0, rx0) > e and least(z1, rz0 + 0.06) - greatest(z0, rz0 - 0.06) > e then
      return 'overlap|Something is already there (wall or fixture).';
    end if;
    if db < rx1 and least(x1, rx1) - greatest(x0, db) > e and least(z1, rz0 + 0.06) - greatest(z0, rz0 - 0.06) > e then
      return 'overlap|Something is already there (wall or fixture).';
    end if;
  end loop;
  for rm in select * from jsonb_array_elements(v_ext->'structs') loop
    if least(x1, (rm->'rect'->>2)::numeric) - greatest(x0, (rm->'rect'->>0)::numeric) > e
       and least(z1, (rm->'rect'->>3)::numeric) - greatest(z0, (rm->'rect'->>1)::numeric) > e then
      return 'overlap|Something is already there (wall or fixture).';
    end if;
  end loop;
  return null;
end $$;

-- The bonus the finished upgrades add to one home activity: {need: n}. Settles first (lazy, no cron).
create or replace function public.bl_house_bonus(p_uid uuid, p_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cap numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_bonus_cap'), 12);
  v jsonb;
begin
  perform bl_house_upgrades_settle(p_uid);
  select coalesce(jsonb_object_agg(k, case when s >= 0 then least(s, v_cap) else greatest(s, -v_cap) end), '{}'::jsonb) into v
    from (select kv.key as k, sum(kv.value::numeric) as s
            from player_house_upgrades p
            join house_upgrades u on u.id = p.upgrade_id
            cross join lateral jsonb_each_text(coalesce(u.effect -> 'bonus' -> p_activity, '{}'::jsonb)) kv
           where p.user_id = p_uid and p.done_at is not null
           group by kv.key) x;
  return v;
end $$;

-- A garage the player has right now: for this home only (same rule as garage_home)
create or replace function public.bl_house_garage(p_me profiles) returns public.player_garages
language sql stable security definer set search_path = public as $$
  select g.* from player_garages g
   where g.user_id = p_me.id and g.housing_id is not distinct from p_me.housing_id
     and g.home_location_id is not distinct from p_me.home_location_id
$$;

-- Why p_me can't buy u right now (null = fine). Ownership: your own current home only.
create or replace function public.bl_house_upgrade_lock(p_me profiles, u public.house_upgrades) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_kind text := bl_housing_kind(p_me.housing_id);
  g public.player_garages;
  gt public.garage_types;
  r  public.house_upgrades;
  h  public.start_homes;
begin
  if not (v_kind = any (u.tiers)) then return 'Not for a ' || replace(v_kind, '_', ' ') || '.'; end if;
  if u.requires is not null then
    if not exists (select 1 from player_house_upgrades where user_id = p_me.id and upgrade_id = u.requires and done_at is not null) then
      select * into r from house_upgrades where id = u.requires;
      return 'Needs ' || coalesce(r.name, 'an earlier upgrade') || ' first.';
    end if;
  end if;
  g := bl_house_garage(p_me);
  if coalesce((u.effect->>'requires_no_garage')::boolean, false) and g.user_id is not null then
    return 'You already have a garage here.';
  end if;
  if coalesce((u.effect->>'requires_garage')::boolean, false) and g.user_id is null then
    return 'Build a garage first.';
  end if;
  if u.effect ? 'garage_space' and g.user_id is not null then
    select * into gt from garage_types where id = g.garage_type;
    if gt.capacity + g.extra_capacity >= 4 then return 'Your garage is already full size.'; end if;
  end if;
  if u.effect ? 'garage_type' and not bl_cfg_bool('garage.enabled') then return 'Garages are switched off right now.'; end if;
  if u.effect ? 'to_home' then
    select * into h from start_homes where id = u.effect->>'to_home' and active;
    if not found then return 'That home is not available.'; end if;
    if exists (select 1 from player_released_homes where user_id = p_me.id and start_home = h.id) then
      return 'You moved out of ' || h.name || ' already. You can''t go back.';
    end if;
  end if;
  return null;
end $$;

-- Extra move-in style fee for an in-place tier upgrade: the rent difference x house.move_in_weeks
create or replace function public.bl_house_upgrade_rent_fee(p_me profiles, u public.house_upgrades) returns bigint
language sql stable security definer set search_path = public as $$
  select case when u.effect ? 'to_home'
    then coalesce((select greatest(0, h.weekly_rent - p_me.weekly_rent) from start_homes h where h.id = u.effect->>'to_home'), 0)::numeric
         * greatest(0, coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.move_in_weeks'), 4))
    else 0 end::bigint
$$;

-- What the player gets back for their upgrades if they move now (50% of paid, unfinished builds in full)
create or replace function public.bl_house_upgrades_value(p_uid uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when done_at is null then price_paid
                           else floor(price_paid * greatest(0, least(100, coalesce((select (value #>> '{}')::numeric from game_config
                                  where key = 'house.upgrade_resale_pct'), 50))) / 100.0) end), 0)::bigint
    from player_house_upgrades where user_id = p_uid
$$;

-- Moving out: pay the sale value into the bank and clear the upgrades (the old home is gone for good). Returns the refund.
create or replace function public.bl_house_upgrades_release(p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint; n int;
begin
  select count(*) into n from player_house_upgrades where user_id = p_uid;
  if n = 0 then return 0; end if;
  v := bl_house_upgrades_value(p_uid);
  if v > 0 then
    perform bl_add_money(p_uid, 'bank', v, 'house_upgrade', jsonb_build_object('refund', true, 'count', n));
  end if;
  delete from player_house_upgrades where user_id = p_uid;
  return v;
end $$;

-- In-place tier upgrade: the player's address stays, the home becomes the target tier. Furniture is placed again
-- (default slot, else the nearest free spot, else My items), the garage stays (re-keyed), the new tier's built-ins are given once.
create or replace function public.bl_house_apply_tier(p_uid uuid, p_to text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me     profiles;
  h        start_homes;
  v_loc    locations;
  v_old_layout text; v_new_layout text;
  v_old_w numeric; v_old_d numeric;
  hl       home_layouts;
  v_slots  text[] := '{}';
  r        record;
  v_ok     boolean;
begin
  select * into v_me from profiles where id = p_uid for update;
  select * into h from start_homes where id = p_to;
  if not found or v_me.id is null then return; end if;
  v_old_layout := bl_furniture_materialize(p_uid);
  select w, d into v_old_w, v_old_d from home_layouts where id = v_old_layout;
  create temp table if not exists bl_r8_move (key text, slot text, sort int, copy int, rx numeric, rz numeric) on commit drop;
  truncate bl_r8_move;
  insert into bl_r8_move
  select hf.furniture_key, coalesce(pf.slot, f.slot), f.sort, bl_furniture_copy_of(hf.furniture_key),
         hf.x / nullif(v_old_w, 0), hf.z / nullif(v_old_d, 0)
    from player_house_furniture hf
    join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
    join furniture f on f.id = pf.furniture_id
   where hf.owner_id = p_uid and not hf.stored;

  if v_me.start_home is not null and v_me.start_home <> h.id then
    insert into player_released_homes (user_id, start_home, housing_id, released_at)
    values (p_uid, v_me.start_home, v_me.housing_id, bl_now()) on conflict (user_id, start_home) do nothing;
  end if;
  -- same address: the private home keeps its map spot; only the interior scene (and its home actions) become the new tier's
  v_loc := bl_location(h.location_id);
  update locations set scene = v_loc.scene, actions = v_loc.actions
   where id = v_me.home_location_id and private_home_owner_id = p_uid;
  update profiles set start_home = h.id, housing_id = h.housing_id, weekly_rent = h.weekly_rent where id = p_uid;
  update player_garages set housing_id = h.housing_id where user_id = p_uid and housing_id is not distinct from v_me.housing_id;

  v_new_layout := bl_home_layout_id(h.housing_id);
  select * into hl from home_layouts where id = v_new_layout;
  delete from player_house_furniture where owner_id = p_uid;
  insert into player_house_furniture (owner_id, furniture_key, x, z, rotation, stored, layout, updated_at)
  select p_uid, case when n = 1 then 'own_' || pf.furniture_id else 'own_' || pf.furniture_id || '-' || n end,
         0, 0, 0, true, v_new_layout, bl_now()
    from player_furniture pf join furniture f on f.id = pf.furniture_id
   cross join lateral generate_series(1, pf.qty) n
   where pf.user_id = p_uid and f.active
  on conflict (owner_id, furniture_key) do nothing;
  if hl.id is not null then
    for r in select * from bl_r8_move order by (copy = 1 and hl.slots ? slot) desc, sort, key loop
      v_ok := false;
      if r.copy = 1 and hl.slots ? r.slot and not (r.slot = any (v_slots)) then
        v_ok := bl_furniture_autoplace(p_uid, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                  (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int, true);
        if v_ok then v_slots := v_slots || r.slot; end if;
      end if;
      if not v_ok then
        v_ok := bl_furniture_autoplace(p_uid, v_new_layout, r.key, r.rx * hl.w, r.rz * hl.d, 0, false);
      end if;
    end loop;
    -- a bigger home has more default slots: pieces waiting in My items take a free default slot when valid
    for r in select hf.furniture_key as key, coalesce(pf.slot, f.slot) as slot
               from player_house_furniture hf
               join player_furniture pf on pf.user_id = hf.owner_id and pf.furniture_id = bl_furniture_id_of(hf.furniture_key)
               join furniture f on f.id = pf.furniture_id
              where hf.owner_id = p_uid and hf.stored and bl_furniture_copy_of(hf.furniture_key) = 1
                and hl.slots ? coalesce(pf.slot, f.slot)
              order by f.sort, hf.furniture_key loop
      continue when r.slot = any (v_slots)
        or bl_furniture_check(p_uid, v_new_layout, r.key, (hl.slots->r.slot->>0)::numeric,
                              (hl.slots->r.slot->>1)::numeric, (hl.slots->r.slot->>2)::int) is not null;
      update player_house_furniture
         set x = (hl.slots->r.slot->>0)::numeric, z = (hl.slots->r.slot->>1)::numeric,
             rotation = ((((hl.slots->r.slot->>2)::int) % 4) + 4) % 4, stored = false, updated_at = bl_now()
       where owner_id = p_uid and furniture_key = r.key;
      v_slots := v_slots || r.slot;
    end loop;
  end if;
  perform bl_house_items_grant(p_uid, null);
end $$;

-- The side effects of a finished upgrade (garage, car space, tier change). Bonuses and looks are read live.
create or replace function public.bl_house_upgrade_apply(p_uid uuid, u public.house_upgrades, p_paid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles;
  g    public.player_garages;
  gt   public.garage_types;
  nt   public.garage_types;
begin
  select * into v_me from profiles where id = p_uid;
  if u.effect ? 'garage_type' then
    select * into nt from garage_types where id = u.effect->>'garage_type';
    g := bl_house_garage(v_me);
    if nt.id is not null then
      if g.user_id is null then
        insert into player_garages (user_id, garage_type, housing_id, home_location_id, price_paid, built_at, extra_capacity)
        values (p_uid, nt.id, v_me.housing_id, v_me.home_location_id, p_paid, bl_now(), 0)
        on conflict (user_id) do update set garage_type = excluded.garage_type, housing_id = excluded.housing_id,
          home_location_id = excluded.home_location_id, price_paid = excluded.price_paid, built_at = excluded.built_at, extra_capacity = 0;
      else
        select * into gt from garage_types where id = g.garage_type;
        if nt.capacity > gt.capacity then
          update player_garages set garage_type = nt.id, built_at = bl_now() where user_id = p_uid;
        end if;
      end if;
    end if;
  end if;
  if u.effect ? 'garage_space' then
    g := bl_house_garage(v_me);
    if g.user_id is not null then
      update player_garages set extra_capacity = least(4, extra_capacity + greatest(0, coalesce((u.effect->>'garage_space')::int, 1)))
       where user_id = p_uid;
    end if;
  end if;
  if u.effect ? 'to_home' then
    perform bl_house_apply_tier(p_uid, u.effect->>'to_home');
  end if;
end $$;

-- Lazy settle: every build whose timer has run out becomes finished now and its effects run. Returns how many.
create or replace function public.bl_house_upgrades_settle(p_uid uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; u public.house_upgrades; n int := 0;
begin
  if not exists (select 1 from player_house_upgrades where user_id = p_uid and done_at is null and ready_at <= bl_now()) then
    return 0;
  end if;
  for r in with c as (update player_house_upgrades set done_at = ready_at
                       where user_id = p_uid and done_at is null and ready_at <= bl_now() returning *)
           select * from c order by ready_at, upgrade_id loop
    select * into u from house_upgrades where id = r.upgrade_id;
    perform bl_house_upgrade_apply(p_uid, u, r.price_paid);
    n := n + 1;
  end loop;
  return n;
end $$;

-- compact card of an upgrade for the lists
create or replace function public.bl_house_upgrade_card(u public.house_upgrades, p_kind text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', u.id, 'name', u.name, 'emoji', u.emoji, 'category', u.category,
                            'description', u.description, 'preview', u.preview, 'minutes', bl_house_upgrade_minutes(u),
                            'bonus', coalesce(u.effect -> 'bonus', '{}'::jsonb),
                            'finish', u.effect -> 'finish', 'security', u.effect -> 'security')
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs
-- ---------------------------------------------------------------------------------------------
-- The Upgrade tab: what is built, what the builders are on, what can be bought. Settles finished builds (lazy).
create or replace function public.house_upgrade_state() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_kind  text;
  v_reason text;
  v_fee_pct numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10);
  v_fin   jsonb;
  v_done  jsonb; v_build jsonb; v_avail jsonb;
  v_finish int;
  v_busy  int;
  v_tier_building boolean;
  v_garage public.player_garages;
begin
  perform bl_house_upgrades_settle(v_me.id);
  select * into v_me from profiles where id = v_me.id; -- a finished tier upgrade changed the home
  v_kind := bl_housing_kind(v_me.housing_id);
  v_reason := case
    when not bl_cfg_bool('house.upgrades_enabled') then 'House upgrades are paused right now.'
    when v_kind = 'hostel' then 'Hostel rooms belong to UNIBEN. You can''t renovate them.'
    when v_me.home_visit_host_id is not null then 'Go back to your own home first.'
    when v_me.rent_owed > 0 then 'Settle your ' || bl_naira(v_me.rent_owed) || ' rent first. The landlord won''t approve works while you owe.'
    else null end;
  -- the toast list: finished and not yet announced
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'emoji', u.emoji) order by p.done_at), '[]'::jsonb) into v_fin
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id
   where p.user_id = v_me.id and p.done_at is not null and not p.notified;
  update player_house_upgrades set notified = true where user_id = v_me.id and done_at is not null and not notified;
  select count(*) into v_busy from player_house_upgrades where user_id = v_me.id and done_at is null;
  select exists (select 1 from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id
                  where p.user_id = v_me.id and p.done_at is null and u.effect ? 'to_home') into v_tier_building;
  select coalesce(max((u.effect->>'finish')::int), 0) into v_finish
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id
   where p.user_id = v_me.id and p.done_at is not null;
  select coalesce(jsonb_agg(bl_house_upgrade_card(u, v_kind) || jsonb_build_object('paid', p.price_paid, 'done_at', p.done_at, 'source', p.source)
                            order by p.done_at, u.sort), '[]'::jsonb) into v_done
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id where p.user_id = v_me.id and p.done_at is not null;
  select coalesce(jsonb_agg(bl_house_upgrade_card(u, v_kind) || jsonb_build_object(
            'started_at', p.bought_at, 'ready_at', p.ready_at,
            'progress', round(least(1, greatest(0, extract(epoch from (bl_now() - p.bought_at)) / greatest(1, extract(epoch from (p.ready_at - p.bought_at))))) * 100)::int,
            'seconds_left', greatest(0, ceil(extract(epoch from (p.ready_at - bl_now()))))::int) order by p.ready_at), '[]'::jsonb) into v_build
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id where p.user_id = v_me.id and p.done_at is null;
  v_garage := bl_house_garage(v_me);
  select coalesce(jsonb_agg(
           bl_house_upgrade_card(u, v_kind) || jsonb_build_object(
             'price', bl_house_upgrade_price(u, v_kind),
             'rent_fee', bl_house_upgrade_rent_fee(v_me, u),
             'landlord_fee', round(bl_house_upgrade_price(u, v_kind) * v_fee_pct / 100.0)::bigint,
             'total', bl_house_upgrade_price(u, v_kind) + bl_house_upgrade_rent_fee(v_me, u) + round(bl_house_upgrade_price(u, v_kind) * v_fee_pct / 100.0)::bigint,
             'requires', u.requires,
             'to_home', (select jsonb_build_object('id', h.id, 'name', h.name, 'weekly_rent', h.weekly_rent, 'area', round(hl.w * hl.d))
                           from start_homes h left join home_layouts hl on hl.id = bl_home_layout_id(h.housing_id)
                          where h.id = u.effect->>'to_home'),
             'state', case when p.upgrade_id is not null and p.done_at is not null then 'owned'
                           when p.upgrade_id is not null then 'building'
                           when bl_house_upgrade_lock(v_me, u) is not null then 'locked'
                           else 'available' end,
             'locked', case when p.upgrade_id is null then bl_house_upgrade_lock(v_me, u) end)
           order by u.sort, u.id), '[]'::jsonb) into v_avail
    from house_upgrades u
    left join player_house_upgrades p on p.user_id = v_me.id and p.upgrade_id = u.id
   where u.active and v_kind = any (u.tiers) and v_kind <> 'hostel';
  return jsonb_build_object(
    'enabled', bl_cfg_bool('house.upgrades_enabled'),
    'can_upgrade', v_reason is null, 'reason', v_reason, 'kind', v_kind,
    'resale_pct', coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_resale_pct'), 50),
    'landlord_fee_pct', v_fee_pct,
    'max_builds', coalesce((select (value #>> '{}')::int from game_config where key = 'house.upgrade_max_builds'), 1),
    'building_count', v_busy, 'tier_building', v_tier_building,
    'sale_value', bl_house_upgrades_value(v_me.id), 'finish', v_finish,
    'garage', case when v_garage.user_id is null then null else jsonb_build_object('type', v_garage.garage_type, 'extra', v_garage.extra_capacity) end,
    'done', v_done, 'building', v_build, 'available', v_avail, 'just_finished', v_fin);
end $$;

create or replace function public.house_upgrade_buy(p_id text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  u       public.house_upgrades;
  v_kind  text;
  v_lock  text;
  v_fee_pct numeric := coalesce((select (value #>> '{}')::numeric from game_config where key = 'house.upgrade_landlord_fee_pct'), 10);
  v_base  bigint; v_rent bigint; v_fee bigint; v_total bigint;
  v_bank  bigint; v_cash bigint;
  v_min   int;
  v_max   int := greatest(1, coalesce((select (value #>> '{}')::int from game_config where key = 'house.upgrade_max_builds'), 1));
  v_ready timestamptz;
  v_meta  jsonb;
begin
  if not bl_cfg_bool('house.upgrades_enabled') then
    raise exception 'House upgrades are paused right now.' using errcode = 'P0001', hint = 'upgrades_disabled';
  end if;
  v_kind := bl_housing_kind(v_me.housing_id);
  if v_kind = 'hostel' then
    raise exception 'Hostel rooms belong to UNIBEN. You can''t renovate them.' using errcode = 'P0001', hint = 'not_yours';
  end if;
  if v_me.home_visit_host_id is not null then
    raise exception 'You are visiting someone. Go back to your own home first.' using errcode = 'P0001', hint = 'visiting';
  end if;
  if v_me.jailed_until is not null and v_me.jailed_until > bl_now() then
    raise exception 'You can''t arrange building works from jail.' using errcode = 'P0001', hint = 'jailed';
  end if;
  if v_me.rent_owed > 0 then
    raise exception 'Settle the % rent you owe first. The landlord won''t approve works while you owe.', bl_naira(v_me.rent_owed)
      using errcode = 'P0001', hint = 'rent_owed';
  end if;
  select * into u from house_upgrades where id = p_id and active;
  if not found then
    raise exception 'That upgrade isn''t available.' using errcode = 'P0001', hint = 'unknown_upgrade';
  end if;
  perform bl_house_upgrades_settle(v_me.id);
  select * into v_me from profiles where id = v_me.id for update;
  if exists (select 1 from player_house_upgrades where user_id = v_me.id and upgrade_id = u.id) then
    raise exception 'You already have % (or the builders are on it).', lower(u.name) using errcode = 'P0001', hint = 'already_have';
  end if;
  v_lock := bl_house_upgrade_lock(v_me, u);
  if v_lock is not null then
    raise exception '%', v_lock using errcode = 'P0001', hint = case when not (v_kind = any (u.tiers)) then 'not_for_this_home' else 'locked' end;
  end if;
  if exists (select 1 from player_house_upgrades p join house_upgrades x on x.id = p.upgrade_id
              where p.user_id = v_me.id and p.done_at is null and x.effect ? 'to_home') then
    raise exception 'The builders are changing your whole home right now. Wait until they finish.' using errcode = 'P0001', hint = 'tier_building';
  end if;
  if u.effect ? 'to_home' and exists (select 1 from player_house_upgrades where user_id = v_me.id and done_at is null) then
    raise exception 'Let the builders finish the other works before you change the whole home.' using errcode = 'P0001', hint = 'builders_busy';
  end if;
  if (select count(*) from player_house_upgrades where user_id = v_me.id and done_at is null) >= v_max then
    raise exception 'The builders are busy. Wait until they finish the current work.' using errcode = 'P0001', hint = 'builders_busy';
  end if;
  v_base := bl_house_upgrade_price(u, v_kind);
  v_rent := bl_house_upgrade_rent_fee(v_me, u);
  v_fee := round(v_base * v_fee_pct / 100.0)::bigint;
  v_total := v_base + v_rent + v_fee;
  if v_me.bank + v_me.cash < v_total then
    raise exception 'Not enough money. % costs % (works % + landlord fee %) and you have %.', u.name, bl_naira(v_total), bl_naira(v_base + v_rent),
      bl_naira(v_fee), bl_naira(v_me.bank + v_me.cash)
      using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  v_meta := jsonb_build_object('upgrade', u.id, 'name', u.name);
  v_bank := least(greatest(v_me.bank, 0), v_total);
  v_cash := v_total - v_bank;
  if v_bank > 0 then perform bl_add_money(v_me.id, 'bank', -v_bank, 'house_upgrade', v_meta); end if;
  if v_cash > 0 then perform bl_add_money(v_me.id, 'cash', -v_cash, 'house_upgrade', v_meta); end if;
  v_min := bl_house_upgrade_minutes(u);
  v_ready := bl_now() + make_interval(mins => v_min);
  insert into player_house_upgrades (user_id, upgrade_id, start_home, price_paid, fee_paid, bought_at, ready_at, done_at, source)
  values (v_me.id, u.id, v_me.start_home, v_base + v_rent, v_fee, bl_now(), v_ready, null, 'buy');
  if v_min = 0 then perform bl_house_upgrades_settle(v_me.id); end if;
  return jsonb_build_object(
    'message', case when v_min = 0 then u.name || ' done for ' || bl_naira(v_total) || '.'
                    else 'Builders don arrive for ' || lower(u.name) || '. Ready in about ' || v_min || ' min.' end,
    'upgrade', u.id, 'name', u.name, 'spent', v_total, 'landlord_fee', v_fee, 'from_bank', v_bank, 'from_cash', v_cash,
    'minutes', v_min, 'ready_at', v_ready, 'instant', v_min = 0);
end $$;

-- The upgrades the 3D home needs (extension rooms, yard buildings, finish, security, scaffolding) for p_owner (default me).
-- Owner or admitted house guest only (same rule as garage_home).
create or replace function public.house_upgrade_home(p_owner uuid default null) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid := coalesce(p_owner, auth.uid());
  v_done  jsonb; v_build jsonb;
begin
  if v_uid is null then
    raise exception 'Please sign in.' using errcode = 'P0001', hint = 'not_signed_in';
  end if;
  if v_owner <> v_uid and not bl_social_can_view_owner_home(v_owner) then
    raise exception 'You can only see the upgrades of a home you are inside.' using errcode = 'P0001', hint = 'not_allowed';
  end if;
  if v_owner = v_uid then perform bl_house_upgrades_settle(v_owner); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'effect', u.effect - 'bonus') order by p.done_at, u.sort), '[]'::jsonb) into v_done
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id where p.user_id = v_owner and p.done_at is not null;
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'effect', u.effect - 'bonus', 'ready_at', p.ready_at, 'started_at', p.bought_at,
                                               'name', u.name, 'emoji', u.emoji) order by p.ready_at), '[]'::jsonb) into v_build
    from player_house_upgrades p join house_upgrades u on u.id = p.upgrade_id where p.user_id = v_owner and p.done_at is null;
  return jsonb_build_object('owner', v_owner, 'done', v_done, 'building', v_build);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Admin: look at a player's upgrades and grant one (audited)
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_house_upgrade_get(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); p profiles; v_kind text;
begin
  select * into p from profiles where id = p_user;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  v_kind := bl_housing_kind(p.housing_id);
  return jsonb_build_object(
    'kind', v_kind, 'start_home', p.start_home,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'emoji', u.emoji, 'state', case when x.done_at is null then 'building' else 'done' end,
                          'paid', x.price_paid, 'ready_at', x.ready_at, 'done_at', x.done_at, 'source', x.source) order by x.bought_at)
                        from player_house_upgrades x join house_upgrades u on u.id = x.upgrade_id where x.user_id = p_user), '[]'::jsonb),
    'options', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'emoji', u.emoji) order by u.sort, u.id)
                           from house_upgrades u
                          where v_kind = any (u.tiers)
                            and not exists (select 1 from player_house_upgrades x where x.user_id = p_user and x.upgrade_id = u.id)), '[]'::jsonb));
end $$;

create or replace function public.admin_house_upgrade_grant(p_user uuid, p_upgrade text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard();
  p       profiles;
  u       public.house_upgrades;
  v_kind  text;
begin
  select * into p from profiles where id = p_user for update;
  if not found then
    raise exception 'That player doesn''t exist.' using errcode = 'P0001', hint = 'no_player';
  end if;
  select * into u from house_upgrades where id = p_upgrade;
  if not found then
    raise exception 'That upgrade doesn''t exist.' using errcode = 'P0001', hint = 'unknown_upgrade';
  end if;
  v_kind := bl_housing_kind(p.housing_id);
  if not (v_kind = any (u.tiers)) then
    raise exception '% isn''t for a % home.', u.name, replace(v_kind, '_', ' ') using errcode = 'P0001', hint = 'not_for_this_home';
  end if;
  if exists (select 1 from player_house_upgrades where user_id = p_user and upgrade_id = u.id) then
    raise exception 'That player already has %.', lower(u.name) using errcode = 'P0001', hint = 'already_have';
  end if;
  perform bl_house_upgrades_settle(p_user);
  insert into player_house_upgrades (user_id, upgrade_id, start_home, price_paid, fee_paid, bought_at, ready_at, done_at, source, granted_by)
  values (p_user, u.id, p.start_home, 0, 0, bl_now(), bl_now(), bl_now(), 'admin', v_admin);
  perform bl_house_upgrade_apply(p_user, u, 0);
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'house_upgrade_grant', p_user, jsonb_build_object('upgrade', u.id, 'name', u.name, 'home', p.start_home));
  perform bl_event(p_user, 'house_upgrade', u.emoji || ' ' || u.name || ' done',
                   'Your builders finished ' || lower(u.name) || ' at home. Enjoy!', jsonb_build_object('upgrade', u.id));
  return jsonb_build_object('message', u.name || ' granted.', 'upgrade', u.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Patches of live functions
-- ---------------------------------------------------------------------------------------------
-- furniture check: extension rooms are floor you may furnish, yard buildings and the extension doorway block solid pieces
select pg_temp.bl_patch1('public.bl_furniture_check(uuid, text, text, numeric, numeric, integer)', 'bl_home_ext_flags(',
  E'  b jsonb;\n  o record;\nbegin',
  E'  b jsonb;\n  v_f jsonb;\n  v_xb text;\n  o record;\nbegin');
select pg_temp.bl_patch1('public.bl_furniture_check(uuid, text, text, numeric, numeric, integer)', 'v_f := bl_home_ext_flags(',
  E'  if f.placement = ''in'' and not v_in then',
  E'  v_f := bl_home_ext_flags(p_uid, p_layout, x0, z0, x1, z1); -- R8: extension rooms + grown yard\n  v_in := v_in or (v_f->>''in'')::boolean;\n  v_yard := (v_f->>''yard'')::boolean;\n  if f.placement = ''in'' and not v_in then');
select pg_temp.bl_patch1('public.bl_furniture_check(uuid, text, text, numeric, numeric, integer)', 'bl_home_ext_block(',
  E'  for o in\n    select h.x, h.z, h.rotation, fo.w, fo.d, fo.name',
  E'  v_xb := bl_home_ext_block(p_uid, p_layout, x0, z0, x1, z1);\n  if v_xb is not null then return v_xb; end if;\n  for o in\n    select h.x, h.z, h.rotation, fo.w, fo.d, fo.name');

-- home activities get the upgrade bonuses (generator, solar, borehole, security, finish ...)
select pg_temp.bl_patch1('public.do_activity(text)', 'bl_house_bonus(',
  E'  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text(''rent.owed_sleep_activities''), a.id)',
  E'  -- R8: house upgrades on top of home activities\n  if a.home_only and bl_house_bonus(v_me.id, a.id) <> ''{}''::jsonb then\n    v_eff := v_eff || bl_effects_add(bl_need_effects(v_eff), bl_need_effects(bl_house_bonus(v_me.id, a.id)));\n  end if;\n  if v_me.rent_owed > 0 and bl_csv_has(bl_cfg_text(''rent.owed_sleep_activities''), a.id)');

-- the garage in the 3D home counts the extra car spaces
select pg_temp.bl_patch1('public.garage_home(uuid)', 'pg.extra_capacity',
  E'''type'', g.id, ''name'', g.name, ''capacity'', g.capacity,',
  E'''type'', g.id, ''name'', g.name, ''capacity'', least(4, g.capacity + coalesce(pg.extra_capacity, 0)),');

-- moving out: the upgrades are sold with the home
select pg_temp.bl_patch1('public.house_move(text)', 'v_upg    bigint',
  E'  v_ok     boolean;\nbegin',
  E'  v_ok     boolean;\n  v_upg    bigint := 0;\nbegin');
select pg_temp.bl_patch1('public.house_move(text)', 'bl_house_upgrades_release(',
  E'  -- the old home is gone for good; its garage stays behind (the cars stay yours)',
  E'  -- R8: the upgrades are sold with the old home (house.upgrade_resale_pct back into the bank)\n  v_upg := bl_house_upgrades_release(v_me.id);\n  -- the old home is gone for good; its garage stays behind (the cars stay yours)');
select pg_temp.bl_patch1('public.house_move(text)', '''upgrade_refund''',
  E'    ''spent'', v_cost,',
  E'    ''upgrade_refund'', v_upg, ''spent'', v_cost,');

-- ledger text
select pg_temp.bl_patch1('public.bl_ledger_label(text, jsonb)', 'when ''house_upgrade'' then',
  E'    when ''garage'' then return',
  E'    when ''house_upgrade'' then return case when coalesce((p_meta->>''refund'')::boolean, false) then ''Upgrades sold with your old home'' else ''House upgrade: '' || coalesce(nullif(p_meta->>''name'', ''''), ''works'') end;\n    when ''garage'' then return');

-- admin Content editor: House upgrades
select pg_temp.bl_patch1('public.bl_admin_table_spec(text)', 'when ''house_upgrades'' then',
  E'when ''skill_sources'' then',
  E'when ''house_upgrades'' then ''{"pk":["id"],"insert":true,"order":"sort, id",\n      "cols":{"name":"text","emoji":"text","category":"text","description":"text","preview":"text","tiers":"arr","price":"money","tier_prices":"obj","build_minutes":"int","requires":"text_null","effect":"obj","sort":"int","active":"bool"}}''\n    when ''skill_sources'' then');

-- ---------------------------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------------------------
revoke all on function public.bl_house_upgrade_price(public.house_upgrades, text) from public, anon, authenticated;
revoke all on function public.bl_house_upgrade_minutes(public.house_upgrades) from public, anon, authenticated;
revoke all on function public.bl_home_ext(uuid) from public, anon, authenticated;
revoke all on function public.bl_home_ext_flags(uuid, text, numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.bl_home_ext_block(uuid, text, numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.bl_house_bonus(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_house_garage(profiles) from public, anon, authenticated;
revoke all on function public.bl_house_upgrade_lock(profiles, public.house_upgrades) from public, anon, authenticated;
revoke all on function public.bl_house_upgrade_rent_fee(profiles, public.house_upgrades) from public, anon, authenticated;
revoke all on function public.bl_house_upgrades_value(uuid) from public, anon, authenticated;
revoke all on function public.bl_house_upgrades_release(uuid) from public, anon, authenticated;
revoke all on function public.bl_house_apply_tier(uuid, text) from public, anon, authenticated;
revoke all on function public.bl_house_upgrade_apply(uuid, public.house_upgrades, bigint) from public, anon, authenticated;
revoke all on function public.bl_house_upgrades_settle(uuid) from public, anon, authenticated;
revoke all on function public.bl_house_upgrade_card(public.house_upgrades, text) from public, anon, authenticated;

revoke all on function public.house_upgrade_state() from public, anon;
grant execute on function public.house_upgrade_state() to authenticated, service_role;
revoke all on function public.house_upgrade_buy(text) from public, anon;
grant execute on function public.house_upgrade_buy(text) to authenticated, service_role;
revoke all on function public.house_upgrade_home(uuid) from public, anon;
grant execute on function public.house_upgrade_home(uuid) to authenticated, service_role;
revoke all on function public.admin_house_upgrade_get(uuid) from public, anon;
grant execute on function public.admin_house_upgrade_get(uuid) to authenticated, service_role;
revoke all on function public.admin_house_upgrade_grant(uuid, text) from public, anon;
grant execute on function public.admin_house_upgrade_grant(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
