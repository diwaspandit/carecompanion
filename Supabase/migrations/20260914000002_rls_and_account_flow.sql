-- Row Level Security, account bootstrap RPCs and realtime publication.
-- Rule: a signed-in user sees and writes only rows whose account_id belongs to a
-- care account they are a member of. Nothing is readable by the anon role.

-- Membership helpers ---------------------------------------------------------
-- SECURITY DEFINER so policies on account_members do not recurse into themselves.

create or replace function public.is_account_member(target_account_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.account_members
    where account_id = target_account_id and profile_id = auth.uid()
  );
$$;

create or replace function public.senior_in_account(target_senior_id uuid, target_account_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.account_seniors
    where id = target_senior_id and account_id = target_account_id
  );
$$;

create or replace function public.shares_account_with(other_profile_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.account_members mine
    join public.account_members theirs on theirs.account_id = mine.account_id
    where mine.profile_id = auth.uid() and theirs.profile_id = other_profile_id
  );
$$;

revoke all on function public.is_account_member(uuid) from public, anon;
revoke all on function public.senior_in_account(uuid, uuid) from public, anon;
revoke all on function public.shares_account_with(uuid) from public, anon;
grant execute on function public.is_account_member(uuid) to authenticated;
grant execute on function public.senior_in_account(uuid, uuid) to authenticated;
grant execute on function public.shares_account_with(uuid) to authenticated;

-- Profiles are created automatically for every new auth user ---------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Invite codes let a second person join an existing family account -----------

alter table public.care_accounts
  add column invite_code text not null unique
  default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

create or replace function public.create_care_account(account_name text, member_role text default 'family')
returns public.care_accounts
language plpgsql security definer set search_path = public
as $$
declare
  new_account public.care_accounts;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if member_role not in ('senior', 'family') then
    raise exception 'invalid role %', member_role using errcode = '22023';
  end if;

  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;

  insert into public.care_accounts (name, kind, created_by)
  values (account_name, 'family', auth.uid())
  returning * into new_account;

  insert into public.account_members (account_id, profile_id, role)
  values (new_account.id, auth.uid(), member_role);

  insert into public.audit_events (account_id, actor_profile_id, action)
  values (new_account.id, auth.uid(), 'account.created');

  return new_account;
end;
$$;

create or replace function public.join_care_account(code text, member_role text default 'family')
returns public.care_accounts
language plpgsql security definer set search_path = public
as $$
declare
  target public.care_accounts;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if member_role not in ('senior', 'family') then
    raise exception 'invalid role %', member_role using errcode = '22023';
  end if;

  select * into target from public.care_accounts where invite_code = upper(trim(code));
  if not found then
    raise exception 'invite code not found' using errcode = 'P0002';
  end if;

  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;

  insert into public.account_members (account_id, profile_id, role)
  values (target.id, auth.uid(), member_role)
  on conflict (account_id, profile_id) do nothing;

  insert into public.audit_events (account_id, actor_profile_id, action, metadata)
  values (target.id, auth.uid(), 'account.member_joined', jsonb_build_object('role', member_role));

  return target;
end;
$$;

revoke all on function public.create_care_account(text, text) from public, anon;
revoke all on function public.join_care_account(text, text) from public, anon;
grant execute on function public.create_care_account(text, text) to authenticated;
grant execute on function public.join_care_account(text, text) to authenticated;

-- Enable RLS everywhere ------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.care_accounts enable row level security;
alter table public.account_members enable row level security;
alter table public.account_seniors enable row level security;
alter table public.check_ins enable row level security;
alter table public.mood_entries enable row level security;
alter table public.medications enable row level security;
alter table public.medication_events enable row level security;
alter table public.health_snapshots enable row level security;
alter table public.appointments enable row level security;
alter table public.alerts enable row level security;
alter table public.care_insights enable row level security;
alter table public.appointment_ai_preps enable row level security;
alter table public.subscription_statuses enable row level security;
alter table public.audit_events enable row level security;

-- Profiles -------------------------------------------------------------------

create policy "profiles: read self and co-members" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_account_with(id));

create policy "profiles: update self" on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Care accounts (inserts only through create_care_account) -------------------

create policy "care_accounts: members read" on public.care_accounts
  for select to authenticated
  using (public.is_account_member(id));

create policy "care_accounts: members update" on public.care_accounts
  for update to authenticated
  using (public.is_account_member(id)) with check (public.is_account_member(id));

-- Account members (inserts only through the RPCs; members may leave) ---------

create policy "account_members: members read roster" on public.account_members
  for select to authenticated
  using (public.is_account_member(account_id));

create policy "account_members: leave account" on public.account_members
  for delete to authenticated
  using (profile_id = auth.uid());

-- Seniors --------------------------------------------------------------------

create policy "account_seniors: members read" on public.account_seniors
  for select to authenticated
  using (public.is_account_member(account_id));

create policy "account_seniors: members insert" on public.account_seniors
  for insert to authenticated
  with check (public.is_account_member(account_id));

create policy "account_seniors: members update" on public.account_seniors
  for update to authenticated
  using (public.is_account_member(account_id))
  with check (public.is_account_member(account_id));

-- Senior-scoped care tables: account membership AND senior belongs to account.
-- Generated per table to keep policies identical.

do $$
declare
  t text;
begin
  foreach t in array array[
    'check_ins', 'mood_entries', 'medications', 'medication_events',
    'health_snapshots', 'appointments', 'alerts', 'care_insights', 'appointment_ai_preps'
  ] loop
    execute format(
      'create policy "%1$s: members read" on public.%1$I for select to authenticated
         using (public.is_account_member(account_id))', t);
    execute format(
      'create policy "%1$s: members insert" on public.%1$I for insert to authenticated
         with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id))', t);
    execute format(
      'create policy "%1$s: members update" on public.%1$I for update to authenticated
         using (public.is_account_member(account_id))
         with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id))', t);
  end loop;
end;
$$;

-- Hard delete is allowed only where losing the row is the user's intent.
create policy "appointments: members delete" on public.appointments
  for delete to authenticated
  using (public.is_account_member(account_id));

-- Subscription statuses are written server-side (service role); clients read.

create policy "subscription_statuses: members or purchaser read" on public.subscription_statuses
  for select to authenticated
  using (purchaser_profile_id = auth.uid() or (account_id is not null and public.is_account_member(account_id)));

-- Audit events are append-only for members.

create policy "audit_events: members read" on public.audit_events
  for select to authenticated
  using (public.is_account_member(account_id));

create policy "audit_events: members append" on public.audit_events
  for insert to authenticated
  with check (public.is_account_member(account_id) and actor_profile_id = auth.uid());

-- Lock out the anon role entirely ---------------------------------------------

revoke all on all tables in schema public from anon;

-- Realtime: postgres_changes respects RLS, so members only receive their rows.

alter publication supabase_realtime add table
  public.check_ins,
  public.mood_entries,
  public.medications,
  public.medication_events,
  public.health_snapshots,
  public.appointments,
  public.alerts,
  public.appointment_ai_preps;
