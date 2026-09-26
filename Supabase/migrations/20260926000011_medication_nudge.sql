-- A family Remind sets this. Adding or editing a medicine leaves it empty, so the
-- dose alert waits for scheduled_time instead of firing when the row is saved.
alter table public.medications
  add column if not exists nudge_at timestamptz;
