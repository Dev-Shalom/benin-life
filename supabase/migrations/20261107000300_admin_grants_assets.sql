-- Benin Life: Admin Grant toolbox, part 3 (docs/ADMIN_GRANTS.md): owned assets and standing.
-- Business levels / staff / insurance / stock, companies (give, format, staff, manager, generator), homes (home type, give a
-- property, land plots), crew and rank, chief title, courses, and the two read RPCs the toolbox screen uses
-- (admin_grant_state = the player's numbers, admin_grant_catalog = what can be granted).
-- Gifts keep "invested / basis / cost" at 0 like admin_business_grant does, so a gift can never be sold back for cash profit
-- beyond what the game already pays for a gift. No ledger rows, nothing counts as earned.

-- ---------------------------------------------------------------------
-- 1. Business: level (up to the type's top level), staff, insurance, stock
-- ---------------------------------------------------------------------
create or replace function public.admin_business_set(p_business bigint, p_level int default null, p_staff int default null,
                                                     p_insured_days int default null, p_stock_hours int default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  b businesses; t business_types; p profiles; v_now timestamptz := bl_now(); v_old jsonb; v_up boolean; v_max_stock int;
begin
  if p_level is null and p_staff is null and p_insured_days is null and p_stock_hours is null then
    perform bl_ag_fail('Nothing to set.', 'bad_value');
  end if;
  select * into b from businesses where id = p_business for update;
  if not found then
    perform bl_ag_fail('That business doesn''t exist.', 'gone');
  end if;
  p := bl_ag_target(b.owner_id);
  select * into t from business_types where id = b.type_id;
  if b.listed then
    perform bl_ag_fail('That business is on the Market right now. Cancel the listing first (nothing can change while it is for sale).', 'listed');
  end if;
  if p_level is not null and (p_level < 1 or p_level > t.max_level) then
    perform bl_ag_fail(t.name || ' goes from level 1 to ' || t.max_level || '.', 'bad_value');
  end if;
  if p_staff is not null and (p_staff < 0 or p_staff > t.staff_slots) then
    perform bl_ag_fail(t.name || ' has room for 0 to ' || t.staff_slots || ' staff.', 'bad_value');
  end if;
  if p_insured_days is not null and (p_insured_days < 0 or p_insured_days > 90) then
    perform bl_ag_fail('Insurance goes from 0 to 90 days (0 removes it).', 'bad_value');
  end if;
  v_max_stock := bl_biz_num('business.stock_max_hours', 168)::int;
  if p_stock_hours is not null and (p_stock_hours < 0 or p_stock_hours > v_max_stock) then
    perform bl_ag_fail('Stock goes from 0 to ' || v_max_stock || ' hours (0 empties the shelf).', 'bad_value');
  end if;
  b := bl_biz_settle(b.id, false);                       -- earn up to now under the old level first
  v_old := jsonb_build_object('level', b.level, 'staff', b.staff, 'insured_until', b.insured_until, 'stock_until', b.stock_until);
  v_up := coalesce(p_level, b.level) >= b.level;
  update businesses set level = coalesce(p_level, level), staff = coalesce(p_staff, staff),
         insured_until = case when p_insured_days is null then insured_until when p_insured_days = 0 then null else v_now + make_interval(days => p_insured_days) end,
         stock_until = case when p_stock_hours is null then stock_until else v_now + make_interval(hours => p_stock_hours) end
   where id = b.id returning * into b;
  perform bl_biz_loc_sync(b.plot_id);
  perform bl_biz_log(b.id, b.owner_id, 'admin_set', 'Set by Benin Life', 0, jsonb_build_object('admin', v_admin));
  perform bl_ag_log(v_admin, b.owner_id, 'grant_business_level', jsonb_build_object('business', b.id, 'name', b.name, 'type', b.type_id, 'old', v_old,
    'new', jsonb_build_object('level', b.level, 'staff', b.staff, 'insured_until', b.insured_until, 'stock_until', b.stock_until), 'reason', v_reason));
  perform bl_ag_alert(b.owner_id, case when v_up then 'admin_grant' else 'admin_take' end, b.name || ' updated',
    'An admin set ' || b.name || ' to level ' || b.level || case when p_staff is not null then ', ' || b.staff || ' staff' else '' end || '.', v_reason,
    jsonb_build_object('business', b.id, 'level', b.level));
  return jsonb_build_object('message', b.name || ' is now level ' || b.level || ' with ' || b.staff || ' staff.', 'business', b.id, 'level', b.level);
end $$;

-- ---------------------------------------------------------------------
-- 2. Companies: give one, set head-office format (size), staff, manager, generator
-- ---------------------------------------------------------------------
create or replace function public.admin_company_grant(p_user uuid, p_industry text, p_area text, p_name text default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; i company_industries; a company_areas; v_name text; c companies;
begin
  p := bl_ag_target(p_user);
  select * into i from company_industries where id = p_industry and active;
  if not found then
    perform bl_ag_fail('That company type doesn''t exist.', 'bad_industry');
  end if;
  select * into a from company_areas where id = p_area and active;
  if not found then
    perform bl_ag_fail('That area doesn''t exist.', 'bad_area');
  end if;
  if (select count(*) from companies where owner_id = p_user) >= bl_co_num('company.max_owned', 20) then
    perform bl_ag_fail('They already own ' || bl_co_num('company.max_owned', 20)::int || ' companies. That is the limit.', 'max_owned');
  end if;
  v_name := left(bl_chat_clean(coalesce(nullif(btrim(p_name), ''), i.name || ' of ' || p.username)), 28);
  if char_length(v_name) < 3 or v_name ~ '[<>]' or bl_chat_mask(v_name) <> v_name or not bl_rb_text_ok(v_name) then
    perform bl_ag_fail('Choose a cleaner company name (3 to 28 letters, no rude words, no real politicians or parties).', 'bad_name');
  end if;
  if exists (select 1 from companies where lower(name) = lower(v_name)) then
    perform bl_ag_fail('A company called "' || v_name || '" already exists. Pick another name.', 'name_taken');
  end if;
  insert into companies (owner_id, name, industry_id, rating, staff, pricing, settled_through, invested, source)
  values (p_user, v_name, i.id, bl_co_num('company.rating_start', 3), 0, 'fair', bl_co_night_at(), 0, 'admin')
  returning * into c;
  insert into company_branches (company_id, area_id, format_id, is_hq) values (c.id, a.id, 'kiosk', true);
  perform bl_co_log(c.id, p_user, 'founded', 'Given by Benin Life: ' || v_name || ' (' || i.name || ') in ' || a.name, 0, jsonb_build_object('admin', v_admin));
  perform bl_ag_log(v_admin, p_user, 'grant_company', jsonb_build_object('company', c.id, 'name', v_name, 'industry', i.id, 'area', a.id, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', v_name || ' is yours', 'An admin gave you a ' || lower(i.name) || ' company in ' || a.name || '. Open the Business app.', v_reason, jsonb_build_object('company', c.id));
  return jsonb_build_object('message', v_name || ' given to @' || p.username || '.', 'company', c.id);
end $$;

create or replace function public.admin_company_set(p_company bigint, p_format text default null, p_staff int default null,
                                                    p_manager boolean default null, p_generator boolean default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  c companies; p profiles; v_old jsonb; v_slots int; v_fmt text;
begin
  if p_format is null and p_staff is null and p_manager is null and p_generator is null then
    perform bl_ag_fail('Nothing to set.', 'bad_value');
  end if;
  select * into c from companies where id = p_company for update;
  if not found then
    perform bl_ag_fail('That company doesn''t exist.', 'gone');
  end if;
  p := bl_ag_target(c.owner_id);
  if c.listed then
    perform bl_ag_fail('That company is on the Market right now. Cancel the listing first.', 'listed');
  end if;
  if p_format is not null and not exists (select 1 from company_formats where id = p_format) then
    perform bl_ag_fail('That company size doesn''t exist.', 'bad_format');
  end if;
  c := bl_co_settle(c.id, false);                        -- evenings already earned stay at the old size
  select format_id into v_fmt from company_branches where company_id = c.id and is_hq;
  v_old := jsonb_build_object('format', v_fmt, 'staff', c.staff, 'manager', c.manager, 'generator', c.generator);
  if p_format is not null then
    update company_branches set format_id = p_format where company_id = c.id and is_hq;
  end if;
  v_slots := bl_co_slots(c.id);
  if p_staff is not null and (p_staff < 0 or p_staff > v_slots) then
    perform bl_ag_fail('This company has room for 0 to ' || v_slots || ' staff at its current size.', 'bad_value');
  end if;
  update companies set staff = coalesce(p_staff, least(staff, v_slots)), manager = coalesce(p_manager, manager), generator = coalesce(p_generator, generator)
   where id = c.id returning * into c;
  perform bl_co_log(c.id, c.owner_id, 'admin_set', 'Set by Benin Life', 0, jsonb_build_object('admin', v_admin));
  perform bl_ag_log(v_admin, c.owner_id, 'grant_company_set', jsonb_build_object('company', c.id, 'name', c.name, 'old', v_old,
    'new', jsonb_build_object('format', coalesce(p_format, v_fmt), 'staff', c.staff, 'manager', c.manager, 'generator', c.generator), 'reason', v_reason));
  perform bl_ag_alert(c.owner_id, 'admin_grant', c.name || ' updated', 'An admin changed ' || c.name || ' (size, staff or manager).', v_reason, jsonb_build_object('company', c.id));
  return jsonb_build_object('message', c.name || ' updated: ' || c.staff || ' staff' || case when c.manager then ', manager' else '' end || '.', 'company', c.id);
end $$;

-- ---------------------------------------------------------------------
-- 3. Home type, a property, land plots
-- ---------------------------------------------------------------------
-- The same path house_move and property_live_in use (bl_home_enter): furniture is re-placed, upgrades and the garage
-- follow the home. No rent is charged for the move-in; the home's normal weekly rent starts like any move.
create or replace function public.admin_set_home(p_user uuid, p_home text default null, p_property uuid default null, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; h start_homes; pr properties; v_res jsonb; v_old text; v_msg text;
begin
  if (p_home is null) = (p_property is null) then
    perform bl_ag_fail('Pick a home type, or one of their properties.', 'bad_value');
  end if;
  p := bl_ag_target(p_user);
  begin
    perform bl_prop_move_guard(p);
  exception when others then
    perform bl_ag_fail('They can''t move right now: ' || sqlerrm, 'cannot_move');
  end;
  perform bl_past_homes_expire(p_user);
  v_old := p.start_home;
  if p_property is not null then
    select * into pr from properties where id = p_property and owner_id = p_user for update;
    if not found then
      perform bl_ag_fail('That property isn''t theirs.', 'not_yours');
    end if;
    if exists (select 1 from player_residence where property_id = pr.id) then
      perform bl_ag_fail('Someone already lives in that property.', 'occupied');
    end if;
    h := bl_prop_home(pr);
    v_res := bl_home_enter(p_user, h, pr.id, 'owner', 0, 0, null, 0);
    update properties set listed = false where id = pr.id;
    perform bl_prop_log(pr.id, p_user, 'owner_moved_in', jsonb_build_object('admin', v_admin));
    v_msg := bl_prop_name(pr);
  else
    select * into h from start_homes where id = lower(btrim(p_home)) and active;
    if not found then
      perform bl_ag_fail('That home type doesn''t exist.', 'bad_home');
    end if;
    if h.id = p.start_home and not exists (select 1 from player_residence where user_id = p_user) then
      perform bl_ag_fail('They already live in a ' || h.name || '.', 'same_home');
    end if;
    v_res := bl_home_enter(p_user, h, null, null, h.weekly_rent, 0, null, 0);
    v_msg := h.name;
  end if;
  perform bl_ag_log(v_admin, p_user, 'set_home', jsonb_build_object('old', v_old, 'new', h.id, 'property', p_property, 'layout', v_res ->> 'layout', 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'New home', 'An admin moved you into ' || v_msg || '. Your things came along; check My items in Arrange.', v_reason, jsonb_build_object('home', h.id));
  return jsonb_build_object('message', '@' || p.username || ' now lives in ' || v_msg || '.', 'home', h.id);
end $$;

create or replace function public.admin_give_property(p_user uuid, p_offer text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; o property_offers; t property_types; a property_areas; v_id uuid; v_name text;
begin
  p := bl_ag_target(p_user);
  select * into o from property_offers where id = p_offer and active;
  if not found then
    perform bl_ag_fail('That home isn''t on the list.', 'bad_offer');
  end if;
  select * into t from property_types where id = o.type_id and active;
  select * into a from property_areas where id = o.area and active;
  if t.id is null or a.id is null then
    perform bl_ag_fail('That home isn''t on the list.', 'bad_offer');
  end if;
  if bl_prop_owned_count(p_user) >= bl_prop_num('property.max_owned', 20) then
    perform bl_ag_fail('They own the most homes allowed (' || bl_prop_num('property.max_owned', 20)::int || ').', 'too_many');
  end if;
  v_name := t.name || ' · ' || a.name;
  insert into properties (owner_id, area, type_id, source, basis, acquired_at) values (p_user, a.id, t.id, 'bought', 0, bl_now()) returning id into v_id;
  perform bl_prop_log(v_id, p_user, 'bought', jsonb_build_object('price', 0, 'total', 0, 'admin', v_admin));
  perform bl_ag_log(v_admin, p_user, 'grant_property', jsonb_build_object('property', v_id, 'offer', o.id, 'name', v_name, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'A home for you', 'An admin gave you a ' || lower(t.name) || ' in ' || a.name || '. Open Phone, Houses, My properties to live in it.', v_reason, jsonb_build_object('property', v_id));
  return jsonb_build_object('message', v_name || ' given to @' || p.username || '.', 'property', v_id);
end $$;

create or replace function public.admin_take_property(p_user uuid, p_property uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true); p profiles; pr properties; v_name text;
begin
  p := bl_ag_target(p_user, true);
  select * into pr from properties where id = p_property and owner_id = p_user for update;
  if not found then
    perform bl_ag_fail('That property isn''t theirs.', 'not_yours');
  end if;
  if exists (select 1 from player_residence where property_id = pr.id) then
    perform bl_ag_fail('Someone lives in it (the owner or a tenant). Move them out first (Set home, or Admin → Property → Force end).', 'occupied');
  end if;
  if pr.build_id is not null then
    perform bl_ag_fail('That home is a unit of a block they built. Remove it from the builder side, not here.', 'built');
  end if;
  v_name := bl_prop_name(pr);
  delete from properties where id = pr.id;
  perform bl_ag_log(v_admin, p_user, 'take_property', jsonb_build_object('property', pr.id, 'name', v_name, 'basis', pr.basis, 'had_stash', pr.stash is not null, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Property removed', 'An admin removed your ' || v_name || '.', v_reason);
  return jsonb_build_object('message', v_name || ' removed from @' || p.username || '.');
end $$;

create or replace function public.admin_give_land(p_user uuid, p_market text, p_plots int, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; m invest_markets; v_old numeric; v_new numeric;
begin
  if p_plots is null or p_plots < 1 or p_plots > 100 then
    perform bl_ag_fail('Plots go from 1 to 100.', 'bad_qty');
  end if;
  select * into m from invest_markets where id = p_market and kind = 'land';
  if not found then
    perform bl_ag_fail('That land area doesn''t exist.', 'bad_market');
  end if;
  p := bl_ag_target(p_user);
  v_old := coalesce((select qty from invest_positions where user_id = p_user and ref_id = m.id), 0);
  if v_old + p_plots > 1000 then
    perform bl_ag_fail('They would hold more than 1,000 plots here.', 'max_owned');
  end if;
  insert into invest_positions (user_id, ref_id, kind, qty, cost, opened_at, last_at) values (p_user, m.id, 'land', p_plots, 0, bl_now(), bl_now())
  on conflict (user_id, ref_id) where kind = any (array['savings', 'mmf', 'bond', 'stock', 'crypto', 'land'])
  do update set qty = invest_positions.qty + excluded.qty
  returning qty into v_new;
  perform bl_inv_log(p_user, 'buy', m.id, 'Land: ' || p_plots || ' plot(s) · ' || m.name || ' (gift)', 0, null, jsonb_build_object('admin', true));
  perform bl_ag_log(v_admin, p_user, 'grant_land', jsonb_build_object('market', m.id, 'plots', p_plots, 'old', v_old, 'new', v_new, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'Land for you', 'An admin gave you ' || p_plots || ' plot' || case when p_plots > 1 then 's' else '' end || ' of land in ' || m.name || '.', v_reason, jsonb_build_object('market', m.id, 'plots', p_plots));
  return jsonb_build_object('message', 'Gave ' || p_plots || ' plot(s) in ' || m.name || ' to @' || p.username || ' (now ' || v_new || ').', 'plots', v_new);
end $$;

create or replace function public.admin_take_land(p_user uuid, p_market text, p_plots int, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; m invest_markets; pos invest_positions; v_locked int; v_new numeric;
begin
  if p_plots is null or p_plots < 1 or p_plots > 1000 then
    perform bl_ag_fail('Plots go from 1 to 1000.', 'bad_qty');
  end if;
  select * into m from invest_markets where id = p_market and kind = 'land';
  if not found then
    perform bl_ag_fail('That land area doesn''t exist.', 'bad_market');
  end if;
  p := bl_ag_target(p_user, true);
  select * into pos from invest_positions where user_id = p_user and ref_id = m.id for update;
  v_locked := bl_land_locked(p_user, m.id);
  if not found or pos.qty - v_locked < p_plots then
    perform bl_ag_fail('They only have ' || greatest(coalesce(pos.qty, 0) - v_locked, 0) || ' free plot(s) there (plots under a house or a build are locked).', 'not_enough');
  end if;
  v_new := pos.qty - p_plots;
  if v_new = 0 then
    delete from invest_positions where id = pos.id;
  else
    update invest_positions set qty = v_new, cost = round(cost * v_new / pos.qty)::bigint where id = pos.id;
  end if;
  perform bl_ag_log(v_admin, p_user, 'take_land', jsonb_build_object('market', m.id, 'plots', p_plots, 'old', pos.qty, 'new', v_new, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Land removed', 'An admin took ' || p_plots || ' plot' || case when p_plots > 1 then 's' else '' end || ' of land in ' || m.name || ' from you.', v_reason);
  return jsonb_build_object('message', 'Took ' || p_plots || ' plot(s) in ' || m.name || ' from @' || p.username || ' (now ' || v_new || ').', 'plots', v_new);
end $$;

-- ---------------------------------------------------------------------
-- 4. Crew (gang) and rank, chief title
-- ---------------------------------------------------------------------
create or replace function public.admin_crew_set(p_user uuid, p_crew bigint, p_rank text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; c crews; m crew_members; v_rank text := lower(btrim(coalesce(p_rank, ''))); v_old text;
begin
  if v_rank not in ('lieutenant', 'member', 'prospect') then
    perform bl_ag_fail('Pick Lieutenant, Member or Prospect. (The Boss changes through the gang itself.)', 'bad_rank');
  end if;
  p := bl_ag_target(p_user);
  select * into c from crews where id = p_crew and disbanded_at is null for update;
  if not found then
    perform bl_ag_fail('That gang doesn''t exist.', 'bad_crew');
  end if;
  select * into m from crew_members where user_id = p_user for update;
  if found then
    if m.crew_id <> c.id then
      perform bl_ag_fail('They are in another gang. Remove them from it first.', 'in_other_crew');
    end if;
    if m.rank = 'boss' then
      perform bl_ag_fail('They are the Boss of this gang. Their rank can''t be changed here.', 'is_boss');
    end if;
    if m.rank = v_rank then
      perform bl_ag_fail('They are already ' || initcap(v_rank) || '.', 'same_rank');
    end if;
  else
    if (select count(*) from crew_members where crew_id = c.id) >= bl_crew_max_members(c.level) then
      perform bl_ag_fail(c.name || ' is full (' || bl_crew_max_members(c.level) || ' members at its level).', 'crew_full');
    end if;
  end if;
  if v_rank = 'lieutenant' and (select count(*) from crew_members where crew_id = c.id and rank = 'lieutenant' and user_id <> p_user) >= bl_crew_num('crew.max_lieutenants', 3) then
    perform bl_ag_fail(c.name || ' already has the most Lieutenants allowed.', 'max_lieutenants');
  end if;
  v_old := m.rank;
  if m.user_id is null then
    perform bl_crew_add_member(c.id, p_user, v_rank);
  else
    update crew_members set rank = v_rank where user_id = p_user;
  end if;
  perform bl_ag_log(v_admin, p_user, 'grant_crew', jsonb_build_object('crew', c.id, 'name', c.name, 'old_rank', v_old, 'new_rank', v_rank, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', case when v_old is null then 'You joined ' || c.name else 'Your gang rank changed' end,
    case when v_old is null then 'An admin put you in ' || c.name || ' [' || c.tag || '] as ' || initcap(v_rank) || '.' else 'An admin made you ' || initcap(v_rank) || ' in ' || c.name || '.' end,
    v_reason, jsonb_build_object('crew', c.id, 'rank', v_rank));
  return jsonb_build_object('message', '@' || p.username || ' is ' || initcap(v_rank) || ' in ' || c.name || '.', 'crew', c.id);
end $$;

create or replace function public.admin_crew_remove(p_user uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; m crew_members; c crews;
begin
  p := bl_ag_target(p_user, true);
  select * into m from crew_members where user_id = p_user for update;
  if not found then
    perform bl_ag_fail('They are not in a gang.', 'no_crew');
  end if;
  if m.rank = 'boss' then
    perform bl_ag_fail('They are the Boss. Disband the gang from Admin → Crews, or let the Boss hand over first.', 'is_boss');
  end if;
  if exists (select 1 from crew_run_members x join crew_runs r on r.id = x.run_id where x.user_id = p_user and r.status = 'running') then
    perform bl_ag_fail('They are on a gang job right now. Wait for it to finish.', 'on_job');
  end if;
  select * into c from crews where id = m.crew_id;
  delete from crew_run_members x using crew_runs r where x.user_id = p_user and r.id = x.run_id and r.status = 'lobby';
  delete from crew_members where user_id = p_user;
  perform bl_crew_notify(c.id, p_user, 'crew_left', '@' || p.username || ' left the gang', '@' || p.username || ' is no longer in ' || c.name || '.', false);
  perform bl_ag_log(v_admin, p_user, 'crew_remove', jsonb_build_object('crew', c.id, 'name', c.name, 'rank', m.rank, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'You left ' || c.name, 'An admin took you out of ' || c.name || '.', v_reason);
  return jsonb_build_object('message', '@' || p.username || ' removed from ' || c.name || '.');
end $$;

create or replace function public.admin_set_chief_title(p_user uuid, p_tier int, p_ward text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, true);
  p profiles; t record; w wards; old chief_titles;
begin
  p := bl_ag_target(p_user);
  select * into t from bl_econ_tiers('economy.chief_tiers', 'Chief:10000000') x where x.idx = p_tier;
  if not found then
    perform bl_ag_fail('Pick a title from the list.', 'bad_tier');
  end if;
  select * into w from wards where id = p_ward and active;
  if not found then
    perform bl_ag_fail('Pick the part of Benin the title is "of".', 'bad_ward');
  end if;
  select * into old from chief_titles where user_id = p_user;
  insert into chief_titles (user_id, tier, name, ward, paid, since) values (p_user, t.idx, t.name, w.id, 0, bl_now())
  on conflict (user_id) do update set tier = excluded.tier, name = excluded.name, ward = excluded.ward, paid = excluded.paid, since = excluded.since;
  perform bl_ag_log(v_admin, p_user, 'grant_chief_title', jsonb_build_object('old', case when old.user_id is not null then jsonb_build_object('tier', old.tier, 'name', old.name, 'ward', old.ward) end,
                                                                             'new', jsonb_build_object('tier', t.idx, 'name', t.name, 'ward', w.id), 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', 'You are now ' || t.name || ' ' || p.username || ' of ' || w.name, 'An admin gave you the title ' || t.name || ' of ' || w.name || '. It shows next to your name.', v_reason, jsonb_build_object('tier', t.idx));
  return jsonb_build_object('message', '@' || p.username || ' is now ' || t.name || ' of ' || w.name || '.');
end $$;

create or replace function public.admin_remove_chief_title(p_user uuid, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; old chief_titles;
begin
  p := bl_ag_target(p_user, true);
  delete from chief_titles where user_id = p_user returning * into old;
  if old.user_id is null then
    perform bl_ag_fail('They have no chief title.', 'no_title');
  end if;
  perform bl_ag_log(v_admin, p_user, 'remove_chief_title', jsonb_build_object('tier', old.tier, 'name', old.name, 'ward', old.ward, 'paid', old.paid, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', 'Title removed', 'An admin removed your title ' || old.name || '.', v_reason);
  return jsonb_build_object('message', 'Title removed from @' || p.username || '.');
end $$;

-- ---------------------------------------------------------------------
-- 5. Courses: mark completed (with the certificate, like finishing the last class) and reset
-- ---------------------------------------------------------------------
create or replace function public.admin_complete_course(p_user uuid, p_course text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false);
  p profiles; k courses; e course_enrolments; v_cert jsonb;
begin
  select * into k from courses where id = p_course and active;
  if not found then
    perform bl_ag_fail('That course doesn''t exist.', 'bad_course');
  end if;
  p := bl_ag_target(p_user);
  select * into e from course_enrolments where user_id = p_user and course_id = k.id for update;
  if found and e.status = 'completed' then
    perform bl_ag_fail('They already finished ' || k.name || '.', 'already');
  end if;
  insert into course_enrolments (user_id, course_id, status, classes_done, fee_paid, enrolled_at, completed_at, updated_at)
  values (p_user, k.id, 'completed', k.classes, 0, bl_now(), bl_now(), bl_now())
  on conflict (user_id, course_id) do update set status = 'completed', classes_done = k.classes, completed_at = bl_now(), updated_at = bl_now();
  if k.cert_id is not null then
    v_cert := bl_cert_award(p_user, k.cert_id, 'course', k.id);
  end if;
  perform bl_ag_log(v_admin, p_user, 'grant_course', jsonb_build_object('course', k.id, 'name', k.name, 'cert', k.cert_id, 'was', e.status, 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_grant', k.name || ' completed', 'An admin marked ' || k.name || ' as completed for you.', v_reason, jsonb_build_object('course', k.id));
  return jsonb_build_object('message', k.name || ' marked completed for @' || p.username || coalesce(' (certificate: ' || (v_cert ->> 'name') || ')', '') || '.');
end $$;

create or replace function public.admin_reset_course(p_user uuid, p_course text, p_revoke_cert boolean default false, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_reason text := bl_ag_reason(p_reason, false); p profiles; k courses; e course_enrolments;
begin
  select * into k from courses where id = p_course;
  if not found then
    perform bl_ag_fail('That course doesn''t exist.', 'bad_course');
  end if;
  p := bl_ag_target(p_user, true);
  delete from course_enrolments where user_id = p_user and course_id = k.id returning * into e;
  if e.user_id is null then
    perform bl_ag_fail('They never started ' || k.name || '.', 'not_enrolled');
  end if;
  delete from course_runs where user_id = p_user and course_id = k.id and status = 'running';
  if coalesce(p_revoke_cert, false) and k.cert_id is not null then
    delete from player_certificates where user_id = p_user and cert_id = k.cert_id;
  end if;
  perform bl_ag_log(v_admin, p_user, 'reset_course', jsonb_build_object('course', k.id, 'name', k.name, 'was', e.status, 'classes_done', e.classes_done, 'cert_revoked', coalesce(p_revoke_cert, false), 'reason', v_reason));
  perform bl_ag_alert(p_user, 'admin_take', k.name || ' reset', 'An admin reset your ' || k.name || ' course.', v_reason);
  return jsonb_build_object('message', k.name || ' reset for @' || p.username || '.');
end $$;

-- ---------------------------------------------------------------------
-- 6. Read side: the player's numbers and what can be granted
-- ---------------------------------------------------------------------
create or replace function public.admin_grant_state(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p profiles; n profiles; v_now timestamptz := bl_now(); r player_path; y yahoo_players;
begin
  perform bl_admin_guard();
  select * into p from profiles where id = p_user;
  if not found then
    perform bl_ag_fail('That player doesn''t exist.', 'no_player');
  end if;
  n := bl_decay_row(p, v_now);                           -- needs as the player would see them now
  select * into r from player_path where user_id = p_user;
  select * into y from yahoo_players where user_id = p_user;
  return jsonb_build_object(
    'id', p.id, 'username', p.username, 'banned', p.banned, 'gender', p.gender,
    'career', jsonb_build_object('track', p.job_id, 'track_name', (select name from career_tracks where id = p.job_id), 'level', p.job_level,
      'title', (select title from career_levels where track_id = p.job_id and level = p.job_level), 'xp', p.job_xp,
      'xp_to_next', (select xp_to_next from career_levels where track_id = p.job_id and level = p.job_level),
      'top', (select max(level) from career_levels where track_id = p.job_id), 'on_shift', p.job_shift_ends_at is not null, 'best', p.career_best),
    'status', jsonb_build_object('street_cred', p.street_cred, 'wanted', p.wanted,
      'path', jsonb_build_object('goodwill', coalesce(r.goodwill, 0), 'hustle', coalesce(r.hustle, 0), 'luck', coalesce(r.luck, 0),
                                 'trouble', coalesce(r.trouble, 0), 'faith', coalesce(r.faith, 0), 'family', coalesce(r.family, 0)),
      'yahoo_rank', bl_yahoo_rank(p_user), 'yahoo_total', coalesce(y.total_earned, 0),
      'rent_owed', p.rent_owed, 'tax_owed', p.tax_owed),
    'needs', jsonb_build_object('hunger', round(n.hunger), 'energy', round(n.energy), 'hygiene', round(n.hygiene), 'fun', round(n.fun),
                                'social', round(n.social), 'health', round(n.health), 'stress', round(n.stress), 'bladder', round(coalesce(n.bladder, 100))),
    'states', jsonb_build_object(
      'jail_left', case when p.jailed_until > v_now then ceil(extract(epoch from p.jailed_until - v_now))::int else 0 end, 'jail_reason', p.jail_reason,
      'hospital_left', case when p.hospitalized_until > v_now then ceil(extract(epoch from p.hospitalized_until - v_now))::int else 0 end,
      'busy_left', case when p.busy_until > v_now then ceil(extract(epoch from p.busy_until - v_now))::int else 0 end, 'busy_label', p.busy_label,
      'travelling', p.travel_to is not null, 'travel_to', p.travel_to, 'on_shift', p.job_shift_ends_at is not null,
      'visiting', p.home_visit_host_id is not null),
    'home', jsonb_build_object('start_home', p.start_home, 'name', (select name from start_homes where id = p.start_home), 'kind', bl_housing_kind(p.housing_id),
      'residence', (select jsonb_build_object('role', role, 'property', property_id) from player_residence where user_id = p_user)),
    'garage', (select jsonb_build_object('type', g.garage_type, 'name', t.name) from player_garages g join garage_types t on t.id = g.garage_type where g.user_id = p_user),
    'inventory', coalesce((select jsonb_agg(jsonb_build_object('item', i.item_id, 'name', it.name, 'category', it.category, 'qty', i.qty) order by it.category, it.name)
                             from inventory i join items it on it.id = i.item_id where i.user_id = p_user), '[]'::jsonb),
    'furniture', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'emoji', f.emoji, 'qty', pf.qty, 'house_qty', pf.house_qty, 'max', f.max_qty) order by f.name)
                             from player_furniture pf join furniture f on f.id = pf.furniture_id where pf.user_id = p_user), '[]'::jsonb),
    'wardrobe', coalesce((select jsonb_agg(jsonb_build_object('id', w.item_id, 'name', it.name, 'colour', w.colour) order by it.name)
                            from player_wardrobe w join wardrobe_items it on it.id = w.item_id where w.user_id = p_user), '[]'::jsonb),
    'passes', coalesce((select jsonb_agg(jsonb_build_object('pass', pass_id, 'until', until_at)) from hustle_passes where user_id = p_user and until_at > v_now), '[]'::jsonb),
    'properties', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', bl_prop_name(x), 'area', x.area, 'type', x.type_id, 'listed', x.listed,
                                'lives', exists (select 1 from player_residence r2 where r2.property_id = x.id and r2.user_id = p_user),
                                'occupied', exists (select 1 from player_residence r3 where r3.property_id = x.id), 'built', x.build_id is not null) order by x.acquired_at)
                              from properties x where x.owner_id = p_user), '[]'::jsonb),
    'land', coalesce((select jsonb_agg(jsonb_build_object('market', ip.ref_id, 'name', m.name, 'plots', ip.qty, 'locked', bl_land_locked(p_user, ip.ref_id)) order by m.name)
                        from invest_positions ip join invest_markets m on m.id = ip.ref_id where ip.user_id = p_user and ip.kind = 'land'), '[]'::jsonb),
    'businesses', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'type', t.name, 'icon', t.icon, 'level', b.level, 'max_level', t.max_level,
                                'staff', b.staff, 'staff_slots', t.staff_slots, 'insured_until', b.insured_until, 'stock_until', b.stock_until, 'listed', b.listed) order by b.id)
                              from businesses b join business_types t on t.id = b.type_id where b.owner_id = p_user), '[]'::jsonb),
    'companies', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'logo', c.logo, 'industry', i.name, 'format', hq.format_id, 'staff', c.staff,
                                'slots', bl_co_slots(c.id), 'manager', c.manager, 'generator', c.generator, 'listed', c.listed) order by c.id)
                             from companies c join company_industries i on i.id = c.industry_id
                             left join company_branches hq on hq.company_id = c.id and hq.is_hq where c.owner_id = p_user), '[]'::jsonb),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'rank', m.rank) from crew_members m join crews c on c.id = m.crew_id where m.user_id = p_user),
    'chief', (select jsonb_build_object('tier', ct.tier, 'name', ct.name, 'ward', ct.ward, 'ward_name', (select name from wards where id = ct.ward)) from chief_titles ct where ct.user_id = p_user),
    'courses', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'icon', k.icon, 'classes', k.classes, 'status', coalesce(e.status, 'none'), 'done', coalesce(e.classes_done, 0)) order by k.sort)
                           from courses k left join course_enrolments e on e.course_id = k.id and e.user_id = p_user where k.active), '[]'::jsonb),
    'gist_ban', (select jsonb_build_object('until', until_at, 'reason', reason) from gist_bans where user_id = p_user and (until_at is null or until_at > v_now)));
end $$;

create or replace function public.admin_grant_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform bl_admin_guard();
  return jsonb_build_object(
    'careers', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'emoji', t.emoji,
                  'levels', (select jsonb_agg(jsonb_build_object('level', l.level, 'title', l.title, 'xp_to_next', l.xp_to_next) order by l.level) from career_levels l where l.track_id = t.id)) order by t.sort, t.id)
                  from career_tracks t where t.active), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'category', category, 'icon', icon) order by category, sort, name) from items), '[]'::jsonb),
    'furniture', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'emoji', emoji, 'category', category, 'max', least(max_qty, 20)) order by category, sort, name) from furniture where active), '[]'::jsonb),
    'wardrobe', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'gender', gender, 'colours', to_jsonb(colours)) order by sort, name) from wardrobe_items where active), '[]'::jsonb),
    'garages', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'allowed', to_jsonb(allowed_housing)) order by sort) from garage_types where active), '[]'::jsonb),
    'homes', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'district', district) order by sort) from start_homes where active), '[]'::jsonb),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'label', t.name || ' · ' || a.name) order by a.sort, o.sort)
                          from property_offers o join property_types t on t.id = o.type_id join property_areas a on a.id = o.area where o.active and t.active and a.active), '[]'::jsonb),
    'land', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort) from invest_markets where kind = 'land'), '[]'::jsonb),
    'crews', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'tag', c.tag, 'members', (select count(*) from crew_members m where m.crew_id = c.id)) order by c.name)
                         from crews c where c.disbanded_at is null), '[]'::jsonb),
    'chief_tiers', coalesce((select jsonb_agg(jsonb_build_object('tier', idx, 'name', name) order by idx) from bl_econ_tiers('economy.chief_tiers', 'Chief:10000000')), '[]'::jsonb),
    'wards', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort) from wards where active), '[]'::jsonb),
    'yahoo_ranks', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort) from yahoo_ranks), '[]'::jsonb),
    'passes', coalesce((select jsonb_agg(distinct pass_id) from hustles where pass_id is not null), '[]'::jsonb),
    'company_industries', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'icon', icon) order by sort) from company_industries where active), '[]'::jsonb),
    'company_areas', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort) from company_areas where active), '[]'::jsonb),
    'company_formats', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'staff_slots', staff_slots) order by sort) from company_formats), '[]'::jsonb),
    'path_keys', to_jsonb(bl_path_keys()),
    'needs', jsonb_build_array('hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress', 'bladder'));
end $$;

-- ---------------------------------------------------------------------
-- 7. Privileges
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'admin_business_set(bigint, int, int, int, int, text)',
    'admin_company_grant(uuid, text, text, text, text)', 'admin_company_set(bigint, text, int, boolean, boolean, text)',
    'admin_set_home(uuid, text, uuid, text)', 'admin_give_property(uuid, text, text)', 'admin_take_property(uuid, uuid, text)',
    'admin_give_land(uuid, text, int, text)', 'admin_take_land(uuid, text, int, text)',
    'admin_crew_set(uuid, bigint, text, text)', 'admin_crew_remove(uuid, text)',
    'admin_set_chief_title(uuid, int, text, text)', 'admin_remove_chief_title(uuid, text)',
    'admin_complete_course(uuid, text, text)', 'admin_reset_course(uuid, text, boolean, text)',
    'admin_grant_state(uuid)', 'admin_grant_catalog()'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
