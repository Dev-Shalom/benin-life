-- Owner: more seats in Benin Votes. Three new city-wide elected offices next to Councillor / Chairman / Governor.
-- They use kind 'chairman' (a plain elected seat: title, badge, salary, race on every ballot, no Governor or Councillor powers),
-- so every existing rule (requirements, Godfather ticket, ballots, tallies, terms, salaries) applies without code changes.
-- Every number is editable in Admin -> Content -> Offices. Idempotent: seeded once, an admin edit is never overwritten.
insert into public.offices (id, name, kind, title, icon, blurb, elected, ward_scoped, salary_per_day, fee, min_charisma, min_account_days,
                            cert_any, alt_job_level, ticket_price, sort) values
('youth_leader', 'Youth Leader of Benin', 'chairman', 'Youth Ldr.', '🧢',
 'The voice of the young people of Benin City. The easiest seat to win: perfect for new politicians. Every ward votes.',
 true, false, 5000, 5000, 1, 1, '{}', 0, 1000000000, 4),
('speaker', 'Speaker of the House', 'chairman', 'Rt. Hon.', '🔨',
 'Leads the House and keeps order. A proper big title, without the Governor''s headaches. Every ward votes.',
 true, false, 20000, 30000, 2, 5, '{}', 0, 15000000000, 5),
('deputy_governor', 'Deputy Governor', 'chairman', 'Dep. Gov.', '🎖️',
 'Number two in the state. Sits at the top table next to the Governor. Every ward votes.',
 true, false, 35000, 150000, 3, 7, '{}', 0, 35000000000, 6)
on conflict (id) do nothing;
notify pgrst, 'reload schema';
