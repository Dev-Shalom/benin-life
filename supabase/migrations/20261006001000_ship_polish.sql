-- Benin Life — S1 quick polish (docs/SHIP_TODAY.md S1).
-- 1. Anti-farming: new accounts wait 24 h (1440 real minutes) before sending bank transfers,
--    but only if the admin has not tuned the old default (30) away.
-- 2. The phone food app is now "Chowdeck" (was ChopNow): rename the player-visible server strings.
--    RPC names / ids (food_order, food_menu, 'food_delivery') stay the same.
-- Idempotent: safe to run twice and on a non-empty DB.

-- ---------- 1. transfer wait for new accounts ----------
update public.game_config
   set value = '1440'::jsonb, updated_at = now()
 where key = 'bank.transfer_min_account_real_minutes'
   and value = '30'::jsonb;

-- ---------- 2. ChopNow -> Chowdeck (display strings only) ----------
update public.game_config
   set label = replace(label, 'ChopNow', 'Chowdeck'),
       description = replace(description, 'ChopNow', 'Chowdeck')
 where label like '%ChopNow%' or description like '%ChopNow%';

-- Re-create the two functions whose messages name the app, from their live definitions
-- (keeps the latest body, owner and grants; only the brand string changes).
do $$
declare
  f   regprocedure;
  src text;
begin
  foreach f in array array['public.food_order(text, int)'::regprocedure,
                           'public.bl_ledger_label(text, jsonb)'::regprocedure] loop
    src := pg_get_functiondef(f);
    if position('ChopNow' in src) > 0 then
      execute replace(src, 'ChopNow', 'Chowdeck');
    end if;
  end loop;
end $$;
