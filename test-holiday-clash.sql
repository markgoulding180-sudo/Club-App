-- TEST APP ONLY (Club-APP-test): sets up a holiday clash so you can see the "who's already off" box.
-- Adam and Luis get APPROVED holiday on Fri 27 – Sat 28 Nov (2 people off = the limit).
-- Joe ASKS for Thu 26 – Sat 28 Nov (waiting), so he shows as "⏳ asked".
-- Then as Heather, ask for Sat 28 Nov and open it as Sam: it should go red ("Approving makes 3"). Safe to run again.
-- (Approves directly, the same way the app does, so it works in the SQL editor where no one is signed in.)
do $$
declare adam uuid; luis uuid; joe uuid; mark uuid; r record;
begin
  select id into adam from public.profiles where lower(email) = 'adam@railway.com';
  select id into luis from public.profiles where lower(email) = 'luis@railway.com';
  select id into joe  from public.profiles where lower(email) = 'joe@railway.com';
  select id into mark from public.profiles where lower(email) = 'mark@railway.com';
  -- clear any earlier run
  delete from public.staff_unavailability where holiday_id in (select id from public.holiday_requests where staff_id in (adam, luis, joe) and days && array['2026-11-26','2026-11-27','2026-11-28']::date[]);
  update public.shifts set status = 'assigned', reason = null where staff_id in (adam, luis) and shift_date in ('2026-11-27','2026-11-28') and status = 'cannot_work' and reason = 'Holiday';
  delete from public.holiday_requests where staff_id in (adam, luis, joe) and days && array['2026-11-26','2026-11-27','2026-11-28']::date[];

  insert into public.holiday_requests (staff_id, days, status, note, decided_by, decided_at) values
    (adam, array['2026-11-27','2026-11-28']::date[], 'approved', 'Weekend away', mark, now()),
    (luis, array['2026-11-27','2026-11-28']::date[], 'approved', 'Wedding', mark, now());
  insert into public.holiday_requests (staff_id, days, status, note) values
    (joe,  array['2026-11-26','2026-11-27','2026-11-28']::date[], 'pending', 'Family visit');

  -- what approving does: mark the days off and take them off any shifts
  for r in select * from public.holiday_requests where staff_id in (adam, luis) and status = 'approved' and days @> array['2026-11-27']::date[] loop
    insert into public.staff_unavailability (staff_id, off_date, reason, holiday_id)
      select r.staff_id, d, 'Holiday', r.id from unnest(r.days) d on conflict (staff_id, off_date) do nothing;
    update public.shifts set status = 'cannot_work', reason = 'Holiday'
      where staff_id = r.staff_id and shift_date = any(r.days) and status in ('assigned', 'confirmed');
  end loop;
end $$;

select p.first_name, h.days, h.status from public.holiday_requests h join public.profiles p on p.id = h.staff_id
where h.days && array['2026-11-26','2026-11-27','2026-11-28']::date[] order by h.status, p.first_name;
