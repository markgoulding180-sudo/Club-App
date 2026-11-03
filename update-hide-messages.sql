-- Staff can close (hide) a message in the app. The message itself is never deleted, it stays as a record;
-- this only remembers who closed which one. Safe to run again.
create table if not exists public.hidden_messages (
  user_id   uuid not null default auth.uid() references auth.users on delete cascade,
  item_key  text not null check (length(item_key) <= 60),
  hidden_at timestamptz not null default now(),
  primary key (user_id, item_key)
);
alter table public.hidden_messages enable row level security;
drop policy if exists "own hidden messages" on public.hidden_messages;
create policy "own hidden messages" on public.hidden_messages for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant all on public.hidden_messages to authenticated;
select 'done' as result;
