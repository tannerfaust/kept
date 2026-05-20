insert into public.profiles (id, display_name, handle, bio, avatar_symbol, integrity_score)
values
  ('a1111111-1111-4111-8111-111111111111', 'Tanner', '@tanner', 'Thirty days of doing what I said I would do.', 'bolt.fill', 0.91),
  ('b2222222-2222-4222-8222-222222222222', 'Maya', '@maya', 'No skipped reps.', 'flame.fill', 0.88)
on conflict (id) do nothing;

insert into public.friendships (requester_id, addressee_id, status)
values
  ('a1111111-1111-4111-8111-111111111111', 'b2222222-2222-4222-8222-222222222222', 'accepted')
on conflict do nothing;

insert into public.pacts (id, created_by, title, description, start_date, finish_date, core, status, reminder_hour, reminder_minute)
values
  ('d1111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', 'Cold shower streak', 'No excuses before coffee. Check in every morning.', current_date - 4, current_date + 25, 'reactive', 'active', 8, 15),
  ('d2222222-2222-4222-8222-222222222222', 'a1111111-1111-4111-8111-111111111111', '30-day digital detox', 'Assume clean days unless a slip is reported.', current_date - 8, current_date + 21, 'proactive', 'active', 21, 30)
on conflict (id) do nothing;

insert into public.pact_participants (pact_id, user_id, is_owner)
values
  ('d1111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', true),
  ('d1111111-1111-4111-8111-111111111111', 'b2222222-2222-4222-8222-222222222222', false),
  ('d2222222-2222-4222-8222-222222222222', 'a1111111-1111-4111-8111-111111111111', true),
  ('d2222222-2222-4222-8222-222222222222', 'b2222222-2222-4222-8222-222222222222', false)
on conflict do nothing;

insert into public.pact_conditions (id, pact_id, title, input_type, comparison, target_value, is_required)
values
  ('e1111111-1111-4111-8111-111111111111', 'd1111111-1111-4111-8111-111111111111', 'Cold shower completed', 'boolean', 'equals', 1, true),
  ('e2222222-2222-4222-8222-222222222222', 'd2222222-2222-4222-8222-222222222222', 'Social media slip', 'boolean', 'equals', 0, true)
on conflict (id) do nothing;
