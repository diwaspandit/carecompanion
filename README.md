# CareCompanion

CareCompanion is a native iOS app that connects older adults living at home with the family members who look after them from far away. A senior in Kathmandu taps one large button to check in, records how they feel, marks medicines as taken, and can send an SOS. Their family in Austin sees that day at a glance, in the senior's own time zone, together with Apple Health trends, visits and a shared family conversation.

## Contents

- [Features](#features)
- [Screens](#screens)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Running the demo](#running-the-demo)
- [Testing](#testing)
- [Documentation](#documentation)
- [Privacy and safety](#privacy-and-safety)

## Features

### For the senior

- **One tap check-in.** A large "I'm okay" button that the family sees immediately.
- **Mood.** Great, Okay or Low, with an optional note for the family.
- **Medicines.** Today's list with large controls to mark each dose as taken.
- **Visits.** Upcoming appointments added by the family.
- **SOS.** A full screen flow with a short countdown that alerts every family member and lists emergency contacts to call.
- **Apple Health sharing.** Daily steps, sleep and resting heart rate, read on the senior's own iPhone only.
- **Messages.** The family conversation, with larger text.

### For the family

- **Home.** A personal greeting, a status card that summarises the selected senior's day, a photo tile for each senior with a live status badge, and a care insight shortcut.
- **Care details.** Check-in time in the senior's time zone, medicines taken, mood, steps, sleep, resting heart rate and a one tap call button.
- **Care insight.** A plain language summary built from real account data. It states observations only and never gives medical interpretation.
- **Health.** Seven day sleep bars, steps and resting heart rate trends, weekly medicine adherence and mood history.
- **Alerts.** Open SOS alerts and missed medicines, with Call, Message and mark as handled.
- **Visits.** A calendar of appointments with a preparation card for each visit.
- **Messages.** One conversation per family, refreshed in real time.
- **Profile.** Senior details, emergency contacts, medicine management, family members, the invite code and a health baseline.

### Accounts

- Email and password sign up with email confirmation, sign in, and password reset through a deep link.
- Create a family or join one with an invite code, choosing the family or senior role.
- A senior joining on their own iPhone links their login to the senior record their family created.
- Settings include profile editing, privacy information, sign out and full account deletion.

## Screens

| Screen | What it shows |
| --- | --- |
| Welcome | Animated illustration of care travelling between Kathmandu and Austin, then sign in or create account |
| Account setup | Role cards ("I look after someone" or "I'm the senior") and create or join a family |
| Family home | Greeting, day status card, senior photo tiles, add a senior tile, care insight shortcut, soft landscape backdrop |
| Senior care details | Full daily summary and care insight for the selected senior |
| Senior home | Check-in button, mood prompt, next visit, Apple Health card, people to call, SOS |

## Tech stack

| Area | Choice |
| --- | --- |
| Platform | iOS 17 and later, iPhone first, portrait |
| Language and UI | Swift 6, SwiftUI, Observation |
| Domain logic | `CareCore`, a local Swift package with no third party dependencies |
| Backend | Supabase: Postgres with Row Level Security, Auth, Realtime |
| Health | HealthKit with background delivery |
| Animation | Lottie 4.6.1 (Airbnb `lottie-spm`) for the welcome illustration |
| Tests | XCTest for `CareCore`, XCUITest for launch and form validation, SQL tests for RLS |

There is no custom server. The app uses only the Supabase publishable key, and the database decides which rows a signed in user can read or write.

## Project structure

```
App/
  CareCompanionApp.swift        App entry, session routing, signed in root
  DesignSystem.swift            Colors, cards, avatars, buttons, form fields
  Features/                     SwiftUI screens (auth, onboarding, family, senior, shared)
  Services/                     Supabase, HealthKit and session services
  Assets.xcassets/              Senior portraits
  Resources/care-connection.json  Welcome animation
Sources/CareCore/               Models, AppState, repositories, rules, health aggregation
Tests/CareCoreTests/            Unit tests for CareCore
CareCompanionUITests/           UI tests
Supabase/migrations/            Database schema, RLS policies and RPCs
Supabase/tests/                 RLS contract tests and a live smoke test
Config/                         xcconfig, Info.plist, entitlements, secrets template
Scripts/                        Dependency free CareCore smoke check
docs/                           Architecture, database, Apple Health, design and demo guides
```

## Getting started

### Requirements

- macOS with Xcode 16 or later (verified with Xcode 27)
- An iOS 17 or later Simulator or device
- A Supabase project with the migrations in `Supabase/migrations/` applied

### 1. Clone

```bash
git clone https://github.com/diwaspandit/carecompanion.git
```

### 2. Add your Supabase keys

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig` and set:

```
SUPABASE_HOST = your-project-ref.supabase.co
SUPABASE_ANON_KEY = your-publishable-key
```

The host is written without `https://`. `Config/Secrets.xcconfig` is git ignored. Without it the app opens a "Backend not configured" screen.

### 3. Set up the database

Apply every file in `Supabase/migrations/` in order, then follow the "Live project set-up" checklist in [docs/DATABASE.md](docs/DATABASE.md) (redirect URL, email provider, SMTP).

### 4. Build and run

Open `CareCompanion.xcodeproj`, choose the `CareCompanion` scheme and an iPhone Simulator, and press Run. Xcode resolves Supabase and Lottie through Swift Package Manager on first build.

From the command line:

```bash
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Running the demo

The full step by step script, including how to prepare two Simulators (a family phone and a senior phone), is in [docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md). In short:

1. Create a family account on the first Simulator and add a senior.
2. Join as that senior on a second Simulator with the invite code.
3. Check in, record a mood, mark a medicine and send an SOS as the senior.
4. Watch the family home, alerts and health tabs update in real time.

Seniors named Maya, Ramesh, Lakshmi or Hari show a bundled portrait on their tile. Anyone else shows their initials.

## Testing

| What | Command |
| --- | --- |
| CareCore unit tests (63 tests) | `swift test` |
| UI tests | `xcodebuild test -project CareCompanion.xcodeproj -scheme CareCompanion -destination 'platform=iOS Simulator,name=iPhone 17'` |
| RLS contract tests in Docker | `Supabase/tests/run_docker.sh` |
| RLS contract tests with local Postgres | `Supabase/tests/run_local.sh` |
| Live project smoke test | `Supabase/tests/live_smoke.sh` (see the header of the script for required variables) |
| Dependency free core check | `Scripts/check-core.sh` |

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | App layers, session flow, state, data flow and key engineering decisions |
| [docs/DATABASE.md](docs/DATABASE.md) | Schema, Row Level Security, RPCs and live project set-up |
| [docs/HEALTHKIT.md](docs/HEALTHKIT.md) | What is read from Apple Health, day bucketing and sync triggers |
| [docs/DESIGN.md](docs/DESIGN.md) | Visual language, components, family home layout and bundled assets |
| [docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md) | Demo preparation and a presenter script |

## Privacy and safety

- Health samples stay on the senior's iPhone. Only one daily total per metric is shared, and only with members of the same family account.
- The app never writes to Apple Health in release builds.
- Care insights and visit preparation describe what happened. They do not diagnose, recommend treatment or interpret values medically.
- SOS alerts the family inside the app. It does not contact emergency services.
- Users can delete their account and data from Settings.
