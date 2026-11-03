-- Profile photos for everyone (staff, manager, secretary, committee, members).
-- People can add their own photo; the bosses can add anyone's. Photos are kept in the Supabase storage folder "photos".
-- Safe to run again.
alter table public.profiles add column if not exists photo_url text;

insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
on conflict (id) do update set public = true;
drop policy if exists "anyone views photos" on storage.objects;
create policy "anyone views photos" on storage.objects for select using (bucket_id = 'photos');
drop policy if exists "upload own photo or admin" on storage.objects;
create policy "upload own photo or admin" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));
drop policy if exists "change own photo or admin" on storage.objects;
create policy "change own photo or admin" on storage.objects for update to authenticated
  using (bucket_id = 'photos' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));
drop policy if exists "remove own photo or admin" on storage.objects;
create policy "remove own photo or admin" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));

create or replace function public.set_profile_photo(pid uuid, url text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or (pid <> auth.uid() and not public.is_admin()) then raise exception 'You can only change your own photo.'; end if;
  if url is not null and url !~ '^https://' then raise exception 'That isn''t a valid photo.'; end if;
  update public.profiles set photo_url = url where id = pid;
end $$;
grant execute on function public.set_profile_photo(uuid, text) to authenticated;

-- Staff list and club officers now include the photo
drop function if exists public.get_staff();
create or replace function public.get_staff()
returns table (id uuid, first_name text, last_name text, skill text, role text, photo_url text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.first_name, p.last_name, p.skill, p.role, p.photo_url from public.profiles p
  where public.is_staff_or_admin() and p.role in ('staff', 'admin') and p.skill is not null
  order by p.first_name, p.last_name;
$$;
grant execute on function public.get_staff() to authenticated;

drop function if exists public.club_officers();
create or replace function public.club_officers()
returns table (id uuid, first_name text, last_initial text, title text, photo_url text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.first_name, left(coalesce(p.last_name, ''), 1), coalesce(p.title, 'Club'), p.photo_url
  from public.profiles p
  where p.role = 'admin' and p.id <> auth.uid()
    and exists (select 1 from public.profiles me where me.id = auth.uid() and (me.role in ('admin', 'staff') or cardinality(me.perms) > 0))
  order by p.title, p.first_name;
$$;
grant execute on function public.club_officers() to authenticated;
select 'done' as result;
