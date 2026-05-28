create or replace function public.send_friend_request(search_handle text)
returns public.friendships
language plpgsql
security definer
set search_path = public
as $$
declare
  target_profile public.profiles;
  existing_friendship public.friendships;
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

  select *
  into existing_friendship
  from public.friendships
  where least(requester_id, addressee_id) = least(auth.uid(), target_profile.id)
    and greatest(requester_id, addressee_id) = greatest(auth.uid(), target_profile.id)
  limit 1;

  if existing_friendship.id is not null then
    if existing_friendship.status = 'blocked' then
      raise exception 'This friendship is blocked' using errcode = '42501';
    end if;

    if existing_friendship.status = 'accepted' then
      return existing_friendship;
    end if;

    if existing_friendship.addressee_id = auth.uid() then
      update public.friendships
      set status = 'accepted',
          updated_at = now()
      where id = existing_friendship.id
      returning * into friendship;

      return friendship;
    end if;

    return existing_friendship;
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (auth.uid(), target_profile.id, 'pending')
  returning * into friendship;

  return friendship;
end;
$$;
