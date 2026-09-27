# Demo guide

Use two Simulators: one for the family, one for the senior. A paired watch Simulator is optional.

## Prepare

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Add the Supabase host and publishable key, apply `Supabase/migrations/`, then run the `CareCompanion` scheme on both iPhones.

On the family phone, create an account, start a family, and add a senior. Kathmandu and a senior named Maya, Ramesh, Lakshmi, or Hari make the time zone and portrait obvious. Add a medicine for a later time, a visit, and an emergency contact. Copy the invite code from Profile.

On the senior phone, create an account, join with that code, and choose the senior record. Allow Apple Health. On a Simulator, a debug build can write a sample week of health data.

## Show

1. On the family Home, the senior is waiting to check in.
2. On the senior phone, tap check-in. The family Home updates without a refresh.
3. Record a mood and mark a medicine. The family is notified, and the care page shows the green mood and the dose.
4. Open the senior's care page. The day fits on one screen. Open Medicines or Care insight for the rest.
5. Open Profile. It shows the family member. Open the senior's row to edit their details.
6. Send a message each way. Names have different colors, and a tap opens Messages.
7. Send an SOS from the senior phone. The family status card turns coral.

If the watch is paired, the same mood, medicine, message, and SOS actions work from Mood, New, Talk, and SOS. A medicine added for later does not alert until that time.

## If something fails

| What you see | What to check |
| --- | --- |
| Backend not configured | `Config/Secrets.xcconfig` |
| No confirmation email | Supabase email limits, or confirm the user in the dashboard |
| No health data | The senior is linked and has allowed Apple Health |
| Package errors | Xcode, File > Packages > Reset Package Caches |
