# CareCompanion — TXST Shipaton

## Mission

Build a polished native iOS application called CareCompanion.

Primary goal:

WIN THE TXST SHIPATON.

Optimize for:
1. flawless 90-second demo
2. exceptional visual quality
3. clear emotional story
4. real RevenueCat integration
5. useful premium AI
6. reliability

Do not optimize for feature count.

## Product Story

Maya Sharma is an elderly woman living in Kathmandu, Nepal.

Diwas is her family member living in Austin, Texas.

CareCompanion allows Maya to communicate basic wellbeing with
extremely little technological complexity while giving Diwas useful
care context from thousands of miles away.

The hackathon demo focuses only on Maya and Diwas.

## Technology

Native iOS only.

Use:
- Swift
- SwiftUI
- iOS 17+
- NavigationStack
- async/await
- Swift Charts when useful
- XCTest
- RevenueCat Purchases
- RevenueCatUI
- Supabase Swift only after the core demo is stable

Do not introduce:
- React
- React Native
- Node backend
- Python backend
- custom REST server
- Android

## Visual Source of Truth

The existing Lovable project "CareCompanion Connect" is the visual
reference.

Design characteristics:

Background:
#FAFAF7

Sage:
#6B9E78

Coral:
#E8806A

Secondary gray:
#8A8A8A

Primary text:
#2C2C2A

Preserve:
- "Care that travels across time zones."
- strongly rounded cards
- warm premium visual style
- very large senior controls
- sophisticated family dashboard
- dramatic SOS countdown
- simple mood selection
- appointment-manager visual language

Do NOT port React/Tailwind code.

Translate the design into idiomatic SwiftUI with SF Symbols,
native sheets and native navigation.

## Demo Data

Senior:

Maya Sharma
74 years old
Kathmandu, Nepal

Family:

Diwas
Austin, Texas

Demo health values:

Steps: 2,840
Sleep: 6h 20min
Resting heart rate: 72 bpm

Medication:
3 of 4 taken

Mood:
Okay

Use deterministic realistic historical data for approximately
7 days where necessary.

Never claim seeded data came from HealthKit.

## Required Architecture

Create:

CareRepository
- DemoCareRepository
- SupabaseCareRepository

AIService
- MockAIService
- LiveAIService

HealthDataProvider
- DemoHealthDataProvider

SubscriptionService

PlanService / AccessPolicy

DemoScenarioController

Views must not call Supabase, RevenueCat or AI APIs directly.

All critical demo functionality must work with DemoCareRepository.

## Demo Mode

Demo Mode must work without:
- Supabase
- AI network requests
- backend availability

Support deterministic states:

initial
checkedIn
moodRecorded
premiumUnlocked
appointmentPrepared
sosTriggered

Create a hidden developer/demo menu that can reset the entire demo.

The demo must be repeatable.

## Required Demo Flow

The application must support:

1. Launch.
2. Show onboarding:
   "Care that travels across time zones."
3. Select Senior.
4. Show Maya's Senior Home.
5. Maya taps "I'm okay".
6. Show confirmation.
7. Maya records mood.
8. Switch to Family.
9. Diwas sees Maya checked in.
10. Dashboard shows:
    - check-in
    - medication adherence
    - mood
    - 2,840 steps
    - 6h 20min sleep
    - 72 bpm resting heart rate
11. Show CareCompanion AI Insight teaser.
12. Full insight is premium.
13. Present REAL RevenueCat paywall.
14. RevenueCat Test Store purchase unlocks premium.
15. Full Care Insight appears.
16. Open Maya's appointment.
17. Tap:
    "Prepare with CareCompanion AI"
18. Generate appointment preparation.
19. Show recent observations and questions to discuss with clinician.
20. Switch to Maya.
21. Trigger SOS.
22. Show animated 5-second countdown.
23. Family experience changes to emergency state.

## AI Safety/Product Requirement

AI assists with organization and preparation.

It must NOT:
- diagnose
- prescribe treatment
- estimate disease probability
- claim medical emergencies based on health data

Prefer language such as:
- recent change
- care insight
- consider checking in
- worth discussing
- questions to discuss at the appointment

## Plans

### Free
Maximum 1 monitored senior.

Includes:
- check-in
- SOS
- medications
- mood
- basic dashboard
- manual appointments
- basic health metrics

### Plus
Maximum 5 monitored seniors.

Includes:
- everything in Free
- AI Care Insights
- AI Appointment Prep
- premium health explanations

### Pro
Maximum 25 monitored seniors.

Includes:
- everything in Plus
- larger family care networks

### Organization — Future

Designed for organizations monitoring hundreds of seniors.

Organization functionality is NOT part of the hackathon build.

Architecture may support future:
- organizations
- admins
- caregivers
- configurable senior limits

Do not build organization UI.

## RevenueCat

RevenueCat integration must be real.

Use Test Store during development.

Entitlements:

plus_plan
pro_plan
premium_insights

Plus and Pro provide premium AI.

Do not build a custom paywall if RevenueCatUI can provide it.

Core safety functionality must never require premium.

## Data Model

Architect for:

CareAccount
AccountMember
AccountSenior

CareAccount may eventually be:

family
organization

Although the hackathon UI shows only Maya, domain models must support
multiple seniors.

Suggested entities:

profiles
care_accounts
account_members
account_seniors
check_ins
mood_entries
medications
medication_events
health_snapshots
appointments
alerts
care_insights
appointment_ai_preps

## Hackathon Scope

P0:
- compiling app
- Demo Mode
- onboarding
- Senior Home
- check-in
- mood
- Family Dashboard
- shared state
- SOS

P1:
- RevenueCat
- premium entitlement
- AI Care Insight
- appointment management
- AI Appointment Prep

P2:
- visual polish
- animations
- haptics
- accessibility
- demo reset
- reliability

P3:
- Supabase
- Realtime
- live AI backend
- Swift Charts

P3 must never delay P0-P2.

## Explicitly Out Of Scope

Do NOT implement during TXST build:

- HealthKit
- Apple Watch
- fall detection
- ECG
- blood oxygen
- real SMS
- voice messaging
- complex messaging
- push-notification infrastructure
- Android
- machine-learning anomaly detection
- organization dashboard
- production enterprise billing
- full multi-senior management UI

## Engineering Rules

After every meaningful phase:

1. Build.
2. Fix build failures.
3. Run tests.
4. Fix failing tests.
5. Update docs/STATUS.md.
6. Commit the stable checkpoint.

Do not knowingly proceed from a broken build.

Do not leave critical-path TODOs.

Never commit secrets.

Prefer simple deterministic implementations over unnecessary
abstractions.

## Autonomous Operation

You are expected to own implementation.

Do not ask the human routine programming questions.

Make reasonable technical decisions yourself.

Only stop for the human when:
- credentials are required
- external account authentication is required
- signing requires manual interaction
- an irreversible external action requires approval
- product requirements are genuinely contradictory

If an integration is blocked, continue unrelated work.

## Definition of Done

Before claiming completion:

- clean build succeeds
- tests succeed
- Demo Mode works offline
- demo reset works
- RevenueCat paywall works
- Test Store premium unlock works
- AI deterministic fallback works
- primary screens look production quality
- no debug UI is accidentally visible
- complete 90-second demo succeeds three consecutive times

After reaching feature completeness:

DO NOT ADD FEATURES.

Perform QA and polish instead.