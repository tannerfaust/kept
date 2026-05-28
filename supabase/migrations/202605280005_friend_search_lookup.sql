create or replace function public.find_profile_by_handle(search_handle text)
returns table (
  id uuid,
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
  with query as (
    select
      lower(trim(search_handle)) as raw_query,
      case
        when left(trim(search_handle), 1) = '@' then lower(trim(search_handle))
        else '@' || lower(trim(search_handle))
      end as handle_query
  )
  select
    p.id,
    p.display_name,
    p.handle,
    p.bio,
    p.avatar_symbol,
    p.avatar_url,
    p.accent_color,
    p.integrity_score,
    p.current_streak,
    p.best_streak,
    p.completion_rate
  from public.profiles p
  cross join query q
  where p.handle = q.handle_query
     or p.handle like q.handle_query || '%'
     or lower(p.display_name) like q.raw_query || '%'
  order by
    case
      when p.handle = q.handle_query then 0
      when p.handle like q.handle_query || '%' then 1
      else 2
    end,
    p.display_name
  limit 1;
$$;

create or replace function public.send_friend_request(search_handle text)
returns public.friendships
language plpgsql
security definer
set search_path = public
as $$
declare
  target_profile public.profiles;
  friendship public.friendships;
begin
  select p.*
  into target_profile
  from public.find_profile_by_handle(search_handle) found
  join public.profiles p on p.id = found.id
  limit 1;

  if target_profile.id is null then
    raise exception 'No user found for handle %', search_handle using errcode = 'P0002';
  end if;

  if target_profile.id = auth.uid() then
    raise exception 'You cannot add yourself as a friend' using errcode = '23514';
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (auth.uid(), target_profile.id, 'pending')
  on conflict ((least(requester_id, addressee_id)), (greatest(requester_id, addressee_id)))
  do update set
    requester_id = excluded.requester_id,
    addressee_id = excluded.addressee_id,
    status = case
      when public.friendships.status = 'blocked' then public.friendships.status
      else 'pending'
    end,
    updated_at = now()
  returning * into friendship;

  return friendship;
end;
$$;
