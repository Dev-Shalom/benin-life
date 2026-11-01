-- Fix it 11: balance. Less robbery and EFCC, faster early skills (every number old -> new is in docs/BALANCE.md "Fix it").
-- GUARDED: a setting moves only while it still equals its old default, so anything the owner already tuned in Admin stays as it is.
-- Data only plus two guarded function patches; nothing touches profiles; no loops over players.
create or replace function pg_temp.fx11_set(p_key text, p_old numeric, p_new numeric) returns void
language sql as $$
  update public.game_config set value = to_jsonb(p_new)
   where key = p_key and jsonb_typeof(value) = 'number' and (value #>> '{}')::numeric = p_old
$$;

-- travel / street robbery: the base chance and the ceiling
select pg_temp.fx11_set('crime.npc_base_pct', 6, 4.5);
select pg_temp.fx11_set('crime.npc_max_pct', 35, 25);
-- one robbery takes a smaller share of the cash on you (the bank is never touched)
select pg_temp.fx11_set('crime.loss_min_pct', 20, 10);
select pg_temp.fx11_set('crime.loss_max_pct', 60, 35);
-- pickpocketing between players: thieves get caught more, take less
select pg_temp.fx11_set('crime.steal_caught_pct', 62, 70);
select pg_temp.fx11_set('crime.steal_max_pct', 15, 10);

-- EFCC: the caught chance of every Yahoo job, only where it is still the old number
update public.yahoo_jobs set caught_pct = 10 where id = 'chat_client' and caught_pct = 12;
update public.yahoo_jobs set caught_pct = 14 where id = 'romance_job' and caught_pct = 16;
update public.yahoo_jobs set caught_pct = 17 where id = 'elon_format' and caught_pct = 20;
update public.yahoo_jobs set caught_pct = 20 where id = 'big_job' and caught_pct = 24;
update public.yahoo_jobs set caught_pct = 12 where id = 'cash_out' and caught_pct = 14;

-- skills: XP earned while the skill is level 1, 2 or 3 is multiplied (levels 4+ unchanged)
insert into public.game_config (key, value, category, label, description, kind, min, max) values
('skills.early_xp_mult', '1.5', 'skills', 'Skill XP boost for levels 1 to 3',
 'Fix it 11: XP earned while a skill is at level 1, 2 or 3 is multiplied by this (1 = no boost). Level 4 and up are unaffected.', 'number', 1, 5),
('crime.robbery_cap_pct', '35', 'crime', 'Most one street robbery can take (% of cash on you)',
 'Fix it 11: hard ceiling on the share of the cash in your pocket that one robbery takes, whatever the min / max loss percents say. Bank money is never touched.', 'number', 1, 100)
on conflict (key) do nothing;

create or replace function pg_temp.fx11_patch(p_sig text, p_old text, p_new text, p_done text) returns void
language plpgsql as $$
declare v_def text; v_n int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into v_def;
  if position(p_done in v_def) > 0 then return; end if;
  v_n := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_n <> 1 then raise exception 'fixit11: % : marker found % times: %', p_sig, v_n, left(p_old, 80); end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.fx11_patch('public.bl_skill_award(uuid,text,text)',
  E'    v_old := bl_skill_level_for_xp(bl_skill_xp(p_uid, r.skill_id));\n',
  E'    v_old := bl_skill_level_for_xp(bl_skill_xp(p_uid, r.skill_id));\n    if v_old <= 3 then v_gain := greatest(v_gain, round(v_gain * bl_skill_num(''skills.early_xp_mult'', 1))::int); end if;\n',
  'skills.early_xp_mult');

select pg_temp.fx11_patch('public.bl_roll_street_robbery(uuid,text,text,numeric)',
  E'  v_amount := least(v_cash, greatest(1, floor(v_cash * v_pct / 100.0)))::bigint;\n',
  E'  v_amount := least(v_cash, greatest(1, floor(v_cash * v_pct / 100.0)))::bigint;\n  v_amount := least(v_amount, greatest(1, floor(v_cash * coalesce(bl_cfg(''crime.robbery_cap_pct''), 100) / 100.0)))::bigint;\n',
  'crime.robbery_cap_pct');
notify pgrst, 'reload schema';
