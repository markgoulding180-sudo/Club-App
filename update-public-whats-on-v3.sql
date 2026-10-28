-- What's On (public): leave out league nights and sports-league bookings (they stay in the diary). Tournaments, competitions and cups still show.
create or replace function public.get_public_whats_on(max_rows int default 3)
returns table (title text, starts_at timestamptz, info text, kind text)
language sql stable security definer set search_path = '' as $$
  select x.title, x.starts_at, x.info, x.kind from (
    select e.title, e.starts_at, coalesce(e.category, '') as info, 'event'::text as kind
    from public.events e
    where e.starts_at >= date_trunc('day', now())
      and not (e.category = 'Sport' and coalesce(e.description, '') like 'Premier League%')
    union all
    select b.event_type,
           (b.booking_date + coalesce(b.start_time, time '19:00')) at time zone 'Europe/London',
           (case b.room when 'hall' then 'Function Room' else 'Lounge Bar' end) || (case when b.ticketed then ' · Tickets' else ' · Free entry' end),
           'club'
    from public.bookings b
    where b.booking_kind = 'club' and b.status <> 'cancelled' and b.booking_date >= current_date
      and not (coalesce((b.event_details->>'sport')::boolean, false) and b.event_type !~* '(tournament|competition|\mcomp\M|cup|final|knock-?out|\mopen\M|championship)')
  ) x
  where not (x.title ~* 'league' and x.title !~* '(tournament|competition|\mcomp\M|cup|final|knock-?out|\mopen\M|championship)')
  order by x.starts_at
  limit least(greatest(coalesce(max_rows, 3), 1), 10);
$$;
grant execute on function public.get_public_whats_on(int) to anon, authenticated;
