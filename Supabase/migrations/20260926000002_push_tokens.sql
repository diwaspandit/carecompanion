-- Device tokens for Apple push. The senior's own phones and watches register after sign-in.
-- Family phones may store a token; only the senior's profile is selected when a dose is due.

create table public.device_tokens (
  token text primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('ios', 'watch')),
  updated_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;

create policy "device_tokens: own read" on public.device_tokens
  for select to authenticated
  using (profile_id = auth.uid());

-- One scheduled alert per medicine per local day. Immediate bells are not limited by this index.
create table public.medication_push_log (
  id uuid primary key default gen_random_uuid(),
  medication_id uuid not null references public.medications(id) on delete cascade,
  local_date date not null,
  kind text not null check (kind in ('scheduled', 'now')),
  sent_at timestamptz not null default now()
);

create unique index medication_push_scheduled_once
  on public.medication_push_log (medication_id, local_date)
  where kind = 'scheduled';

alter table public.medication_push_log enable row level security;

-- Replaces any previous owner of this token, then stores it for the signed-in person.
create or replace function public.register_device_token(device_token text, device_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if device_platform not in ('ios', 'watch') or length(device_token) < 16 then
    raise exception 'invalid device token';
  end if;
  delete from public.device_tokens where token = device_token;
  insert into public.device_tokens (token, profile_id, platform)
  values (device_token, auth.uid(), device_platform);
end;
$$;

revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;

-- Claims medicines whose clock time matches this minute in the senior's time zone.
-- A medicine is returned only the first time it is claimed for that local day.
create or replace function public.claim_due_medications()
returns table (id uuid, name text, dosage text, profile_id uuid)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  return query
  with due as (
    select m.id, m.name, m.dosage, s.profile_id,
           (now() at time zone s.time_zone_identifier)::date as local_date
    from public.medications m
    join public.account_seniors s on s.id = m.senior_id
    where m.deleted_at is null
      and s.deleted_at is null
      and s.profile_id is not null
      and s.time_zone_identifier in (select pg_timezone_names.name from pg_timezone_names)
      and upper(regexp_replace(replace(m.scheduled_time, chr(8239), ' '), '[[:space:]]+', ' ', 'g'))
          = to_char(now() at time zone s.time_zone_identifier, 'FMHH12:MI AM')
  ),
  claimed as (
    insert into public.medication_push_log (medication_id, local_date, kind)
    select due.id, due.local_date, 'scheduled' from due
    on conflict (medication_id, local_date) where kind = 'scheduled' do nothing
    returning medication_id
  )
  select due.id, due.name, due.dosage, due.profile_id
  from due
  join claimed on claimed.medication_id = due.id;
end;
$$;

revoke all on function public.claim_due_medications() from public, anon, authenticated;
grant execute on function public.claim_due_medications() to service_role;
