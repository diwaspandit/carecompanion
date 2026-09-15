-- Production features: contact details, medication dosage, emergency contacts,
-- family messages, senior self-linking and in-app account deletion.

-- Contact details ------------------------------------------------------------

alter table public.profiles add column if not exists phone text not null default '';
alter table public.medications add column if not exists dosage text not null default '';

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  relation text not null default '',
  phone text not null check (length(trim(phone)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace trigger emergency_contacts_updated_at before update on public.emergency_contacts
  for each row execute function public.set_updated_at();
create index if not exists emergency_contacts_senior_idx on public.emergency_contacts (senior_id);

-- Family messages: one conversation per care account ---------------------------

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  sender_profile_id uuid references public.profiles(id) on delete set null default auth.uid(),
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists messages_account_recent_idx on public.messages (account_id, created_at desc);

-- RLS for the new tables -------------------------------------------------------

alter table public.emergency_contacts enable row level security;
alter table public.messages enable row level security;
revoke all on public.emergency_contacts, public.messages from anon;

drop policy if exists "emergency_contacts: members read" on public.emergency_contacts;
create policy "emergency_contacts: members read" on public.emergency_contacts
  for select to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "emergency_contacts: members insert" on public.emergency_contacts;
create policy "emergency_contacts: members insert" on public.emergency_contacts
  for insert to authenticated
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

drop policy if exists "emergency_contacts: members update" on public.emergency_contacts;
create policy "emergency_contacts: members update" on public.emergency_contacts
  for update to authenticated
  using (public.is_account_member(account_id))
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

drop policy if exists "emergency_contacts: members delete" on public.emergency_contacts;
create policy "emergency_contacts: members delete" on public.emergency_contacts
  for delete to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "messages: members read" on public.messages;
create policy "messages: members read" on public.messages
  for select to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "messages: members send as self" on public.messages;
create policy "messages: members send as self" on public.messages
  for insert to authenticated
  with check (public.is_account_member(account_id) and sender_profile_id = auth.uid());

drop policy if exists "messages: senders delete own" on public.messages;
create policy "messages: senders delete own" on public.messages
  for delete to authenticated
  using (sender_profile_id = auth.uid());

-- Senior self-linking ----------------------------------------------------------
-- account_seniors.profile_id says which login *is* the senior (their phone syncs Apple Health).
-- Members may edit senior details, but only the senior themself can link a login, via
-- claim_senior() or by creating their own senior record.

create or replace function public.guard_senior_profile_link()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if new.profile_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.profile_id is not distinct from old.profile_id then
    return new;
  end if;
  if coalesce(current_setting('carecompanion.claiming_senior', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' and new.profile_id = auth.uid() and exists (
    select 1 from public.account_members
    where account_id = new.account_id and profile_id = auth.uid() and role = 'senior'
  ) then
    return new;
  end if;
  raise exception 'only the senior can link their own login' using errcode = '42501';
end;
$$;

create or replace trigger account_seniors_guard_profile_link
  before insert or update on public.account_seniors
  for each row execute function public.guard_senior_profile_link();

create or replace function public.claim_senior(target_senior_id uuid)
returns public.account_seniors
language plpgsql security definer set search_path = public
as $$
declare
  target public.account_seniors;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into target from public.account_seniors
  where id = target_senior_id and deleted_at is null;
  if not found then
    raise exception 'senior not found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.account_members
    where account_id = target.account_id and profile_id = auth.uid() and role = 'senior'
  ) then
    raise exception 'only a senior member of this account can link a senior profile' using errcode = '42501';
  end if;

  if target.profile_id is not null and target.profile_id <> auth.uid() then
    raise exception 'this senior is already linked to someone else' using errcode = 'P0001';
  end if;

  perform set_config('carecompanion.claiming_senior', 'on', true);
  update public.account_seniors set profile_id = null
  where account_id = target.account_id and profile_id = auth.uid() and id <> target.id;
  update public.account_seniors set profile_id = auth.uid()
  where id = target.id
  returning * into target;
  perform set_config('carecompanion.claiming_senior', 'off', true);

  insert into public.audit_events (account_id, actor_profile_id, action, metadata)
  values (target.account_id, auth.uid(), 'senior.claimed', jsonb_build_object('senior_id', target.id));

  return target;
end;
$$;

-- Account deletion (App Store guideline 5.1.1(v)) --------------------------------
-- Removes the caller's login and profile. Accounts where they were the only member are
-- deleted with all their care data; shared accounts keep the other members' data.

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  delete from public.care_accounts a
  where exists (select 1 from public.account_members m where m.account_id = a.id and m.profile_id = me)
    and not exists (select 1 from public.account_members m where m.account_id = a.id and m.profile_id <> me);

  delete from auth.users where id = me;
end;
$$;

revoke all on function public.guard_senior_profile_link() from public, anon;
revoke all on function public.claim_senior(uuid) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.claim_senior(uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

-- Realtime: roster, senior details, contacts and messages refresh other devices ----

do $$
declare
  t text;
begin
  foreach t in array array['account_members', 'account_seniors', 'emergency_contacts', 'messages'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
