create or replace function public.list_friendships()
returns table (
  friendship_id uuid,
  requester_id uuid,
  addressee_id uuid,
  status public.friendship_status,
  profile_id uuid,
  display_name text,
  handle text,
  bio text,
  avatar_symbol text,
  avatar_url text,
  accent_color text,
  integrity_score numeric,
  current_streak int,
  best_streak int,
  completion_rate numeric
)
language sql
security definer
set search_path = public
as $$
  select
    f.id as friendship_id,
    f.requester_id,
    f.addressee_id,
    f.status,
    p.id as profile_id,
    p.display_name,
    coalesce(p.handle, '@user') as handle,
    coalesce(p.bio, '') as bio,
    coalesce(p.avatar_symbol, 'person.fill') as avatar_symbol,
    p.avatar_url,
    coalesce(p.accent_color, '#ff564d') as accent_color,
    coalesce(p.integrity_score, 1) as integrity_score,
    coalesce(p.current_streak, 0) as current_streak,
    coalesce(p.best_streak, 0) as best_streak,
    coalesce(p.completion_rate, 1) as completion_rate
  from public.friendships f
  join public.profiles p
    on p.id = case
      when f.requester_id = auth.uid() then f.addressee_id
      else f.requester_id
    end
  where f.requester_id = auth.uid()
     or f.addressee_id = auth.uid()
  order by f.updated_at desc;
$$;
