# Apple Health

Only the senior's iPhone and paired Apple Watch read Apple Health. Family phones never do. Individual samples stay on those devices. The family sees daily totals and hourly readings for that senior.

## What is read

| Metric | HealthKit type | What is shared |
| --- | --- | --- |
| Steps | step count | Sum for the local day |
| Sleep | sleep analysis | Minutes asleep, on the day the sleep ended |
| Resting heart rate | resting heart rate | Latest reading of the local day |
| Heart rate | heart rate | Hourly average |
| Blood pressure | blood pressure | Hourly systolic and diastolic |

Overlapping sleep from the iPhone and the watch is merged before it is summed. Days with nothing to report are omitted.

The watch also infers whether it is being worn from a recent heart-rate sample. The family senior card shows Watch on or Watch off from that live row. Worn minutes for each hour are stored separately.

## Where it goes

The watch reads HealthKit and sends a report to the paired iPhone. The iPhone writes the database.

- `health_snapshots` keeps one daily row per senior, date, and source: steps, sleep, and resting heart rate.
- `health_readings` keeps hourly heart rate, blood pressure, steps, sleep, worn minutes, and one live presence row.
- The first report of an hour is uploaded immediately. Later reports for that hour wait until the hour rolls.

Release builds do not write to Apple Health. A debug build can add a sample week on the Simulator.

## When it syncs

The senior's iPhone syncs after Health access is allowed, when the app becomes active, when HealthKit reports new samples, and when the user taps Share now. The watch sends wear about once a minute, and health totals on the hourly schedule above.

If the senior has not joined on their own iPhone, the family is told that Apple Health cannot sync yet.

## Files

| File | Purpose |
| --- | --- |
| `App/Services/HealthKitHealthDataProvider.swift` | iPhone queries and background delivery |
| `Watch/WatchHealthRelay.swift` | Watch queries and the report sent to the iPhone |
| `Sources/CareCore/HealthDataProvider.swift` | The provider protocol and day aggregation |
| `App/Features/HealthPermissionsView.swift` | The senior's sharing screen |

```sh
swift test --filter HealthDayAggregatorTests
```
