-- Payment deadlines: remember when a booking was confirmed (the 7-day deposit clock starts then)
alter table public.bookings add column if not exists confirmed_at timestamptz;
update public.bookings set confirmed_at = created_at where status = 'confirmed' and confirmed_at is null;
create or replace function public.bookings_confirmed_at() returns trigger language plpgsql as $$
begin
  if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status is distinct from 'confirmed') then new.confirmed_at := now(); end if;
  return new;
end $$;
drop trigger if exists bookings_confirmed_at on public.bookings;
create trigger bookings_confirmed_at before insert or update of status on public.bookings for each row execute function public.bookings_confirmed_at();
