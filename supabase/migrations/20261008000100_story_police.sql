-- E1 first playable slice: weekly stories, robbery case filing, and bail.
-- Story scenes are fictional game situations and do not describe current law.
create table if not exists public.weekly_storyline_catalog (
  id text primary key, title text not null, summary text not null,
  choices jsonb not null check (jsonb_typeof(choices) = 'array'), active boolean not null default true, sort int not null default 0
);
create table if not exists public.weekly_storyline_choices (
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null, episode_id text not null references public.weekly_storyline_catalog(id),
  choice_id text not null, result jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(),
  primary key (user_id, week_start)
);
create table if not exists public.police_cases (
  id bigserial primary key, user_id uuid not null references auth.users(id) on delete cascade,
  event_id bigint references public.events(id) on delete set null,
  location_id text not null references public.locations(id),
  statement text not null check (char_length(statement) between 1 and 400),
  status text not null default 'filed' check (status in ('filed','reviewing','closed')),
  created_at timestamptz not null default now(), unique (user_id, event_id)
);
alter table public.weekly_storyline_catalog enable row level security;
alter table public.weekly_storyline_choices enable row level security;
alter table public.police_cases enable row level security;
revoke all on public.weekly_storyline_catalog, public.weekly_storyline_choices, public.police_cases from public, anon, authenticated;
revoke all on sequence public.police_cases_id_seq from public, anon, authenticated;

insert into public.weekly_storyline_catalog (id,title,summary,choices,sort) values
('community_cleanup','Saturday on the street','Your neighbours are clearing a blocked drain before the rain. The waste team has posted a collection point nearby.',
 '[{"id":"join","label":"Help clear the area","reply":"The neighbours thank you. The street feels lighter already.","effects":{"social":5,"stress":-3,"street_cred":1}},{"id":"organize","label":"Help organize bags and water","reply":"You help the volunteers keep the work moving. Small things make a difference.","effects":{"social":3,"fun":2,"street_cred":1}},{"id":"rest","label":"Wish them well and head home","reply":"You save your energy and leave the cleanup to the people already there.","effects":{"stress":-2,"energy":2}}]'::jsonb,10),
('power_cut','NEPA don take light','The power is out in the neighbourhood. A nearby shop has a small generator running, and people are checking on one another.',
 '[{"id":"check_neighbors","label":"Check on a neighbour","reply":"Aunty Eki says she is alright and shares a cold sachet of water with you.","effects":{"social":4,"stress":-2}},{"id":"charge_phone","label":"Pay to charge your phone","reply":"You get enough battery to call home. The shop owner appreciates your custom.","effects":{"stress":-3,"fun":2}},{"id":"wait","label":"Wait it out at home","reply":"You settle in and let the evening pass quietly.","effects":{"energy":2,"stress":-1}}]'::jsonb,20),
('traffic_checkpoint','A slow evening checkpoint','Traffic is crawling near a fictional checkpoint. Drivers are being asked to pause while officers clear the road.',
 '[{"id":"cooperate","label":"Cooperate and wait your turn","reply":"The stop is brief. You continue your journey calmly.","effects":{"stress":-1,"street_cred":1}},{"id":"ask","label":"Ask politely what is happening","reply":"An officer explains there was a minor obstruction ahead. You move on when the lane clears.","effects":{"social":1,"stress":-1}},{"id":"flee","label":"Ignore the warning and run","reply":"You are stopped and held briefly in this fictional story. Take a moment to cool off.","effects":{"stress":5,"street_cred":-1},"jail_game_minutes":5}]'::jsonb,30)
on conflict (id) do nothing;
insert into public.game_config (key,value,category,label,description,kind,min,max) values
('crime.bail_amount','5000','crime','Bail amount','Game-only bail amount for a short story sentence.','naira',0,100000000),
('storyline.enabled','true','storyline','Weekly stories','Show one rotating community story per Benin Life week.','bool',null,null)
on conflict (key) do nothing;

create or replace function public.bl_current_storyline(p_week date) returns public.weekly_storyline_catalog
language plpgsql stable security definer set search_path = public as $$
declare v_count int; v_index int; v_row public.weekly_storyline_catalog;
begin
 select count(*) into v_count from weekly_storyline_catalog where active;
 if v_count = 0 then return null; end if;
 v_index := mod(greatest(0,(p_week-date '2026-01-05')/7),v_count);
 select * into v_row from weekly_storyline_catalog where active order by sort,id offset v_index limit 1;
 return v_row;
end $$;

create or replace function public.storyline_current() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_week date := date_trunc('week',bl_now() at time zone 'Africa/Lagos')::date;
 v_story public.weekly_storyline_catalog; v_progress public.weekly_storyline_choices; v_choices jsonb;
begin
 if not bl_cfg_bool('storyline.enabled') then return jsonb_build_object('enabled',false,'week_start',v_week); end if;
 v_story := bl_current_storyline(v_week);
 select * into v_progress from weekly_storyline_choices where user_id=v_uid and week_start=v_week;
 select coalesce(jsonb_agg(jsonb_build_object('id',c->>'id','label',c->>'label') order by n),'[]'::jsonb)
 into v_choices from jsonb_array_elements(coalesce(v_story.choices,'[]'::jsonb)) with ordinality x(c,n);
 return jsonb_build_object('enabled',true,'week_start',v_week,
   'episode',jsonb_build_object('id',v_story.id,'title',v_story.title,'summary',v_story.summary,'choices',v_choices),
   'choice',case when v_progress.user_id is null then null else jsonb_build_object('id',v_progress.choice_id,'result',v_progress.result,'created_at',v_progress.created_at) end);
end $$;

create or replace function public.storyline_choose(p_choice text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.profiles := bl_me(); v_week date := date_trunc('week',bl_now() at time zone 'Africa/Lagos')::date;
 v_story public.weekly_storyline_catalog; v_choice jsonb; v_result jsonb; v_effects jsonb; v_jail int; v_until timestamptz;
begin
 if not bl_cfg_bool('storyline.enabled') then raise exception 'Stories are paused for now.' using errcode='P0001',hint='storyline_off'; end if;
 if v_me.travel_to is not null then raise exception 'Wait till you arrive before choosing.' using errcode='P0001',hint='traveling'; end if;
 v_story := bl_current_storyline(v_week);
 select c.choice into v_choice from jsonb_array_elements(v_story.choices) as c(choice) where c.choice->>'id'=p_choice limit 1;
 if v_choice is null then raise exception 'That story choice is not available.' using errcode='P0001',hint='bad_choice'; end if;
 if exists(select 1 from weekly_storyline_choices where user_id=v_me.id and week_start=v_week) then
   raise exception 'You already made this week’s choice.' using errcode='P0001',hint='already_chosen'; end if;
 v_effects := coalesce(v_choice->'effects','{}'::jsonb);
 update profiles set social=greatest(0,least(100,social+coalesce((v_effects->>'social')::numeric,0))),
   stress=greatest(0,least(100,stress+coalesce((v_effects->>'stress')::numeric,0))),
   fun=greatest(0,least(100,fun+coalesce((v_effects->>'fun')::numeric,0))),
   energy=greatest(0,least(100,energy+coalesce((v_effects->>'energy')::numeric,0))),
   street_cred=greatest(0,street_cred+coalesce((v_effects->>'street_cred')::int,0)) where id=v_me.id;
 v_jail := greatest(0,least(10,coalesce((v_choice->>'jail_game_minutes')::int,0)));
 if v_jail>0 then v_until := bl_jail(v_me.id,v_jail,'Held briefly after a reckless choice in a fictional Benin Life story.'); end if;
 v_result := jsonb_build_object('reply',v_choice->>'reply','jail_until',v_until);
 insert into weekly_storyline_choices(user_id,week_start,episode_id,choice_id,result,created_at)
 values(v_me.id,v_week,v_story.id,p_choice,v_result,bl_now());
 perform bl_event(v_me.id,'story_choice',v_story.title,coalesce(v_choice->>'reply',''),jsonb_build_object('episode',v_story.id,'choice',p_choice,'week_start',v_week));
 return jsonb_build_object('message',v_choice->>'reply','jailed_until',v_until,'story',public.storyline_current());
end $$;

create or replace function public.police_cases_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
 return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'event_id',c.event_id,'location_id',c.location_id,
   'statement',c.statement,'status',c.status,'created_at',c.created_at,'event_title',e.title,'event_body',e.body) order by c.id desc)
   from police_cases c left join events e on e.id=c.event_id where c.user_id=v_uid),'[]'::jsonb);
end $$;

create or replace function public.police_report_robbery(p_event_id bigint,p_statement text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.profiles := bl_me(); v_event public.events;
 v_statement text := regexp_replace(coalesce(p_statement,''),'[[:cntrl:]]+',' ','g'); v_id bigint;
begin
 if v_me.travel_to is not null then raise exception 'You can file this after you arrive.' using errcode='P0001',hint='traveling'; end if;
 if not exists(select 1 from locations where id=v_me.location_id and scene='police')
    and not(v_me.jailed_until is not null and v_me.jailed_until>bl_now()) then
   raise exception 'Go to Police HQ to file your report.' using errcode='P0001',hint='not_at_station'; end if;
 if char_length(btrim(v_statement))<8 or char_length(v_statement)>400 then
   raise exception 'Add a short statement between 8 and 400 characters.' using errcode='P0001',hint='bad_statement'; end if;
 select * into v_event from events where id=p_event_id and user_id=v_me.id and kind='robbed' for share;
 if not found then raise exception 'That robbery alert is not available to report.' using errcode='P0001',hint='no_robbery'; end if;
 insert into police_cases(user_id,event_id,location_id,statement,created_at)
 values(v_me.id,p_event_id,v_me.location_id,btrim(v_statement),bl_now())
 on conflict(user_id,event_id) do nothing returning id into v_id;
 if v_id is null then raise exception 'You already filed a report for that alert.' using errcode='P0001',hint='already_reported'; end if;
 perform bl_event(v_me.id,'police_report','Report filed','Police HQ has logged your robbery report. Keep the case number.',jsonb_build_object('case_id',v_id,'event_id',p_event_id));
 return jsonb_build_object('message','Your report has been filed at Police HQ.','case_id',v_id);
end $$;

create or replace function public.police_bail() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me public.profiles := bl_me(); v_cost bigint := greatest(0,round(bl_cfg('crime.bail_amount'))::bigint);
 v_from_bank bigint; v_from_cash bigint;
begin
 if v_me.jailed_until is null or v_me.jailed_until<=bl_now() then raise exception 'You are not in a cell right now.' using errcode='P0001',hint='not_jailed'; end if;
 v_from_bank := least(v_me.bank,v_cost); v_from_cash := v_cost-v_from_bank;
 if v_from_cash>v_me.cash then raise exception 'Bail is % (bank first, then cash). You have % total.',bl_naira(v_cost),bl_naira(v_me.bank+v_me.cash) using errcode='P0001',hint='not_enough_money'; end if;
 if v_from_bank>0 then perform bl_add_money(v_me.id,'bank',-v_from_bank,'police_bail',jsonb_build_object('bank_first',true)); end if;
 if v_from_cash>0 then perform bl_add_money(v_me.id,'cash',-v_from_cash,'police_bail',jsonb_build_object('bank_first',true)); end if;
 update profiles set jailed_until=null,jail_reason=null,wanted=greatest(0,wanted-1) where id=v_me.id;
 perform bl_event(v_me.id,'police_release','You are released','Bail has been paid. You are free to go.',jsonb_build_object('paid',v_cost));
 return jsonb_build_object('message','Bail paid. You are free to go.','paid',v_cost,'bank',v_from_bank,'cash',v_from_cash);
end $$;

revoke execute on function public.bl_current_storyline(date) from public,anon,authenticated;
revoke execute on function public.storyline_current() from public,anon;
revoke execute on function public.storyline_choose(text) from public,anon;
revoke execute on function public.police_cases_list() from public,anon;
revoke execute on function public.police_report_robbery(bigint,text) from public,anon;
revoke execute on function public.police_bail() from public,anon;
grant execute on function public.storyline_current() to authenticated;
grant execute on function public.storyline_choose(text) to authenticated;
grant execute on function public.police_cases_list() to authenticated;
grant execute on function public.police_report_robbery(bigint,text) to authenticated;
grant execute on function public.police_bail() to authenticated;
