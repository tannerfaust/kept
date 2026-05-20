alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists accent_color text not null default '#ff564d',
  add column if not exists current_streak int not null default 0,
  add column if not exists best_streak int not null default 0,
  add column if not exists completion_rate numeric(5, 4) not null default 1.0;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/heic', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "avatar images are readable"
on storage.objects for select
using (bucket_id = 'profile-avatars');

create policy "users upload their own avatar"
on storage.objects for insert
with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "users update their own avatar"
on storage.objects for update
using (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "users delete their own avatar"
on storage.objects for delete
using (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);
