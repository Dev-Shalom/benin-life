-- Daily return pack, part 4: the HUD "Today" card (docs/DAILY_RETURN.md).
-- today_card(): ONE call that gathers every daily reason to open the game, built from the functions that already exist
-- (daily_reward_status, gem_hunt_status, bl_story_badge, weekly_calendar) plus the things that need the player (a child, rent,
-- business takings, a waiting welcome-back gift). Read-only apart from what those functions already do. Idempotent.

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('return.today_enabled', 'true', 'return', 'Today card on', 'The compact "Today" card on the game screen: daily reward, today''s story, gem hunt, today''s event and anything that needs the player, one tap each. Off = the card is hidden.', 'bool', null, null)
on conflict (key) do nothing;

create or replace function public.today_card() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_me profiles; v_now timestamptz := bl_now(); v_today date := bl_wat_date(v_now);
  v_rw jsonb; v_step jsonb; v_reward jsonb := null;
  v_gem jsonb; v_gems jsonb := null;
  v_sb jsonb; v_story jsonb := null;
  v_cal jsonb; v_ev jsonb := null;
  v_needs jsonb := '[]'::jsonb; v_kid text; v_n int := 0; g return_gifts; v_gift jsonb := null; it items; v_biz text; v_due int;
begin
  select * into v_me from profiles where id = v_uid;
  if not found or v_me.banned or not coalesce(bl_cfg_bool('return.today_enabled'), true) then
    return jsonb_build_object('enabled', false, 'count', 0);
  end if;

  -- daily reward
  begin
    v_rw := daily_reward_status();
    if coalesce((v_rw->>'enabled')::boolean, false) then
      v_step := v_rw -> 'steps' -> (greatest(1, coalesce((v_rw->>'day')::int, 1)) - 1);
      v_reward := jsonb_build_object('ready', coalesce((v_rw->>'ready')::boolean, false), 'day', (v_rw->>'day')::int,
                    'cash', (v_step->>'cash')::bigint, 'item_name', v_step->>'item_name');
      if (v_reward->>'ready')::boolean then v_n := v_n + 1; end if;
    end if;
  exception when others then v_reward := null; end;

  -- today's story
  begin
    v_sb := bl_story_badge(v_uid);
    if coalesce(bl_cfg_bool('stories.daily_enabled'), true) then
      v_story := jsonb_build_object('waiting', coalesce((v_sb->>'waiting')::int, 0), 'chapters', coalesce((v_sb->>'chapters')::int, 0));
      if (v_story->>'waiting')::int > 0 then v_n := v_n + 1; end if;
    end if;
  exception when others then v_story := null; end;

  -- gem hunt
  begin
    v_gem := gem_hunt_status();
    if coalesce((v_gem->>'enabled')::boolean, false) and coalesce((v_gem->>'total')::int, 0) > 0 then
      v_gems := jsonb_build_object('found', (v_gem->>'found')::int, 'total', (v_gem->>'total')::int, 'next_prize', (v_gem->>'next_prize')::bigint);
      if (v_gem->>'found')::int < (v_gem->>'total')::int then v_n := v_n + 1; end if;
    end if;
  exception when others then v_gems := null; end;

  -- today's weekly event
  begin
    v_cal := weekly_calendar();
    if coalesce((v_cal->>'enabled')::boolean, false) and v_cal->'today_event' <> 'null'::jsonb then
      v_ev := v_cal -> 'today_event';
      if coalesce((v_ev->>'checkin')::boolean, false) and not coalesce((v_ev->>'checked_in')::boolean, false) then v_n := v_n + 1; end if;
    end if;
  exception when others then v_ev := null; end;

  -- welcome-back gift waiting
  begin
    if coalesce(bl_cfg_bool('return.gift_enabled'), false) then
      select * into g from return_gifts where user_id = v_uid and claimed_at is null
         and created_at > now() - make_interval(days => greatest(1, bl_cfg('return.gift_keep_days'))::int);
      if found then
        if g.item_id is not null then select * into it from items where id = g.item_id; end if;
        v_gift := jsonb_build_object('cash', g.cash, 'away_days', g.away_days, 'item_name', it.name);
        v_n := v_n + 1;
      end if;
    end if;
  exception when others then v_gift := null; end;

  -- something needs you: a child, rent, takings
  begin
    if bl_kids_on() then
      select coalesce(k.name, 'Your baby') into v_kid from kids_children k
       where k.status = 'home' and (k.parent_a = v_uid or k.parent_b = v_uid) and k.alerts_unanswered > 0 order by k.next_alert_at limit 1;
      if found then
        v_needs := v_needs || jsonb_build_array(jsonb_build_object('kind', 'kid', 'icon', '👶', 'text', v_kid || ' needs you', 'go', 'family:family'));
      end if;
    end if;
  exception when others then null; end;
  begin
    if coalesce(bl_cfg_bool('rent.enabled'), false) and v_me.weekly_rent > 0 then
      if v_me.rent_owed > 0 then
        v_needs := v_needs || jsonb_build_array(jsonb_build_object('kind', 'rent', 'icon', '🏠', 'text', 'Rent owed: ' || bl_naira(v_me.rent_owed), 'go', 'bank'));
      elsif v_me.rent_due_at is not null then
        v_due := bl_wat_date(v_me.rent_due_at) - v_today;
        if v_due between 0 and 1 then
          v_needs := v_needs || jsonb_build_array(jsonb_build_object('kind', 'rent', 'icon', '🏠', 'text', case when v_due = 0 then 'Rent is due today: ' else 'Rent is due tomorrow: ' end || bl_naira(v_me.weekly_rent), 'go', 'bank'));
        end if;
      end if;
    end if;
  exception when others then null; end;
  begin
    select b.name into v_biz from businesses b
     where b.owner_id = v_uid and not b.listed and b.ready_at <= v_now
       and b.last_collect_at <= v_now - make_interval(hours => greatest(1, bl_cfg('return.takings_hours'))::int)
     order by b.last_collect_at limit 1;
    if found then
      v_needs := v_needs || jsonb_build_array(jsonb_build_object('kind', 'takings', 'icon', '💰', 'text', v_biz || ': takings are ready', 'go', 'business'));
    end if;
  exception when others then null; end;
  v_n := v_n + jsonb_array_length(v_needs);

  return jsonb_build_object('enabled', true, 'date', v_today, 'count', v_n, 'reward', v_reward, 'story', v_story, 'gems', v_gems,
                            'event', v_ev, 'gift', v_gift, 'needs', v_needs);
end $$;

revoke all on function public.today_card() from public, anon;
grant execute on function public.today_card() to authenticated;

notify pgrst, 'reload schema';
