-- TEST APP ONLY (Club-APP-test): clears every cover request and every yes / no answer,
-- so you can test cover from the start. The rota and shifts are left alone. Safe to run again.
delete from public.shift_offers;
delete from public.cover_calls;
delete from public.push_queue where sent_at is null and (title like '%cover%' or title like '%Cover%' or title like '%can work%');
select (select count(*) from public.cover_calls) as cover_requests_left, (select count(*) from public.shift_offers) as answers_left;
