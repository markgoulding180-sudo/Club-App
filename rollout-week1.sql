-- Roll-out WEEK 1: staff and manager basics only. Run add-feature-switches.sql first.
-- ON:  Rota for staff, What's On, Newsletter, Phone notifications, Poster (and everything managers use to run the rota)
-- OFF: Swaps, Holiday requests, Can't work, Cover requests, Staff chat, To-do list,
--      Room hire for members, Tickets, Card payments, Friends, Jobs, New member sign-ups
-- You can change any of these afterwards on Home → Features on / off. Safe to run again.
insert into public.app_features (key, enabled, updated_at) values
  ('rota_staff', true, now()), ('whatson', true, now()), ('newsletter', true, now()), ('alerts', true, now()), ('poster', true, now()),
  ('swaps', false, now()), ('holidays', false, now()), ('cantwork', false, now()), ('cover', false, now()), ('staffchat', false, now()),
  ('todo', false, now()), ('member_bookings', false, now()), ('tickets', false, now()), ('payments', false, now()),
  ('friends', false, now()), ('jobs', false, now()), ('register', false, now())
on conflict (key) do update set enabled = excluded.enabled, updated_at = now();

select key as "Feature", case when enabled then 'ON' else 'off' end as "Week 1" from public.app_features order by enabled desc, key;
