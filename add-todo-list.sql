-- To-do list for the bosses (e.g. Sam): add things as he goes, from a message at one tap or typed in.
-- Each person has their own list. Safe to run again.
create table if not exists public.todos (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  body        text not null check (length(trim(body)) between 1 and 600),
  from_note   text check (from_note is null or length(from_note) <= 120),
  done        boolean not null default false,
  done_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists todos_user_idx on public.todos (user_id, done, created_at desc);
alter table public.todos enable row level security;
drop policy if exists "own to-do list" on public.todos;
create policy "own to-do list" on public.todos for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_admin());
grant select, insert, update, delete on public.todos to authenticated;
select 'To-do list ready' as done;
