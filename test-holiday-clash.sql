-- TEST APP ONLY (Club-APP-test): sets up a holiday clash so you can see the "who's already off" box.
-- Adam and Luis are given APPROVED holiday on Fri 27 – Sat 28 Nov (2 people off = the limit).
-- Joe ASKS for Thu 26 – Sat 28 Nov (waiting), so he shows as "⏳ asked".
-- Then as Heather, ask for Sat 28 Nov and open it as Sam: it should go red ("Approving makes 3"). Safe to run again.
do $$
declare adam uuid; luis uuid; joe uuid;
begin
  select id into adam from public.profiles where lower(email) = 'adam@railway.com';
  select id into luis from public.profiles where lower(email) = 'luis@railway.com';
  select id into joe  from public.profiles where lower(email) = 'joe@railway.com';
  delete from public.holiday_requests where staff_id in (adam, luis, joe) and days && array['2026-11-26','2026-11-27','2026-11-28']::date[];
  insert into public.holiday_requests (staff_id, days, status, note) values
    (adam, array['2026-11-27','2026-11-28']::date[], 'pending', 'Weekend away'),
    (luis, array['2026-11-27','2026-11-28']::date[], 'pending', 'Wedding'),
    (joe,  array['2026-11-26','2026-11-27','2026-11-28']::date[], 'pending', 'Family visit');
  -- approve Adam and Luis the normal way, so they come off their shifts and the days are marked
  -- act as Mark (App admin) so the approve function allows it: Supabase reads request.jwt.claim.sub / request.jwt.claims
  perform set_config('request.jwt.claim.sub', (select id::text from public.profiles where lower(email) = 'mark@railway.com'), true);
  perform set_config('request.jwt.claims', json_build_object('sub', (select id::text from public.profiles where lower(email) = 'mark@railway.com'), 'role', 'authenticated')::text, true);
  perform set_config('request.uid', (select id::text from public.profiles where lower(email) = 'mark@railway.com'), true);
  perform public.admin_decide_holiday(h.id, 'approved', null) from public.holiday_requests h where h.staff_id in (adam, luis) and h.status = 'pending' and h.days @> array['2026-11-27']::date[];
end $$;

select p.first_name, h.days, h.status from public.holiday_requests h join public.profiles p on p.id = h.staff_id
where h.days && array['2026-11-26','2026-11-27','2026-11-28']::date[] order by h.status, p.first_name;
