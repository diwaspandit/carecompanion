-- Whether a visit happened. Logged from the phone or watch, including after the device was offline.

alter table public.appointments
  add column if not exists outcome text;

alter table public.appointments drop constraint if exists appointments_outcome_check;
alter table public.appointments add constraint appointments_outcome_check
  check (outcome is null or outcome in ('went', 'missed'));
