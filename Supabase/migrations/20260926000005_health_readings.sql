-- Hourly Apple Health readings, kept for each senior so they can be reviewed later.
-- The same hour is updated in place. Heart rate is the hour's average. Blood pressure keeps
-- systolic in value and diastolic in value_secondary.

create table if not exists public.health_readings (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  recorded_at timestamptz not null,
  kind text not null check (kind in ('heart_rate', 'blood_pressure', 'steps', 'sleep')),
  value double precision not null check (value >= 0),
  value_secondary double precision check (value_secondary is null or value_secondary >= 0),
  source text not null default 'healthkit',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (senior_id, kind, recorded_at)
);

create index if not exists health_readings_senior_recent_idx
  on public.health_readings (senior_id, recorded_at desc);

drop trigger if exists health_readings_updated_at on public.health_readings;
create trigger health_readings_updated_at before update on public.health_readings
  for each row execute function public.set_updated_at();

alter table public.health_readings enable row level security;
revoke all on public.health_readings from anon;
grant select, insert, update on public.health_readings to authenticated;
grant all on public.health_readings to service_role;

drop policy if exists "health_readings: members read" on public.health_readings;
create policy "health_readings: members read" on public.health_readings
  for select to authenticated
  using (public.is_account_member(account_id));

drop policy if exists "health_readings: members insert" on public.health_readings;
create policy "health_readings: members insert" on public.health_readings
  for insert to authenticated
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

drop policy if exists "health_readings: members update" on public.health_readings;
create policy "health_readings: members update" on public.health_readings
  for update to authenticated
  using (public.is_account_member(account_id))
  with check (public.is_account_member(account_id) and public.senior_in_account(senior_id, account_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'health_readings'
  ) then
    alter publication supabase_realtime add table public.health_readings;
  end if;
end;
$$;
