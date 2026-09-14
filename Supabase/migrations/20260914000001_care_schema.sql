-- CareCompanion core schema: family network first, then care events.
-- Every care table carries account_id so RLS can check membership without joins.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Identity -----------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  city text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.care_accounts (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'family' check (kind in ('family', 'organization')),
  name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.account_members (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('senior', 'family')),
  created_at timestamptz not null default now(),
  unique (account_id, profile_id)
);

create table public.account_seniors (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  name text not null,
  age integer not null check (age between 0 and 130),
  city text not null default '',
  time_zone_identifier text not null default 'UTC',
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Care events ----------------------------------------------------------------

create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.mood_entries (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  check_in_id uuid references public.check_ins(id) on delete set null,
  mood text not null check (mood in ('Great', 'Okay', 'Low')),
  note text,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.medications (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  name text not null,
  scheduled_time text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.medication_events (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  medication_id uuid not null references public.medications(id) on delete cascade,
  status text not null check (status in ('taken', 'skipped', 'missed')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.health_snapshots (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  snapshot_date date not null,
  steps integer not null default 0 check (steps >= 0),
  sleep_minutes integer not null default 0 check (sleep_minutes >= 0),
  resting_heart_rate integer not null default 0 check (resting_heart_rate >= 0),
  source text not null check (source in ('demo', 'manual', 'healthkit', 'device_import')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (senior_id, snapshot_date, source)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  title text not null,
  clinician text not null default '',
  scheduled_at timestamptz not null,
  location text not null default '',
  notes text not null default '',
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  kind text not null default 'sos' check (kind in ('sos', 'missed_check_in', 'medication_concern')),
  acknowledged boolean not null default false,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles(id) on delete set null,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Only one open SOS per senior; mirrors DemoCareRepository idempotency.
create unique index alerts_one_open_sos_per_senior
  on public.alerts (senior_id) where kind = 'sos' and not acknowledged;

-- AI outputs -----------------------------------------------------------------

create table public.care_insights (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  title text not null,
  summary text not null,
  observations jsonb not null default '[]'::jsonb,
  suggestion text not null,
  data_window_start timestamptz,
  data_window_end timestamptz,
  model_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.appointment_ai_preps (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  senior_id uuid not null references public.account_seniors(id) on delete cascade,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  title text not null,
  observations jsonb not null default '[]'::jsonb,
  questions jsonb not null default '[]'::jsonb,
  safety_note text not null,
  model_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Billing & audit ------------------------------------------------------------

create table public.subscription_statuses (
  id uuid primary key default gen_random_uuid(),
  account_id uuid references public.care_accounts(id) on delete cascade,
  purchaser_profile_id uuid references public.profiles(id) on delete cascade,
  active_entitlements text[] not null default '{}',
  source text not null default 'revenuecat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (account_id is not null or purchaser_profile_id is not null)
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.care_accounts(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id) on delete set null default auth.uid(),
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- updated_at triggers --------------------------------------------------------

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger care_accounts_updated_at before update on public.care_accounts for each row execute function public.set_updated_at();
create trigger account_seniors_updated_at before update on public.account_seniors for each row execute function public.set_updated_at();
create trigger medications_updated_at before update on public.medications for each row execute function public.set_updated_at();
create trigger health_snapshots_updated_at before update on public.health_snapshots for each row execute function public.set_updated_at();
create trigger appointments_updated_at before update on public.appointments for each row execute function public.set_updated_at();
create trigger subscription_statuses_updated_at before update on public.subscription_statuses for each row execute function public.set_updated_at();

-- Indexes --------------------------------------------------------------------

-- Membership lookups (every RLS check) and account feed loading.
create index account_members_profile_idx on public.account_members (profile_id, account_id);
create index account_seniors_account_idx on public.account_seniors (account_id) where deleted_at is null;

-- Senior dashboard loading: latest-first per senior.
create index check_ins_senior_recent_idx on public.check_ins (senior_id, occurred_at desc);
create index mood_entries_senior_recent_idx on public.mood_entries (senior_id, occurred_at desc);
create index medications_senior_idx on public.medications (senior_id) where deleted_at is null;
create index medication_events_med_recent_idx on public.medication_events (medication_id, occurred_at desc);
create index appointments_senior_upcoming_idx on public.appointments (senior_id, scheduled_at) where deleted_at is null;
create index alerts_senior_open_idx on public.alerts (senior_id, occurred_at desc) where not acknowledged;
create index care_insights_senior_recent_idx on public.care_insights (senior_id, created_at desc);
create index appointment_ai_preps_appointment_idx on public.appointment_ai_preps (appointment_id, created_at desc);

-- Latest health snapshot queries.
create index health_snapshots_senior_latest_idx on public.health_snapshots (senior_id, snapshot_date desc);

-- Account-wide feeds used by realtime refreshes.
create index check_ins_account_recent_idx on public.check_ins (account_id, occurred_at desc);
create index medication_events_account_recent_idx on public.medication_events (account_id, occurred_at desc);
create index alerts_account_recent_idx on public.alerts (account_id, occurred_at desc);
create index audit_events_account_recent_idx on public.audit_events (account_id, created_at desc);
create index subscription_statuses_account_idx on public.subscription_statuses (account_id);
create index subscription_statuses_purchaser_idx on public.subscription_statuses (purchaser_profile_id);
