# CareCompanion Complete Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete Claude v2-inspired Maya/Diwas native SwiftUI demo with offline deterministic care state, AI text, paywall seam, SOS, and family dashboard.

**Architecture:** `CareCore` owns deterministic domain state, AI text, access policy, and demo scenarios. SwiftUI views consume `@Observable AppState` plus small local navigation enums; feature views are split by screen and composed by `RootView`. RevenueCat remains behind a paywall seam so the UI can be completed without credentials while preserving the real integration point.

**Tech Stack:** Swift 6, SwiftUI, Observation, iOS 17+, XCTest, local `CareCore` Swift package, Xcode simulator build.

**Spec:** `docs/superpowers/specs/2026-09-14-carecompanion-complete-demo-design.md`

## Global Constraints

- Use the CareCompanion v2 Claude Design prototype as the main visual reference.
- Native iOS only: Swift, SwiftUI, iOS 17+, NavigationStack, async/await, XCTest.
- Do not introduce React, React Native, Node backend, Python backend, custom REST server, Android, HealthKit, or real messaging.
- Demo UI shows only Maya Sharma and Diwas.
- Demo data must remain deterministic and offline.
- Never claim demo health data came from HealthKit.
- SOS must not imply emergency services, real push notifications, SMS, or guaranteed assistance.
- AI must not diagnose, prescribe, estimate disease probability, or infer emergencies from passive health data.
- Check-in, mood, medicines, manual appointments, health metrics, and SOS remain free.
- Premium unlock gates full AI Care Insight and Appointment Prep.
- Views must not call RevenueCat, Supabase, or AI APIs directly.

---

## File Structure

Create or modify these files:

- `Sources/CareCore/AppNavigation.swift`: care app screen enums, paywall context, toast model.
- `Sources/CareCore/AIService.swift`: `AIService`, `CareInsight`, `AppointmentPrep`, and deterministic `MockAIService`.
- `Sources/CareCore/DemoCareRepository.swift`: refined demo medicine names and appointment details that match the Claude v2 design.
- `Sources/CareCore/AppState.swift`: app navigation state, toast state, premium preview helpers, appointment prep state, medicine toggling, and demo-safe call/message affordances.
- `Sources/CareCore/DemoScenarioController.swift`: scenario application aligned with the new screen flow.
- `Tests/CareCoreTests/CareCoreTests.swift`: extend existing tests for AI safety, medicine toggles, app screen reset, and SOS state.
- `App/CareCompanionApp.swift`: replace `FoundationView` with `RootView`.
- `App/DesignSystem.swift`: expand tokens/components for Claude v2.
- `App/Features/RootView.swift`: onboarding vs senior shell vs family shell routing.
- `App/Features/OnboardingView.swift`: role selection.
- `App/Features/Senior/SeniorShellView.swift`: senior container and floating tab bar.
- `App/Features/Senior/SeniorHomeView.swift`: home, check-in, medicines summary, appointment summary.
- `App/Features/Senior/CheckInMoodViews.swift`: check-in confirmation and mood selection.
- `App/Features/Senior/SOSViews.swift`: countdown and confirmation.
- `App/Features/Senior/MedicinesView.swift`: full medicine list.
- `App/Features/Shared/AppointmentsView.swift`: shared visits screen with family AI prep controls.
- `App/Features/Family/FamilyShellView.swift`: family container and floating tab bar.
- `App/Features/Family/FamilyDashboardView.swift`: Diwas dashboard.
- `App/Features/Family/HealthTimelineView.swift`: deterministic charts/cards.
- `App/Features/Family/AlertsView.swift`: alert center and emergency acknowledgement.
- `App/Features/Family/ProfileView.swift`: lightweight profile tab.
- `App/Features/Premium/PaywallView.swift`: polished fallback paywall and RevenueCat integration seam.
- `App/Features/Developer/DemoMenuView.swift`: hidden reset/scenario controls.
- `docs/STATUS.md`: update after implementation/build results.

---

### Task 1: Core Navigation, AI, And Demo State

**Files:**
- Create: `Sources/CareCore/AppNavigation.swift`
- Create: `Sources/CareCore/AIService.swift`
- Modify: `Sources/CareCore/AppState.swift`
- Modify: `Sources/CareCore/DemoCareRepository.swift`
- Modify: `Sources/CareCore/DemoScenarioController.swift`
- Modify: `Tests/CareCoreTests/CareCoreTests.swift`

**Interfaces:**
- Consumes: existing `AppState`, `DemoCareRepository`, `CareSnapshot`, `Appointment`, `SubscriptionAccess`.
- Produces:
  - `public enum AppScreen: String, Codable, Sendable`
  - `public enum SeniorTab: String, CaseIterable, Codable, Sendable`
  - `public enum FamilyTab: String, CaseIterable, Codable, Sendable`
  - `public enum PaywallContext: String, Codable, Sendable`
  - `public struct CareInsight: Equatable, Sendable`
  - `public struct AppointmentPrep: Equatable, Sendable`
  - `@MainActor public protocol AIService`
  - `@MainActor public final class MockAIService`
  - `AppState.screen`, `seniorTab`, `familyTab`, `paywallContext`, `toastMessage`, `appointmentPrep`
  - `AppState.toggleMedication(id:)`, `showPaywall(for:)`, `unlockPremiumPreview()`, `prepareAppointment(using:)`

- [ ] **Step 1: Add failing tests for AI and navigation state**

Add these tests to `Tests/CareCoreTests/CareCoreTests.swift`:

```swift
func testMockAIIsDeterministicAndSafe() async {
    await MainActor.run {
        let state = AppState(repository: DemoCareRepository())
        let service = MockAIService()
        let insight = service.careInsight(for: state.snapshot, seniorID: state.selectedSeniorID)
        XCTAssertTrue(insight.teaser.contains("2,840"))
        XCTAssertTrue(insight.full.contains("consider checking in") || insight.full.contains("call today"))
        let unsafe = ["diagnosis", "prescribe", "probability", "emergency services"]
        XCTAssertFalse(unsafe.contains { insight.full.localizedCaseInsensitiveContains($0) })
    }
}

func testNavigationAndPreviewReset() async {
    await MainActor.run {
        let state = AppState(repository: DemoCareRepository())
        state.role = .family
        state.screen = .paywall
        state.familyTab = .alerts
        state.showPaywall(for: .appointmentPrep)
        state.unlockPremiumPreview()
        XCTAssertTrue(state.isPremiumPreview)
        state.resetDemo()
        XCTAssertNil(state.role)
        XCTAssertEqual(state.screen, .onboarding)
        XCTAssertEqual(state.familyTab, .home)
        XCTAssertNil(state.paywallContext)
        XCTAssertFalse(state.isPremiumPreview)
    }
}

func testMedicationToggleUpdatesAdherence() async {
    await MainActor.run {
        let state = AppState(repository: DemoCareRepository())
        let evening = state.snapshot.medications.first { $0.name == "Atorvastatin" }
        XCTAssertNotNil(evening)
        XCTAssertEqual(state.snapshot.medications.filter(\.taken).count, 3)
        state.toggleMedication(id: evening!.id)
        XCTAssertEqual(state.snapshot.medications.filter(\.taken).count, 4)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test
```

Expected: FAIL because `MockAIService`, `AppScreen`, navigation properties, and `toggleMedication(id:)` do not exist.

- [ ] **Step 3: Add navigation types**

Create `Sources/CareCore/AppNavigation.swift`:

```swift
import Foundation

public enum AppScreen: String, Codable, Sendable {
    case onboarding, home, checkInConfirmation, mood, medicines, visits, health, alerts, paywall, profile, sosCountdown, sosConfirmation
}

public enum SeniorTab: String, CaseIterable, Codable, Sendable {
    case home, medicines, visits
}

public enum FamilyTab: String, CaseIterable, Codable, Sendable {
    case home, health, alerts, visits, profile
}

public enum PaywallContext: String, Codable, Sendable {
    case careInsight, appointmentPrep
}
```

- [ ] **Step 4: Add deterministic AI service**

Create `Sources/CareCore/AIService.swift`:

```swift
import Foundation

public struct CareInsight: Equatable, Sendable {
    public let teaser: String
    public let full: String
    public init(teaser: String, full: String) {
        self.teaser = teaser
        self.full = full
    }
}

public struct AppointmentPrep: Equatable, Sendable {
    public let observations: [String]
    public let questions: [String]
    public init(observations: [String], questions: [String]) {
        self.observations = observations
        self.questions = questions
    }
}

@MainActor public protocol AIService {
    func careInsight(for snapshot: CareSnapshot, seniorID: String) -> CareInsight
    func appointmentPrep(for snapshot: CareSnapshot, appointmentID: String) -> AppointmentPrep
}

@MainActor public final class MockAIService: AIService {
    public init() {}

    public func careInsight(for snapshot: CareSnapshot, seniorID: String) -> CareInsight {
        let health = snapshot.health.first { $0.seniorID == seniorID }
        let medsTaken = snapshot.medications.filter { $0.seniorID == seniorID && $0.taken }.count
        let medsTotal = snapshot.medications.filter { $0.seniorID == seniorID }.count
        let steps = health?.steps ?? 0
        let sleepMinutes = health?.sleepMinutes ?? 0
        let sleep = "\(sleepMinutes / 60)h \(sleepMinutes % 60)m"
        return CareInsight(
            teaser: "Maya logged \(steps.formatted()) steps today and \(medsTaken) of \(medsTotal) medicines are marked as taken. Her mood today is Okay...",
            full: "Maya logged \(steps.formatted()) steps today, below her usual weekly rhythm, slept \(sleep), and has \(medsTaken) of \(medsTotal) medicines marked as taken. Her mood has held steady at Okay. Nothing here diagnoses a problem, but it is worth a warm call today and a note for the next appointment."
        )
    }

    public func appointmentPrep(for snapshot: CareSnapshot, appointmentID: String) -> AppointmentPrep {
        AppointmentPrep(
            observations: [
                "Sleep is lower than her recent average, with 6h 20m last night.",
                "Resting heart rate is 72 bpm, within the recent 67-74 bpm demo range.",
                "One evening medicine is still unmarked today."
            ],
            questions: [
                "Has Maya mentioned dizziness, fatigue, or changes in routine?",
                "Would moving the evening reminder earlier make the dose easier to remember?",
                "Are the recent sleep changes worth discussing at this visit?"
            ]
        )
    }
}
```

- [ ] **Step 5: Extend repository medication support**

Modify `CareRepository` and `DemoCareRepository`:

```swift
@MainActor public protocol CareRepository: AnyObject {
    var snapshot: CareSnapshot { get }
    func checkIn(seniorID: String, at date: Date)
    func recordMood(_ mood: Mood, seniorID: String, at date: Date)
    func triggerSOS(seniorID: String, at date: Date)
    func acknowledgeAlerts(seniorID: String)
    func toggleMedication(id: String)
    func reset()
}
```

Seed medicines in `DemoCareRepository.init`:

```swift
medications: [
    Medication(id: "med-amlodipine", seniorID: senior, name: "Amlodipine", scheduledTime: "8:00 AM", taken: true),
    Medication(id: "med-metformin", seniorID: senior, name: "Metformin", scheduledTime: "8:30 AM", taken: true),
    Medication(id: "med-calcium", seniorID: senior, name: "Calcium + D3", scheduledTime: "1:00 PM", taken: true),
    Medication(id: "med-atorvastatin", seniorID: senior, name: "Atorvastatin", scheduledTime: "8:00 PM", taken: false)
],
```

Add implementation:

```swift
public func toggleMedication(id: String) {
    guard let index = snapshot.medications.firstIndex(where: { $0.id == id }) else { return }
    snapshot.medications[index].taken.toggle()
}
```

- [ ] **Step 6: Extend `AppState`**

Add properties and methods to `Sources/CareCore/AppState.swift`:

```swift
public var screen: AppScreen = .onboarding
public var seniorTab: SeniorTab = .home
public var familyTab: FamilyTab = .home
public var paywallContext: PaywallContext?
public var toastMessage: String?
public private(set) var appointmentPrep: AppointmentPrep?
```

Add methods:

```swift
public var hasPremiumAccess: Bool { subscription.canUsePremiumAI || isPremiumPreview }

public func toggleMedication(id: String) {
    repository.toggleMedication(id: id)
    snapshot = repository.snapshot
}

public func showPaywall(for context: PaywallContext) {
    paywallContext = context
    screen = .paywall
}

public func unlockPremiumPreview() {
    isPremiumPreview = true
}

public func prepareAppointment(using service: any AIService) {
    guard let appointment = snapshot.appointments.first(where: { $0.seniorID == selectedSeniorID }) else { return }
    appointmentPrep = service.appointmentPrep(for: snapshot, appointmentID: appointment.id)
    isAppointmentPreparedPreview = true
}

public func showDemoToast(_ message: String) {
    toastMessage = message
}

public func clearToast() {
    toastMessage = nil
}
```

In `resetDemo()`, reset navigation:

```swift
screen = .onboarding
seniorTab = .home
familyTab = .home
paywallContext = nil
toastMessage = nil
appointmentPrep = nil
```

- [ ] **Step 7: Update scenarios**

Modify `DemoScenarioController.apply(_:)` so `.checkedIn` ends on senior home, `.moodRecorded` ends on senior home, `.premiumUnlocked` ends on family home, `.appointmentPrepared` includes deterministic appointment prep preview flag, and `.sosTriggered` ends with family alert state:

```swift
state.screen = .home
state.seniorTab = .home
state.familyTab = .home
```

Keep preview flags separate from real `subscription`.

- [ ] **Step 8: Run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add CareCompanion/Sources/CareCore CareCompanion/Tests/CareCoreTests
git commit -m "Add demo navigation and deterministic AI core"
```

---

### Task 2: Claude v2 Design System

**Files:**
- Modify: `App/DesignSystem.swift`

**Interfaces:**
- Consumes: SwiftUI.
- Produces reusable components:
  - `CareTheme`
  - `CareScreen`
  - `CareDisplayTitle`
  - `CareCard`
  - `CarePrimaryButton`
  - `CareSecondaryButton`
  - `CareMetricTile`
  - `CareDateBadge`
  - `CareStatusChip`
  - `CareBottomNav`
  - `CareToast`
  - `CareMiniBarChart`

- [ ] **Step 1: Replace basic tokens with Claude v2 tokens**

Update `CareTheme` in `App/DesignSystem.swift`:

```swift
enum CareTheme {
    static let background = Color(red: 251/255, green: 249/255, blue: 244/255)
    static let cream = Color(red: 243/255, green: 241/255, blue: 232/255)
    static let softCream = Color(red: 249/255, green: 247/255, blue: 240/255)
    static let ink = Color(red: 31/255, green: 35/255, blue: 32/255)
    static let secondaryText = Color(red: 90/255, green: 95/255, blue: 88/255)
    static let mutedText = Color(red: 138/255, green: 142/255, blue: 134/255)
    static let sage = Color(red: 79/255, green: 122/255, blue: 91/255)
    static let darkSage = Color(red: 63/255, green: 107/255, blue: 76/255)
    static let coral = Color(red: 201/255, green: 84/255, blue: 58/255)
    static let amber = Color(red: 138/255, green: 97/255, blue: 25/255)
    static let blue = Color(red: 47/255, green: 107/255, blue: 143/255)
    static let cardStroke = Color.black.opacity(0.10)
    static let cardRadius: CGFloat = 22
}
```

- [ ] **Step 2: Add display title and screen wrappers**

Add:

```swift
struct CareDisplayTitle: View {
    let text: String
    var size: CGFloat = 34
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .lineSpacing(1)
            .foregroundStyle(CareTheme.ink)
    }
}

struct CareScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 20)
                .padding(.top, 54)
                .padding(.bottom, 128)
        }
        .background(CareTheme.background.ignoresSafeArea())
    }
}
```

- [ ] **Step 3: Add reusable cards and buttons**

Add:

```swift
struct CarePrimaryButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

struct CareSecondaryButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content
                .font(.body.weight(.bold))
                .foregroundStyle(CareTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(CareTheme.cream, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
```

Replace existing `CareCard` with the v2 card:

```swift
struct CareCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: CareTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: CareTheme.cardRadius).stroke(CareTheme.cardStroke))
    }
}
```

- [ ] **Step 4: Add metric, date, status, nav, toast, and mini chart components**

Add compact components:

```swift
struct CareMetricTile: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(CareTheme.mutedText)
            Text(value).font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(CareTheme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
    }
}

struct CareDateBadge: View {
    let day: String
    let number: String
    var tint = CareTheme.cream
    var body: some View {
        VStack(spacing: 2) {
            Text(day.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(CareTheme.darkSage)
            Text(number).font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(CareTheme.ink)
        }
        .frame(width: 54, height: 54)
        .background(tint, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CareStatusChip: View {
    let text: String
    let background: Color
    let foreground: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(background, in: Capsule())
    }
}
```

Add `CareBottomNav` with generic items:

```swift
struct CareNavItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let badge: Int
    let action: () -> Void
}

struct CareBottomNav: View {
    let selected: String
    let items: [CareNavItem]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button(action: item.action) {
                    VStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.systemImage).font(.system(size: 20, weight: .semibold))
                            if item.badge > 0 {
                                Text("\(item.badge)")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(CareTheme.coral, in: Capsule())
                                    .offset(x: 9, y: -6)
                            }
                        }
                        Text(item.title).font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(item.id == selected ? CareTheme.darkSage : CareTheme.mutedText)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(CareTheme.cardStroke))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }
}
```

Add mini chart:

```swift
struct CareMiniBarChart: View {
    let values: [Double]
    let tint: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 5)
                    .fill(index == values.indices.last ? tint : tint.opacity(0.25))
                    .frame(height: max(14, 76 * value))
            }
        }
        .frame(height: 76)
    }
}
```

- [ ] **Step 5: Build to catch SwiftUI syntax errors**

Run:

```bash
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add CareCompanion/App/DesignSystem.swift
git commit -m "Refine CareCompanion design system"
```

---

### Task 3: Root View, Onboarding, Shells, And Demo Menu

**Files:**
- Modify: `App/CareCompanionApp.swift`
- Create: `App/Features/RootView.swift`
- Create: `App/Features/OnboardingView.swift`
- Create: `App/Features/Senior/SeniorShellView.swift`
- Create: `App/Features/Family/FamilyShellView.swift`
- Create: `App/Features/Developer/DemoMenuView.swift`
- Create: `App/Features/PlaceholderViews.swift`

**Interfaces:**
- Consumes: `AppState.role`, `AppState.screen`, `SeniorTab`, `FamilyTab`, design system components.
- Produces: App launch routing and floating tab shell containers.

- [ ] **Step 1: Replace launch surface**

Modify `App/CareCompanionApp.swift`:

```swift
import SwiftUI
import CareCore

@main
struct CareCompanionApp: App {
    @State private var state = AppState(repository: DemoCareRepository())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.light)
        }
    }
}
```

- [ ] **Step 2: Create `RootView`**

Create `App/Features/RootView.swift`:

```swift
import SwiftUI
import CareCore

struct RootView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack {
            switch state.screen {
            case .onboarding:
                OnboardingView()
            case .sosCountdown:
                SOSCountdownView()
            case .sosConfirmation:
                SOSConfirmationView()
            default:
                if state.role == .family {
                    FamilyShellView()
                } else {
                    SeniorShellView()
                }
            }
        }
        .background(CareTheme.background)
    }
}
```

- [ ] **Step 3: Create onboarding**

Create `App/Features/OnboardingView.swift`:

```swift
import SwiftUI
import CareCore

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "heart").foregroundStyle(CareTheme.sage)
                Text("CareCompanion")
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(CareTheme.secondaryText)
            }
            .padding(.top, 72)
            .padding(.bottom, 52)

            CareDisplayTitle(text: "Care that travels across time zones.", size: 46)
            Text("CareCompanion connects elders at home with the family looking after them from far away.")
                .font(.body)
                .foregroundStyle(CareTheme.secondaryText)
                .lineSpacing(4)
                .padding(.top, 18)
                .frame(maxWidth: 310, alignment: .leading)

            Spacer(minLength: 24)
            roleDivider
            roleButton(title: "I am a senior", subtitle: "Simple screens, big buttons", image: "leaf.fill", isPrimary: true) {
                state.role = .senior
                state.screen = .home
                state.seniorTab = .home
            }
            .padding(.bottom, 12)
            roleButton(title: "I am a family member", subtitle: "Dashboard, health data and alerts", image: "person.2", isPrimary: false) {
                state.role = .family
                state.screen = .home
                state.familyTab = .home
            }
            Text("You can switch roles in the demo menu.")
                .font(.caption)
                .foregroundStyle(CareTheme.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [CareTheme.background, CareTheme.cream], startPoint: .top, endPoint: .bottom))
    }

    private var roleDivider: some View {
        HStack {
            Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
            Text("CHOOSE YOUR VIEW").font(.caption2).tracking(1).foregroundStyle(CareTheme.secondaryText)
            Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
        }
        .padding(.bottom, 14)
    }

    private func roleButton(title: String, subtitle: String, image: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: image).font(.title2.weight(.semibold)).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 24, weight: .regular, design: .serif))
                    Text(subtitle).font(.caption).opacity(0.82)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.body.weight(.bold))
            }
            .foregroundStyle(isPrimary ? .white : CareTheme.ink)
            .padding(22)
            .background(isPrimary ? CareTheme.sage : .white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(isPrimary ? .clear : CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Create senior shell**

Create `App/Features/Senior/SeniorShellView.swift`:

```swift
import SwiftUI
import CareCore

struct SeniorShellView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch state.screen {
                case .checkInConfirmation:
                    CheckInConfirmationView()
                case .mood:
                    MoodSelectionView()
                case .medicines:
                    MedicinesView()
                case .visits:
                    AppointmentsView()
                case .paywall:
                    PaywallView()
                default:
                    SeniorHomeView()
                }
            }
            if shouldShowNav {
                CareBottomNav(selected: state.seniorTab.rawValue, items: seniorItems)
            }
        }
        .overlay(alignment: .topTrailing) { DemoMenuView().padding(.top, 8).padding(.trailing, 8) }
    }

    private var shouldShowNav: Bool {
        ![AppScreen.checkInConfirmation, .mood, .paywall].contains(state.screen)
    }

    private var seniorItems: [CareNavItem] {
        [
            CareNavItem(id: SeniorTab.home.rawValue, title: "Home", systemImage: "house", badge: 0) { state.seniorTab = .home; state.screen = .home },
            CareNavItem(id: SeniorTab.medicines.rawValue, title: "Medicines", systemImage: "pills", badge: 0) { state.seniorTab = .medicines; state.screen = .medicines },
            CareNavItem(id: SeniorTab.visits.rawValue, title: "Visits", systemImage: "calendar", badge: 0) { state.seniorTab = .visits; state.screen = .visits }
        ]
    }
}
```

- [ ] **Step 5: Create family shell**

Create `App/Features/Family/FamilyShellView.swift`:

```swift
import SwiftUI
import CareCore

struct FamilyShellView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch state.screen {
                case .health:
                    HealthTimelineView()
                case .alerts:
                    AlertsView()
                case .visits:
                    AppointmentsView()
                case .paywall:
                    PaywallView()
                case .profile:
                    ProfileView()
                default:
                    FamilyDashboardView()
                }
            }
            CareBottomNav(selected: state.familyTab.rawValue, items: familyItems)
        }
        .overlay(alignment: .topTrailing) { DemoMenuView().padding(.top, 8).padding(.trailing, 8) }
    }

    private var alertBadge: Int {
        state.hasEmergency ? 1 : max(1, state.snapshot.medications.contains { !$0.taken } ? 1 : 0)
    }

    private var familyItems: [CareNavItem] {
        [
            CareNavItem(id: FamilyTab.home.rawValue, title: "Home", systemImage: "house", badge: 0) { state.familyTab = .home; state.screen = .home },
            CareNavItem(id: FamilyTab.health.rawValue, title: "Health", systemImage: "heart", badge: 0) { state.familyTab = .health; state.screen = .health },
            CareNavItem(id: FamilyTab.alerts.rawValue, title: "Alerts", systemImage: "bell", badge: alertBadge) { state.familyTab = .alerts; state.screen = .alerts },
            CareNavItem(id: FamilyTab.visits.rawValue, title: "Visits", systemImage: "calendar", badge: 0) { state.familyTab = .visits; state.screen = .visits },
            CareNavItem(id: FamilyTab.profile.rawValue, title: "Profile", systemImage: "person", badge: 0) { state.familyTab = .profile; state.screen = .profile }
        ]
    }
}
```

- [ ] **Step 6: Create hidden demo menu**

Create `App/Features/Developer/DemoMenuView.swift`:

```swift
import SwiftUI
import CareCore

struct DemoMenuView: View {
    @Environment(AppState.self) private var state
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "circle.grid.2x2")
                .font(.caption.weight(.bold))
                .foregroundStyle(CareTheme.mutedText.opacity(0.35))
                .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Demo controls")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List {
                    Button("Reset demo") { state.resetDemo(); isPresented = false }
                    Button("View as Maya") { state.role = .senior; state.screen = .home; state.seniorTab = .home; isPresented = false }
                    Button("View as Diwas") { state.role = .family; state.screen = .home; state.familyTab = .home; isPresented = false }
                    Section("Scenarios") {
                        ForEach(DemoScenario.allCases, id: \.rawValue) { scenario in
                            Button(scenario.rawValue) {
                                DemoScenarioController(state: state).apply(scenario)
                                isPresented = false
                            }
                        }
                    }
                }
                .navigationTitle("Demo")
            }
            .presentationDetents([.medium])
        }
    }
}
```

- [ ] **Step 7: Build**
- [ ] **Step 7: Create placeholder feature views for this checkpoint**

Create `App/Features/PlaceholderViews.swift` so the shells compile before feature screens are expanded:

```swift
import SwiftUI

struct SeniorHomeView: View { var body: some View { CareScreen { Text("Senior Home") } } }
struct CheckInConfirmationView: View { var body: some View { CareScreen { Text("Check-in") } } }
struct MoodSelectionView: View { var body: some View { CareScreen { Text("Mood") } } }
struct MedicinesView: View { var body: some View { CareScreen { Text("Medicines") } } }
struct SOSCountdownView: View { var body: some View { Text("SOS").frame(maxWidth: .infinity, maxHeight: .infinity).background(CareTheme.coral).foregroundStyle(.white) } }
struct SOSConfirmationView: View { var body: some View { Text("SOS Sent").frame(maxWidth: .infinity, maxHeight: .infinity).background(CareTheme.sage).foregroundStyle(.white) } }
struct FamilyDashboardView: View { var body: some View { CareScreen { Text("Family Dashboard") } } }
struct HealthTimelineView: View { var body: some View { CareScreen { Text("Health") } } }
struct AlertsView: View { var body: some View { CareScreen { Text("Alerts") } } }
struct ProfileView: View { var body: some View { CareScreen { Text("Profile") } } }
struct AppointmentsView: View { var body: some View { CareScreen { Text("Appointments") } } }
struct PaywallView: View { var body: some View { CareScreen { Text("Paywall") } } }
```

- [ ] **Step 8: Build**

Run:

```bash
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Commit**

```bash
git add CareCompanion/App CareCompanion/Sources/CareCore
git commit -m "Add app routing and demo shells"
```

---

### Task 4: Senior Flow And Medicines

**Files:**
- Create: `App/Features/Senior/SeniorHomeView.swift`
- Create: `App/Features/Senior/CheckInMoodViews.swift`
- Create: `App/Features/Senior/MedicinesView.swift`
- Modify: `App/Features/PlaceholderViews.swift`

**Interfaces:**
- Consumes: `AppState.checkIn()`, `recordMood(_:)`, `toggleMedication(id:)`, `snapshot.medications`, `snapshot.appointments`.
- Produces: complete senior home, check-in confirmation, mood selection, medicines screen.

- [ ] **Step 1: Create senior home helpers**

Remove these placeholder structs from `App/Features/PlaceholderViews.swift` before creating real senior files:

```swift
struct SeniorHomeView
struct CheckInConfirmationView
struct MoodSelectionView
struct MedicinesView
```

Create `App/Features/Senior/SeniorHomeView.swift` with this structure:

```swift
import SwiftUI
import CareCore

struct SeniorHomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        CareScreen {
            header
            Text("Monday, 14 September")
                .font(.subheadline)
                .foregroundStyle(CareTheme.mutedText)
                .padding(.top, 26)
            CareDisplayTitle(text: "Good morning,\nMaya", size: 40)
                .padding(.bottom, 26)
            if state.isCheckedIn {
                checkedInCard
            } else {
                okayButton
            }
            medicinesSummary
            nextVisitCard
        }
    }
}
```

- [ ] **Step 2: Add senior header and check-in controls**

Add inside `SeniorHomeView`:

```swift
private extension SeniorHomeView {
    var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "heart").foregroundStyle(CareTheme.sage)
                Text("CareCompanion").font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(CareTheme.secondaryText)
            }
            Spacer()
            Button {
                state.screen = .sosCountdown
            } label: {
                Label("SOS", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color(red: 168/255, green: 62/255, blue: 38/255))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 248/255, green: 226/255, blue: 218/255), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start SOS countdown")
        }
    }

    var okayButton: some View {
        Button {
            state.checkIn()
            state.screen = .checkInConfirmation
        } label: {
            VStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.white.opacity(0.18), in: Circle())
                Text("I'm okay").font(.system(size: 32, weight: .regular, design: .serif))
                Text("Tap to tell your family").font(.subheadline).opacity(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }

    var checkedInCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(CareTheme.sage, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Checked in just now").font(.system(size: 23, weight: .regular, design: .serif))
                Text("Feeling \(moodLabel) · Diwas can see this").font(.subheadline).foregroundStyle(CareTheme.secondaryText)
            }
            Spacer()
            Text(moodEmoji).font(.title)
        }
        .padding(22)
        .background(Color(red: 239/255, green: 244/255, blue: 238/255), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(CareTheme.sage.opacity(0.22)))
    }
}
```

- [ ] **Step 3: Add medicines and next visit cards**

Add:

```swift
private extension SeniorHomeView {
    var medicinesSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                CareDisplayTitle(text: "Today's medicines", size: 26)
                Spacer()
                Text("\(takenCount) of \(state.snapshot.medications.count)")
                    .font(.caption)
                    .foregroundStyle(CareTheme.secondaryText)
            }
            ForEach(state.snapshot.medications) { med in
                MedicineRow(medication: med) { state.toggleMedication(id: med.id) }
            }
            CareSecondaryButton(action: { state.screen = .medicines; state.seniorTab = .medicines }) {
                Text("See medicine reminder")
            }
        }
        .padding(.top, 28)
    }

    var nextVisitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CareDisplayTitle(text: "Next visit", size: 26)
            CareCard {
                HStack(alignment: .top, spacing: 16) {
                    CareDateBadge(day: "Fri", number: "4", tint: CareTheme.cream)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dr. Rana — Routine check-up").font(.headline)
                        Text("10:30 AM · Kathmandu clinic").font(.subheadline).foregroundStyle(CareTheme.secondaryText)
                    }
                }
            }
        }
        .padding(.top, 28)
    }

    var takenCount: Int { state.snapshot.medications.filter(\.taken).count }
    var moodLabel: String { state.currentMood?.rawValue ?? "Okay" }
    var moodEmoji: String {
        switch state.currentMood ?? .okay {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        }
    }
}
```

- [ ] **Step 4: Create reusable medicine row**

Add in `SeniorHomeView.swift`:

```swift
struct MedicineRow: View {
    let medication: Medication
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(medication.taken ? CareTheme.sage : .white)
                        .overlay(Circle().stroke(medication.taken ? CareTheme.sage : Color.black.opacity(0.22), lineWidth: 1.5))
                    if medication.taken {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(medication.name).font(.body.weight(.semibold)).foregroundStyle(CareTheme.ink)
                    Text("\(doseText(for: medication.name)) · \(medication.scheduledTime)")
                        .font(.subheadline)
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
            }
            .padding(18)
            .background(medication.taken ? Color(red: 247/255, green: 249/255, blue: 246/255) : .white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(medication.taken ? CareTheme.sage.opacity(0.22) : CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
    }

    private func doseText(for name: String) -> String {
        switch name {
        case "Amlodipine": "5 mg — 1 tablet"
        case "Metformin": "500 mg — 1 tablet"
        case "Atorvastatin": "10 mg — 1 tablet"
        default: "1 tablet"
        }
    }
}
```

- [ ] **Step 5: Create check-in and mood screens**

Create `App/Features/Senior/CheckInMoodViews.swift`:

```swift
import SwiftUI
import CareCore

struct CheckInConfirmationView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)
            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(CareTheme.sage)
                .frame(width: 94, height: 94)
                .background(Color(red: 239/255, green: 244/255, blue: 238/255), in: Circle())
                .overlay(Circle().stroke(CareTheme.sage.opacity(0.25)))
            CareDisplayTitle(text: "You're marked as okay", size: 34)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text("Diwas will see this on his dashboard right away.")
                .font(.body)
                .foregroundStyle(CareTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
                .frame(maxWidth: 280)
            Spacer()
            CarePrimaryButton(action: { state.screen = .mood }) { Text("Continue") }
        }
        .padding(26)
        .background(CareTheme.background.ignoresSafeArea())
    }
}

struct MoodSelectionView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        CareScreen {
            CareDisplayTitle(text: "How are you feeling today?", size: 38)
                .padding(.top, 40)
            Text("Tap one face.")
                .font(.body)
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 10)
                .padding(.bottom, 30)
            moodButton("😊", "Good", .great)
            moodButton("😐", "Okay", .okay)
            moodButton("😔", "Not great", .low)
        }
    }

    private func moodButton(_ emoji: String, _ title: String, _ mood: Mood) -> some View {
        Button {
            state.recordMood(mood)
            state.screen = .home
            state.seniorTab = .home
        } label: {
            HStack(spacing: 18) {
                Text(emoji).font(.system(size: 40))
                Text(title).font(.system(size: 28, weight: .regular, design: .serif))
                Spacer()
            }
            .padding(24)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 6: Create medicines screen**

Create `App/Features/Senior/MedicinesView.swift`:

```swift
import SwiftUI
import CareCore

struct MedicinesView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        CareScreen {
            CareDisplayTitle(text: "Medicines", size: 34)
            Text("\(state.snapshot.medications.filter(\.taken).count) of \(state.snapshot.medications.count) taken today · tap a row to change")
                .font(.subheadline)
                .foregroundStyle(CareTheme.mutedText)
                .padding(.top, 6)
                .padding(.bottom, 24)
            ForEach(state.snapshot.medications) { med in
                MedicineRow(medication: med) { state.toggleMedication(id: med.id) }
            }
        }
    }
}
```

- [ ] **Step 7: Build**

Run:

```bash
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: BUILD SUCCEEDED. The remaining checkpoint placeholder views from Task 3 keep the app compiling until their real screens are created.

- [ ] **Step 8: Commit**

```bash
git add CareCompanion/App/Features/Senior
git commit -m "Build senior check-in and medicines flow"
```

---

### Task 5: SOS Countdown And Demo-Safe Emergency State

**Files:**
- Create: `App/Features/Senior/SOSViews.swift`
- Modify: `App/Features/PlaceholderViews.swift`
- Modify: `Tests/CareCoreTests/CareCoreTests.swift`

**Interfaces:**
- Consumes: `AppState.triggerSOS()`, `AppState.screen`, `AppState.hasEmergency`.
- Produces: cancellable five-second countdown and confirmation screen.

- [ ] **Step 1: Add focused SOS reset test**

Add:

```swift
func testResetClearsEmergencyAndScreen() async {
    await MainActor.run {
        let state = AppState(repository: DemoCareRepository())
        state.role = .senior
        state.screen = .sosCountdown
        state.triggerSOS()
        XCTAssertTrue(state.hasEmergency)
        state.resetDemo()
        XCTAssertFalse(state.hasEmergency)
        XCTAssertEqual(state.screen, .onboarding)
    }
}
```

- [ ] **Step 2: Run tests**

Run:

```bash
swift test
```

Expected: PASS if Task 1 was completed; otherwise FAIL on `screen`.

- [ ] **Step 3: Create SOS countdown**

Remove these placeholder structs from `App/Features/PlaceholderViews.swift` before creating the real SOS file:

```swift
struct SOSCountdownView
struct SOSConfirmationView
```

Create `App/Features/Senior/SOSViews.swift`:

```swift
import SwiftUI
import CareCore

struct SOSCountdownView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var count = 5
    @State private var didComplete = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 88)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(.white.opacity(0.18), in: Circle())
                .scaleEffect(reduceMotion ? 1 : 1.02)
            Text("Sending alert to your family")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text("Stay calm. Tap cancel if you are okay.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Spacer()
            Text("\(count)")
                .font(.system(size: 132, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            Button {
                state.screen = .home
            } label: {
                Text("Cancel")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 168/255, green: 62/255, blue: 38/255))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 34)
        .background(CareTheme.coral.ignoresSafeArea())
        .task {
            count = 5
            didComplete = false
            while count > 0 && state.screen == .sosCountdown {
                try? await Task.sleep(for: .seconds(1))
                guard state.screen == .sosCountdown else { return }
                count -= 1
            }
            guard state.screen == .sosCountdown, !didComplete else { return }
            didComplete = true
            state.triggerSOS()
            state.screen = .sosConfirmation
        }
    }
}
```

- [ ] **Step 4: Create SOS confirmation**

Add to `SOSViews.swift`:

```swift
struct SOSConfirmationView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 96)
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(.white.opacity(0.18), in: Circle())
            Text("Your alert was sent")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text("Diwas can see it on his demo dashboard in Austin. You can call him now.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 290)
                .padding(.top, 12)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    state.showDemoToast("This is a demo — no call is placed.")
                } label: {
                    Text("Call Diwas now")
                        .font(.body.weight(.bold))
                        .foregroundStyle(CareTheme.darkSage)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }
                Button {
                    state.screen = .home
                } label: {
                    Text("Back to home")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.45)))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 34)
        .background(CareTheme.sage.ignoresSafeArea())
    }
}
```

- [ ] **Step 5: Build and run core tests**

Run:

```bash
swift test
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: tests pass and app builds.

- [ ] **Step 6: Commit**

```bash
git add CareCompanion/App/Features/Senior/SOSViews.swift CareCompanion/Tests/CareCoreTests/CareCoreTests.swift
git commit -m "Add demo-safe SOS countdown"
```

---

### Task 6: Family Dashboard, Alerts, Health, And Profile

**Files:**
- Create: `App/Features/Family/FamilyDashboardView.swift`
- Create: `App/Features/Family/HealthTimelineView.swift`
- Create: `App/Features/Family/AlertsView.swift`
- Create: `App/Features/Family/ProfileView.swift`
- Modify: `App/Features/PlaceholderViews.swift`

**Interfaces:**
- Consumes: `AppState.snapshot`, `AppState.hasEmergency`, `MockAIService`, design components.
- Produces: complete Diwas family shell screens.

- [ ] **Step 1: Create family dashboard**

Remove these placeholder structs from `App/Features/PlaceholderViews.swift` before creating real family files:

```swift
struct FamilyDashboardView
struct HealthTimelineView
struct AlertsView
struct ProfileView
```

Create `App/Features/Family/FamilyDashboardView.swift`:

```swift
import SwiftUI
import CareCore

struct FamilyDashboardView: View {
    @Environment(AppState.self) private var state
    private let ai = MockAIService()

    var body: some View {
        CareScreen {
            header
            timeZoneCard
            if state.hasEmergency { sosBanner }
            mayaCard
            insightCard
            if missedEveningMedicine && !state.hasEmergency { missedMedicineBanner }
        }
    }
}
```

Add header/time cards:

```swift
private extension FamilyDashboardView {
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR FAMILY").font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(CareTheme.secondaryText)
                CareDisplayTitle(text: "Good evening,\nDiwas", size: 34)
            }
            Spacer()
            Text("D")
                .font(.system(size: 19, weight: .regular, design: .serif))
                .frame(width: 44, height: 44)
                .background(CareTheme.cream, in: Circle())
                .overlay(Circle().stroke(CareTheme.cardStroke))
        }
    }

    var timeZoneCard: some View {
        HStack(spacing: 0) {
            timeBlock(label: "AUSTIN · YOU", time: "9:41 PM", image: "moon")
            Rectangle().fill(CareTheme.cardStroke).frame(width: 1)
            timeBlock(label: "KATHMANDU · MAYA", time: "8:26 AM", image: "sun.max")
                .background(CareTheme.softCream)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CareTheme.cardStroke))
        .padding(.top, 18)
    }

    func timeBlock(label: String, time: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(CareTheme.mutedText)
            HStack(spacing: 7) {
                Text(time).font(.system(size: 21, weight: .regular, design: .serif))
                Image(systemName: image).font(.caption).foregroundStyle(CareTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
```

- [ ] **Step 2: Add Maya card and insight card**

Add:

```swift
private extension FamilyDashboardView {
    var mayaCard: some View {
        CareCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Text("MS")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(CareTheme.sage, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Maya Sharma").font(.system(size: 22, weight: .regular, design: .serif))
                        Text("Grandmother · Kathmandu, Nepal").font(.caption).foregroundStyle(CareTheme.mutedText)
                    }
                    Spacer()
                    CareStatusChip(text: statusText, background: statusBackground, foreground: statusForeground)
                }
                HStack(spacing: 10) {
                    Circle().fill(state.isCheckedIn ? CareTheme.sage : CareTheme.amber).frame(width: 8, height: 8)
                    Text(state.isCheckedIn ? "Checked in just now" : "Checked in 2 hours ago")
                    Spacer()
                    Text(moodEmoji)
                }
                .font(.subheadline)
                .padding(14)
                .background(CareTheme.softCream, in: RoundedRectangle(cornerRadius: 14))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                    CareMetricTile(label: "Medicines", value: "\(takenCount) of \(state.snapshot.medications.count)")
                    CareMetricTile(label: "Mood today", value: moodLabel)
                    CareMetricTile(label: "Steps", value: "2,840")
                    CareMetricTile(label: "Sleep", value: "6h 20m")
                    CareMetricTile(label: "Heart rate", value: "72 bpm")
                    CareMetricTile(label: "Source", value: "Demo")
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 14)
    }

    var insightCard: some View {
        let insight = ai.careInsight(for: state.snapshot, seniorID: state.selectedSeniorID)
        return VStack(alignment: .leading, spacing: 12) {
            Label("CareCompanion AI · today", systemImage: "sparkle")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(CareTheme.darkSage)
            Text(state.hasPremiumAccess ? insight.full : insight.teaser)
                .font(.system(size: 19, weight: .regular, design: .serif))
                .lineSpacing(4)
            Button {
                if state.hasPremiumAccess {
                    state.familyTab = .health
                    state.screen = .health
                } else {
                    state.showPaywall(for: .careInsight)
                }
            } label: {
                Label(state.hasPremiumAccess ? "See the health timeline" : "Unlock the full insight", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(CareTheme.darkSage)
            }
            .buttonStyle(.plain)
            Text("Organizes care information. It does not diagnose, prescribe, or detect emergencies.")
                .font(.caption)
                .foregroundStyle(CareTheme.mutedText)
                .lineSpacing(2)
        }
        .padding(22)
        .background(CareTheme.cream, in: RoundedRectangle(cornerRadius: 24))
        .padding(.top, 14)
    }
}
```

- [ ] **Step 3: Add family dashboard computed helpers**

Add:

```swift
private extension FamilyDashboardView {
    var takenCount: Int { state.snapshot.medications.filter(\.taken).count }
    var missedEveningMedicine: Bool { state.snapshot.medications.contains { $0.name == "Atorvastatin" && !$0.taken } }
    var moodLabel: String { state.currentMood?.rawValue ?? "Okay" }
    var moodEmoji: String {
        switch state.currentMood ?? .okay {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        }
    }
    var statusText: String {
        if state.hasEmergency { "SOS" }
        if missedEveningMedicine { "Needs attention" }
        return "All good"
    }
    var statusBackground: Color {
        if state.hasEmergency { return Color(red: 248/255, green: 226/255, blue: 218/255) }
        if missedEveningMedicine { return Color(red: 246/255, green: 235/255, blue: 214/255) }
        return Color(red: 239/255, green: 244/255, blue: 238/255)
    }
    var statusForeground: Color {
        if state.hasEmergency { return Color(red: 168/255, green: 62/255, blue: 38/255) }
        if missedEveningMedicine { return Color(red: 122/255, green: 86/255, blue: 21/255) }
        return CareTheme.darkSage
    }
    var sosBanner: some View {
        Button {
            state.familyTab = .alerts
            state.screen = .alerts
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maya sent an SOS").font(.body.weight(.heavy))
                    Text("Just now · open the alert").font(.caption).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(CareTheme.coral, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }
    var missedMedicineBanner: some View {
        Button {
            state.familyTab = .alerts
            state.screen = .alerts
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(CareTheme.amber)
                Text("Maya missed her evening medicine").font(.subheadline.weight(.bold)).foregroundStyle(Color(red: 122/255, green: 86/255, blue: 21/255))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(CareTheme.amber)
            }
            .padding(17)
            .background(Color(red: 246/255, green: 235/255, blue: 214/255), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }
}
```

- [ ] **Step 4: Create health timeline**

Create `App/Features/Family/HealthTimelineView.swift`:

```swift
import SwiftUI
import CareCore

struct HealthTimelineView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        CareScreen {
            CareDisplayTitle(text: "Health timeline", size: 34)
            Text("Maya Sharma · last 7 days · demo data")
                .font(.subheadline)
                .foregroundStyle(CareTheme.mutedText)
                .padding(.top, 5)
                .padding(.bottom, 22)
            chartCard(title: "Sleep", value: "6h 20m", subtitle: "Weekly average 6.7h", values: [0.79,0.75,0.71,0.76,0.64,0.62,0.66], tint: CareTheme.sage)
            chartCard(title: "Steps", value: "2,840", subtitle: "Below her 4,100 step weekly average", values: [0.72,0.75,1.0,0.78,0.68,0.70,0.60], tint: CareTheme.blue)
            heartRateCard
            adherenceCard
            moodCard
        }
    }
}
```

Add helper cards:

```swift
private extension HealthTimelineView {
    func chartCard(title: String, value: String, subtitle: String, values: [Double], tint: Color) -> some View {
        CareCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline) {
                    Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(CareTheme.mutedText)
                    Spacer()
                    Text(value).font(.system(size: 24, weight: .regular, design: .serif))
                }
                CareMiniBarChart(values: values, tint: tint)
                Text(subtitle).font(.caption).foregroundStyle(CareTheme.mutedText)
            }
        }
    }

    var heartRateCard: some View {
        CareCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline) {
                    Text("RESTING HEART RATE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(CareTheme.mutedText)
                    Spacer()
                    Text("72 bpm").font(.system(size: 24, weight: .regular, design: .serif))
                }
                Path { path in
                    path.move(to: CGPoint(x: 6, y: 52))
                    [CGPoint(x: 54, y: 58), CGPoint(x: 102, y: 64), CGPoint(x: 150, y: 58), CGPoint(x: 198, y: 48), CGPoint(x: 246, y: 26), CGPoint(x: 294, y: 44)].forEach { path.addLine(to: $0) }
                }
                .stroke(CareTheme.coral, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(height: 80)
                Text("Range 67-74 bpm this week").font(.caption).foregroundStyle(CareTheme.mutedText)
            }
        }
    }

    var adherenceCard: some View {
        CareCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(CareTheme.cream, lineWidth: 12)
                    Circle().trim(from: 0, to: 0.92).stroke(CareTheme.sage, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("92%").font(.system(size: 20, weight: .regular, design: .serif))
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEDICINE ADHERENCE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(CareTheme.mutedText)
                    Text("22 of 24 doses").font(.system(size: 21, weight: .regular, design: .serif))
                    Text("This week").font(.caption).foregroundStyle(CareTheme.mutedText)
                }
            }
        }
    }

    var moodCard: some View {
        CareCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("MOOD").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(CareTheme.mutedText)
                HStack {
                    ForEach(["😊","😊","😊","😐","😐","😔", moodEmoji], id: \.self) { emoji in
                        Text(emoji).font(.title2).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    var moodEmoji: String {
        switch state.currentMood ?? .okay {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        }
    }
}
```

- [ ] **Step 5: Create alerts**

Create `App/Features/Family/AlertsView.swift`:

```swift
import SwiftUI
import CareCore

struct AlertsView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        CareScreen {
            CareDisplayTitle(text: "Alerts", size: 34)
            Text("\(alertCount) open · newest first")
                .font(.subheadline)
                .foregroundStyle(CareTheme.mutedText)
                .padding(.top, 5)
                .padding(.bottom, 22)
            if state.hasEmergency { emergencyAlert }
            if missedEveningMedicine { alertCard(category: "MEDICINE", title: "Maya missed her evening medicine", detail: "Atorvastatin 10 mg was due at 8:00 PM. Nothing has been marked as taken since.", accent: CareTheme.amber) }
            alertCard(category: "ACTIVITY", title: "Quieter day than usual", detail: "2,840 steps today against a 4,100 step weekly average.", accent: CareTheme.blue)
            alertCard(category: "CHECK-IN", title: "Later check-in than usual", detail: "Maya checked in later than her usual morning rhythm.", accent: CareTheme.secondaryText)
            alertCard(category: "EMERGENCY", title: "SOS alert — resolved", detail: "Maya triggered an SOS on a previous demo day. It was resolved after a family call.", accent: CareTheme.coral)
        }
    }
}
```

Add alert helpers:

```swift
private extension AlertsView {
    var alertCount: Int { (state.hasEmergency ? 1 : 0) + (missedEveningMedicine ? 1 : 0) + 3 }
    var missedEveningMedicine: Bool { state.snapshot.medications.contains { $0.name == "Atorvastatin" && !$0.taken } }

    var emergencyAlert: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Color(red: 1, green: 230/255, blue: 222/255)).frame(width: 7, height: 7)
                Text("EMERGENCY · ACTIVE").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.white.opacity(0.95))
                Spacer()
                Text("Just now").font(.caption).foregroundStyle(.white.opacity(0.80))
            }
            Text("Maya sent an SOS from her phone")
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(.white)
            Text("She tapped SOS and the five second countdown completed. Call her now in the demo script.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
            HStack {
                Button("Call now") { state.showDemoToast("This is a demo — no call is placed.") }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(CareTheme.coral)
                Button("Dismiss") { state.acknowledgeEmergency() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(20)
        .background(CareTheme.coral, in: RoundedRectangle(cornerRadius: 22))
    }

    func alertCard(category: String, title: String, detail: String, accent: Color) -> some View {
        CareCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(category).font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(accent)
                    Spacer()
                    Text("Today").font(.caption).foregroundStyle(CareTheme.mutedText)
                }
                Text(title).font(.system(size: 21, weight: .regular, design: .serif))
                Text(detail).font(.subheadline).foregroundStyle(CareTheme.secondaryText).lineSpacing(3)
                HStack {
                    Button("Call now") { state.showDemoToast("This is a demo — no call is placed.") }
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(CareTheme.sage, in: Capsule())
                        .foregroundStyle(.white)
                    Button("Message") { state.showDemoToast("Messaging is not part of this demo.") }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(CareTheme.cream, in: Capsule())
                }
            }
        }
    }
}
```

- [ ] **Step 6: Create profile**

Create `App/Features/Family/ProfileView.swift`:

```swift
import SwiftUI
import CareCore

struct ProfileView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        CareScreen {
            CareDisplayTitle(text: "Profile", size: 34)
            CareCard {
                HStack(spacing: 16) {
                    Text("D")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .frame(width: 52, height: 52)
                        .background(CareTheme.cream, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diwas Sharma").font(.system(size: 22, weight: .regular, design: .serif))
                        Text("Austin, Texas · \(state.hasPremiumAccess ? "Plus plan" : "Free plan")")
                            .font(.subheadline)
                            .foregroundStyle(CareTheme.mutedText)
                    }
                }
            }
            settingsRows
            Text("Demo data. Settings are not editable in this build.")
                .font(.caption)
                .foregroundStyle(CareTheme.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
        }
    }

    var settingsRows: some View {
        VStack(spacing: 0) {
            row("Caring for", "Maya Sharma")
            Divider()
            row("Her time zone", "Kathmandu (+11:45)")
            Divider()
            row("Quiet hours", "10 PM - 7 AM")
        }
        .padding(.horizontal, 20)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CareTheme.cardStroke))
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(CareTheme.secondaryText)
        }
        .font(.subheadline)
        .padding(.vertical, 17)
    }
}
```

- [ ] **Step 7: Build**

Run:

```bash
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add CareCompanion/App/Features/Family
git commit -m "Build family dashboard health and alerts"
```

---

### Task 7: Appointments, Paywall, Premium Preview, And Toast

**Files:**
- Create: `App/Features/Shared/AppointmentsView.swift`
- Create: `App/Features/Premium/PaywallView.swift`
- Modify: `App/Features/RootView.swift`
- Modify: `App/Features/PlaceholderViews.swift`

**Interfaces:**
- Consumes: `AppState.hasPremiumAccess`, `showPaywall(for:)`, `unlockPremiumPreview()`, `prepareAppointment(using:)`, `MockAIService`.
- Produces: appointments screen, appointment prep, fallback paywall, and toast overlay.

- [ ] **Step 1: Create appointments screen**

Remove these placeholder structs from `App/Features/PlaceholderViews.swift` before creating real appointment and paywall files:

```swift
struct AppointmentsView
struct PaywallView
```

Create `App/Features/Shared/AppointmentsView.swift`:

```swift
import SwiftUI
import CareCore

struct AppointmentsView: View {
    @Environment(AppState.self) private var state
    private let ai = MockAIService()

    var body: some View {
        CareScreen {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    CareDisplayTitle(text: "Appointments", size: 34)
                    Text("September 2026 · Maya Sharma").font(.subheadline).foregroundStyle(CareTheme.mutedText)
                }
                Spacer()
                if state.role == .family {
                    Button {
                        state.showDemoToast("Adding appointments is not part of this demo.")
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(CareTheme.sage, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            appointmentCard
            staticAppointment(day: "MON", number: "7", title: "Physiotherapy session", detail: "4:00 PM · Home visit", note: "Knee mobility exercises.")
            staticAppointment(day: "THU", number: "17", title: "Eye clinic — annual screening", detail: "9:15 AM · Tilganga Institute", note: "Annual diabetic eye screening.")
        }
    }
}
```

Add appointment cards:

```swift
private extension AppointmentsView {
    var appointmentCard: some View {
        CareCard {
            HStack(alignment: .top, spacing: 16) {
                CareDateBadge(day: "Fri", number: "4", tint: Color(red: 239/255, green: 244/255, blue: 238/255))
                VStack(alignment: .leading, spacing: 9) {
                    Text("Dr. Rana — Routine check-up").font(.headline)
                    Text("10:30 AM · Kathmandu clinic").font(.subheadline).foregroundStyle(CareTheme.secondaryText)
                    Text("Discuss recent sleep and daily routine. Bring the blood pressure diary.")
                        .font(.subheadline)
                    if state.role == .family {
                        familyPrepContent
                    } else {
                        Label("Reminder set on your phone", systemImage: "bell")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CareTheme.darkSage)
                    }
                }
            }
        }
    }

    @ViewBuilder var familyPrepContent: some View {
        if let prep = state.appointmentPrep {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT CHANGED THIS WEEK").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(CareTheme.darkSage)
                ForEach(prep.observations, id: \.self) { Text($0).font(.caption).foregroundStyle(CareTheme.secondaryText) }
                Text("QUESTIONS FOR DR. RANA").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(CareTheme.darkSage).padding(.top, 5)
                ForEach(prep.questions, id: \.self) { Text($0).font(.caption).foregroundStyle(CareTheme.secondaryText) }
            }
            .padding(16)
            .background(CareTheme.softCream, in: RoundedRectangle(cornerRadius: 16))
            .padding(.top, 5)
        } else {
            Button {
                if state.hasPremiumAccess {
                    state.prepareAppointment(using: ai)
                } else {
                    state.showPaywall(for: .appointmentPrep)
                }
            } label: {
                Label("Prepare with CareCompanion AI", systemImage: "sparkle")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(CareTheme.darkSage)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    func staticAppointment(day: String, number: String, title: String, detail: String, note: String) -> some View {
        CareCard {
            HStack(alignment: .top, spacing: 16) {
                CareDateBadge(day: day, number: number)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(CareTheme.secondaryText)
                    Text(note).font(.subheadline)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create fallback paywall**

Create `App/Features/Premium/PaywallView.swift`:

```swift
import SwiftUI
import CareCore

struct PaywallView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        CareScreen {
            Label("CareCompanion AI", systemImage: "sparkle")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(CareTheme.darkSage)
            CareDisplayTitle(text: title, size: 34)
                .padding(.top, 16)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(CareTheme.secondaryText)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.bottom, 26)
            planRow(name: "Free", detail: "1 senior · check-ins, SOS, medicines", price: "Current", highlighted: false)
            planRow(name: "Plus", detail: "5 seniors · weekly Care Insight & appointment prep", price: "$6.99", highlighted: true)
            planRow(name: "Pro", detail: "25 seniors · larger family networks", price: "$14.99", highlighted: false)
            CarePrimaryButton(action: unlock) { Text("Continue with Plus") }
                .padding(.top, 22)
            Button("Not now") { state.screen = .home }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CareTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Text("RevenueCat Test Store seam · local preview unlock until credentials are configured.")
                .font(.caption2)
                .foregroundStyle(CareTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }
}
```

Add helpers:

```swift
private extension PaywallView {
    var title: String {
        state.paywallContext == .appointmentPrep ? "Walk in prepared" : "The full weekly insight"
    }
    var subtitle: String {
        state.paywallContext == .appointmentPrep
        ? "Plus turns Maya's week into a short list of changes and questions to raise with Dr. Rana."
        : "Plus reads the week across sleep, steps, heart rate, medicines and mood, then tells you what is worth a call."
    }

    func planRow(name: String, detail: String, price: String, highlighted: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 21, weight: .regular, design: .serif))
                Text(detail).font(.caption).foregroundStyle(highlighted ? CareTheme.secondaryText : CareTheme.mutedText)
            }
            Spacer()
            Text(price).font(.system(size: 18, weight: .regular, design: .serif)).foregroundStyle(highlighted ? CareTheme.darkSage : CareTheme.ink)
        }
        .padding(18)
        .background(highlighted ? .white : CareTheme.softCream, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(highlighted ? CareTheme.sage : CareTheme.cardStroke, lineWidth: highlighted ? 2 : 1))
    }

    func unlock() {
        let context = state.paywallContext
        state.unlockPremiumPreview()
        if context == .appointmentPrep {
            state.prepareAppointment(using: MockAIService())
            state.screen = .visits
            state.familyTab = .visits
        } else {
            state.screen = .home
            state.familyTab = .home
        }
    }
}
```

- [ ] **Step 3: Add toast overlay**

Modify `RootView`:

```swift
.overlay(alignment: .bottom) {
    if let message = state.toastMessage {
        CareToast(message: message)
            .padding(.bottom, 104)
            .task {
                try? await Task.sleep(for: .seconds(2))
                state.clearToast()
            }
    }
}
```

Add `CareToast` to `DesignSystem.swift` if Task 2 did not add it:

```swift
struct CareToast: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(CareTheme.ink, in: RoundedRectangle(cornerRadius: 14))
    }
}
```

- [ ] **Step 4: Build and test**

Run:

```bash
swift test
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: tests pass and app builds.

- [ ] **Step 5: Commit**

```bash
git add CareCompanion/App/Features/Shared CareCompanion/App/Features/Premium CareCompanion/App/Features/RootView.swift CareCompanion/App/DesignSystem.swift
git commit -m "Add appointments and premium demo flow"
```

---

### Task 8: Simulator Verification, Visual Polish, Status, And Checkpoint

**Files:**
- Modify: `docs/STATUS.md`
- Modify: SwiftUI files only for fixes found during simulator verification.

**Interfaces:**
- Consumes: complete app from Tasks 1-7.
- Produces: verified simulator run and documented status.

- [ ] **Step 1: Run full core tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build for the booted simulator**

Use the available booted simulator, or boot the existing iPhone 17 Pro device:

```bash
xcrun simctl list devices available
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Install and launch**

Run:

```bash
xcrun simctl install booted .build/DerivedData/Build/Products/Debug-iphonesimulator/CareCompanion.app
xcrun simctl launch booted com.carecompanion.txst
open -a Simulator
```

Expected: Simulator shows CareCompanion onboarding.

- [ ] **Step 4: Manual visual pass**

Run the demo path in the simulator:

1. Onboarding senior card.
2. Senior Home.
3. Tap “I'm okay.”
4. Continue to mood.
5. Choose Okay.
6. Demo menu to Diwas.
7. Family dashboard.
8. Unlock full insight.
9. Visits and appointment prep.
10. Demo menu to Maya.
11. SOS countdown and confirmation.
12. Demo menu to Diwas.
13. Alerts shows active SOS.

Expected: no clipped text, no overlapping bottom nav, and no safety-incorrect copy.

- [ ] **Step 5: Fix visual defects**

Use scoped edits only:

- If bottom nav overlaps content, increase `CareScreen` bottom padding to `148`.
- If display headings wrap poorly, reduce the screen-specific `CareDisplayTitle` size by 2-4 points.
- If SOS copy implies real notification delivery, replace it with “Diwas can see it on his demo dashboard.”
- If metric tiles crowd on smaller phones, keep the two-column grid but shorten labels to “Meds,” “Mood,” “Steps,” “Sleep,” “Heart,” and “Source.”

- [ ] **Step 6: Update status**

Edit `docs/STATUS.md` to include:

```markdown
## 2026-09-14 Complete Demo UI Pass

- Implemented Claude v2-inspired native SwiftUI demo shell for Maya and Diwas.
- Implemented onboarding, senior home, check-in, mood, medicines, SOS, family dashboard, health timeline, alerts, appointments, profile and premium fallback paywall.
- Demo mode remains offline and deterministic.
- Real RevenueCat credentials are not configured in this pass; premium uses local preview unlock and the RevenueCat seam remains documented.
- Latest verification:
  - `swift test`: record the exact command and observed result.
  - `xcodebuild ... build`: record the exact command and observed result.
  - Simulator launch: record whether the app reached onboarding or the first failing screen.
```

- [ ] **Step 7: Final commit**

```bash
git add CareCompanion/App CareCompanion/Sources/CareCore CareCompanion/Tests/CareCoreTests CareCompanion/docs/STATUS.md
git commit -m "Complete CareCompanion demo experience"
```

---

## Self-Review Checklist

- Spec coverage:
  - Onboarding: Task 3.
  - Senior home/check-in/mood/medicines: Task 4.
  - SOS: Task 5.
  - Family dashboard/health/alerts/profile: Task 6.
  - Appointments/AI prep/paywall: Task 7.
  - Demo reset/scenarios: Tasks 1 and 3.
  - Safety language: Tasks 1, 5, 6, 7, 8.
  - Build/test/status: Tasks 1, 5, 7, 8.
- Placeholder scan: no unfinished marker text or vague handler-only steps are intentionally present.
- Type consistency:
  - `AppScreen`, `SeniorTab`, `FamilyTab`, and `PaywallContext` are defined in Task 1 and consumed later.
  - `MockAIService`, `CareInsight`, and `AppointmentPrep` are defined in Task 1 and consumed in Tasks 6-7.
  - `AppState.hasPremiumAccess`, `showPaywall(for:)`, `unlockPremiumPreview()`, and `prepareAppointment(using:)` are defined in Task 1 and consumed in Task 7.
