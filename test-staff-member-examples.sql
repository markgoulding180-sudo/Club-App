-- Test examples for the "Staff Member" account (staff@railway.com) on the 2 Nov – 29 Nov 2026 rota.
-- Run AFTER update-rota-periods.sql. Safe to run again: it clears and re-adds the same examples.
do $$
declare
  me  uuid; ben uuid; sam uuid; hol bigint;
  s_sat7 bigint; s_fri20 bigint; s_ben10 bigint; s_sam11 bigint;
begin
  select id into me from public.profiles where email ilike 'staff@railway.com' limit 1;
  if me is null then select id into me from public.profiles where first_name = 'Staff' and last_name = 'Member' order by id limit 1; end if;
  if me is null then raise exception 'Can''t find the Staff Member account.'; end if;
  select id into ben from public.profiles where first_name ilike 'Ben%' and id <> me and role in ('staff', 'admin') limit 1;
  select id into sam from public.profiles where first_name ilike 'Sam%' and id <> me and id is distinct from ben and role in ('staff', 'admin') limit 1;
  if ben is null or sam is null then raise exception 'Need staff called Ben and Sam for the swap examples.'; end if;

  update public.profiles set role = 'staff', skill = 'both' where id = me;

  -- Clear old examples
  delete from public.shift_swaps where from_staff = me or to_staff = me;
  delete from public.staff_unavailability where staff_id = me and off_date between '2026-11-02' and '2026-12-31';
  delete from public.holiday_requests where staff_id = me and note like 'Example:%';
  delete from public.shifts where staff_id = me and shift_date between '2026-11-02' and '2026-11-29';
  delete from public.shifts where staff_id in (ben, sam) and shift_date in ('2026-11-06','2026-11-07','2026-11-10','2026-11-11','2026-11-12','2026-11-14','2026-11-20');
  -- Free the slots used below so the rota doesn't show two people on one bar
  delete from public.shifts where session = 'eve' and job = 'lounge' and staff_id <> me
    and shift_date in ('2026-11-06','2026-11-07','2026-11-12','2026-11-14','2026-11-20','2026-11-21');

  -- Publish the November rota so staff can see it
  insert into public.rota_periods (start_date, published_at) values ('2026-11-02', now())
  on conflict (start_date) do update set published_at = coalesce(public.rota_periods.published_at, now());

  -- 1. Normal shifts
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-06', 'eve', 'lounge', me);
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-21', 'eve', 'lounge', me);
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-07', 'eve', 'lounge', me) returning id into s_sat7;
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-20', 'eve', 'lounge', me) returning id into s_fri20;

  -- 2. Can't work, waiting for the manager (Thu 12 Nov)
  insert into public.shifts (shift_date, session, job, staff_id, status, reason)
  values ('2026-11-12', 'eve', 'lounge', me, 'cannot_work', 'Hospital appointment');

  -- 3. Can't work, approved: Ben is covering (Sat 14 Nov)
  insert into public.shifts (shift_date, session, job, staff_id, status, reason, covered, decision, decided_at)
  values ('2026-11-14', 'eve', 'lounge', me, 'cannot_work', 'Family wedding', true, 'approved', now());
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-14', 'eve', 'lounge', ben);

  -- 4. Unavailable day (Tue 17 Nov)
  insert into public.staff_unavailability (staff_id, off_date, reason) values (me, '2026-11-17', 'Family event');

  -- 5. Approved holiday 24–26 Nov, and a holiday request waiting 8–9 Dec
  insert into public.holiday_requests (staff_id, days, note, status, decided_at)
  values (me, array['2026-11-24','2026-11-25','2026-11-26']::date[], 'Example: short break', 'approved', now()) returning id into hol;
  insert into public.staff_unavailability (staff_id, off_date, reason, holiday_id)
  select me, d::date, 'Holiday', hol from unnest(array['2026-11-24','2026-11-25','2026-11-26']) d;
  insert into public.holiday_requests (staff_id, days, note, status)
  values (me, array['2026-12-08','2026-12-09']::date[], 'Example: Christmas shopping trip', 'pending');

  -- 6. Ben asks Staff Member to swap: Ben's Tue 10 Nov for Staff Member's Fri 20 Nov (Staff Member to answer)
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-10', 'eve', 'lounge', ben) returning id into s_ben10;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (s_ben10, s_fri20, ben, me, 'It''s my son''s birthday on the 20th', 'asked');

  -- 7. Staff Member asked Sam to swap Sat 7 Nov for Sam's Wed 11 Nov. Sam said yes, so it's waiting for the manager.
  insert into public.shifts (shift_date, session, job, staff_id) values ('2026-11-11', 'eve', 'lounge', sam) returning id into s_sam11;
  insert into public.shift_swaps (from_shift, to_shift, from_staff, to_staff, note, status)
  values (s_sat7, s_sam11, me, sam, 'Going to a concert on the 7th', 'accepted');
end $$;
