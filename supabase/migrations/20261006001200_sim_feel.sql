-- M2 "Movement & task feel" (docs/HUD_HOME.md "M2 movement & task feel").
-- Idempotent and safe on a non-empty DB:
--   * config: sim.walk_speed, sim.robe_speed_mult, sim.tired_slowdown (read by the client's walker) and
--     action.queue_max (client-side action queue length). Inserted only when missing; admin edits are kept.
--   * home.walk_max_share_pct is no longer used (the Sim always walks first, then the action starts);
--     the key stays (value untouched) and its description says so.
--   * activity_stop(): the small x on the task pill. Ends the running activity now and keeps the part of
--     the need change earned so far (same ease-out curve as the live bars, so nothing jumps). No refund.
--     Work shifts, travel, jail and hospital cannot be stopped this way.

insert into public.game_config (key, value, category, label, description, kind, min, max) values
('sim.walk_speed', '1.9', 'sim', 'Walk speed (m/s)',
 'How fast the Sim walks at home in trousers (metres per second). The stride and step rate follow, so the feet never slide.',
 'number', 0.5, 4),
('sim.robe_speed_mult', '0.7', 'sim', 'Robe / wrapper walk speed (x)',
 'Walk speed in a long robe, wrapper or maxi as a share of the normal walk speed (short, quick steps). Skirts sit halfway.',
 'number', 0.3, 1.5),
('sim.tired_slowdown', '0.18', 'sim', 'Tired slow-down',
 'How much slower a very tired Sim walks (0.18 = 18 % slower when exhausted; scales with tiredness).',
 'number', 0, 0.8),
('action.queue_max', '5', 'action', 'Action queue length',
 'How many tasks a player can line up (the one running counts). Tasks run one after another; the Sim walks to each spot first.',
 'number', 1, 20)
on conflict (key) do nothing;

update public.game_config
   set description = 'Not used since M2: the Sim now always walks to the furniture first and the action starts on arrival. Kept for older clients.'
 where key = 'home.walk_max_share_pct'
   and description not like 'Not used since M2%';

-- ---------------------------------------------------------------------
-- activity_stop(): end the running activity early
-- ---------------------------------------------------------------------
create or replace function public.activity_stop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me    profiles := bl_me();
  v_now   timestamptz := bl_now();
  v_from  jsonb;
  v_f     numeric;
  v_e     numeric;
begin
  if v_me.busy_until is null or v_me.busy_until <= v_now then
    return jsonb_build_object('stopped', false, 'message', 'Nothing is running.');
  end if;
  if v_me.job_shift_ends_at is not null and v_me.job_shift_ends_at = v_me.busy_until then
    raise exception 'A work shift can''t be stopped halfway. It ends soon.' using errcode = 'P0001', hint = 'shift';
  end if;
  v_from := v_me.busy_needs_from;
  if v_from is null or v_me.busy_started_at is null or v_me.busy_started_at >= v_me.busy_until then
    raise exception 'This one can''t be stopped. It ends soon.' using errcode = 'P0001', hint = 'not_stoppable';
  end if;
  v_f := greatest(0, least(1, extract(epoch from v_now - v_me.busy_started_at)
                              / extract(epoch from v_me.busy_until - v_me.busy_started_at)));
  v_e := 1 - (1 - v_f) * (1 - v_f); -- the live bars' ease-out (src/lib/live.ts)
  update profiles set
    hunger  = round(coalesce((v_from->>'hunger')::numeric,  hunger)  + (hunger  - coalesce((v_from->>'hunger')::numeric,  hunger))  * v_e, 4),
    energy  = round(coalesce((v_from->>'energy')::numeric,  energy)  + (energy  - coalesce((v_from->>'energy')::numeric,  energy))  * v_e, 4),
    hygiene = round(coalesce((v_from->>'hygiene')::numeric, hygiene) + (hygiene - coalesce((v_from->>'hygiene')::numeric, hygiene)) * v_e, 4),
    fun     = round(coalesce((v_from->>'fun')::numeric,     fun)     + (fun     - coalesce((v_from->>'fun')::numeric,     fun))     * v_e, 4),
    social  = round(coalesce((v_from->>'social')::numeric,  social)  + (social  - coalesce((v_from->>'social')::numeric,  social))  * v_e, 4),
    stress  = round(coalesce((v_from->>'stress')::numeric,  stress)  + (stress  - coalesce((v_from->>'stress')::numeric,  stress))  * v_e, 4),
    health  = round(coalesce((v_from->>'health')::numeric,  health)  + (health  - coalesce((v_from->>'health')::numeric,  health))  * v_e, 4),
    bladder = round(coalesce((v_from->>'bladder')::numeric, bladder) + (bladder - coalesce((v_from->>'bladder')::numeric, bladder)) * v_e, 4),
    busy_until = v_now,
    busy_needs_from = null
  where id = v_me.id;
  return jsonb_build_object('stopped', true, 'label', v_me.busy_label, 'kept_pct', round(v_e * 100),
                            'message', 'You stopped "' || coalesce(v_me.busy_label, 'that') || '".');
end $$;

revoke execute on function public.activity_stop() from public, anon;
grant execute on function public.activity_stop() to authenticated;
