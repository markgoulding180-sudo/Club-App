-- Club bookings always take priority. A club event (including league nights) can go in even if a member has
-- already booked that room and session; the bosses are then told about the double booking so they can move or cancel
-- the member's booking. Two club events still can't share a room, and members still can't book over a club event.
-- Run after add-push-notifications.sql and update-boss-push.sql. Safe to run again.

create or replace function public.check_booking_clash()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'cancelled' and not public.is_admin()
     and exists (select 1 from public.closed_days c
                 where c.closed_date = new.booking_date
                   and (c.part = 'all' or new.slot = 'full_day' or c.part = new.slot)) then
    raise exception 'Sorry, the club isn''t taking bookings for that day.';
  end if;
  if new.status <> 'cancelled' and exists (
    select 1 from public.bookings b
    where b.room = new.room and b.booking_date = new.booking_date and b.status <> 'cancelled'
      and b.id is distinct from new.id
      and (b.slot = new.slot or b.slot = 'full_day' or new.slot = 'full_day')
      and not (new.booking_kind = 'club' and b.booking_kind <> 'club')       -- a club event can go over a member booking
  ) then
    raise exception 'That room is already booked for this session.';
  end if;
  return new;
end $$;

-- Tell the bosses about any double booking a club event causes
create or replace function public.push_on_club_clash() returns trigger language plpgsql security definer set search_path = '' as $$
declare m record;
begin
  if new.booking_kind = 'club' and new.status <> 'cancelled' then
    for m in select b.* from public.bookings b
             where b.room = new.room and b.booking_date = new.booking_date and b.status <> 'cancelled' and b.id <> new.id
               and b.booking_kind <> 'club' and (b.slot = new.slot or b.slot = 'full_day' or new.slot = 'full_day') loop
      perform public.push_bosses('bookings', 'bookings', '⚠️ Double booking',
        coalesce(new.event_type, 'Club event') || ' and ' || coalesce(m.first_name || ' ' || m.last_name, 'a member') || '''s ' || coalesce(m.event_type, 'booking')
        || ', ' || case new.room when 'hall' then 'Function Room' else 'Lounge Bar' end || ' ' || trim(to_char(new.booking_date, 'Dy FMDD Mon'))
        || '. The club event stands: move or cancel the member booking.', '/?go=bookings');
    end loop;
  end if; return new;
end $$;
drop trigger if exists push_on_club_clash on public.bookings;
create trigger push_on_club_clash after insert or update of booking_date, room, slot, status on public.bookings for each row execute function public.push_on_club_clash();

-- Check: any double bookings right now
select to_char(c.booking_date, 'Dy DD Mon') as day, case c.room when 'hall' then 'Function Room' else 'Lounge Bar' end as room,
       c.event_type as club_event, m.first_name || ' ' || m.last_name || ': ' || coalesce(m.event_type, 'booking') as member_booking
from public.bookings c join public.bookings m on m.room = c.room and m.booking_date = c.booking_date
  and (m.slot = c.slot or m.slot = 'full_day' or c.slot = 'full_day')
where c.booking_kind = 'club' and m.booking_kind <> 'club' and c.status <> 'cancelled' and m.status <> 'cancelled' and c.booking_date >= current_date
order by c.booking_date;
