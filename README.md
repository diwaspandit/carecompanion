# CareCompanion

CareCompanion keeps an older adult at home in touch with the family who looks after them from somewhere else. The senior checks in, shares how they feel, marks medicines, and can ask for help. The family sees that day in the senior's own time zone: mood, medicines, visits, Apple Health, and one shared conversation.

The senior uses an iPhone, and can use a paired Apple Watch for the same everyday tasks. The family uses the iPhone app. There is no separate server. The app talks to Supabase, and the database decides what each signed-in person can see.

## Run it

You need Xcode 16 or later, an iOS 17 Simulator or device, and a Supabase project.

```bash
git clone https://github.com/diwaspandit/carecompanion.git
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Put the project host and publishable key in `Config/Secrets.xcconfig`. Apply every file in `Supabase/migrations/` in order. Open `CareCompanion.xcodeproj`, choose the `CareCompanion` scheme, and run it. The watch uses the `CareCompanionWatch` scheme.

`Config/Secrets.xcconfig` is not in git. Without it the app shows "Backend not configured".

```bash
swift test
```

## More detail

| Document | What it covers |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the iPhone, watch, and database fit together |
| [docs/DATABASE.md](docs/DATABASE.md) | Tables, access rules, and project setup |
| [docs/HEALTHKIT.md](docs/HEALTHKIT.md) | What is read from Apple Health, and what the watch sends |
| [docs/DESIGN.md](docs/DESIGN.md) | Colors, the family screens, and the watch |
| [docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md) | A short two-phone walkthrough |

Health samples stay on the senior's devices. The family sees daily totals and hourly readings for that senior only. Care notes describe what happened. They do not diagnose or recommend treatment. An SOS tells the family inside the app. It does not call emergency services.
