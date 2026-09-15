# Apple Health

CareCompanion reads steps, sleep and resting heart rate on the **senior's own iPhone** and shares one daily total per metric with the members of their care account. Family members' phones never read Apple Health.

## What is read

| Metric | HealthKit type | Daily value |
| --- | --- | --- |
| Steps | `HKQuantityType(.stepCount)` | Sum for the local day (`HKStatisticsCollectionQuery`, which de-duplicates iPhone and Watch) |
| Sleep | `HKCategoryType(.sleepAnalysis)` | Minutes asleep, credited to the day the sleep ended |
| Resting heart rate | `HKQuantityType(.restingHeartRate)` | Latest reading of the local day |

Read access only. Release builds never write to Apple Health. Debug builds have a "Write a sample week into Apple Health" button so the Simulator (which has no Health data) can exercise the pipeline.

## Where the data goes

```
Senior's iPhone                      Supabase (RLS)                    Family iPhones
HealthKit samples -> HealthDayAggregator -> health_snapshots row -> realtime refresh -> Health tab
(stay on device)     one row per day        source = 'healthkit'
```

- `health_snapshots` stores `steps`, `sleep_minutes` and `resting_heart_rate` for each `(senior_id, snapshot_date, source)`. Individual samples never leave the phone.
- Only members of the senior's care account can read those rows (RLS).
- Syncing is an upsert on `(senior_id, snapshot_date, source)`, so repeating it is harmless.

## Day bucketing rules (`Sources/CareCore/HealthDataProvider.swift`)

`HealthDayAggregator` is pure and covered by `HealthDayAggregatorTests`:

- The day key is the phone's local calendar day, stored as midnight UTC so it matches the Postgres `date` column. A reading at 00:30 in Kathmandu belongs to that Kathmandu date, not the previous UTC date.
- Sleep: overlapping samples (iPhone plus Apple Watch) are merged before summing, so time is never double counted. Each merged period counts toward the day it **ended**, so last night's sleep shows up as today. "In bed" time is used only on days with no "asleep" samples.
- Resting heart rate: the most recent reading of the day wins.
- Days with no steps, sleep or heart rate are omitted.

## When it syncs

`AppState.syncHealthData()` runs only when the signed-in user is linked to a senior record (`account_seniors.profile_id`) and permission has been requested:

1. Right after the senior allows access (Settings > Apple Health, or the Apple Health card on the senior home screen).
2. Whenever the app becomes active.
3. When `HKObserverQuery` background delivery reports new samples (hourly).
4. "Share now" in the Apple Health sheet.

## Permissions

HealthKit never tells an app whether read access was granted. The provider records that the system prompt was shown and treats the result of each query as the truth: denied types simply return no samples. The sheet explains how to stop sharing (Health app > Sharing > Apps > CareCompanion) and links to Settings.

## Family view

- Health tab: seven-day sleep bars, steps and resting-heart-rate trends, weekly medication adherence and mood.
- If the senior hasn't joined on their own iPhone, the family sees "Health data syncs from Maya's own iPhone once they join with your invite code".
- Values are observations only; the app never interprets them medically.

## Files

| File | Purpose |
| --- | --- |
| `App/Services/HealthKitHealthDataProvider.swift` | HealthKit queries, background delivery, debug sample writer |
| `Sources/CareCore/HealthDataProvider.swift` | Provider protocol and `HealthDayAggregator` |
| `Sources/CareCore/AppState.swift` | `syncHealthData`, `canSyncHealth`, automatic sync set-up |
| `App/Features/HealthPermissionsView.swift` | Senior-facing permission and sync sheet |
| `Config/CareCompanion.entitlements` | HealthKit capability and background delivery |
| `Config/App.xcconfig` | Usage descriptions |

## Testing

```sh
swift test --filter HealthDayAggregatorTests
swift test --filter CareCoreTests/testHealthSync
```

On the Simulator, as the senior user: Settings > Apple Health > "Write a sample week into Apple Health", then confirm the family device's Health tab shows seven days.
