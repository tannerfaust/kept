drop policy if exists "profiles involved friendships read" on public.profiles;
create policy "profiles involved friendships read"
on public.profiles for select
using (
  id = auth.uid()
  or public.are_friends(id, auth.uid())
  or exists (
    select 1
    from public.friendships
    where status = 'pending'
      and (
        (requester_id = auth.uid() and addressee_id = profiles.id)
        or (addressee_id = auth.uid() and requester_id = profiles.id)
      )
  )
);

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
  where p.handle = case
    when left(trim(search_handle), 1) = '@' then lower(trim(search_handle))
    else '@' || lower(trim(search_handle))
  end
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
  select *
  into target_profile
  from public.profiles
  where handle = case
    when left(trim(search_handle), 1) = '@' then lower(trim(search_handle))
    else '@' || lower(trim(search_handle))
  end;

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

create or replace function public.accept_friend_request(friendship_id uuid)
returns public.friendships
language plpgsql
security definer
set search_path = public
as $$
declare
  friendship public.friendships;
begin
  update public.friendships
  set status = 'accepted',
      updated_at = now()
  where id = friendship_id
    and addressee_id = auth.uid()
    and status = 'pending'
  returning * into friendship;

  if friendship.id is null then
    raise exception 'Friend request not found' using errcode = 'P0002';
  end if;

  return friendship;
end;
$$;
