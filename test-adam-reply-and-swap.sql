-- TEST: the manager replies to Adam's latest message, and a colleague offers a shift for Adam's swap.
-- If Adam hasn't sent a message or asked for a swap yet, this makes one for him first.
do $$
declare
  adam uuid; sam uuid; m bigint; sh record; req bigint; mate record; give record;
begin
  select id into adam from public.profiles where lower(email) = 'adam@railway.com';
  if adam is null then raise exception 'Adam''s account not found.'; end if;

  -- 1) Manager's reply
  select id into m from public.staff_messages where staff_id = adam order by created_at desc limit 1;
  if m is null then
    insert into public.staff_messages (staff_id, topic, body) values (adam, 'other', 'Can I swap one of my shifts next week?') returning id into m;
  end if;
  update public.staff_messages set reply = 'Hi Adam, no problem. Put it on Swaps and someone will pick it up. If no one can, let me know and I''ll sort it. Sam',
    status = 'done', replied_at = now() where id = m;

  -- 2) Adam's swap request (use his open one, or ask for his next shift)
  select id into req from public.swap_requests where staff_id = adam and status = 'open' order by created_at desc limit 1;
  if req is null then
    select * into sh from public.shifts where staff_id = adam and shift_date > current_date and status in ('assigned', 'confirmed') order by shift_date, session limit 1;
    if sh.id is null then raise exception 'Adam has no shifts coming up to swap. Fill the rota first.'; end if;
    insert into public.swap_requests (shift_id, staff_id, note) values (sh.id, adam, 'Family do, can anyone take this?') returning id into req;
  end if;
  select s.* into sh from public.swap_requests r join public.shifts s on s.id = r.shift_id where r.id = req;

  -- 3) A colleague who isn't working that day offers one of their shifts on a day Adam is free
  for mate in
    select p.* from public.profiles p
    where p.role = 'staff' and p.id <> adam and (p.skill = 'both' or (sh.job = 'door') = (p.skill = 'door'))
      and not exists (select 1 from public.shifts x where x.staff_id = p.id and x.shift_date = sh.shift_date and x.status in ('assigned','confirmed','late'))
      and not exists (select 1 from public.swap_offers o where o.request_id = req and o.staff_id = p.id)
    order by p.first_name
  loop
    select x.* into give from public.shifts x
    where x.staff_id = mate.id and x.shift_date > current_date and x.status in ('assigned', 'confirmed')
      and not exists (select 1 from public.shifts y where y.staff_id = adam and y.shift_date = x.shift_date and y.status in ('assigned','confirmed','late'))
      and (x.job <> 'door' or true)
    order by x.shift_date limit 1;
    if give.id is not null then
      insert into public.swap_offers (request_id, shift_id, staff_id) values (req, give.id, mate.id);
      raise notice '% offered their % shift on % for Adam''s shift on %', mate.first_name, give.job, give.shift_date, sh.shift_date;
      exit;
    end if;
  end loop;
  if give.id is null then raise notice 'No colleague free that day with a shift to give. Add more shifts to the rota and run again.'; end if;
end $$;

-- Check
select 'Reply' as what, left(reply, 60) as detail from public.staff_messages m join public.profiles p on p.id = m.staff_id where lower(p.email) = 'adam@railway.com' and reply is not null
union all
select 'Swap offer', o2.first_name || ' offers ' || s2.job || ' ' || to_char(s2.shift_date, 'Dy DD Mon') || ' for Adam''s ' || s1.job || ' ' || to_char(s1.shift_date, 'Dy DD Mon')
from public.swap_requests r join public.profiles p on p.id = r.staff_id and lower(p.email) = 'adam@railway.com'
join public.shifts s1 on s1.id = r.shift_id
join public.swap_offers o on o.request_id = r.id and o.status = 'offered'
join public.profiles o2 on o2.id = o.staff_id join public.shifts s2 on s2.id = o.shift_id;
