create table if not exists public.books (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  title text not null,
  author text not null,
  theme text not null default '',
  year integer,
  color text not null default '#8D6E63',
  pages integer,
  status text not null default 'to_read'
    check (status in ('to_read', 'reading', 'read')),
  plot text,
  notes text,
  location text,
  cover_url text,
  cover_path text,
  isbn text,
  created_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

alter table public.books enable row level security;

drop policy if exists "Users can read their own books" on public.books;
create policy "Users can read their own books"
  on public.books for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their own books" on public.books;
create policy "Users can insert their own books"
  on public.books for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own books" on public.books;
create policy "Users can update their own books"
  on public.books for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('book-covers', 'book-covers', false)
on conflict (id) do nothing;

drop policy if exists "Users can read their own covers" on storage.objects;
create policy "Users can read their own covers"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'book-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can upload their own covers" on storage.objects;
create policy "Users can upload their own covers"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'book-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users can update their own covers" on storage.objects;
create policy "Users can update their own covers"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'book-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'book-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
