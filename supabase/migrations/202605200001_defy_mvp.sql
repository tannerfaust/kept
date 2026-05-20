create type public.pact_core as enum ('reactive', 'proactive');
create type public.input_type as enum ('boolean', 'integer');
create type public.friendship_status as enum ('pending', 'accepted', 'blocked');
create type public.pact_status as enum ('draft', 'active', 'completed', 'failed', 'cancelled');
create type public.comparison_operator as enum ('equals', 'at_least');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  handle text not null unique,
  bio text not null default '',
  avatar_symbol text not null default 'bolt.fill',
  integrity_score numeric(5, 4) not null default 1.0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status public.friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendships_distinct_users check (requester_id <> addressee_id)
);

create table public.pacts (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  start_date date not null,
  finish_date date not null,
  core public.pact_core not null,
  status public.pact_status not null default 'active',
  visibility text not null default 'participants',
  reminder_hour int not null default 20 check (reminder_hour between 0 and 23),
  reminder_minute int not null default 0 check (reminder_minute between 0 and 59),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pacts_valid_dates check (finish_date >= start_date),
  constraint pacts_private_visibility check (visibility in ('private', 'participants'))
);

create table public.pact_participants (
  id uuid primary key default gen_random_uuid(),
  pact_id uuid not null references public.pacts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_owner boolean not null default false,
  joined_at timestamptz not null default now(),
  unique (pact_id, user_id)
);

create table public.pact_conditions (
  id uuid primary key default gen_random_uuid(),
  pact_id uuid not null references public.pacts(id) on delete cascade,
  title text not null,
  input_type public.input_type not null,
  comparison public.comparison_operator not null default 'equals',
  target_value int not null default 1,
  is_required boolean not null default true,
  cadence text not null default 'daily',
  created_at timestamptz not null default now(),
  constraint pact_conditions_daily_only check (cadence = 'daily')
);

create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  pact_id uuid not null references public.pacts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  note text not null default '',
  did_report_violation boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (pact_id, user_id, day)
);

create table public.check_in_values (
  id uuid primary key default gen_random_uuid(),
  check_in_id uuid not null references public.check_ins(id) on delete cascade,
  condition_id uuid not null references public.pact_conditions(id) on delete cascade,
  integer_value int not null,
  created_at timestamptz not null default now(),
  unique (check_in_id, condition_id)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  pact_id uuid references public.pacts(id) on delete cascade,
  title text not null,
  message text not null,
  scheduled_for timestamptz,
  delivered_at timestamptz,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.pacts enable row level security;
alter table public.pact_participants enable row level security;
alter table public.pact_conditions enable row level security;
alter table public.check_ins enable row level security;
alter table public.check_in_values enable row level security;
alter table public.notifications enable row level security;

create or replace function public.is_pact_participant(target_pact_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.pact_participants
    where pact_id = target_pact_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.are_friends(left_user_id uuid, right_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships
    where status = 'accepted'
      and (
        (requester_id = left_user_id and addressee_id = right_user_id)
        or (requester_id = right_user_id and addressee_id = left_user_id)
      )
  );
$$;

create policy "profiles self and accepted friends read"
on public.profiles for select
using (id = auth.uid() or public.are_friends(id, auth.uid()));

create policy "profiles self insert"
on public.profiles for insert
with check (id = auth.uid());

create policy "profiles self update"
on public.profiles for update
using (id = auth.uid())
with check (id = auth.uid());

create policy "friendships involved users read"
on public.friendships for select
using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "friendships requester insert"
on public.friendships for insert
with check (requester_id = auth.uid());

create policy "friendships involved users update"
on public.friendships for update
using (requester_id = auth.uid() or addressee_id = auth.uid())
with check (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "pacts participants read"
on public.pacts for select
using (public.is_pact_participant(id));

create policy "pacts creator insert"
on public.pacts for insert
with check (created_by = auth.uid());

create policy "pacts owner update"
on public.pacts for update
using (
  exists (
    select 1 from public.pact_participants
    where pact_id = pacts.id and user_id = auth.uid() and is_owner
  )
)
with check (public.is_pact_participant(id));

create policy "participants pact members read"
on public.pact_participants for select
using (public.is_pact_participant(pact_id));

create policy "participants creator insert"
on public.pact_participants for insert
with check (
  user_id = auth.uid()
  or exists (
    select 1 from public.pacts
    where pacts.id = pact_id and pacts.created_by = auth.uid()
  )
);

create policy "conditions pact members read"
on public.pact_conditions for select
using (public.is_pact_participant(pact_id));

create policy "conditions pact creator insert"
on public.pact_conditions for insert
with check (
  exists (
    select 1 from public.pacts
    where pacts.id = pact_id and pacts.created_by = auth.uid()
  )
);

create policy "checkins participant read"
on public.check_ins for select
using (public.is_pact_participant(pact_id));

create policy "checkins self insert"
on public.check_ins for insert
with check (user_id = auth.uid() and public.is_pact_participant(pact_id));

create policy "checkins self update"
on public.check_ins for update
using (user_id = auth.uid())
with check (user_id = auth.uid() and public.is_pact_participant(pact_id));

create policy "check values participant read"
on public.check_in_values for select
using (
  exists (
    select 1 from public.check_ins
    where check_ins.id = check_in_id
      and public.is_pact_participant(check_ins.pact_id)
  )
);

create policy "check values self insert"
on public.check_in_values for insert
with check (
  exists (
    select 1 from public.check_ins
    where check_ins.id = check_in_id
      and check_ins.user_id = auth.uid()
  )
);

create policy "notifications self read"
on public.notifications for select
using (user_id = auth.uid());

create policy "notifications self update"
on public.notifications for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

create index friendships_requester_idx on public.friendships(requester_id);
create index friendships_addressee_idx on public.friendships(addressee_id);
create unique index friendships_unique_pair_idx on public.friendships(least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index pact_participants_user_idx on public.pact_participants(user_id);
create index check_ins_pact_day_idx on public.check_ins(pact_id, day);
create index notifications_user_unread_idx on public.notifications(user_id, is_read, created_at desc);
