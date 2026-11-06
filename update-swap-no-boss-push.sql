-- Swaps are agreed between staff and are binding: the manager is no longer sent a phone alert when two staff swap.
-- (The rota still updates straight away, and the Swaps log still shows every swap.) Safe to run again.
drop trigger if exists push_boss_swap on public.shift_swaps;
select 'Manager swap alerts off' as done;
