-- The Court, part 2 (docs/COURT.md): JSON helpers and every player and admin RPC.
--   Players: court_status, court_events, court_file, court_lawyers_list, court_lawyer_register / _update / _retire, court_hire, court_hire_respond,
--            court_hire_cancel, court_case, court_live, court_post, court_rule, court_judge_take, court_gallery_join / _leave, court_after.
--   Admin:   admin_court_overview, admin_court_override, admin_court_dismiss, admin_court_appoint_judge, admin_court_remove_judge, admin_court_ban_lawyer.
-- Read RPCs that tick the lazy court clock are VOLATILE (never `stable`): the tick writes (a Fix it bug was a stable function that locks a row).
-- Idempotent: `create or replace`. All helpers bl_court_* are revoked from clients at the end.

-- ---------------------------------------------------------------------------------------------
-- 1. JSON helpers (private)
-- ---------------------------------------------------------------------------------------------
-- how this player stands in a case: plaintiff / defendant / judge / plaintiff_lawyer / defendant_lawyer / gallery / visitor
create or replace function public.bl_court_role(c public.court_cases, p_uid uuid) returns text
language sql stable set search_path = public as $$
  select case
    when p_uid is null then 'visitor'
    when p_uid = c.plaintiff_id then 'plaintiff'
    when p_uid = c.defendant_id then 'defendant'
    when p_uid = c.judge_id then 'judge'
    else coalesce(
      (select case h.side when 'plaintiff' then 'plaintiff_lawyer' else 'defendant_lawyer' end from court_hires h
        where h.case_id = c.id and h.lawyer_id = p_uid and h.status in ('accepted', 'paid') order by h.id limit 1),
      case when exists (select 1 from court_gallery g where g.case_id = c.id and g.user_id = p_uid) then 'gallery' else 'visitor' end)
  end;
$$;

create or replace function public.bl_court_gallery_count(p_case bigint) returns int
language sql stable set search_path = public as $$
  select count(*)::int from court_gallery g
   where g.case_id = p_case and g.seen_at > bl_now() - make_interval(secs => bl_court_num('court.gallery_idle_minutes', 10) * 60);
$$;

create or replace function public.bl_court_name(p_tier text) returns text
language sql immutable set search_path = public as $$
  select case p_tier when 'customary' then 'Customary Court, Benin' else 'High Court, Benin' end;
$$;

create or replace function public.bl_court_card_json(c public.court_cases, p_uid uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'case_no', c.case_no, 'tier', c.tier, 'court', bl_court_name(c.tier), 'kind', c.kind, 'title', c.title, 'claim', c.claim, 'status', c.status,
    'live', c.status = 'scheduled' and c.hearing_at <= bl_now(), 'hearing_at', c.hearing_at, 'ruling_deadline', c.ruling_deadline,
    'verdict', c.verdict, 'verdict_by', c.verdict_by, 'ruled_at', c.ruled_at, 'created_at', c.created_at,
    'plaintiff', bl_court_person(c.plaintiff_id), 'defendant', bl_court_person(c.defendant_id), 'judge', bl_court_person(c.judge_id),
    'gallery', bl_court_gallery_count(c.id), 'gallery_size', greatest(0, bl_court_num('court.gallery_size', 30))::int, 'role', bl_court_role(c, p_uid),
    'lawyers', coalesce((select jsonb_agg(jsonb_build_object('side', h.side, 'username', bl_username(h.lawyer_id), 'status', h.status) order by h.id)
                           from court_hires h where h.case_id = c.id and h.status in ('pending', 'accepted', 'paid')), '[]'::jsonb));
$$;

create or replace function public.bl_court_lawyer_json(l public.court_lawyers, p_viewer uuid) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'user_id', l.user_id, 'username', p.username, 'avatar', p.avatar, 'title', bl_pol_title(l.user_id), 'fee', l.fee, 'bio', l.bio,
    'wins', l.wins, 'losses', l.losses, 'rank', bl_court_rank(l.wins), 'available', l.available and not l.retired and not l.banned,
    'available_now', l.available and not l.retired and not l.banned
        and p.last_seen > bl_now() - make_interval(secs => bl_court_num('court.lawyer_online_minutes', 10) * 60),
    'open_cases', (select count(*) from court_hires h join court_cases c on c.id = h.case_id
                    where h.lawyer_id = l.user_id and h.status in ('pending', 'accepted') and c.status = 'scheduled'),
    'me', l.user_id = p_viewer)
  from profiles p where p.id = l.user_id;
$$;

create or replace function public.bl_court_statements_json(p_case bigint, p_after bigint) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.id), '[]'::jsonb) from (
    select s.id, jsonb_build_object('id', s.id, 'side', s.side, 'kind', s.kind, 'as_lawyer', s.as_lawyer, 'body', s.body, 'at', s.created_at,
             'author', (select p.username from profiles p where p.id = s.author_id)) as j
      from court_statements s where s.case_id = p_case and s.id > coalesce(p_after, 0) order by s.id desc limit 200) x;
$$;

-- the full case: card + record + the caller's powers
create or replace function public.bl_court_case_json(c public.court_cases, p_uid uuid, p_full boolean default true) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_role text := bl_court_role(c, p_uid); v_now timestamptz := bl_now(); v_part boolean; v_side text; v_used int; v_live boolean; v_hires int;
  v_card jsonb := bl_court_card_json(c, p_uid); v_can_see boolean;
begin
  v_part := v_role in ('plaintiff', 'defendant', 'judge', 'plaintiff_lawyer', 'defendant_lawyer');
  v_live := c.status = 'scheduled' and c.hearing_at <= v_now;
  v_side := case when v_role in ('plaintiff', 'plaintiff_lawyer') then 'plaintiff' when v_role in ('defendant', 'defendant_lawyer') then 'defendant' when v_role = 'judge' then 'bench' else null end;
  select count(*) into v_used from court_statements s where s.case_id = c.id and s.side = v_side and s.kind in ('statement', 'note');
  select count(*) into v_hires from court_hires h where h.case_id = c.id and h.side = v_side;
  v_can_see := c.status <> 'scheduled' or v_part or v_role = 'gallery';
  return v_card || jsonb_build_object(
    'evidence', c.evidence, 'filing_fee', c.filing_fee, 'verdict_note', c.verdict_note, 'restitution_paid', c.restitution_paid, 'restitution_debt', c.restitution_debt,
    'fine', c.fine, 'fine_paid', c.fine_paid, 'cred_hit', c.cred_hit, 'jail_seconds', c.jail_seconds, 'overridden', c.overridden,
    'hires', coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'side', h.side, 'status', h.status, 'fee', h.fee, 'lawyer', bl_court_lawyer_json(l, p_uid),
                                    'mine', h.lawyer_id = p_uid or h.client_id = p_uid) order by h.id)
                         from court_hires h join court_lawyers l on l.user_id = h.lawyer_id where h.case_id = c.id and h.status in ('pending', 'accepted', 'paid')), '[]'::jsonb),
    'statements', case when p_full and v_can_see then bl_court_statements_json(c.id, 0) else '[]'::jsonb end,
    'can_see', v_can_see,
    'me', jsonb_build_object(
      'role', v_role, 'participant', v_part,
      'can_post', v_live and v_role in ('plaintiff', 'defendant', 'plaintiff_lawyer', 'defendant_lawyer', 'judge') and bl_court_on(),
      'statements_left', greatest(0, bl_court_num('court.statements_per_side', 8)::int - v_used),
      'can_rule', c.status = 'scheduled' and v_role = 'judge' and v_now >= c.hearing_at + make_interval(secs => bl_court_num('court.min_hearing_minutes', 2) * 60) and bl_court_on(),
      'rule_from', c.hearing_at + make_interval(secs => bl_court_num('court.min_hearing_minutes', 2) * 60),
      'can_hire', c.status = 'scheduled' and v_now < c.hearing_at and v_role in ('plaintiff', 'defendant') and bl_court_on()
                  and not exists (select 1 from court_hires h where h.case_id = c.id and h.side = v_role and h.status in ('pending', 'accepted', 'paid'))
                  and v_hires < bl_court_num('court.hire_attempts', 3),
      'in_gallery', v_role = 'gallery'),
    'settings', jsonb_build_object('statement_max_len', bl_court_num('court.statement_max_len', 240)::int,
      'min_hearing_minutes', bl_court_num('court.min_hearing_minutes', 2), 'gallery_size', bl_court_num('court.gallery_size', 30)::int));
end $$;

-- the lawyer requirements checklist: {ok, checks:[{key,label,ok}]}
create or replace function public.bl_court_lawyer_checks(p_uid uuid) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  p profiles; v_cert text := coalesce(btrim(bl_cfg_text('court.lawyer_cert')), ''); v_days numeric := bl_court_num('court.lawyer_min_account_days', 2);
  v_checks jsonb; v_ok boolean; v_cname text;
begin
  select * into p from profiles where id = p_uid;
  v_checks := jsonb_build_array(jsonb_build_object('key', 'age', 'label', 'Account at least ' || trim_scale(v_days)::text || ' day' || case when v_days = 1 then '' else 's' end || ' old',
    'ok', p.id is not null and p.created_at <= bl_now() - make_interval(secs => v_days * 86400)));
  if v_cert <> '' then
    select name into v_cname from certificates where id = v_cert;
    v_checks := v_checks || jsonb_build_array(jsonb_build_object('key', 'cert', 'label', 'School certificate: ' || coalesce(v_cname, v_cert),
      'ok', exists (select 1 from player_certificates pc where pc.user_id = p_uid and pc.cert_id = v_cert)));
  end if;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('key', 'judge', 'label', 'Not a sitting judge', 'ok', not bl_court_judge_ok(p_uid)));
  select coalesce(bool_and((x ->> 'ok')::boolean), true) into v_ok from jsonb_array_elements(v_checks) x;
  return jsonb_build_object('ok', v_ok, 'checks', v_checks);
end $$;

-- why this player cannot file right now (null = they can)
create or replace function public.bl_court_file_block(p_uid uuid) returns text
language plpgsql stable set search_path = public as $$
declare p profiles; v_now timestamptz := bl_now(); v_last timestamptz; v_open int; v_day int; v_cd numeric := bl_court_num('court.file_cooldown_minutes', 5);
begin
  select * into p from profiles where id = p_uid;
  if not bl_court_on() then return 'The court is closed for now.'; end if;
  if p.created_at > v_now - make_interval(secs => bl_court_num('court.min_account_hours', 12) * 3600) then
    return 'Your account is too new to use the court. Come back later.';
  end if;
  select max(created_at), count(*) filter (where status = 'scheduled'),
         count(*) filter (where created_at >= (date_trunc('day', v_now at time zone 'Africa/Lagos') at time zone 'Africa/Lagos'))
    into v_last, v_open, v_day from court_cases where plaintiff_id = p_uid;
  if v_open >= bl_court_num('court.max_open_cases', 3) then return 'You already have ' || v_open || ' open cases. Wait for a ruling first.'; end if;
  if v_day >= bl_court_num('court.max_per_day', 5) then return 'You have filed the most cases allowed today.'; end if;
  if v_last is not null and v_cd > 0 and v_last > v_now - make_interval(secs => v_cd * 60) then
    return 'Wait ' || ceil(extract(epoch from (v_last + make_interval(secs => v_cd * 60) - v_now)) / 60.0)::int || ' minute(s) before filing again.';
  end if;
  return null;
end $$;

-- hire a lawyer for one side: checks, escrow (the client pays now; paid out on the verdict, returned if declined or expired), request alert
create or replace function public.bl_court_hire_create(c public.court_cases, p_side text, p_client uuid, p_lawyer uuid) returns bigint
language plpgsql set search_path = public as $$
declare l court_lawyers; v_id bigint; v_open int; v_tries int; v_cn text;
begin
  select * into l from court_lawyers where user_id = p_lawyer;
  if not found or l.banned or l.retired or not l.available then
    raise exception 'That lawyer is not taking cases right now.' using errcode = 'P0001', hint = 'lawyer_unavailable';
  end if;
  if p_lawyer in (c.plaintiff_id, c.defendant_id) then
    raise exception 'A lawyer cannot act in a case they are part of.' using errcode = 'P0001', hint = 'lawyer_party';
  end if;
  if p_lawyer = c.judge_id then
    raise exception 'That player is the judge of this case.' using errcode = 'P0001', hint = 'lawyer_judge';
  end if;
  if exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = p_lawyer and h.status in ('pending', 'accepted', 'paid')) then
    raise exception 'That lawyer is already on this case. A lawyer cannot take both sides.' using errcode = 'P0001', hint = 'lawyer_taken';
  end if;
  if exists (select 1 from court_hires h where h.case_id = c.id and h.side = p_side and h.status in ('pending', 'accepted', 'paid')) then
    raise exception 'You already have a lawyer on this case.' using errcode = 'P0001', hint = 'has_lawyer';
  end if;
  select count(*) into v_tries from court_hires h where h.case_id = c.id and h.side = p_side;
  if v_tries >= bl_court_num('court.hire_attempts', 3) then
    raise exception 'You have used all your lawyer requests for this case. Speak for yourself.' using errcode = 'P0001', hint = 'hire_limit';
  end if;
  select count(*) into v_open from court_hires h join court_cases x on x.id = h.case_id
   where h.lawyer_id = p_lawyer and h.status in ('pending', 'accepted') and x.status = 'scheduled';
  if v_open >= bl_court_num('court.lawyer_max_open', 5) then
    raise exception 'That lawyer has too many cases right now.' using errcode = 'P0001', hint = 'lawyer_busy';
  end if;
  perform bl_sink_pay(p_client, l.fee, 'lawyer_escrow', jsonb_build_object('label', 'Lawyer fee held (' || c.case_no || ')', 'case', c.case_no));
  insert into court_hires (case_id, side, client_id, lawyer_id, fee, status, created_at) values (c.id, p_side, p_client, p_lawyer, l.fee, 'pending', bl_now()) returning id into v_id;
  v_cn := bl_username(p_client);
  perform bl_event(p_lawyer, 'court_hire_request', '@' || v_cn || ' wants you as their lawyer',
    c.case_no || ': ' || c.title || '. Fee ' || bl_naira(l.fee) || '. Accept before the hearing starts at ' ||
    to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') || '.', jsonb_build_object('case', c.id, 'hire', v_id));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. Player RPCs: status and lists
-- ---------------------------------------------------------------------------------------------
create or replace function public.court_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_now timestamptz := bl_now(); l court_lawyers; v_lawyer jsonb := null; v_judge boolean; v_wins int; v_next text; v_need int;
  v_cases jsonb; v_reqs jsonb; v_queue jsonb := '[]'::jsonb; v_debts jsonb; v_owed bigint;
begin
  perform bl_court_tick(v_uid);
  v_judge := bl_court_judge_ok(v_uid);
  select * into l from court_lawyers where user_id = v_uid;
  if found then
    v_wins := l.wins;
    select case when v_wins < bl_court_num('court.rank_advocate_wins', 5) then 'Advocate' when v_wins < bl_court_num('court.rank_barrister_wins', 15) then 'Barrister'
                when v_wins < bl_court_num('court.rank_senior_wins', 40) then 'Senior Advocate' else null end,
           case when v_wins < bl_court_num('court.rank_advocate_wins', 5) then bl_court_num('court.rank_advocate_wins', 5)::int - v_wins
                when v_wins < bl_court_num('court.rank_barrister_wins', 15) then bl_court_num('court.rank_barrister_wins', 15)::int - v_wins
                when v_wins < bl_court_num('court.rank_senior_wins', 40) then bl_court_num('court.rank_senior_wins', 40)::int - v_wins else null end
      into v_next, v_need;
    v_lawyer := bl_court_lawyer_json(l, v_uid) || jsonb_build_object('retired', l.retired, 'banned', l.banned, 'ban_reason', l.ban_reason, 'next_rank', v_next, 'wins_to_next', v_need);
  end if;
  select coalesce(jsonb_agg(bl_court_card_json(cc, v_uid) order by cc.id desc), '[]'::jsonb) into v_cases
    from court_cases cc join (
      select c.id from court_cases c where c.plaintiff_id = v_uid or c.defendant_id = v_uid or c.judge_id = v_uid
         or exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = v_uid and h.status in ('accepted', 'paid'))
      order by c.id desc limit 40) x on x.id = cc.id;
  select coalesce(jsonb_agg(jsonb_build_object('hire', h.id, 'fee', h.fee, 'side', h.side, 'client', bl_court_person(h.client_id), 'case', bl_court_card_json(c, v_uid)) order by h.id), '[]'::jsonb)
    into v_reqs from court_hires h join court_cases c on c.id = h.case_id
   where h.lawyer_id = v_uid and h.status = 'pending' and c.status = 'scheduled' and c.hearing_at > v_now;
  if v_judge then
    select coalesce(jsonb_agg(bl_court_card_json(cc, v_uid) order by cc.hearing_at), '[]'::jsonb) into v_queue
      from court_cases cc join (
        select c.id from court_cases c where c.status = 'scheduled' and c.judge_id is null and c.plaintiff_id <> v_uid and c.defendant_id <> v_uid
           and not exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = v_uid and h.status in ('pending', 'accepted'))
        order by c.hearing_at limit 10) x on x.id = cc.id;
  end if;
  select coalesce(sum(owed), 0) into v_owed from court_debts where debtor_id = v_uid and owed > 0;
  v_debts := jsonb_build_object('owed', v_owed, 'collect_pct', bl_court_num('court.debt_collect_pct', 30),
    'items', coalesce((select jsonb_agg(jsonb_build_object('case_no', cc.case_no, 'kind', d.kind, 'owed', d.owed, 'amount', d.amount) order by d.id)
                         from court_debts d join court_cases cc on cc.id = d.case_id where d.debtor_id = v_uid and d.owed > 0), '[]'::jsonb));
  return jsonb_build_object(
    'now', v_now, 'enabled', bl_court_on(), 'judge', v_judge, 'lawyer', v_lawyer, 'lawyer_requirements', bl_court_lawyer_checks(v_uid),
    'cases', v_cases, 'hire_requests', v_reqs, 'judge_queue', v_queue, 'debts', v_debts, 'blocked', bl_court_file_block(v_uid),
    'settings', jsonb_build_object(
      'filing_fee', bl_court_fee('high'), 'customary_fee', bl_court_fee('customary'), 'customary_max', bl_court_num('court.customary_max', 100000)::bigint,
      'lookback_hours', bl_court_num('court.lookback_hours', 72), 'hearing_delay_minutes', bl_court_num('court.hearing_delay_minutes', 30),
      'ruling_window_minutes', bl_court_num('court.ruling_window_minutes', 60), 'gallery_size', bl_court_num('court.gallery_size', 30)::int,
      'statement_max_len', bl_court_num('court.statement_max_len', 240)::int, 'fine_pct', bl_court_num('court.fine_pct', 20), 'cut_pct', bl_court_num('court.cut_pct', 5),
      'lawyer_min_fee', bl_court_num('court.lawyer_min_fee', 2000)::bigint, 'lawyer_max_fee', bl_court_num('court.lawyer_max_fee', 2000000)::bigint,
      'debt_collect_pct', bl_court_num('court.debt_collect_pct', 30), 'cred_hit', bl_court_num('court.cred_hit', 5)::int,
      'types', jsonb_build_object('pickpocket', bl_pol_flag('court.type_pickpocket_enabled', true), 'rent_owed', bl_pol_flag('court.type_rent_owed_enabled', true),
                                  'eviction', bl_pol_flag('court.type_eviction_enabled', true), 'overcharge', bl_pol_flag('court.type_overcharge_enabled', true))));
end $$;

-- step 1 of "Take them to court": the events the game recorded that this player can sue about
create or replace function public.court_events() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  perform bl_court_tick(v_uid);
  return jsonb_build_object('events', bl_court_my_events(v_uid), 'blocked', bl_court_file_block(v_uid),
    'lookback_hours', bl_court_num('court.lookback_hours', 72), 'filing_fee', bl_court_fee('high'), 'customary_fee', bl_court_fee('customary'),
    'customary_max', bl_court_num('court.customary_max', 100000)::bigint);
end $$;

create or replace function public.court_lawyers_list(p_q text default '', p_filter text default 'all', p_limit int default 30) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_q text := replace(replace(replace(btrim(coalesce(p_q, '')), '\', ''), '%', ''), '_', '');
  v_n int := greatest(1, least(coalesce(p_limit, 30), 50)); v_f text := case when p_filter in ('available', 'top') then p_filter else 'all' end;
  v_online interval := make_interval(secs => bl_court_num('court.lawyer_online_minutes', 10) * 60);
begin
  v_q := regexp_replace(v_q, '^@', '');
  return coalesce((select jsonb_agg(bl_court_lawyer_json(x.l, v_uid) order by x.o1 desc, x.o2 desc, x.o3 desc, x.uname) from (
    select l, p.username as uname,
           case when v_f = 'top' then 0 else (l.available and p.last_seen > bl_now() - v_online)::int end as o1,
           l.wins as o2,
           (l.wins::numeric / greatest(l.wins + l.losses, 1)) as o3
      from court_lawyers l join profiles p on p.id = l.user_id
     where not l.banned and not l.retired and not p.banned
       and (v_q = '' or p.username ilike '%' || v_q || '%')
       and (v_f <> 'available' or (l.available and p.last_seen > bl_now() - v_online))
     order by o1 desc, o2 desc, o3 desc, p.username limit v_n) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Player RPCs: file a case, lawyers
-- ---------------------------------------------------------------------------------------------
create or replace function public.court_file(p_kind text, p_ref text, p_lawyer uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me profiles; v_now timestamptz; ev jsonb; v_def uuid; v_dp profiles; v_claim bigint; v_tier text; v_fee bigint; v_id bigint; v_no text; c court_cases;
  v_hire bigint := null; v_judge uuid; v_block text;
begin
  v_me := bl_me();
  perform bl_court_guard();
  v_now := bl_now();
  v_block := bl_court_file_block(v_me.id);
  if v_block is not null then raise exception '%', v_block using errcode = 'P0001', hint = 'blocked'; end if;
  ev := bl_court_evidence(v_me.id, p_kind, btrim(coalesce(p_ref, '')));
  if not coalesce((ev ->> 'ok')::boolean, false) then
    raise exception '%', coalesce(ev ->> 'why', 'We have no record of that.') using errcode = 'P0001', hint = 'no_record';
  end if;
  v_def := (ev ->> 'defendant')::uuid;
  if v_def = v_me.id then raise exception 'You cannot take yourself to court.' using errcode = 'P0001', hint = 'self'; end if;
  select * into v_dp from profiles where id = v_def and not banned;
  if not found then raise exception 'That player can no longer be summoned.' using errcode = 'P0001', hint = 'no_defendant'; end if;
  if exists (select 1 from court_cases x where x.kind = p_kind and x.event_ref = btrim(p_ref) and x.status <> 'dismissed') then
    raise exception 'That event already has a case.' using errcode = 'P0001', hint = 'already_filed';
  end if;
  v_claim := (ev ->> 'claim')::bigint; v_tier := bl_court_tier(v_claim); v_fee := bl_court_fee(v_tier);
  if p_lawyer is not null and p_lawyer = v_me.id then raise exception 'You cannot be your own lawyer. Leave the lawyer empty to speak for yourself.' using errcode = 'P0001', hint = 'lawyer_self'; end if;
  v_id := nextval(pg_get_serial_sequence('public.court_cases', 'id'));
  v_no := case v_tier when 'customary' then 'CC' else 'BC' end || '/' || v_id || '/' || bl_court_year();
  perform bl_sink_pay(v_me.id, v_fee, 'court_fee', jsonb_build_object('label', 'Court filing fee (' || v_no || ')', 'case', v_no));
  insert into court_cases (id, case_no, tier, kind, event_ref, title, evidence, plaintiff_id, defendant_id, claim, filing_fee, status, hearing_at, ruling_deadline, created_at)
  values (v_id, v_no, v_tier, p_kind, btrim(p_ref), ev ->> 'title', coalesce(ev -> 'evidence', '{}'::jsonb), v_me.id, v_def, v_claim, v_fee, 'scheduled',
          v_now + make_interval(secs => greatest(1, bl_court_num('court.hearing_delay_minutes', 30)) * 60),
          v_now + make_interval(secs => (greatest(1, bl_court_num('court.hearing_delay_minutes', 30)) + greatest(1, bl_court_num('court.ruling_window_minutes', 60))) * 60), v_now)
  returning * into c;
  if p_lawyer is not null then v_hire := bl_court_hire_create(c, 'plaintiff', v_me.id, p_lawyer); end if;
  v_judge := bl_court_assign_judge(c.id);
  perform bl_event(v_def, 'court_summons', '@' || v_me.username || ' is taking you to court',
    c.case_no || ': ' || c.title || '. The hearing starts at ' || to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') ||
    '. Open the Court app: you can hire a lawyer or speak for yourself.', jsonb_build_object('case', c.id));
  perform bl_event(v_me.id, 'court_filed', 'Case filed', c.case_no || ' is set for ' || to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') || '.', jsonb_build_object('case', c.id));
  select * into c from court_cases where id = c.id;
  return jsonb_build_object('message', 'Case ' || c.case_no || ' filed. The hearing starts at ' || to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') || '.',
    'case', bl_court_case_json(c, v_me.id, false), 'hire', v_hire, 'fee', v_fee);
end $$;

create or replace function public.court_lawyer_register(p_fee bigint, p_bio text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); v_chk jsonb; v_bad text; v_bio text; l court_lawyers;
  v_min bigint := greatest(0, bl_court_num('court.lawyer_min_fee', 2000))::bigint; v_max bigint := greatest(0, bl_court_num('court.lawyer_max_fee', 2000000))::bigint;
begin
  perform bl_court_guard();
  if not exists (select 1 from profiles where id = v_uid and home_chosen and not banned) then
    raise exception 'Create your Sim first.' using errcode = 'P0001', hint = 'no_profile';
  end if;
  select * into l from court_lawyers where user_id = v_uid;
  if found and l.banned then raise exception 'The court removed you as a lawyer.' using errcode = 'P0001', hint = 'banned_lawyer'; end if;
  v_chk := bl_court_lawyer_checks(v_uid);
  if not (v_chk ->> 'ok')::boolean then
    select x ->> 'label' into v_bad from jsonb_array_elements(v_chk -> 'checks') x where not (x ->> 'ok')::boolean limit 1;
    raise exception 'You cannot register yet. Needed: %.', v_bad using errcode = 'P0001', hint = 'requirements';
  end if;
  if coalesce(p_fee, -1) < v_min or p_fee > v_max then
    raise exception 'Your fee must be between % and %.', bl_naira(v_min), bl_naira(v_max) using errcode = 'P0001', hint = 'bad_fee';
  end if;
  v_bio := left(bl_chat_mask(bl_chat_clean(p_bio)), 120);
  insert into court_lawyers (user_id, fee, bio, available, retired, registered_at) values (v_uid, p_fee, v_bio, true, false, bl_now())
  on conflict (user_id) do update set fee = excluded.fee, bio = excluded.bio, available = true, retired = false;
  select * into l from court_lawyers where user_id = v_uid;
  return jsonb_build_object('message', 'You are a registered lawyer: Junior Lawyer. Clients can now hire you.', 'lawyer', bl_court_lawyer_json(l, v_uid));
end $$;

create or replace function public.court_lawyer_update(p_fee bigint, p_bio text, p_available boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); l court_lawyers; v_bio text;
  v_min bigint := greatest(0, bl_court_num('court.lawyer_min_fee', 2000))::bigint; v_max bigint := greatest(0, bl_court_num('court.lawyer_max_fee', 2000000))::bigint;
begin
  perform bl_court_guard();
  select * into l from court_lawyers where user_id = v_uid for update;
  if not found or l.retired then raise exception 'Register as a lawyer first.' using errcode = 'P0001', hint = 'not_lawyer'; end if;
  if l.banned then raise exception 'The court removed you as a lawyer.' using errcode = 'P0001', hint = 'banned_lawyer'; end if;
  if p_fee is not null and (p_fee < v_min or p_fee > v_max) then
    raise exception 'Your fee must be between % and %.', bl_naira(v_min), bl_naira(v_max) using errcode = 'P0001', hint = 'bad_fee';
  end if;
  v_bio := case when p_bio is null then l.bio else left(bl_chat_mask(bl_chat_clean(p_bio)), 120) end;
  update court_lawyers set fee = coalesce(p_fee, fee), bio = v_bio, available = coalesce(p_available, available) where user_id = v_uid returning * into l;
  return jsonb_build_object('message', 'Saved. The new fee applies to new requests.', 'lawyer', bl_court_lawyer_json(l, v_uid));
end $$;

create or replace function public.court_lawyer_retire() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); l court_lawyers;
begin
  select * into l from court_lawyers where user_id = v_uid for update;
  if not found or l.retired then raise exception 'You are not a registered lawyer.' using errcode = 'P0001', hint = 'not_lawyer'; end if;
  if exists (select 1 from court_hires h join court_cases c on c.id = h.case_id where h.lawyer_id = v_uid and h.status in ('pending', 'accepted') and c.status = 'scheduled') then
    raise exception 'Finish your open cases first.' using errcode = 'P0001', hint = 'open_cases';
  end if;
  update court_lawyers set retired = true, available = false where user_id = v_uid;
  return jsonb_build_object('message', 'You retired as a lawyer. Your record is kept if you register again.');
end $$;

create or replace function public.court_hire(p_case bigint, p_lawyer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me profiles; c court_cases; v_side text; v_id bigint;
begin
  v_me := bl_me();
  perform bl_court_guard();
  select * into c from court_cases where id = p_case;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  v_side := case when c.plaintiff_id = v_me.id then 'plaintiff' when c.defendant_id = v_me.id then 'defendant' else null end;
  if v_side is null then raise exception 'Only the two sides can hire a lawyer.' using errcode = 'P0001', hint = 'not_party'; end if;
  if c.status <> 'scheduled' or bl_now() >= c.hearing_at then
    raise exception 'The hearing has started. It is too late to hire a lawyer.' using errcode = 'P0001', hint = 'too_late';
  end if;
  v_id := bl_court_hire_create(c, v_side, v_me.id, p_lawyer);
  return jsonb_build_object('message', 'Request sent. The fee is held until the verdict. If the lawyer says no, it comes back.', 'hire', v_id);
end $$;

create or replace function public.court_hire_respond(p_hire bigint, p_accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h court_hires; c court_cases; l court_lawyers; v_open int;
begin
  perform bl_court_guard();
  select * into h from court_hires where id = p_hire and lawyer_id = v_uid for update;
  if not found then raise exception 'That request is not yours.' using errcode = 'P0001', hint = 'not_yours'; end if;
  if h.status <> 'pending' then raise exception 'That request is already closed.' using errcode = 'P0001', hint = 'closed'; end if;
  select * into c from court_cases where id = h.case_id;
  if c.status <> 'scheduled' or bl_now() >= c.hearing_at then
    perform bl_court_hire_refund(h.id, 'expired', 'The hearing started before the lawyer answered.');
    return jsonb_build_object('expired', true, 'message', 'The hearing has started, so the request expired.');
  end if;
  if p_accept then
    select * into l from court_lawyers where user_id = v_uid;
    if not found or l.banned or l.retired then raise exception 'You are not an active lawyer.' using errcode = 'P0001', hint = 'not_lawyer'; end if;
    select count(*) into v_open from court_hires x join court_cases y on y.id = x.case_id where x.lawyer_id = v_uid and x.status = 'accepted' and y.status = 'scheduled';
    if v_open >= bl_court_num('court.lawyer_max_open', 5) then raise exception 'You have too many open cases.' using errcode = 'P0001', hint = 'lawyer_busy'; end if;
    update court_hires set status = 'accepted', decided_at = bl_now() where id = h.id;
    perform bl_event(h.client_id, 'court_hire_answer', '@' || bl_username(v_uid) || ' took your case', c.case_no || ': your lawyer is ready for the hearing at ' ||
      to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') || '.', jsonb_build_object('case', c.id, 'hire', h.id));
    return jsonb_build_object('message', 'You are the lawyer for ' || c.case_no || '. Be there when the hearing starts.');
  end if;
  perform bl_court_hire_refund(h.id, 'declined', '@' || bl_username(v_uid) || ' declined your request.');
  return jsonb_build_object('message', 'Declined. The client got the fee back.');
end $$;

create or replace function public.court_hire_cancel(p_hire bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); h court_hires;
begin
  select * into h from court_hires where id = p_hire and client_id = v_uid and status = 'pending' for update;
  if not found then raise exception 'There is no waiting request to cancel.' using errcode = 'P0001', hint = 'closed'; end if;
  perform bl_court_hire_refund(h.id, 'cancelled', 'You cancelled the request.');
  return jsonb_build_object('message', 'Request cancelled. The fee is back in your bank.');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Player RPCs: cases, hearings, statements, rulings, gallery
-- ---------------------------------------------------------------------------------------------
create or replace function public.court_case(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c court_cases;
begin
  perform bl_court_tick(v_uid);
  select * into c from court_cases where id = p_id;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  return bl_court_case_json(c, v_uid, true);
end $$;

create or replace function public.court_live() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); v_now timestamptz; v_live jsonb; v_up jsonb; v_recent jsonb;
begin
  perform bl_court_tick(v_uid);
  v_now := bl_now();
  select coalesce(jsonb_agg(bl_court_card_json(cc, v_uid) order by cc.hearing_at), '[]'::jsonb) into v_live
    from court_cases cc join (select id from court_cases where status = 'scheduled' and hearing_at <= v_now order by hearing_at limit 30) x on x.id = cc.id;
  select coalesce(jsonb_agg(bl_court_card_json(cc, v_uid) order by cc.hearing_at), '[]'::jsonb) into v_up
    from court_cases cc join (select id from court_cases where status = 'scheduled' and hearing_at > v_now and hearing_at <= v_now + interval '3 hours' order by hearing_at limit 20) x on x.id = cc.id;
  select coalesce(jsonb_agg(bl_court_card_json(cc, v_uid) order by cc.ruled_at desc), '[]'::jsonb) into v_recent
    from court_cases cc join (select id from court_cases where status = 'ruled' and ruled_at > v_now - interval '3 hours' order by ruled_at desc limit 10) x on x.id = cc.id;
  return jsonb_build_object('live', v_live, 'upcoming', v_up, 'recent', v_recent);
end $$;

create or replace function public.court_post(p_case bigint, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c court_cases; v_role text; v_side text; v_kind text; v_body text; v_max int; v_used int; v_gap numeric; v_last timestamptz; v_id bigint;
  v_muted timestamptz; v_now timestamptz;
begin
  perform bl_court_guard();
  perform bl_court_tick(v_uid);
  v_now := bl_now();
  select * into c from court_cases where id = p_case;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  if c.status <> 'scheduled' then return jsonb_build_object('closed', true, 'message', 'This hearing is over.'); end if;
  if v_now < c.hearing_at then
    raise exception 'The hearing has not started. It starts at %.', to_char(c.hearing_at at time zone 'Africa/Lagos', 'HH24:MI') using errcode = 'P0001', hint = 'not_started';
  end if;
  v_role := bl_court_role(c, v_uid);
  v_side := case when v_role in ('plaintiff', 'plaintiff_lawyer') then 'plaintiff' when v_role in ('defendant', 'defendant_lawyer') then 'defendant' when v_role = 'judge' then 'bench' else null end;
  if v_side is null then raise exception 'Only the two sides, their lawyers and the judge can speak. You can watch from the gallery.' using errcode = 'P0001', hint = 'not_party'; end if;
  select chat_muted_until into v_muted from profiles where id = v_uid;
  if v_muted is not null and v_muted > v_now then raise exception 'You are muted right now.' using errcode = 'P0001', hint = 'muted'; end if;
  v_max := bl_court_num('court.statement_max_len', 240)::int;
  v_body := bl_chat_mask(bl_chat_clean(p_body));
  if char_length(v_body) < 1 then raise exception 'Write something first.' using errcode = 'P0001', hint = 'empty'; end if;
  if char_length(v_body) > v_max then raise exception 'Keep it under % characters.', v_max using errcode = 'P0001', hint = 'too_long'; end if;
  v_gap := bl_court_num('court.statement_gap_seconds', 3);
  select max(created_at) into v_last from court_statements where case_id = c.id and author_id = v_uid;
  if v_last is not null and v_gap > 0 and v_last > v_now - make_interval(secs => v_gap) then
    raise exception 'Slow down a little.' using errcode = 'P0001', hint = 'slow';
  end if;
  select count(*) into v_used from court_statements where case_id = c.id and side = v_side and kind in ('statement', 'note');
  if v_used >= bl_court_num('court.statements_per_side', 8) then
    raise exception 'Your side has used all % statements.', bl_court_num('court.statements_per_side', 8)::int using errcode = 'P0001', hint = 'limit';
  end if;
  v_kind := case when v_side = 'bench' then 'note' else 'statement' end;
  insert into court_statements (case_id, side, kind, author_id, as_lawyer, body, created_at)
  values (c.id, v_side, v_kind, v_uid, v_role in ('plaintiff_lawyer', 'defendant_lawyer'), v_body, v_now) returning id into v_id;
  return jsonb_build_object('id', v_id, 'body', v_body);
end $$;

create or replace function public.court_rule(p_case bigint, p_verdict text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c court_cases; v_note text; v_now timestamptz;
begin
  perform bl_court_guard();
  perform bl_court_tick(v_uid);
  v_now := bl_now();
  select * into c from court_cases where id = p_case for update;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  if c.status <> 'scheduled' then return jsonb_build_object('closed', true, 'message', 'This case already has a ruling.'); end if;
  if c.judge_id is distinct from v_uid then raise exception 'Only the judge of this case can rule.' using errcode = 'P0001', hint = 'not_judge'; end if;
  if v_uid in (c.plaintiff_id, c.defendant_id) or exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = v_uid and h.status in ('pending', 'accepted')) then
    raise exception 'A judge cannot rule on a case they are part of.' using errcode = 'P0001', hint = 'judge_party';
  end if;
  if not bl_court_judge_ok(v_uid) then raise exception 'You no longer hold a judge''s seat.' using errcode = 'P0001', hint = 'not_judge'; end if;
  if p_verdict not in ('guilty', 'not_guilty') then raise exception 'Rule guilty or not guilty.' using errcode = 'P0001', hint = 'bad_verdict'; end if;
  if v_now < c.hearing_at + make_interval(secs => bl_court_num('court.min_hearing_minutes', 2) * 60) then
    raise exception 'Let the hearing run a little longer so both sides can speak.' using errcode = 'P0001', hint = 'too_early';
  end if;
  v_note := left(bl_chat_mask(bl_chat_clean(p_note)), 300);
  perform bl_court_execute(c.id, p_verdict, 'judge', v_note, v_uid);
  return jsonb_build_object('message', 'Ruling delivered: ' || case p_verdict when 'guilty' then 'guilty.' else 'not guilty.' end, 'case', bl_court_case_json((select x from court_cases x where x.id = c.id), v_uid, false));
end $$;

create or replace function public.court_judge_take(p_case bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c court_cases;
begin
  perform bl_court_guard();
  if not bl_court_judge_ok(v_uid) then raise exception 'Only sitting judges can take a case.' using errcode = 'P0001', hint = 'not_judge'; end if;
  select * into c from court_cases where id = p_case and status = 'scheduled' for update;
  if not found then raise exception 'That case is not waiting for a judge.' using errcode = 'P0001', hint = 'closed'; end if;
  if c.judge_id is not null then raise exception 'A judge is already assigned.' using errcode = 'P0001', hint = 'has_judge'; end if;
  if v_uid in (c.plaintiff_id, c.defendant_id) or exists (select 1 from court_hires h where h.case_id = c.id and h.lawyer_id = v_uid and h.status in ('pending', 'accepted', 'paid')) then
    raise exception 'You cannot judge a case you are part of.' using errcode = 'P0001', hint = 'judge_party';
  end if;
  update court_cases set judge_id = v_uid where id = c.id;
  return jsonb_build_object('message', 'You are the judge for ' || c.case_no || '.');
end $$;

create or replace function public.court_gallery_join(p_case bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c court_cases; v_role text; v_n int; v_size int := greatest(0, bl_court_num('court.gallery_size', 30))::int; v_now timestamptz := bl_now();
begin
  perform bl_court_guard();
  select * into c from court_cases where id = p_case;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  v_role := bl_court_role(c, v_uid);
  if v_role in ('plaintiff', 'defendant', 'judge', 'plaintiff_lawyer', 'defendant_lawyer') then
    return jsonb_build_object('joined', true, 'participant', true, 'count', bl_court_gallery_count(c.id));
  end if;
  if c.status <> 'scheduled' then raise exception 'This hearing is over.' using errcode = 'P0001', hint = 'closed'; end if;
  -- seats of watchers who stopped checking in are free again
  delete from court_gallery where case_id = c.id and seen_at <= v_now - make_interval(secs => bl_court_num('court.gallery_idle_minutes', 10) * 60);
  if exists (select 1 from court_gallery where case_id = c.id and user_id = v_uid) then
    update court_gallery set seen_at = v_now where case_id = c.id and user_id = v_uid;
  else
    select count(*) into v_n from court_gallery where case_id = c.id;
    if v_n >= v_size then raise exception 'The gallery is full (%).', v_size using errcode = 'P0001', hint = 'gallery_full'; end if;
    insert into court_gallery (case_id, user_id, joined_at, seen_at) values (c.id, v_uid, v_now, v_now) on conflict (case_id, user_id) do update set seen_at = v_now;
  end if;
  return jsonb_build_object('joined', true, 'participant', false, 'count', bl_court_gallery_count(c.id));
end $$;

create or replace function public.court_gallery_leave(p_case bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid();
begin
  delete from court_gallery where case_id = p_case and user_id = v_uid;
  return jsonb_build_object('left', true);
end $$;

-- polling fallback and gallery check-in: statements after an id (people in the case or the gallery, or anyone once the case is ruled)
create or replace function public.court_after(p_case bigint, p_after bigint default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := bl_require_uid(); c court_cases; v_role text;
begin
  perform bl_court_tick(v_uid);
  select * into c from court_cases where id = p_case;
  if not found then raise exception 'That case does not exist.' using errcode = 'P0001', hint = 'no_case'; end if;
  v_role := bl_court_role(c, v_uid);
  if c.status = 'scheduled' and v_role = 'visitor' then raise exception 'Take a seat in the gallery to watch.' using errcode = 'P0001', hint = 'not_seated'; end if;
  if v_role = 'gallery' then update court_gallery set seen_at = bl_now() where case_id = c.id and user_id = v_uid; end if;
  return jsonb_build_object('status', c.status, 'verdict', c.verdict, 'gallery', bl_court_gallery_count(c.id), 'statements', bl_court_statements_json(c.id, p_after));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Admin
-- ---------------------------------------------------------------------------------------------
create or replace function public.admin_court_overview(p_status text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); v_now timestamptz;
begin
  perform bl_court_tick(v_admin);
  v_now := bl_now();
  return jsonb_build_object('now', v_now, 'enabled', bl_court_on(),
    'stats', jsonb_build_object(
      'open', (select count(*) from court_cases where status = 'scheduled'), 'ruled', (select count(*) from court_cases where status = 'ruled'),
      'dismissed', (select count(*) from court_cases where status = 'dismissed'),
      'auto', (select count(*) from court_cases where verdict_by = 'auto'), 'overridden', (select count(*) from court_cases where overridden),
      'lawyers', (select count(*) from court_lawyers where not retired and not banned),
      'debt_owed', (select coalesce(sum(owed), 0) from court_debts where owed > 0),
      'fees_burned', (select coalesce(sum(filing_fee), 0) from court_cases where verdict = 'not_guilty')),
    'cases', coalesce((select jsonb_agg(bl_court_card_json(c, v_admin) || jsonb_build_object('filing_fee', c.filing_fee, 'verdict_note', c.verdict_note, 'overridden', c.overridden,
                         'restitution_paid', c.restitution_paid, 'restitution_debt', c.restitution_debt, 'fine', c.fine, 'jail_seconds', c.jail_seconds) order by c.id desc)
                       from court_cases c join (select id from court_cases where p_status is null or p_status = '' or status = p_status order by id desc limit 60) x on x.id = c.id), '[]'::jsonb),
    'judges', coalesce((select jsonb_agg(jsonb_build_object('office_id', o.id, 'name', o.name, 'salary_per_day', o.salary_per_day, 'active', o.active,
                         'holder', (select jsonb_build_object('id', h.id, 'user_id', h.user_id, 'username', p.username, 'term_end', h.term_end, 'last_seen', p.last_seen,
                                      'open_cases', (select count(*) from court_cases cc where cc.judge_id = h.user_id and cc.status = 'scheduled'))
                                    from ind_holders h join profiles p on p.id = h.user_id where h.office_id = o.id and h.status = 'active' and h.term_end > v_now limit 1)) order by o.sort, o.id)
                       from ind_offices o where o.id like 'court\_judge\_%'), '[]'::jsonb),
    'lawyers', coalesce((select jsonb_agg(bl_court_lawyer_json(l, v_admin) || jsonb_build_object('banned', l.banned, 'ban_reason', l.ban_reason, 'retired', l.retired) order by l.wins desc, l.registered_at)
                         from court_lawyers l join (select user_id from court_lawyers order by wins desc, registered_at limit 60) x on x.user_id = l.user_id), '[]'::jsonb));
end $$;

create or replace function public.admin_court_override(p_case bigint, p_verdict text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c court_cases; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_old text;
begin
  if p_verdict not in ('guilty', 'not_guilty') then raise exception 'Choose guilty or not guilty.' using errcode = 'P0001', hint = 'bad_verdict'; end if;
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into c from court_cases where id = p_case for update;
  if not found or c.status = 'dismissed' then raise exception 'That case cannot be overridden.' using errcode = 'P0001', hint = 'no_case'; end if;
  v_old := c.verdict;
  if c.status = 'ruled' then
    if c.verdict = p_verdict then raise exception 'The case already has that verdict.' using errcode = 'P0001', hint = 'same'; end if;
    perform bl_court_reverse(c.id);
  end if;
  perform bl_court_execute(c.id, p_verdict, 'admin', 'An admin ruled on this case. Reason: ' || v_reason, v_admin);
  update court_cases set overridden = true where id = c.id;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'court_override', c.defendant_id, jsonb_build_object('case', c.id, 'case_no', c.case_no, 'old', v_old, 'new', p_verdict, 'reason', v_reason));
  return jsonb_build_object('message', c.case_no || ' is now ' || case p_verdict when 'guilty' then 'guilty' else 'not guilty' end || '. The money moved as it would for a normal ruling.');
end $$;

create or replace function public.admin_court_dismiss(p_case bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); c court_cases; h court_hires; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_ids uuid[];
begin
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into c from court_cases where id = p_case and status = 'scheduled' for update;
  if not found then raise exception 'Only an open case can be dismissed.' using errcode = 'P0001', hint = 'no_case'; end if;
  select array_agg(distinct u order by u) into v_ids from (select c.plaintiff_id as u union all select x.client_id from court_hires x where x.case_id = c.id and x.status in ('pending', 'accepted')) q;
  perform 1 from profiles where id = any (v_ids) order by id for update;
  for h in select * from court_hires where case_id = c.id and status in ('pending', 'accepted') order by id loop
    perform bl_court_hire_refund(h.id, 'refunded', 'An admin dismissed the case.');
  end loop;
  if c.filing_fee > 0 then
    perform bl_add_money(c.plaintiff_id, 'bank', c.filing_fee, 'court_fee_refund', jsonb_build_object('label', 'Filing fee returned (' || c.case_no || ')', 'case', c.case_no));
  end if;
  update court_cases set status = 'dismissed', verdict_note = 'Dismissed by an admin: ' || v_reason, ruled_at = bl_now() where id = c.id;
  insert into court_statements (case_id, side, kind, author_id, body, created_at) values (c.id, 'bench', 'ruling', v_admin, 'CASE DISMISSED by the court administrator. ' || v_reason, bl_now());
  perform bl_event(c.plaintiff_id, 'court_verdict', 'Case dismissed', c.case_no || ' was dismissed by the court. Your filing fee is back in your bank.', jsonb_build_object('case', c.id));
  perform bl_event(c.defendant_id, 'court_verdict', 'Case dismissed', c.case_no || ' was dismissed by the court.', jsonb_build_object('case', c.id));
  insert into admin_audit (admin_id, action, target_user, data) values (v_admin, 'court_dismiss', c.plaintiff_id, jsonb_build_object('case', c.id, 'case_no', c.case_no, 'reason', v_reason));
  return jsonb_build_object('message', c.case_no || ' dismissed. Fees returned.');
end $$;

create or replace function public.admin_court_appoint_judge(p_username text, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); t profiles; o ind_offices; v_id bigint; v_name text := btrim(coalesce(p_username, ''));
begin
  perform bl_ind_tick();
  select * into t from profiles where lower(username) = lower(regexp_replace(v_name, '^@', '')) and home_chosen and not banned;
  if not found then raise exception 'No player with that username.' using errcode = 'P0001', hint = 'no_player'; end if;
  select * into o from ind_offices x where x.id like 'court\_judge\_%' and x.active
     and not exists (select 1 from ind_holders h where h.office_id = x.id and h.seat_no = 1 and h.status = 'active') order by x.sort, x.id limit 1;
  if not found then raise exception 'All judge seats are filled. Remove a judge first.' using errcode = 'P0001', hint = 'filled'; end if;
  v_id := bl_ind_install(o.id, t.id, v_admin, 'admin');
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'court_judge_appoint', t.id, jsonb_build_object('holder', v_id, 'office', o.id, 'reason', left(coalesce(p_reason, ''), 200)));
  return jsonb_build_object('message', '@' || t.username || ' is now ' || o.name || '.');
end $$;

create or replace function public.admin_court_remove_judge(p_holder bigint, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); h ind_holders; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_n int;
begin
  if v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into h from ind_holders where id = p_holder and status = 'active' and office_id like 'court\_judge\_%' for update;
  if not found then raise exception 'That judge seat is already empty.' using errcode = 'P0001', hint = 'gone'; end if;
  perform bl_ind_end(h.id, 'removed', 'An admin removed you. Reason: ' || v_reason, v_admin, true);
  -- their open cases go back to the pool; the next tick finds another judge
  update court_cases set judge_id = null where judge_id = h.user_id and status = 'scheduled';
  get diagnostics v_n = row_count;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, 'court_judge_remove', h.user_id, jsonb_build_object('holder', h.id, 'office', h.office_id, 'reason', v_reason, 'cases_released', v_n));
  return jsonb_build_object('message', 'Judge removed. ' || v_n || ' open case(s) will get another judge.');
end $$;

create or replace function public.admin_court_ban_lawyer(p_user uuid, p_banned boolean, p_reason text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_admin uuid := bl_admin_guard(); l court_lawyers; h court_hires; v_reason text := left(btrim(coalesce(p_reason, '')), 200); v_n int := 0;
begin
  if coalesce(p_banned, true) and v_reason = '' then raise exception 'Give a reason (it is kept in the audit log).' using errcode = 'P0001', hint = 'reason'; end if;
  select * into l from court_lawyers where user_id = p_user for update;
  if not found then raise exception 'That player is not a registered lawyer.' using errcode = 'P0001', hint = 'not_lawyer'; end if;
  if coalesce(p_banned, true) then
    for h in select x.* from court_hires x join court_cases c on c.id = x.case_id where x.lawyer_id = p_user and x.status in ('pending', 'accepted') and c.status = 'scheduled' order by x.id loop
      perform bl_court_hire_refund(h.id, 'refunded', 'The lawyer was removed by the court.');
      v_n := v_n + 1;
    end loop;
    update court_lawyers set banned = true, available = false, ban_reason = v_reason where user_id = p_user;
    perform bl_event(p_user, 'court_hire_answer', 'You were removed as a lawyer', 'The court removed you. Reason: ' || v_reason, '{}'::jsonb);
  else
    update court_lawyers set banned = false, ban_reason = null where user_id = p_user;
  end if;
  insert into admin_audit (admin_id, action, target_user, data)
  values (v_admin, case when coalesce(p_banned, true) then 'court_lawyer_ban' else 'court_lawyer_unban' end, p_user, jsonb_build_object('reason', v_reason, 'hires_refunded', v_n));
  return jsonb_build_object('message', case when coalesce(p_banned, true) then 'Lawyer banned. ' || v_n || ' open hire(s) refunded.' else 'Lawyer reinstated.' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace and proname like 'bl\_court\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', p.sig);
  end loop;
  for p in select oid::regprocedure as sig from pg_proc where pronamespace = 'public'::regnamespace
            and proname in ('court_status', 'court_events', 'court_file', 'court_lawyers_list', 'court_lawyer_register', 'court_lawyer_update', 'court_lawyer_retire',
                            'court_hire', 'court_hire_respond', 'court_hire_cancel', 'court_case', 'court_live', 'court_post', 'court_rule', 'court_judge_take',
                            'court_gallery_join', 'court_gallery_leave', 'court_after',
                            'admin_court_overview', 'admin_court_override', 'admin_court_dismiss', 'admin_court_appoint_judge', 'admin_court_remove_judge', 'admin_court_ban_lawyer') loop
    execute format('revoke all on function %s from public, anon', p.sig);
    execute format('grant execute on function %s to authenticated, service_role', p.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
