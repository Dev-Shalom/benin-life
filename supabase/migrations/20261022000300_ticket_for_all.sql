-- Godfather ticket for everybody (owner: "nothing can stop a Godfather, even jail"). Idempotent.
-- Before: the ticket only waived age, Charisma, education / career and the clean record, and was refused for players who already
-- qualified. Now: anybody can buy it while registration is open, jail included; the only conditions are the price and the money.
-- The ward rule (a Councillor runs where they live), one candidacy per election, the race cap and the promise moderation stay.

create or replace function public.bl_pol_ticket_info(p_uid uuid, o public.offices) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_req jsonb; v_fail int; v_on boolean := bl_pol_flag('pol.ticket_enabled', true) and o.elected and o.ticket_price is not null;
begin
  if not v_on then return jsonb_build_object('price', null, 'available', false, 'needed', false); end if;
  v_req := bl_pol_requirements(p_uid, o);
  select count(*) filter (where not (c->>'ok')::boolean) into v_fail from jsonb_array_elements(v_req->'checks') c;
  return jsonb_build_object('price', o.ticket_price, 'available', true, 'needed', v_fail > 0);
end $$;

create or replace function public.pol_declare(p_office text, p_ward text default null, p_promise text default '', p_party text default null, p_ticket boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := bl_require_uid(); c election_cycles; o offices; w wards; me profiles; v_req jsonb; v_slot text; v_promise text; v_n int; v_id bigint; v_home text;
  v_ticket bigint := 0; v_from timestamptz; v_pct numeric;
begin
  perform bl_pol_tick(); perform bl_pol_guard();
  select * into c from bl_pol_open_cycle();
  if c.id is null or c.status <> 'registration' then
    raise exception 'Candidate registration is not open right now.' using errcode = 'P0001', hint = 'registration_closed';
  end if;
  select * into me from profiles where id = v_uid for update;
  select * into o from offices where id = p_office and active and elected;
  if not found then
    raise exception 'You cannot run for that office.' using errcode = 'P0001', hint = 'bad_office';
  end if;
  if o.ward_scoped then
    v_home := bl_pol_ward_of(v_uid);
    select * into w from wards where id = coalesce(nullif(p_ward, ''), v_home) and active;
    if not found or w.id <> v_home then
      raise exception 'A Councillor runs in the ward where they live (%). Move house to run somewhere else.', (select name from wards where id = v_home) using errcode = 'P0001', hint = 'wrong_ward';
    end if;
  end if;
  v_slot := bl_pol_slot(o.id, w.id);
  if exists (select 1 from pol_candidates where cycle_id = c.id and user_id = v_uid and status = 'declared') then
    raise exception 'You are already a candidate in this election. Withdraw first to change your race.' using errcode = 'P0001', hint = 'already_candidate';
  end if;
  v_req := bl_pol_requirements(v_uid, o);
  if coalesce(p_ticket, false) then
    if not bl_pol_flag('pol.ticket_enabled', true) or o.ticket_price is null then
      raise exception 'There is no Godfather ticket for %.', o.name using errcode = 'P0001', hint = 'ticket_off';
    end if;
    -- the ticket waives EVERYTHING (owner: nothing can stop a Godfather, jail included): the only conditions are the price and the money.
    -- A player who already qualifies may buy it too (tag, probe and price all apply).
    v_ticket := o.ticket_price;
  elsif not (v_req->>'ok')::boolean then
    raise exception '%', v_req->>'message' using errcode = 'P0001', hint = v_req->>'hint';
  end if;
  v_promise := bl_pol_moderate(p_promise, 10, bl_pol_num('pol.promise_max_len', 140)::int, 'promise');
  if p_party is not null and btrim(p_party) <> '' and not exists (select 1 from parties where id = btrim(p_party) and active) then
    raise exception 'Pick a party from the list, or run as an independent.' using errcode = 'P0001', hint = 'bad_party';
  end if;
  select count(*) into v_n from pol_candidates where cycle_id = c.id and slot_key = v_slot and status = 'declared';
  if v_n >= bl_pol_num('pol.max_candidates_per_slot', 8) then
    raise exception 'That race is full (% candidates).', v_n using errcode = 'P0001', hint = 'race_full';
  end if;
  -- fee + ticket together, all or nothing: the same pay rule (bank first, then cash)
  if v_ticket > 0 and me.cash + greatest(me.bank, 0) < o.fee + v_ticket then
    raise exception 'Not enough money. The fee and the ticket cost % together and you have % (bank % + cash %).', bl_naira(o.fee + v_ticket),
      bl_naira(me.cash + greatest(me.bank, 0)), bl_naira(greatest(me.bank, 0)), bl_naira(me.cash) using errcode = 'P0001', hint = 'not_enough_cash';
  end if;
  perform bl_pol_pay(v_uid, o.fee, 'campaign_fee', jsonb_build_object('label', 'Candidacy fee: ' || o.name, 'office', o.id));
  if v_ticket > 0 then
    perform bl_pol_pay(v_uid, v_ticket, 'godfather_ticket', jsonb_build_object('label', 'Godfather ticket: ' || o.name, 'office', o.id));
  end if;
  insert into pol_candidates (cycle_id, office_id, ward_id, slot_key, user_id, party_id, promise, fee_paid, ticket_paid, declared_at)
  values (c.id, o.id, w.id, v_slot, v_uid, nullif(btrim(coalesce(p_party, '')), ''), v_promise, o.fee, v_ticket, bl_now()) returning id into v_id;
  if v_ticket > 0 then
    -- the secret probe: does EFCC catch them, and when (any moment of the campaign window, from now on)
    v_pct := least(greatest(bl_pol_num('pol.ticket_probe_pct', 25), 0), 100);
    v_from := greatest(bl_now(), c.camp_start);
    insert into pol_ticket_probes (candidate_id, cycle_id, catch, probe_at)
    values (v_id, c.id, random() * 100 < v_pct, v_from + (c.vote_start - v_from) * random());
  end if;
  perform bl_skill_award(v_uid, 'politics', 'declare');
  return jsonb_build_object('id', v_id, 'message', 'You are a candidate for ' || o.name || coalesce(' in ' || w.name, '') || '. Campaign season starts when registration closes.'
    || case when v_ticket > 0 then ' Your Godfather ticket is on your card for everybody to see.' else '' end);
end $$;

revoke all on function public.pol_declare(text, text, text, text, boolean) from public, anon;
grant execute on function public.pol_declare(text, text, text, text, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';
