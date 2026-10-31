begin;

alter table public.books
  drop constraint if exists books_status_check;

alter table public.books
  add constraint books_status_check
  check (status in ('to_buy', 'to_read', 'reading', 'read'));

commit;
