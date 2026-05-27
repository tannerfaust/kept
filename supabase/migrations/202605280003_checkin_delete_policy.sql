drop policy if exists "checkins self delete" on public.check_ins;
create policy "checkins self delete"
on public.check_ins for delete
using (user_id = auth.uid());
