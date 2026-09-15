-- Senior device link: a member who joined as `senior` links their login to one senior record
-- (account_seniors.profile_id). Only that linked login may write HealthKit-sourced snapshots, so a
-- family member's own Apple Health data can never be stored as the senior's.

-- profile_id changes only through claim_senior_profile (security definer, runs as the owner).
create or replace function public.guard_senior_profile_link()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') and (
    (tg_op = 'INSERT' and new.profile_id is not null) or
    (tg_op = 'UPDATE' and new.profile_id is distinct from old.profile_id)
  ) then
    raise exception 'senior profile links change only through claim_senior_profile'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger account_seniors_guard_profile_link
  before insert or update on public.account_seniors
  for each row execute function public.guard_senior_profile_link();

create unique index account_seniors_one_senior_per_profile
  on public.account_seniors (account_id, profile_id) where profile_id is not null;

create or replace function public.claim_senior_profile(target_senior_id uuid)
returns public.account_seniors
language plpgsql security definer set search_path = public
as $$
declare
  target public.account_seniors;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into target from public.account_seniors where id = target_senior_id and deleted_at is null;
  if not found or not exists (
    select 1 from public.account_members
    where account_id = target.account_id and profile_id = auth.uid() and role = 'senior'
  ) then
    raise exception 'only a senior member of this account can link a senior profile'
      using errcode = '42501';
  end if;

  if target.profile_id = auth.uid() then
    return target;
  end if;
  if target.profile_id is not null then
    raise exception 'senior profile is already linked to another member' using errcode = '23505';
  end if;

  update public.account_seniors set profile_id = auth.uid()
    where id = target_senior_id
    returning * into target;

  insert into public.audit_events (account_id, actor_profile_id, action, metadata)
  values (target.account_id, auth.uid(), 'senior.profile_linked', jsonb_build_object('senior_id', target.id));

  return target;
end;
$$;

revoke all on function public.claim_senior_profile(uuid) from public, anon;
grant execute on function public.claim_senior_profile(uuid) to authenticated;

-- HealthKit rows: restrictive policies AND-ed with the existing member policies.
create or replace function public.is_linked_senior(target_senior_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.account_seniors
    where id = target_senior_id and profile_id = auth.uid() and deleted_at is null
  );
$$;

create policy "health_snapshots: healthkit insert by linked senior" on public.health_snapshots
  as restrictive for insert to authenticated
  with check (source <> 'healthkit' or public.is_linked_senior(senior_id));

create policy "health_snapshots: healthkit update by linked senior" on public.health_snapshots
  as restrictive for update to authenticated
  using (source <> 'healthkit' or public.is_linked_senior(senior_id))
  with check (source <> 'healthkit' or public.is_linked_senior(senior_id));
