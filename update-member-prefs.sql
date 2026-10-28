-- Member preferences: favourite nights, football team, drinks. Members can change their own; admins can read them for offers.
alter table public.profiles add column if not exists prefs jsonb;
grant update (prefs) on public.profiles to authenticated;
