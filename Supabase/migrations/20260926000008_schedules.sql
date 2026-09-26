-- Optional repeat and end date for medicines and visits.
-- Medicines: repeat_weekdays is empty for every day, otherwise Sunday=1 ... Saturday=7.
-- Visits: repeat_rule is once, daily, weekly, biweekly, or monthly.
-- logged_at is the visit time that outcome belongs to, so the next repeat can still be logged.

alter table public.medications add column if not exists repeat_weekdays text;
alter table public.medications add column if not exists ends_on date;

alter table public.appointments add column if not exists repeat_rule text not null default 'once';
alter table public.appointments add column if not exists ends_on date;
alter table public.appointments add column if not exists logged_at timestamptz;

alter table public.appointments drop constraint if exists appointments_repeat_rule_check;
alter table public.appointments add constraint appointments_repeat_rule_check
  check (repeat_rule in ('once', 'daily', 'weekly', 'biweekly', 'monthly'));

-- A dose is claimed on its clock time only when today is one of its days and the course has not ended.
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
      and (m.ends_on is null or m.ends_on >= (now() at time zone s.time_zone_identifier)::date)
      and (
        m.repeat_weekdays is null
        or btrim(m.repeat_weekdays) = ''
        or position(
          ',' || (extract(dow from (now() at time zone s.time_zone_identifier))::int + 1)::text || ','
          in ',' || m.repeat_weekdays || ','
        ) > 0
      )
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
