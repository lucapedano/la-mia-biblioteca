create or replace function public.prevent_duplicate_books()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  incoming_isbn text;
  incoming_title text;
  incoming_author text;
  duplicate_exists boolean;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

  incoming_isbn := upper(regexp_replace(coalesce(new.isbn, ''), '[^0-9Xx]', '', 'g'));
  incoming_title := lower(regexp_replace(btrim(coalesce(new.title, '')), '[[:space:]]+', ' ', 'g'));
  incoming_author := lower(regexp_replace(btrim(coalesce(new.author, '')), '[[:space:]]+', ' ', 'g'));

  select exists (
    select 1
    from public.books as existing
    where existing.user_id = new.user_id
      and existing.deleted_at is null
      and existing.id is distinct from new.id
      and (
        (
          incoming_isbn <> ''
          and upper(regexp_replace(coalesce(existing.isbn, ''), '[^0-9Xx]', '', 'g')) = incoming_isbn
        )
        or (
          incoming_title <> ''
          and incoming_author <> ''
          and lower(regexp_replace(btrim(coalesce(existing.title, '')), '[[:space:]]+', ' ', 'g'))
            = incoming_title
          and lower(regexp_replace(btrim(coalesce(existing.author, '')), '[[:space:]]+', ' ', 'g'))
            = incoming_author
        )
      )
  )
  into duplicate_exists;

  if duplicate_exists then
    raise exception using
      errcode = '23505',
      message = 'DUPLICATE_BOOK: questo libro è già presente nella libreria.';
  end if;

  return new;
end;
$$;

drop trigger if exists books_prevent_duplicate_insert on public.books;
create trigger books_prevent_duplicate_insert
  before insert on public.books
  for each row
  execute function public.prevent_duplicate_books();
