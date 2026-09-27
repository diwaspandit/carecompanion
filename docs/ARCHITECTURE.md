# Architecture

CareCompanion is a SwiftUI app for iPhone and Apple Watch, backed by Supabase. Domain rules live in a package with no third-party dependencies. The app targets own the screens and the SDKs.

## Layers

| Layer | Location | Responsibility |
| --- | --- | --- |
| iPhone UI | `App/Features/`, `App/DesignSystem.swift` | Senior and family screens |
| Watch UI | `Watch/` | Mood, New, Talk, and SOS for the paired senior |
| Widget | `Widget/` | A home-screen snapshot of the senior's day |
| Session | `App/Services/SessionController.swift` | Restores sign-in, loads the account, builds `AppState` |
| Device services | `App/Services/` | Supabase, HealthKit, reminders, push, and the watch link |
| Domain | `Sources/CareCore/` | Models, `AppState`, summaries, schedules, and insight rules |
| Database | `Supabase/migrations/`, `Supabase/functions/` | Tables, access rules, and the push function |

`CareCore` does not import UserNotifications, HealthKit, or WatchConnectivity. `swift test` runs it offline. The iPhone and the watch share the reminder code in `MedicationReminderCenter`.

## Launch

`RootView` follows `SessionController.phase`: secrets, then a stored session, then a profile, then a family. A senior who has not linked their login is asked which senior record is theirs. A family with no seniors is asked to add one. Password reset opens `carecompanion://login-callback`.

The watch does not sign in on its own. The paired iPhone publishes the session over Watch Connectivity. The phone refreshes the token. The watch only stores it.

## State and data

`AppState` holds the account snapshot, the selected senior, and the tab for each role. Screens call its methods. Those methods write through `CareRepository`, then refresh. New rows use an id created on the device, so a retry cannot insert a second copy.

Postgres Row Level Security limits every row to members of that family. Realtime tells the other open apps to refresh.

## Reminders

Daily medicine and mood times are scheduled on the senior's iPhone and watch. They fire at the saved clock time even if the app is closed. Adding or editing a medicine does not send an alert. A family Remind sets `medications.nudge_at` and sends a push. Mood checks default to 9:00 AM and 6:00 PM. Answering on one device clears the prompt on the other.

Closed-app pushes go through `Supabase/functions/send-medication-push`. That function uses Apple push credentials stored in Supabase, not in the app.

## Decisions

- The database is the security boundary. The app ships only the publishable key.
- "Today" is the senior's time zone, not the family's.
- Medicine "taken" is the latest event on that local day, not a stored flag.
- Only the senior's iPhone and watch read Apple Health. The phone writes the shared rows.
- Care insight is rule based. It describes the day. It does not give medical advice.
