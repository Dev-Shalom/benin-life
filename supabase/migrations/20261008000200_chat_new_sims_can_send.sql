-- Let brand-new Sims participate in local chat right away. Rate limits, the profanity filter,
-- reporting, and blocking remain active. Preserve an admin override if it no longer has the old default.
update public.game_config
   set value = '0',
       label = 'Minimum account age before chat (real minutes)',
       description = 'Accounts must be at least this many real minutes old before they can send. 0 = no wait.'
 where key = 'chat.min_account_real_minutes'
   and value = '5';
