-- FULL RESET: deletes EVERY account except markgoulding180@gmail.com (staff, admins, members, test logins),
-- the membership register, and all data: bookings, What's On, rota, shifts, swaps, holidays, staff records,
-- messages, friends, Going/Interested, notices, jobs, payments, tickets, closed days.
-- Mark stays as App admin with full access. THIS CANNOT BE UNDONE.
do $$
declare t text; list text := ''; me uuid;
begin
  select id into me from auth.users where lower(email) = 'markgoulding180@gmail.com';
  if me is null then raise exception 'Stopped: markgoulding180@gmail.com not found, nothing was deleted.'; end if;

  -- 1) Empty every data table
  foreach t in array array['cover_calls','staff_messages','member_messages','friendships','event_rsvps','notice_reads','club_notices',
    'job_applications','jobs','club_members','shift_swaps','swap_offers','swap_requests','shift_offers','shifts','staff_unavailability',
    'holiday_requests','staff_notes','rota_periods','ticket_reservations','payments','bookings','events','closed_days'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' restart identity cascade';

  -- 2) Delete every login except Mark (their profiles go with them)
  delete from auth.users where id <> me;

  -- 3) Mark: App admin, everything, fresh
  update public.profiles set role = 'admin', title = 'App admin', perms = array['owner'], regular_shifts = '[]'::jsonb where id = me;
end $$;

-- Check: accounts should be 1 (you), everything else 0
select (select count(*) from auth.users) as accounts,
       (select count(*) from public.profiles where role = 'staff') as staff,
       (select count(*) from public.club_members) as register,
       (select count(*) from public.bookings) as bookings,
       (select count(*) from public.events) as whats_on,
       (select count(*) from public.shifts) as shifts,
       (select count(*) from public.member_messages) as messages;
select email, role, title, perms from public.profiles;
