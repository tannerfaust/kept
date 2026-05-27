do $$
begin
  create type public.condition_type as enum ('todo', 'avoid');
exception
  when duplicate_object then null;
end $$;

alter table public.pacts
  add column if not exists icon_symbol text not null default 'bolt.fill',
  add column if not exists accent_color text not null default '#ff564d';

alter table public.pacts
  alter column core set default 'proactive';

alter table public.pact_conditions
  add column if not exists condition_type public.condition_type not null default 'todo';

create table if not exists public.pact_messages (
  id uuid primary key default gen_random_uuid(),
  pact_id uuid not null references public.pacts(id) on delete cascade,
  user_id uuid,
  sender_name text not null,
  sender_accent_color text not null default '#888888',
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.pact_messages enable row level security;

drop policy if exists "messages pact members read" on public.pact_messages;
create policy "messages pact members read"
on public.pact_messages for select
using (public.is_pact_participant(pact_id));

drop policy if exists "messages pact members insert" on public.pact_messages;
create policy "messages pact members insert"
on public.pact_messages for insert
with check (public.is_pact_participant(pact_id));

create index if not exists pact_messages_pact_created_idx
on public.pact_messages(pact_id, created_at);

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  email_prefix text;
begin
  email_prefix := split_part(new.email, '@', 1);

  insert into public.profiles (
    id,
    display_name,
    handle,
    bio,
    avatar_symbol,
    accent_color,
    integrity_score,
    current_streak,
    best_streak,
    completion_rate
  )
  values (
    new.id,
    initcap(coalesce(nullif(email_prefix, ''), 'Kept')),
    '@' || regexp_replace(lower(coalesce(nullif(email_prefix, ''), 'kept')), '[^a-z0-9_]', '', 'g') || '_' || left(new.id::text, 8),
    '',
    'bolt.fill',
    '#ff564d',
    1.0,
    0,
    0,
    1.0
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();
