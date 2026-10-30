-- Online card payments (Stripe): payments can be marked 'online', and each Stripe payment is only recorded once.
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments add constraint payments_method_check check (method in ('cash', 'card', 'bank', 'other', 'online'));
alter table public.payments add column if not exists stripe_ref text;
create unique index if not exists payments_stripe_ref on public.payments (stripe_ref);
alter table public.ticket_reservations add column if not exists stripe_session text;
