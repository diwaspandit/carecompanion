# Database

CareCompanion stores data in Supabase. The app uses the publishable key only. Row Level Security decides which rows a signed-in person can read or write. The service role key stays on the server, in the push function. It is not in the app or in git.

Apply every file in `Supabase/migrations/` in filename order.

## Tables

Every care table has `account_id`, so a membership check is enough to allow or deny a row.

| Table | What it stores |
| --- | --- |
| `profiles` | Name, city, and phone for each login |
| `care_accounts` | A family and its invite code |
| `account_members` | Who belongs, as `senior` or `family` |
| `account_seniors` | The person being looked after, their time zone, and mood-check times |
| `check_ins` | "I'm okay" |
| `mood_entries` | Great, Okay, or Low |
| `medications` | Name, dose, clock time, optional weekdays, optional end date |
| `medication_events` | Taken, skipped, or missed |
| `medication_snoozes` | A shared snooze so the phone and watch agree |
| `medication_push_log` | One scheduled push per medicine per local day |
| `health_snapshots` | Daily steps, sleep, and resting heart rate |
| `health_readings` | Hourly readings, worn minutes, and live watch presence |
| `appointments` | Visits, repeat rule, end date, and whether the senior went |
| `alerts` | An open SOS, one per senior |
| `emergency_contacts` | People to call from the SOS screen |
| `messages` | The family conversation, including a voice-clip path |
| `message_reads` | Who has opened a message |
| `device_tokens` | iPhone and watch push tokens |

`account_seniors.mood_morning` and `mood_evening` default to `9:00 AM` and `6:00 PM`. `mood_prompt_at` is set when the family asks for a mood now, and cleared when the senior answers.

`medications.nudge_at` is set only when the family taps Remind. Saving a medicine leaves it empty, so the alert waits for `scheduled_time`.

"Today" is the senior's `time_zone_identifier`. A family member in another time zone still sees that senior's day.

## Access

A signed-in member can read and write rows for their own family. The `anon` role cannot. Only the senior can link their login to a senior record. Message senders cannot pretend to be someone else.

Account setup uses `create_care_account`, `join_care_account`, and `claim_senior`. `delete_my_account` removes the login and a family that has no other members.

`Supabase/functions/send-medication-push` sends Apple pushes for a due dose, a family Remind, messages, mood and medicine updates, and a mood check. It runs with the service role. Apple push secrets live in the function environment, not in the repository.

## Project setup

1. Apply the migrations in order.
2. Add `carecompanion://login-callback` to the Auth redirect URLs.
3. Leave email confirmation on.
4. Use custom SMTP before a real launch. The built-in mailer only sends a few messages an hour.
5. Put the host and publishable key in `Config/Secrets.xcconfig`.

```sh
Supabase/tests/run_docker.sh
```
