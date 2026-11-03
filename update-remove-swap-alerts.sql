-- Bosses no longer get a phone alert when two staff swap (swaps are between staff; they message the manager if no one can).
drop trigger if exists push_boss_swap on public.shift_swaps;
select 'done' as result;
