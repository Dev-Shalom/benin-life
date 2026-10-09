-- Adapt the older shared local database's furniture table inside sql-test.sh's rollback-only
-- transaction so the latest starter-furniture and house-visit migrations can be exercised.
alter table public.furniture add column if not exists slot text not null default 'misc';
alter table public.furniture add column if not exists activities text[] not null default '{}';
alter table public.furniture add column if not exists rest_pct integer not null default 100;
alter table public.furniture add column if not exists color text;

create table if not exists public.player_furniture (
  user_id uuid not null references public.profiles(id) on delete cascade,
  furniture_id text not null references public.furniture(id) on delete cascade,
  slot text,
  source text not null default 'starter',
  created_at timestamptz not null default now(),
  primary key (user_id, furniture_id)
);
alter table public.player_furniture enable row level security;
drop policy if exists player_furniture_own on public.player_furniture;
create policy player_furniture_own on public.player_furniture for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.player_furniture from anon, authenticated;
grant select on public.player_furniture to authenticated;
