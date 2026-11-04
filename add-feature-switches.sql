-- Feature switches: the App admin turns parts of the app on or off for everyone (for the roll-out).
-- A feature with no row is ON. Safe to run again.
create table if not exists public.app_features (
  key         text primary key check (key ~ '^[a-z_]{2,40}$'),
  enabled     boolean not null default true,
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid() references auth.users on delete set null
);
alter table public.app_features enable row level security;
drop policy if exists "everyone reads feature switches" on public.app_features;
create policy "everyone reads feature switches" on public.app_features for select to anon, authenticated using (true);
drop policy if exists "app admin sets feature switches" on public.app_features;
create policy "app admin sets feature switches" on public.app_features for all to authenticated
  using (public.has_perm('owner')) with check (public.has_perm('owner'));
grant select on public.app_features to anon, authenticated;
grant insert, update, delete on public.app_features to authenticated;
select 'Feature switches ready' as done;
