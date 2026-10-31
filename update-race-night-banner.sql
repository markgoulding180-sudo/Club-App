-- Race nights get the Race Night banner on What's On
update public.bookings set event_details = coalesce(event_details, '{}'::jsonb) || '{"cat":"race"}'::jsonb
where booking_kind = 'club' and event_type ~* '(race ?night|horse ?rac)';
select booking_date, event_type, event_details->>'cat' as banner from public.bookings where event_type ~* 'race' order by booking_date;
