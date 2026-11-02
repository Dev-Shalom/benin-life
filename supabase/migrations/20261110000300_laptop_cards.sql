-- Fix it 7: MacBook and Dell laptops could not be bought.
-- The shop RPCs always allowed it (items.sold_at lists the Benin City Mall and the Bronze Tech Hub), but a place interior only shows
-- buy cards that exist as zone_actions, and the premium laptops had none: the mall aisle had only the fairly-used laptop, the Tech Hub
-- had no laptop card at all, and HK Quarters only the ThinkPad. Cards are added here (data only, seeded once, never overwritten).
insert into public.zone_actions (id, zone_id, kind, ref, label, icon, sort, active) values
('mall.shoprite.thinkpad_t480',  'mall.shoprite', 'shop', 'thinkpad_t480',  null, null, 5, true),
('mall.shoprite.elitebook_840',  'mall.shoprite', 'shop', 'elitebook_840',  null, null, 6, true),
('mall.shoprite.dell_xps_13',    'mall.shoprite', 'shop', 'dell_xps_13',    null, null, 7, true),
('mall.shoprite.macbook_air_m4', 'mall.shoprite', 'shop', 'macbook_air_m4', null, null, 8, true),
('mall.shoprite.macbook_pro_m4', 'mall.shoprite', 'shop', 'macbook_pro_m4', null, null, 9, true),
('office.desks.laptop',          'office.desks',  'shop', 'laptop',         null, null, 10, true),
('office.desks.thinkpad_t480',   'office.desks',  'shop', 'thinkpad_t480',  null, null, 11, true),
('office.desks.elitebook_840',   'office.desks',  'shop', 'elitebook_840',  null, null, 12, true),
('office.desks.dell_xps_13',     'office.desks',  'shop', 'dell_xps_13',    null, null, 13, true),
('office.desks.macbook_air_m4',  'office.desks',  'shop', 'macbook_air_m4', null, null, 14, true),
('office.desks.macbook_pro_m4',  'office.desks',  'shop', 'macbook_pro_m4', null, null, 15, true),
('hk_quarters.laptops.laptop',        'hk_quarters.laptops', 'shop', 'laptop',        null, null, 2, true),
('hk_quarters.laptops.elitebook_840', 'hk_quarters.laptops', 'shop', 'elitebook_840', null, null, 3, true)
on conflict (id) do nothing;
-- the mall's "All ShopRite items" card moves after the new cards
update public.zone_actions set sort = 20 where id = 'mall.shoprite.shop' and sort = 9;
notify pgrst, 'reload schema';
