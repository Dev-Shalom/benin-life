-- Gang wording: players and admins now see "Gang" where the game said "Crew".
-- Internal ids are untouched: tables, columns, RPC names, crew.* config keys, ledger reason ids (crew_payout ...), routes, /play?go=crew.
-- (1) Player-visible literals inside live function bodies are patched with guarded, exact-literal replaces (never a regex over a body).
-- (2) Seeded display text (levels, job blurbs, group missions, config labels / descriptions, skill source notes) is updated only
--     where the row still holds the seeded text, so anything an admin edited is left alone.
-- Idempotent: a literal already patched is skipped; a literal that is neither old nor new raises. CREATE OR REPLACE keeps grants, and
-- the private bl_* helpers are checked to stay closed to anon / authenticated.

do $$
declare
  r record;
  v_def text;
  v_new text;
  v_changed int;
begin
  create temp table _gang_lit (sig text, old_lit text, new_lit text) on commit drop;
  insert into _gang_lit values
    ($q$bl_crew_bank(bigint,uuid,bigint,text,text)$q$, $q$'The crew bank no reach for that.'$q$, $q$'The gang bank no reach for that.'$q$),
    ($q$bl_crew_add_member(bigint,uuid,text)$q$, $q$' joined the crew'$q$, $q$' joined the gang'$q$),
    ($q$bl_crew_bust(uuid,bigint,text)$q$, $q$' job went bad and the police caught the whole crew. Open the popup to pay bail, serve time or try to escape.'$q$, $q$' job went bad and the police caught the whole gang. Open the popup to pay bail, serve time or try to escape.'$q$),
    ($q$bl_crew_bust(uuid,bigint,text)$q$, $q$'Caught on a crew job: '$q$, $q$'Caught on a gang job: '$q$),
    ($q$bl_crew_bust(uuid,bigint,text)$q$, $q$'Police don catch the crew!'$q$, $q$'Police don catch the gang!'$q$),
    ($q$bl_crew_found_gate(uuid)$q$, $q$'To found a crew you need '$q$, $q$'To start a gang you need '$q$),
    ($q$bl_crew_found_gate(uuid)$q$, $q$'You are already in a crew. Leave it first.'$q$, $q$'You are already in a gang. Leave it first.'$q$),
    ($q$bl_crew_found_gate(uuid)$q$, $q$'You left a crew recently. You can found or join another in about '$q$, $q$'You left a gang recently. You can start or join another in about '$q$),
    ($q$bl_crew_gate(uuid,text)$q$, $q$'Be at a crew meeting spot: '$q$, $q$'Be at a gang meeting spot: '$q$),
    ($q$bl_crew_job_json(crew_jobs,crews,uuid[])$q$, $q$'Needs crew level '$q$, $q$'Needs gang level '$q$),
    ($q$bl_crew_name_check(text,text,bigint)$q$, $q$'Another crew already uses that name.'$q$, $q$'Another gang already uses that name.'$q$),
    ($q$bl_crew_name_check(text,text,bigint)$q$, $q$'Another crew already uses that tag.'$q$, $q$'Another gang already uses that tag.'$q$),
    ($q$bl_crew_name_check(text,text,bigint)$q$, $q$'Choose a cleaner name for your crew.'$q$, $q$'Choose a cleaner name for your gang.'$q$),
    ($q$bl_crew_name_check(text,text,bigint)$q$, $q$'Crew name must be 3 to 20 letters or numbers.'$q$, $q$'Gang name must be 3 to 20 letters or numbers.'$q$),
    ($q$bl_crew_run_start(bigint)$q$, $q$' in the crew. Nobody move.'$q$, $q$' in the gang. Nobody move.'$q$),
    ($q$bl_crew_run_start(bigint)$q$, $q$'Crew job supplies: '$q$, $q$'Gang job supplies: '$q$),
    ($q$bl_crew_run_start(bigint)$q$, $q$'Crew job: '$q$, $q$'Gang job: '$q$),
    ($q$bl_crew_run_start(bigint)$q$, $q$'You are no longer in the crew.'$q$, $q$'You are no longer in the gang.'$q$),
    ($q$bl_crew_run_start(bigint)$q$, $q$'You miss the crew job'$q$, $q$'You miss the gang job'$q$),
    ($q$bl_crew_week_settle()$q$, $q$' is in the crew bank.'$q$, $q$' is in the gang bank.'$q$),
    ($q$bl_crew_week_settle()$q$, $q$'Top crews, week of '$q$, $q$'Top gangs, week of '$q$),
    ($q$bl_crew_week_settle()$q$, $q$'Your crew did '$q$, $q$'Your gang did '$q$),
    ($q$bl_crew_week_settle()$q$, $q$'🥇 Top crew of the week!'$q$, $q$'🥇 Top gang of the week!'$q$),
    ($q$bl_crew_week_settle()$q$, $q$'🥈 2nd top crew of the week!'$q$, $q$'🥈 2nd top gang of the week!'$q$),
    ($q$bl_crew_week_settle()$q$, $q$'🥉 3rd top crew of the week!'$q$, $q$'🥉 3rd top gang of the week!'$q$),
    ($q$crew_create(text,text,text,text)$q$, $q$'Crew: founding fee for '$q$, $q$'Gang: start fee for '$q$),
    ($q$crew_create(text,text,text,text)$q$, $q$'Pick a colour for the crew.'$q$, $q$'Pick a colour for the gang.'$q$),
    ($q$crew_create(text,text,text,text)$q$, $q$'That crew name or tag was just taken. Try another one.'$q$, $q$'That gang name or tag was just taken. Try another one.'$q$),
    ($q$crew_invite(uuid,text)$q$, $q$' invite you to a crew '$q$, $q$' invite you to a gang '$q$),
    ($q$crew_invite(uuid,text)$q$, $q$' wan make you join their crew. Open the Crew app to accept or pass.'$q$, $q$' wan make you join their gang. Open the Gang app to accept or pass.'$q$),
    ($q$crew_invite(uuid,text)$q$, $q$'@% already has an invite from your crew.'$q$, $q$'@% already has an invite from your gang.'$q$),
    ($q$crew_invite(uuid,text)$q$, $q$'The crew is full for its level. Upgrade the crew to take more members.'$q$, $q$'The gang is full for its level. Upgrade the gang to take more members.'$q$),
    ($q$crew_invite(uuid,text)$q$, $q$'You are already in your own crew.'$q$, $q$'You are already in your own gang.'$q$),
    ($q$crew_invite_respond(bigint,boolean)$q$, $q$'That crew is full right now.'$q$, $q$'That gang is full right now.'$q$),
    ($q$crew_kick(uuid)$q$, $q$' removed from the crew.'$q$, $q$' removed from the gang.'$q$),
    ($q$crew_kick(uuid)$q$, $q$'That person is not in your crew.'$q$, $q$'That person is not in your gang.'$q$),
    ($q$crew_kick(uuid)$q$, $q$'The crew leaders removed you. You can join another crew later.'$q$, $q$'The gang leaders removed you. You can join another gang later.'$q$),
    ($q$crew_transfer(uuid)$q$, $q$'Pick another member of your crew.'$q$, $q$'Pick another member of your gang.'$q$),
    ($q$crew_rename(text)$q$, $q$'Another crew already uses that name.'$q$, $q$'Another gang already uses that name.'$q$),
    ($q$crew_rename(text)$q$, $q$'That is already the crew name.'$q$, $q$'That is already the gang name.'$q$),
    ($q$crew_rename(text)$q$, $q$'The crew bank needs % for a rename.'$q$, $q$'The gang bank needs % for a rename.'$q$),
    ($q$crew_rename(text)$q$, $q$'The crew is now '$q$, $q$'The gang is now '$q$),
    ($q$crew_rename(text)$q$, $q$'You renamed the crew recently. Wait a few days.'$q$, $q$'You renamed the gang recently. Wait a few days.'$q$),
    ($q$crew_deposit(bigint)$q$, $q$' is in the crew bank.'$q$, $q$' is in the gang bank.'$q$),
    ($q$crew_deposit(bigint)$q$, $q$'Crew bank: '$q$, $q$'Gang bank: '$q$),
    ($q$crew_report(bigint,text)$q$, $q$'That crew no dey again.'$q$, $q$'That gang no dey again.'$q$),
    ($q$crew_report(bigint,text)$q$, $q$'You cannot report your own crew. Leave it instead.'$q$, $q$'You cannot report your own gang. Leave it instead.'$q$),
    ($q$crew_job_join(bigint)$q$, $q$'The crew for this job is full.'$q$, $q$'The gang for this job is full.'$q$),
    ($q$bl_crew_guard(boolean)$q$, $q$'Crews are switched off for now. Try again later.'$q$, $q$'Gangs are switched off for now. Try again later.'$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$' The crew bank paid '$q$, $q$' The gang bank paid '$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$' crew XP.'$q$, $q$' gang XP.'$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$' loot is in your cash. Part of it went to the crew bank.'$q$, $q$' loot is in your cash. Part of it went to the gang bank.'$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$' of the crew.'$q$, $q$' of the gang.'$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$'Crew job: '$q$, $q$'Gang job: '$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$'Crew job:%'$q$, $q$'Gang job:%'$q$),
    ($q$bl_crew_run_resolve(bigint)$q$, $q$'The police caught the whole crew.'$q$, $q$'The police caught the whole gang.'$q$),
    ($q$bl_yahoo_group_start(bigint)$q$, $q$' in the crew. Laptops open, nobody move.'$q$, $q$' in the gang. Laptops open, nobody move.'$q$),
    ($q$bl_yahoo_bust(uuid,bigint,text,text,text)$q$, $q$'EFCC caught you and the crew doing Yahoo work.'$q$, $q$'EFCC caught you and the gang doing Yahoo work.'$q$),
    ($q$bl_yahoo_group_notify(uuid,profiles,group_missions,bigint)$q$, $q$' · tap to join the crew.'$q$, $q$' · tap to join the gang.'$q$),
    ($q$yahoo_group_create(text,uuid[])$q$, $q$'Group mission open. Waiting for the crew…'$q$, $q$'Group mission open. Waiting for the gang…'$q$),
    ($q$yahoo_group_respond(bigint,boolean)$q$, $q$'You don join the crew.'$q$, $q$'You don join the gang.'$q$),
    ($q$yahoo_group_respond(bigint,boolean)$q$, $q$'You no dey that crew.'$q$, $q$'You no dey that gang.'$q$),
    ($q$yahoo_group_start(bigint)$q$, $q$'You need at least % in the crew to start (% ready).'$q$, $q$'You need at least % in the gang to start (% ready).'$q$),
    ($q$bl_yahoo_group_gate(uuid,group_missions,text)$q$, $q$'Everybody in the crew needs a laptop. Check Bronze Tech Hub or the Wi-Fi Joint.'$q$, $q$'Everybody in the gang needs a laptop. Check Bronze Tech Hub or the Wi-Fi Joint.'$q$),
    ($q$crew_join_open(bigint)$q$, $q$'That crew is full right now.'$q$, $q$'That gang is full right now.'$q$),
    ($q$crew_join_open(bigint)$q$, $q$'That crew is not taking walk-ins. Ask for an invite.'$q$, $q$'That gang is not taking walk-ins. Ask for an invite.'$q$),
    ($q$crew_join_open(bigint)$q$, $q$'That crew no dey again.'$q$, $q$'That gang no dey again.'$q$),
    ($q$pol_back(bigint,text)$q$, $q$'Only a crew Boss or Lieutenant can endorse for the crew.'$q$, $q$'Only a gang Boss or Lieutenant can endorse for the gang.'$q$),
    ($q$pol_back(bigint,text)$q$, $q$'Your crew needs at least % members to endorse.'$q$, $q$'Your gang needs at least % members to endorse.'$q$),
    ($q$bl_crew_join_gate(uuid)$q$, $q$'Already in a crew.'$q$, $q$'Already in a gang.'$q$),
    ($q$bl_crew_join_gate(uuid)$q$, $q$'Left a crew recently: wait about '$q$, $q$'Left a gang recently: wait about '$q$),
    ($q$bl_crew_join_gate(uuid)$q$, $q$'New accounts can join a crew after '$q$, $q$'New accounts can join a gang after '$q$),
    ($q$bl_crew_join_gate(uuid)$q$, $q$'That player cannot join a crew.'$q$, $q$'That player cannot join a gang.'$q$),
    ($q$bl_crew_need(uuid,integer,boolean)$q$, $q$'You are not in a crew.'$q$, $q$'You are not in a gang.'$q$),
    ($q$crew_options(numeric,boolean)$q$, $q$'Crew settings saved.'$q$, $q$'Gang settings saved.'$q$),
    ($q$admin_crew_get(bigint)$q$, $q$'No such crew.'$q$, $q$'No such gang.'$q$),
    ($q$admin_crew_disband(bigint,text)$q$, $q$'That crew is gone already.'$q$, $q$'That gang is gone already.'$q$),
    ($q$bl_ledger_label(text,jsonb)$q$, $q$'Crew bank deposit'$q$, $q$'Gang bank deposit'$q$),
    ($q$bl_ledger_label(text,jsonb)$q$, $q$'Crew founding fee'$q$, $q$'Gang start fee'$q$),
    ($q$bl_ledger_label(text,jsonb)$q$, $q$'Crew job loot'$q$, $q$'Gang job loot'$q$),
    ($q$bl_ledger_label(text,jsonb)$q$, $q$'Crew job supplies'$q$, $q$'Gang job supplies'$q$),
    ($q$bl_ledger_label(text,jsonb)$q$, $q$'Crew refund'$q$, $q$'Gang refund'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'Crew bank returned: '$q$, $q$'Gang bank returned: '$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'Crew disbanded: bank shared out'$q$, $q$'Gang disbanded: bank shared out'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'Crew job supplies refunded'$q$, $q$'Gang job supplies refunded'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'Crew job:%'$q$, $q$'Gang job:%'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'That crew is gone already.'$q$, $q$'That gang is gone already.'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'The crew is closed.'$q$, $q$'The gang is closed.'$q$),
    ($q$bl_crew_dissolve(bigint,uuid,text)$q$, $q$'The crew was disbanded.'$q$, $q$'The gang was disbanded.'$q$),
    ($q$crew_leave()$q$, $q$' left the crew'$q$, $q$' left the gang'$q$),
    ($q$crew_leave()$q$, $q$'. You can join another crew in '$q$, $q$'. You can join another gang in '$q$),
    ($q$crew_leave()$q$, $q$'You are the Boss. Transfer the Boss rank first, or disband the crew.'$q$, $q$'You are the Boss. Transfer the Boss rank first, or disband the gang.'$q$),
    ($q$crew_set_rank(uuid,text)$q$, $q$'Your crew rank changed'$q$, $q$'Your gang rank changed'$q$),
    ($q$crew_upgrade()$q$, $q$'The crew bank needs % (it has %).'$q$, $q$'The gang bank needs % (it has %).'$q$),
    ($q$crew_upgrade()$q$, $q$'The crew needs % XP (it has %). Pull more jobs.'$q$, $q$'The gang needs % XP (it has %). Pull more jobs.'$q$),
    ($q$crew_upgrade()$q$, $q$'Your crew is at the top level.'$q$, $q$'Your gang is at the top level.'$q$),
    ($q$crew_job_open(text)$q$, $q$' is gathering the crew'$q$, $q$' is gathering the gang'$q$),
    ($q$crew_job_open(text)$q$, $q$'Go to a meeting spot and join in the Crew app. Starts in about '$q$, $q$'Go to a meeting spot and join in the Gang app. Starts in about '$q$),
    ($q$crew_job_open(text)$q$, $q$'Lobby open. Wait for your crew at the meeting spot.'$q$, $q$'Lobby open. Wait for your gang at the meeting spot.'$q$),
    ($q$crew_job_open(text)$q$, $q$'The crew already has a job open or running.'$q$, $q$'The gang already has a job open or running.'$q$),
    ($q$crew_job_open(text)$q$, $q$'The crew has done enough jobs today. Rest.'$q$, $q$'The gang has done enough jobs today. Rest.'$q$),
    ($q$crew_job_open(text)$q$, $q$'The crew must lie low on this one for about % minutes.'$q$, $q$'The gang must lie low on this one for about % minutes.'$q$),
    ($q$crew_job_open(text)$q$, $q$'This job needs % crew members. Recruit more.'$q$, $q$'This job needs % gang members. Recruit more.'$q$),
    ($q$crew_job_open(text)$q$, $q$'Your crew must be level % for this job.'$q$, $q$'Your gang must be level % for this job.'$q$),
    ($q$admin_crew_rename(bigint,text,text,text)$q$, $q$'An admin renamed the crew to '$q$, $q$'An admin renamed the gang to '$q$),
    ($q$admin_crew_rename(bigint,text,text,text)$q$, $q$'Crew renamed.'$q$, $q$'Gang renamed.'$q$),
    ($q$admin_crew_rename(bigint,text,text,text)$q$, $q$'That crew is gone already.'$q$, $q$'That gang is gone already.'$q$),
    ($q$admin_crew_rename(bigint,text,text,text)$q$, $q$'Your crew was renamed'$q$, $q$'Your gang was renamed'$q$);

  for r in select sig from _gang_lit group by sig order by sig loop
    if to_regprocedure('public.' || r.sig) is null then
      raise exception 'gang wording: function % not found', r.sig;
    end if;
    select pg_get_functiondef(to_regprocedure('public.' || r.sig)) into v_def;
    v_new := v_def;
    v_changed := 0;
    declare l record;
    begin
      for l in select old_lit, new_lit from _gang_lit where sig = r.sig order by length(old_lit) desc loop
        if position(l.old_lit in v_new) > 0 then
          v_new := replace(v_new, l.old_lit, l.new_lit);
          v_changed := v_changed + 1;
        elsif position(l.new_lit in v_new) = 0 then
          raise exception 'gang wording: % has neither % nor %', r.sig, l.old_lit, l.new_lit;
        end if;
      end loop;
    end;
    if v_changed > 0 then
      execute v_new;
    end if;
  end loop;

  -- the private bl_* helpers touched above stay closed to the API roles (CREATE OR REPLACE keeps the grants; this is belt and braces)
  for r in select distinct sig from _gang_lit where sig like 'bl\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', to_regprocedure('public.' || r.sig));
  end loop;
end $$;

-- ledger and busy labels already written use the new prefix too, so the "Crew job:" busy clear still finds running jobs
update profiles set busy_label = 'Gang job:' || substr(busy_label, length('Crew job:') + 1) where busy_label like 'Crew job:%';
update profiles set busy_label = 'Yahoo: Gang hustle' where busy_label = 'Yahoo: Crew hustle';

-- seeded names and blurbs, only where still the seeded text
update crew_levels set name = 'Street gang'      where level = 1 and name = 'Street crew';
update crew_levels set name = 'Block gang'       where level = 2 and name = 'Block crew';
update crew_levels set name = 'District gang'    where level = 3 and name = 'District crew';
update crew_levels set name = 'City gang'        where level = 4 and name = 'City crew';
update crew_levels set name = 'Big name gang'    where level = 5 and name = 'Big name crew';
update crew_jobs set blurb = 'One container, one night, one big gang. Everybody must show face.'
  where id = 'port_container' and blurb = 'One container, one night, one big crew. Everybody must show face.';
update group_missions set name = 'Gang hustle' where id = 'crew_hustle' and name = 'Crew hustle';
update group_missions set blurb = 'The whole HK gang on one big table. Plenty money, plenty EFCC.'
  where id = 'hk_big_table' and blurb = 'The whole HK crew on one big table. Plenty money, plenty EFCC.';
update skill_sources set note = 'Gang hustle (group mission)' where note = 'Crew hustle (group mission)';
update skill_sources set note = substr(note, 1, length(note) - length('(crew job)')) || '(gang job)' where kind = 'crew' and note like '% (crew job)';

-- config labels and descriptions, only where still the seeded text
update game_config g set label = v.new_text from (values
  ($q$crew.blocked_names$q$, $q$Blocked words in crew names$q$, $q$Blocked words in gang names$q$),
  ($q$crew.bust_fine_pct$q$, $q$Busted job: crew bank fine (%)$q$, $q$Busted job: gang bank fine (%)$q$),
  ($q$crew.chat_burst_per_minute$q$, $q$Crew chat: messages per minute$q$, $q$Gang chat: messages per minute$q$),
  ($q$crew.chat_max_len$q$, $q$Crew chat: longest message$q$, $q$Gang chat: longest message$q$),
  ($q$crew.chat_rate_seconds$q$, $q$Crew chat: seconds between messages$q$, $q$Gang chat: seconds between messages$q$),
  ($q$crew.chat_retention_hours$q$, $q$Crew chat: keep messages (hours)$q$, $q$Gang chat: keep messages (hours)$q$),
  ($q$crew.disband_fee_pct$q$, $q$Disband fee (share of the crew bank)$q$, $q$Disband fee (share of the gang bank)$q$),
  ($q$crew.earn_seeded$q$, $q$Crew loot counted as earned (seeded)$q$, $q$Gang loot counted as earned (seeded)$q$),
  ($q$crew.enabled$q$, $q$Crews on$q$, $q$Gangs on$q$),
  ($q$crew.invite_daily_cap$q$, $q$Invites per crew per day$q$, $q$Invites per gang per day$q$),
  ($q$crew.max_jobs_per_day$q$, $q$Jobs per crew per day$q$, $q$Jobs per gang per day$q$),
  ($q$crew.max_lieutenants$q$, $q$Most Lieutenants per crew$q$, $q$Most Lieutenants per gang$q$),
  ($q$crew.rename_fee$q$, $q$Rename fee (paid from the crew bank)$q$, $q$Rename fee (paid from the gang bank)$q$),
  ($q$crew.report_flag_count$q$, $q$Reports that flag a crew$q$, $q$Reports that flag a gang$q$),
  ($q$crew.weekly_enabled$q$, $q$Top crews weekly prize on$q$, $q$Top gangs weekly prize on$q$),
  ($q$crew.weekly_min_jobs$q$, $q$Jobs a crew needs for a prize$q$, $q$Jobs a gang needs for a prize$q$),
  ($q$crew.weekly_prize_1$q$, $q$Top crews prize: 1st$q$, $q$Top gangs prize: 1st$q$),
  ($q$crew.weekly_prize_2$q$, $q$Top crews prize: 2nd$q$, $q$Top gangs prize: 2nd$q$),
  ($q$crew.weekly_prize_3$q$, $q$Top crews prize: 3rd$q$, $q$Top gangs prize: 3rd$q$),
  ($q$pol.crew_endorse_min_members$q$, $q$Crew endorsement needs members$q$, $q$Gang endorsement needs members$q$),
  ($q$pol.crew_endorse_points$q$, $q$Crew endorsement: points$q$, $q$Gang endorsement: points$q$)
) as v(key, old_text, new_text) where g.key = v.key and g.label = v.old_text;

update game_config g set description = v.new_text from (values
  ($q$crew.bank_pct_min$q$, $q$R11: so a crew always funds its bank a little.$q$, $q$R11: so a gang always funds its bank a little.$q$),
  ($q$crew.blocked_names$q$, $q$R11: comma-separated. Real cult and gang names must never be used, so a crew name that contains any of these (ignoring spaces and punctuation) is refused. Add more as you hear them.$q$, $q$R11: comma-separated. Real cult and gang names must never be used, so a gang name that contains any of these (ignoring spaces and punctuation) is refused. Add more as you hear them.$q$),
  ($q$crew.blocked_tags$q$, $q$R11: comma-separated, 3 or 4 letters. A crew tag in this list is refused.$q$, $q$R11: comma-separated, 3 or 4 letters. A gang tag in this list is refused.$q$),
  ($q$crew.bust_fine_pct$q$, $q$R11: part of the crew bank is lost to legal fees when a job is busted.$q$, $q$R11: part of the gang bank is lost to legal fees when a job is busted.$q$),
  ($q$crew.default_bank_pct$q$, $q$R11: a new crew puts this % of every payout into the crew bank. The Boss can change it inside the limits below.$q$, $q$R11: a new gang puts this % of every payout into the gang bank. The Boss can change it inside the limits below.$q$),
  ($q$crew.disband_fee_pct$q$, $q$E3: when a Boss disbands the crew, this percent of the bank is kept as legal fees and the rest is shared to the members. Stops disbanding being a free way to move money between accounts. 0 = no fee. An admin disband never charges it.$q$, $q$E3: when a Boss disbands the gang, this percent of the bank is kept as legal fees and the rest is shared to the members. Stops disbanding being a free way to move money between accounts. 0 = no fee. An admin disband never charges it.$q$),
  ($q$crew.enabled$q$, $q$R11 (docs/CREWS.md): players can found and join crews and run crew jobs. Off = founding, joining, inviting and new jobs are refused (running jobs still finish; leaving and chat still work).$q$, $q$R11 (docs/CREWS.md): players can start and join gangs and run gang jobs. Off = starting a gang, joining, inviting and new jobs are refused (running jobs still finish; leaving and chat still work).$q$),
  ($q$crew.found_fee$q$, $q$R11: what it costs to found a crew (bank first, then cash). Ledger crew_fee.$q$, $q$R11: what it costs to start a gang (bank first, then cash). Ledger crew_fee.$q$),
  ($q$crew.invite_daily_cap$q$, $q$R11: rate limit on invites sent by one crew in 24 real hours.$q$, $q$R11: rate limit on invites sent by one gang in 24 real hours.$q$),
  ($q$crew.join_min_account_hours$q$, $q$R11: anti-abuse: accounts younger than this cannot join a crew or be invited (a founder is covered by the rule above).$q$, $q$R11: anti-abuse: accounts younger than this cannot join a gang or be invited (a founder is covered by the rule above).$q$),
  ($q$crew.max_jobs_per_day$q$, $q$R11: rate limit: jobs one crew can start in 24 real hours (on top of each job's own cooldown).$q$, $q$R11: rate limit: jobs one gang can start in 24 real hours (on top of each job's own cooldown).$q$),
  ($q$crew.meeting_places$q$, $q$R11: comma-separated place ids where members must stand to join a crew job (default three street corners, no CCTV). A crew hideout was not built: crews meet at a public place.$q$, $q$R11: comma-separated place ids where members must stand to join a gang job (default three street corners, no CCTV). A gang hideout was not built: gangs meet at a public place.$q$),
  ($q$crew.min_deposit$q$, $q$R11: the least a member can put into the crew bank at once.$q$, $q$R11: the least a member can put into the gang bank at once.$q$),
  ($q$crew.rejoin_cooldown_hours$q$, $q$R11: after leaving or being kicked, a player cannot join or found any crew for this long.$q$, $q$R11: after leaving or being kicked, a player cannot join or start any gang for this long.$q$),
  ($q$crew.rename_fee$q$, $q$R11: the Boss renames the crew once per cooldown; the crew bank pays this.$q$, $q$R11: the Boss renames the gang once per cooldown; the gang bank pays this.$q$),
  ($q$crew.report_flag_count$q$, $q$R11: a crew with this many open reports is highlighted in Admin -> Crews.$q$, $q$R11: a gang with this many open reports is highlighted in Admin -> Gangs.$q$),
  ($q$crew.skill_cut_per_level$q$, $q$R11: the crew's caught chance falls by this % (relative) for every average level above 1 of the job's skills across the crew.$q$, $q$R11: the gang's caught chance falls by this % (relative) for every average level above 1 of the job's skills across the gang.$q$),
  ($q$crew.weekly_enabled$q$, $q$R11: the Ranks -> Top crews board and the weekly prizes (paid into the crew bank when the week closes, Monday 00:00 Benin time).$q$, $q$R11: the Ranks -> Top gangs board and the weekly prizes (paid into the gang bank when the week closes, Monday 00:00 Benin time).$q$),
  ($q$crew.weekly_min_jobs$q$, $q$R11: a crew needs at least this many paid jobs in the week to take a prize.$q$, $q$R11: a gang needs at least this many paid jobs in the week to take a prize.$q$),
  ($q$crew.weekly_prize_1$q$, $q$R11: paid into the winning crew's bank.$q$, $q$R11: paid into the winning gang's bank.$q$),
  ($q$crew.weekly_prize_2$q$, $q$R11: paid into the crew bank.$q$, $q$R11: paid into the gang bank.$q$),
  ($q$crew.weekly_prize_3$q$, $q$R11: paid into the crew bank.$q$, $q$R11: paid into the gang bank.$q$),
  ($q$pol.crew_endorse_min_members$q$, $q$R12: a crew needs at least this many members to endorse.$q$, $q$R12: a gang needs at least this many members to endorse.$q$),
  ($q$pol.crew_endorse_points$q$, $q$R12: a crew Boss / Lieutenant endorses for the crew (one per crew per race).$q$, $q$R12: a gang Boss / Lieutenant endorses for the gang (one per gang per race).$q$)
) as v(key, old_text, new_text) where g.key = v.key and g.description = v.old_text;

-- the founding fee label does not contain the word, so it is patched on its own
update game_config set label = 'Start fee' where key = 'crew.found_fee' and label = 'Founding fee';

notify pgrst, 'reload schema';
