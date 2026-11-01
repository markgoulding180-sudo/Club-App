-- ONE GO: clear the rota, swaps, staff records and notifications, then put the fresh 2–29 Nov rota back and publish it.
do $$
declare t text; list text := '';
begin
  foreach t in array array['swap_offers','swap_requests','shift_swaps','shift_offers','cover_calls','holiday_requests',
    'staff_unavailability','staff_notes','staff_messages','notice_reads','club_notices','member_messages','push_queue','push_reminded',
    'shifts','rota_periods'] loop
    if to_regclass('public.' || t) is not null then list := list || case when list = '' then '' else ', ' end || 'public.' || t; end if;
  end loop;
  execute 'truncate table ' || list || ' cascade';   -- ids carry on, so old "cleared" notifications on phones can't hide new ones
end $$;


insert into public.shifts (shift_date, session, job, staff_id)
select d::date, e->>'s', e->>'j', p.id
from public.profiles p
cross join jsonb_array_elements(p.regular_shifts) e
cross join generate_series(date '2026-11-02', date '2026-11-29', interval '1 day') d
where p.role in ('staff', 'admin') and jsonb_array_length(p.regular_shifts) > 0
  and extract(dow from d)::int = (e->>'d')::int
  and d::date > current_date
on conflict do nothing;

insert into public.rota_periods (start_date, published_at) values ('2026-11-02', now())
on conflict (start_date) do update set published_at = now();

-- Check: shifts per person
select p.first_name, count(s.id) as shifts, min(s.shift_date) as first, max(s.shift_date) as last
from public.profiles p left join public.shifts s on s.staff_id = p.id
where p.role = 'staff' group by p.first_name order by shifts desc, p.first_name;
