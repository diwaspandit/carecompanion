-- Who has opened a family message. The sender sees Sent until someone else has a row here.

create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, profile_id)
);

alter table public.message_reads enable row level security;
revoke all on public.message_reads from anon;
grant select, insert on public.message_reads to authenticated;
grant all on public.message_reads to service_role;

drop policy if exists "message_reads: members read" on public.message_reads;
create policy "message_reads: members read" on public.message_reads
  for select to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "message_reads: members mark self" on public.message_reads;
create policy "message_reads: members mark self" on public.message_reads
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and public.is_account_member(account_id)
    and exists (
      select 1 from public.messages m
      where m.id = message_id and m.account_id = message_reads.account_id
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_reads'
  ) then
    alter publication supabase_realtime add table public.message_reads;
  end if;
end;
$$;
