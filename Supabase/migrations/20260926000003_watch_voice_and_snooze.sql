-- Shared snooze so a Snooze on the phone or the watch clears the dose on both.
-- Kept off the medications row so it does not look like a family Remind.

create table if not exists public.medication_snoozes (
  medication_id uuid primary key references public.medications(id) on delete cascade,
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  until_at timestamptz not null
);

alter table public.medication_snoozes enable row level security;
revoke all on public.medication_snoozes from anon;
grant select, insert, update, delete on public.medication_snoozes to authenticated;
grant all on public.medication_snoozes to service_role;

drop policy if exists "medication_snoozes: members read" on public.medication_snoozes;
create policy "medication_snoozes: members read" on public.medication_snoozes
  for select to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "medication_snoozes: members insert" on public.medication_snoozes;
create policy "medication_snoozes: members insert" on public.medication_snoozes
  for insert to authenticated
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

drop policy if exists "medication_snoozes: members update" on public.medication_snoozes;
create policy "medication_snoozes: members update" on public.medication_snoozes
  for update to authenticated
  using (public.is_account_member(account_id))
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

drop policy if exists "medication_snoozes: members delete" on public.medication_snoozes;
create policy "medication_snoozes: members delete" on public.medication_snoozes
  for delete to authenticated
  using (public.is_account_member(account_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'medication_snoozes'
  ) then
    alter publication supabase_realtime add table public.medication_snoozes;
  end if;
end;
$$;

-- Voice clips live in storage. The message row points at the file.
alter table public.messages add column if not exists audio_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice-messages', 'voice-messages', false, 2000000, array['audio/mp4', 'audio/m4a', 'audio/aac', 'audio/x-m4a'])
on conflict (id) do nothing;

drop policy if exists "voice messages: members read" on storage.objects;
create policy "voice messages: members read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'voice-messages'
    and public.is_account_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "voice messages: members upload" on storage.objects;
create policy "voice messages: members upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'voice-messages'
    and public.is_account_member(((storage.foldername(name))[1])::uuid)
  );
