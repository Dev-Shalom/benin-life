-- Owner (2026-10-14): picking sprayed money is a little shameful. Pickers get a 🙈 tag over their head (client),
-- the hype man teases them by name with a random line, and there is NO top-picker list any more.
-- 1. stop the end-of-drop "top picker" shout-out (guarded: only if still at the SP2 default)
update public.game_config set value = 'false'::jsonb where key = 'club.pick_summary' and value = 'true'::jsonb;
-- 2. the 'pick' MC pool becomes teasing lines ({user}, {amount} = what they grabbed first)
insert into public.hype_templates (id, kind, line, ticker, sort, active) values
('pick.1',  'pick', 'Ehen! @{user} don bend down pick {amount} for club floor! Shame no dey catch you? 🙈', '', 1, true),
('pick.2',  'pick', '@{user} abeg stand up! Na spray money for the celebrant, no be your salary o! 🙈', '', 2, true),
('pick.3',  'pick', 'Una see @{user}? E dey pick money for floor like say na palm kernel! 😂', '', 3, true),
('pick.4',  'pick', 'DJ hold am! @{user} don start to gather naira for ground. Who invite this one? 🙈', '', 4, true),
('pick.5',  'pick', '@{user} na your papa spray am? Leave the money for floor, oga! 😂', '', 5, true),
('pick.6',  'pick', 'Breaking news: @{user} caught picking {amount} for club floor! Mama go hear this one! 🙈', '', 6, true),
('pick.7',  'pick', '@{user} you no fit wait make dem sweep? Picking money like say na Christmas bonus! 😂', '', 7, true),
('pick.8',  'pick', 'Camera dey roll o @{user}! Picking money for floor, your village people dey watch! 🙈', '', 8, true),
('pick.9',  'pick', '@{user} don turn cleaner tonight! Sweeping naira with bare hand! 😂', '', 9, true),
('pick.10', 'pick', 'Respect yourself @{user}! Big boy no dey pick money for floor! 🙈', '', 10, true),
('pick.11', 'pick', '@{user} hunger don reach am! E dey pick {amount} for ground, somebody buy am food! 😂', '', 11, true),
('pick.12', 'pick', 'Oya everybody shout am: @{user} PICKER! 🙈 No vex, na play we dey play o!', '', 12, true),
('pick.13', 'pick', '@{user} no gree waste time! Spray land, e don land on top am! Shameless legend! 😂', '', 13, true),
('pick.14', 'pick', 'Somebody tell @{user} say e no dey for market! Na club be this, stop to pick money! 🙈', '', 14, true),
('pick.15', 'pick', '@{user} na professional picker! Even the cleaner dey vex for am now! 😂', '', 15, true)
on conflict (id) do update set line = excluded.line, active = true;
notify pgrst, 'reload schema';
