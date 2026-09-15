# CareCompanion database

Persistence runs on Supabase (Postgres, Auth, Realtime). The iOS app talks to it only through the Supabase Swift SDK with the **publishable key**. Row Level Security is the security boundary: the key is public by design, and the database decides which rows a signed-in user may see.

There is no custom server. The service_role key and the Supabase access token are never in the app.

## Where things live

| Path | Purpose |
| --- | --- |
| `Supabase/migrations/20260914000001_care_schema.sql` | Core tables, constraints, `updated_at` triggers, indexes |
| `Supabase/migrations/20260914000002_rls_and_account_flow.sql` | RLS helpers and policies, profile trigger, account RPCs, realtime publication |
| `Supabase/migrations/20260915000001_production_features.sql` | Phone and dosage columns, emergency contacts, messages, senior self-linking, account deletion |
| `Supabase/tests/run_docker.sh` | Applies all migrations to a throwaway Postgres 17 container and runs both RLS suites |
| `Supabase/tests/run_local.sh` | Same, using Homebrew Postgres |
| `Supabase/tests/rls_test.sql`, `rls_production_test.sql` | RLS contract tests |
| `Config/Secrets.xcconfig` (git-ignored) | `SUPABASE_HOST`, `SUPABASE_ANON_KEY`; template in `Secrets.xcconfig.example` |
| `App/Services/SupabaseCareRepository.swift` | `CareRepository` over PostgREST plus realtime refresh |
| `App/Services/SupabaseAuthSessionService.swift` | Email/password sign-up and sign-in, password reset, deep links |
| `App/Services/SessionController.swift` | Session, then profile, then account, then `AppState` |
| `Sources/CareCore/CareRecords.swift` | Vendor-free row types and row to `CareSnapshot` mapping (unit tested) |

## Schema

Every care table carries `account_id` (denormalized) so each RLS check is one indexed membership lookup, and realtime can filter by account.

| Table | Purpose | Notes |
| --- | --- | --- |
| `profiles` | One row per auth user: `display_name`, `city`, `phone` | Created by `on_auth_user_created` |
| `care_accounts` | A family | `invite_code` lets others join |
| `account_members` | Profile to account link, role `senior` or `family` | Unique per (account, profile) |
| `account_seniors` | Monitored senior | `profile_id` links the senior's own login; soft delete |
| `check_ins` | "I'm okay" confirmations | |
| `mood_entries` | `Great` / `Okay` / `Low` plus optional note | |
| `medications` | Name, `dosage`, `scheduled_time` | Soft delete |
| `medication_events` | `taken` / `skipped` / `missed` | "Taken today" is the latest event on the senior's local day; a week is loaded for adherence |
| `health_snapshots` | Daily steps, sleep, resting heart rate | Unique (senior, date, source); see `docs/HEALTHKIT.md` |
| `appointments` | Visits | Soft delete |
| `alerts` | SOS | Partial unique index: one open SOS per senior |
| `emergency_contacts` | Name, relation, phone per senior | Shown on the SOS screen |
| `messages` | Family conversation per account | `sender_profile_id` defaults to the caller |
| `care_insights`, `appointment_ai_preps` | Reserved for a future server-generated insight | Not written by the app today |
| `subscription_statuses` | Reserved for RevenueCat | Premium is free for now |
| `audit_events` | Account created, member joined, senior claimed | Append-only for members |

### "Today" is the senior's day

`CareRecords.snapshot(now:)` evaluates check-ins and medication status in each senior's `time_zone_identifier`. A caregiver in Austin sees a Kathmandu senior's day, not their own.

### Idempotent writes

New rows get an id generated on the device and are inserted with `Prefer: resolution=ignore-duplicates` (`ON CONFLICT (id) DO NOTHING`). Updates and deletes target explicit ids. A write that fails because a pooled connection dropped is retried once (`TransientRetry`) without risk of duplicates. `create_care_account` is the one call that is not retried.

## Row Level Security

Rule: **a signed-in user can read and write only rows whose `account_id` is an account they belong to.** The `anon` role has no table privileges.

| Helper (SECURITY DEFINER) | Why |
| --- | --- |
| `is_account_member(account_id)` | Membership check without recursive policies |
| `senior_in_account(senior_id, account_id)` | Stops attaching another account's senior |
| `shares_account_with(profile_id)` | Lets co-members see each other's name and phone |

| Table | select | insert | update | delete |
| --- | --- | --- | --- | --- |
| `profiles` | self or co-member | trigger only | self | cascade from auth user |
| `care_accounts` | members | `create_care_account()` | members | `delete_my_account()` when last member |
| `account_members` | members | RPCs only | none | self (leave) |
| `account_seniors` | members | members; `profile_id` only as the senior themself | members; `profile_id` only via `claim_senior()` | none (soft delete) |
| senior-scoped care tables | members | members + senior in account | members + senior in account | `appointments` |
| `emergency_contacts` | members | members + senior in account | members + senior in account | members |
| `messages` | members | members, as themselves | none | own messages |
| `audit_events` | members | members, as self | none | none |

A trigger (`account_seniors_guard_profile_link`) enforces that only the senior can link a login to a senior record.

### RPCs

| Function | Purpose |
| --- | --- |
| `create_care_account(account_name, member_role)` | Creates a family and makes the caller a member |
| `join_care_account(code, member_role)` | Joins by invite code (idempotent) |
| `claim_senior(target_senior_id)` | Senior member links their login to the senior record their family created |
| `delete_my_account()` | Deletes the caller's login and profile, and any account where they were the only member (App Store 5.1.1(v)) |

`rls_production_test.sql` checks that family members cannot link themselves as the senior, outsiders cannot read or post messages or contacts, senders cannot be spoofed, and account deletion removes single-member families but keeps shared ones.

```sh
Supabase/tests/run_docker.sh   # Docker; touches nothing remote
```

## Account flow

```mermaid
sequenceDiagram
    participant Diwas as "Diwas's iPhone"
    participant Maya as "Maya's iPhone"
    participant Auth as "Supabase Auth"
    participant DB as "Postgres + RLS"
    participant RT as "Realtime"

    Diwas->>Auth: sign up (email confirmation link)
    Diwas->>DB: update profiles (name, city, phone)
    Diwas->>DB: rpc create_care_account("Sharma family")
    Diwas->>DB: insert account_seniors (Maya)
    Maya->>Auth: sign up / sign in
    Maya->>DB: rpc join_care_account(invite_code, "senior")
    Maya->>DB: rpc claim_senior(Maya's senior id)
    Maya->>DB: insert check_ins, mood_entries; upsert health_snapshots
    DB-->>RT: postgres_changes (RLS-filtered)
    RT-->>Diwas: change event, refresh, dashboard
```

Realtime-published tables: `account_members`, `account_seniors`, `check_ins`, `mood_entries`, `medications`, `medication_events`, `health_snapshots`, `appointments`, `alerts`, `appointment_ai_preps`, `emergency_contacts`, `messages`.

## Live project set-up

1. Apply every file in `Supabase/migrations/` in order (SQL Editor, `psql`, or the Management API).
2. Authentication > URL Configuration: `carecompanion://login-callback` must be in Redirect URLs (it is).
3. Authentication > Providers > Email: enabled, with "Confirm email" on.
4. Before launch, configure custom SMTP. The built-in email service is limited to a few emails per hour, which blocks real sign-ups and password resets.
5. `Config/Secrets.xcconfig` holds the project host and publishable key.
