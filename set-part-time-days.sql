-- Part-time staff: the days they can usually work (the rota lists them first on those days, marked "can work")
alter table public.profiles add column if not exists avail_days jsonb not null default '[]'::jsonb;

create or replace function public.admin_set_avail(pid uuid, days jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Only admins can do this.'; end if;
  if jsonb_typeof(days) <> 'array' or exists (select 1 from jsonb_array_elements_text(days) d where d !~ '^[0-6]$') then raise exception 'Those days aren''t valid.'; end if;
  update public.profiles set avail_days = days where id = pid;
end $$;
grant execute on function public.admin_set_avail(uuid, jsonb) to authenticated;

-- Days: 0 Sun, 1 Mon, 2 Tue, 3 Wed, 4 Thu, 5 Fri, 6 Sat
update public.profiles set avail_days = '[5,6,0]' where email = 'yan@arcstaff.test';        -- Yan: Fri, Sat, Sun
update public.profiles set avail_days = '[1,3,4]' where email = 'heather@arcstaff.test';    -- Heather: Mon, Wed, Thu
update public.profiles set avail_days = '[2,4,6]' where email = 'ben@arcstaff.test';        -- Ben: Tue, Thu, Sat
update public.profiles set avail_days = '[3,5,0]' where email = 'mark@railway.com';         -- Mark: Wed, Fri, Sun
update public.profiles set avail_days = '[1,2,6]' where email = 'staff@railway.com';        -- Staff Member: Mon, Tue, Sat

-- Check
select first_name, skill, jsonb_array_length(regular_shifts) as regular_shifts_a_week, avail_days as can_work_days
from public.profiles where role in ('staff', 'admin') and skill is not null order by regular_shifts_a_week desc, first_name;
