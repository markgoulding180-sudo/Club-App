-- TEST APP ONLY: two colleagues answer Heather's "Ask everyone" swap by each offering one of their shifts back.
-- (Does the same as Yannika and Joe tapping "Offer this shift" in their app.) Heather then picks one in her app.
do $$
declare h uuid; r public.swap_requests; a public.shifts; who text; p uuid; b public.shifts; n int := 0;
begin
  select id into h from public.profiles where lower(email) = 'heather@railway.com';
  select * into r from public.swap_requests where staff_id = h and status = 'open' order by created_at desc limit 1;
  if r.id is null then raise exception 'Heather has no open swap request. As Heather, tap a shift and Ask everyone first.'; end if;
  select * into a from public.shifts where id = r.shift_id;
  foreach who in array array['yannika@railway.com', 'joe@railway.com', 'jamie@railway.com', 'adam@railway.com'] loop
    exit when n = 2;
    select id into p from public.profiles where lower(email) = who;
    continue when exists (select 1 from public.swap_offers where request_id = r.id and staff_id = p);
    continue when exists (select 1 from public.shifts where staff_id = p and shift_date = a.shift_date and status in ('assigned', 'confirmed', 'late'));
    select s.* into b from public.shifts s
     where s.staff_id = p and s.status in ('assigned', 'confirmed') and s.shift_date > current_date and s.shift_date <> a.shift_date
       and public.rota_published(s.shift_date)
       and not exists (select 1 from public.shifts x where x.staff_id = h and x.shift_date = s.shift_date and x.status in ('assigned', 'confirmed', 'late'))
       and not exists (select 1 from public.staff_unavailability u where u.staff_id = h and u.off_date = s.shift_date)
     order by s.shift_date limit 1;
    continue when b.id is null;
    insert into public.swap_offers (request_id, shift_id, staff_id) values (r.id, b.id, p);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'No one could offer a shift back for that day.'; end if;
end $$;

-- Check: what Heather has been offered
select p.first_name || ' offers ' || s.job || ' ' || s.session || ' ' || to_char(s.shift_date, 'Dy DD Mon')
       || '  for Heather''s ' || a.job || ' ' || a.session || ' ' || to_char(a.shift_date, 'Dy DD Mon') as offers
from public.swap_offers o join public.swap_requests r on r.id = o.request_id
join public.shifts s on s.id = o.shift_id join public.shifts a on a.id = r.shift_id join public.profiles p on p.id = o.staff_id
where r.status = 'open' and o.status = 'offered' and r.staff_id = (select id from public.profiles where lower(email) = 'heather@railway.com');
