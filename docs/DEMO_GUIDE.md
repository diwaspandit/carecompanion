# Demo guide

This guide prepares a two phone demo: a family member in Austin and a senior in Kathmandu. It takes about ten minutes to prepare and five minutes to present.

## Before the demo

### 1. Build

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # then add your Supabase host and key
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Or open the project in Xcode and press Run.

### 2. Prepare two Simulators

Use two different Simulators, for example iPhone 17 for the family and iPhone 17 Pro for the senior. Run the app on both (in Xcode, change the destination and press Run again).

### 3. Create the family (iPhone 17)

1. Choose **Create account**, enter an email and password, and confirm the email link.
2. On **About you**, enter a name such as "Diwas", a city and a phone number.
3. Choose **I look after someone**, keep **Start a family**, enter "Pandit Family" and tap **Create family**.
4. Add the senior: name "Ramesh Pandit", age, city "Kathmandu, Nepal" and time zone Asia/Kathmandu. A senior named Ramesh, Maya, Lakshmi or Hari gets a portrait on the home screen.
5. Open **Profile** and note the invite code. Add an emergency contact and a few medicines.
6. Open **Visits** and add an upcoming appointment.

### 4. Join as the senior (iPhone 17 Pro)

1. Create a second account and fill in **About you**.
2. Choose **I'm the senior**, then **Join with a code**, and enter the invite code.
3. On "Which one is you?", tap "Ramesh Pandit" to link this login to the senior record.
4. In **Settings > Apple Health**, allow access. On a Simulator, tap **Write a sample week into Apple Health** (Debug builds only) so there is health data to share.

## Presenter script

| Step | Phone | Action | What to point out |
| --- | --- | --- | --- |
| 1 | Either | Show the welcome screen on a signed out Simulator | The Kathmandu to Austin animation sets up the story |
| 2 | Family | Open Home | Personal greeting, "Waiting to hear from Ramesh", portrait tile with a clock badge |
| 3 | Senior | Tap the large check-in button | One tap, big target |
| 4 | Family | Watch Home update | Status becomes "Ramesh checked in today" and the badge turns to a check, with no refresh |
| 5 | Senior | Record a mood and mark a medicine as taken | Simple screens, one thing at a time |
| 6 | Family | Tap Ramesh's tile | Care details show check-in time in Kathmandu time, medicines, mood, steps, sleep and resting heart rate |
| 7 | Family | Tap **View health timeline** | Seven day sleep, steps and heart rate trends from Apple Health |
| 8 | Senior | Tap **SOS** and let the countdown finish | Clear confirmation for the senior |
| 9 | Family | Watch Home | The status card turns coral: "Ramesh sent an SOS". Tap it to open Alerts |
| 10 | Family | Tap **Call** or **Message**, then mark the alert handled | The family can act straight away |
| 11 | Either | Open **Messages** and send a note | Shared family conversation in real time |

## Resetting between runs

- Mark open alerts as handled from the family Alerts tab.
- Sign out from Settings to return to the welcome screen.
- To start completely fresh, delete the account from Settings on both phones and repeat the preparation steps.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Backend not configured" | `Config/Secrets.xcconfig` is missing or still has placeholder values |
| Confirmation email does not arrive | The built in Supabase email service sends only a few emails per hour. Configure custom SMTP or confirm the user in the Supabase dashboard |
| Family sees no health data | The senior must be linked on their own phone and have allowed Apple Health access |
| Build cannot find `CareCore` or `Supabase` | In Xcode choose File > Packages > Reset Package Caches, then build again |
