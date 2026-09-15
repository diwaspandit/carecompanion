# CareCompanion database

Production persistence runs on Supabase (Postgres + Auth + Realtime). The iOS app talks to it only through the Supabase Swift SDK with the **publishable (anon) key**. Row Level Security is the security boundary: the key is public by design, and the database decides which rows a signed-in user may see.

There is no custom server. Demo mode never touches any of this.

## Where things live

| Path | Purpose |
| --- | --- |
| `Supabase/migrations/20260914000001_care_schema.sql` | Tables, constraints, `updated_at` triggers, indexes |
| `Supabase/migrations/20260914000002_rls_and_account_flow.sql` | RLS helpers and policies, profile trigger, account RPCs, realtime publication |
| `Supabase/tests/run_local.sh` | Applies both migrations to a throwaway local Postgres and runs `rls_test.sql` |
| `Config/Secrets.xcconfig` (git-ignored) | `SUPABASE_HOST`, `SUPABASE_ANON_KEY`; template in `Secrets.xcconfig.example` |
| `App/Services/SupabaseConfig.swift` | Builds the shared `SupabaseClient`, or `nil` when secrets are absent |
| `App/Services/SupabaseAuthSessionService.swift` | Magic-link sign-in (`carecompanion://login-callback`) |
| `App/Services/SupabaseCareRepository.swift` | `CareRepository` over PostgREST + realtime refresh |
| `Sources/CareCore/CareRecords.swift` | Vendor-free row types and row → `CareSnapshot` mapping (unit tested) |

## Schema

Every care table carries `account_id` (denormalized) so each RLS check is a single indexed membership lookup, and realtime can filter by account.

| Table | Purpose | Notes |
| --- | --- | --- |
| `profiles` | One row per `auth.users` user | Created by `on_auth_user_created` trigger |
| `care_accounts` | Family (future: organization) container | `invite_code` lets a second member join |
| `account_members` | Profile ↔ account, role `senior`/`family` | Unique per (account, profile) |
| `account_seniors` | Monitored senior | Optional `profile_id` if the senior signs in; soft delete |
| `check_ins` | "I'm okay" confirmations | |
| `mood_entries` | `Great` / `Okay` / `Low` + optional note | Optional link to a check-in |
| `medications` | Schedule | Soft delete |
| `medication_events` | `taken` / `skipped` / `missed` | App shows the latest event on the senior's local day |
| `health_snapshots` | Daily metrics | `source` ∈ `demo`, `manual`, `healthkit`, `device_import`; unique (senior, date, source) |
| `appointments` | Visits | Soft delete; hard delete also allowed |
| `alerts` | SOS and care alerts | Partial unique index: one open SOS per senior |
| `care_insights` | Saved AI insight | Data window + model metadata columns for Phase 6 |
| `appointment_ai_preps` | Saved appointment prep | |
| `subscription_statuses` | Cached entitlements | Client read-only; written server-side (Phase 3) |
| `audit_events` | Privacy/security actions | Append-only for members |

### "Today" is the senior's day

`CareRecords.snapshot(now:)` evaluates check-ins and medication status in each senior's `time_zone_identifier`. When Diwas opens the app in Austin, he sees Maya's Kathmandu day, not his own.

## Row Level Security

Rule: **a signed-in user can read and write only rows whose `account_id` is an account they belong to.** The `anon` role has no table privileges at all.

| Helper (SECURITY DEFINER) | Why |
| --- | --- |
| `is_account_member(account_id)` | Membership check without recursive policies on `account_members` |
| `senior_in_account(senior_id, account_id)` | Stops a member of account A from attaching account B's senior to A |
| `shares_account_with(profile_id)` | Lets co-members see each other's display names |
| `is_linked_senior(senior_id)` | True when the signed-in login is the senior's own linked login |

| Table | select | insert | update | delete |
| --- | --- | --- | --- | --- |
| `profiles` | self or co-member | trigger only | self | — |
| `care_accounts` | members | `create_care_account()` only | members | — |
| `account_members` | members | `create_care_account()` / `join_care_account()` only | — | self (leave) |
| `account_seniors` | members | members (never with `profile_id`) | members (`profile_id` only via `claim_senior_profile()`) | — (soft delete) |
| senior-scoped care tables | members | members + senior in account | members + senior in account | `appointments` only |
| `health_snapshots` with `source = 'healthkit'` | members | also linked senior only | also linked senior only | — |
| `subscription_statuses` | members or purchaser | server only | server only | — |
| `audit_events` | members | members, as self | — | — |

`Supabase/tests/rls_test.sql` checks two families. It asserts that the outsider cannot read, insert, attach a foreign senior, or acknowledge alerts across accounts, that anon is locked out, that a second open SOS is rejected, and that bogus invite codes fail. To confirm the test is not vacuous, weakening a read policy to `using (true)` makes it fail.

`Supabase/tests/senior_link_test.sql` checks the senior device link (migration `20260915000003`): a family member or outsider cannot claim a senior or set `profile_id` directly, a senior member can claim once (idempotently), a second senior cannot take over a linked record, and only the linked login can insert or update `healthkit` snapshots.

```sh
Supabase/tests/run_local.sh   # needs Homebrew postgresql; touches nothing remote
```

## Account information flow

```mermaid
sequenceDiagram
    participant Diwas as "Diwas's iPhone"
    participant Maya as "Maya's iPhone"
    participant Auth as "Supabase Auth"
    participant DB as "Postgres + RLS"
    participant RT as "Realtime"

    Diwas->>Auth: signInWithOTP(email) → magic link
    Auth-->>Diwas: carecompanion://login-callback → session
    Diwas->>DB: rpc create_care_account("Sharma family")
    Diwas->>DB: insert account_seniors (Maya)
    DB-->>Diwas: invite_code
    Maya->>Auth: magic link sign-in
    Maya->>DB: rpc join_care_account(invite_code, "senior")
    Maya->>DB: rpc claim_senior_profile(Maya's senior id)
    Diwas->>RT: subscribe care-account-<id> (8 tables, account_id filter)
    Maya->>DB: insert check_ins
    DB-->>RT: postgres_changes (RLS-filtered)
    RT-->>Diwas: change event
    Diwas->>DB: SupabaseCareRepository.refresh()
    Diwas->>Diwas: AppState.refresh() → dashboard shows check-in
```

Realtime-published tables: `check_ins`, `mood_entries`, `medications`, `medication_events`, `health_snapshots`, `appointments`, `alerts`, `appointment_ai_preps`. Postgres changes respect RLS, so a subscriber only receives rows from their own account.

## Indexes

- Membership (hit by every policy): `account_members (profile_id, account_id)`, plus the unique `(account_id, profile_id)`.
- Senior dashboard, latest first: `check_ins`, `mood_entries` and `medication_events` on `(… , occurred_at desc)`; open alerts; upcoming appointments.
- Latest health snapshot: `health_snapshots (senior_id, snapshot_date desc)`.
- Account feeds for realtime refresh: `check_ins`, `medication_events`, `alerts` and `audit_events` by `(account_id, time desc)`.

## Setup checklist (live project)

1. Apply migrations in order. Either paste each file into Supabase Dashboard → SQL Editor and run it, or use `psql "<connection string>" -v ON_ERROR_STOP=1 -f Supabase/migrations/<file>.sql`.
2. Dashboard → Authentication → URL Configuration → add `carecompanion://login-callback` to Redirect URLs.
3. Dashboard → Authentication → Providers → Email: keep enabled (magic link).
4. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` with the project host and publishable key. Never put the `service_role` key in the app.

## Verifying the live project

```sh
SUPABASE_HOST=<ref>.supabase.co SUPABASE_ANON_KEY=<publishable key> \
DIWAS_EMAIL=... MAYA_EMAIL=... OUTSIDER_EMAIL=... TEST_PASSWORD=... \
Supabase/tests/live_smoke.sh
```

The script needs three auto-confirmed email/password test users (Authentication → Users → Add user). Each run creates a new "Smoke Sharma <timestamp>" account.

To check realtime by hand in a Debug build:
1. Long-press the logo to open the demo menu, then Developer → Live Supabase.
2. Sign in as the family test user, add starter medications, tap "Use live data in the app" and choose "I am a family member".
3. Write as the senior user (e.g. a `medication_events` row). The dashboard's medication count updates without interaction.

## Senior device link

A family member's phone must never store its own Apple Health data as the senior's. A member who joined as `senior` calls `claim_senior_profile(senior_id)` to set `account_seniors.profile_id` to their login. A trigger rejects any other change to `profile_id`, and restrictive policies on `health_snapshots` only let that linked login write `healthkit` rows. The app mirrors this with `AppState.healthSyncEligibility`, so a family device never asks for HealthKit permission or syncs. Until Phase 5 onboarding, the link is made from Developer → Live Supabase → "I am <senior>".

## Not in this phase

- Production mode is reachable only through the Debug-only developer screen. The app still boots `DemoCareRepository`. User-facing sign-in, account creation and invite screens belong to Phase 5.
- `subscription_statuses` is still unwritten. It must come from a RevenueCat webhook (server side), never from the app, because a client write could forge entitlements.
- Live AI writes to `care_insights` / `appointment_ai_preps` arrive in Phase 6.
