-- Photos next to messages: members see the photo of the club officer (e.g. the Secretary) who messaged them.
-- Run after update-profile-photos.sql. Safe to run again.
drop function if exists public.msg_contacts();
create function public.msg_contacts()
returns table (id uuid, first_name text, last_initial text, title text, is_club boolean, photo_url text)
language sql stable security definer set search_path = '' as $$
  select distinct p.id, p.first_name, left(coalesce(p.last_name, ''), 1), p.title, p.role = 'admin', p.photo_url
  from public.member_messages m
  join public.profiles p on p.id = case when m.sender = auth.uid() then m.recipient else m.sender end
  where auth.uid() in (m.sender, m.recipient);
$$;
grant execute on function public.msg_contacts() to authenticated;
select 'Message photos ready' as done;
