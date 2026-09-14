import CareCore
import RevenueCat
import RevenueCatUI
import SwiftUI

/// The single paywall entry point the rest of the app opens via `state.showPaywall(for:)`. When
/// RevenueCat is configured (Config/Secrets.xcconfig has a real key) this shows the real
/// RevenueCatUI paywall, per AGENTS.md: "Do not build a custom paywall if RevenueCatUI can
/// provide it." A fresh clone without secrets falls back to the local Test Store sheet so demo
/// mode keeps working fully offline.
struct PaywallHostView: View {
    @Environment(AppState.self) private var state
    @Environment(SubscriptionController.self) private var subscriptions
    let context: PaywallContext
    @State private var showComparison = false

    var body: some View {
        Group {
            if subscriptions.isConfigured {
                RevenueCatUI.PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { customerInfo in
                        subscriptions.apply(RevenueCatSubscriptionService.access(from: customerInfo), to: state)
                        Task { await unlock() }
                    }
                    .onRestoreCompleted { customerInfo in
                        subscriptions.apply(RevenueCatSubscriptionService.access(from: customerInfo), to: state)
                        Task { await unlock() }
                    }
                    .onRequestedDismissal {
                        state.paywallContext = nil
                    }
                    .safeAreaInset(edge: .bottom) { comparePlansButton }
            } else {
                TestStorePaywallFallbackView(context: context)
            }
        }
        .sheet(isPresented: $showComparison) { PlansComparisonView() }
    }

    private var comparePlansButton: some View {
        Button {
            showComparison = true
        } label: {
            Text("Compare all plans")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CareTheme.sageDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("paywall.comparePlans")
    }

    private func unlock() async {
        guard state.hasPremiumAccess else { return }
        switch context {
        case .careInsight: await state.loadCareInsight()
        case .appointmentPrep: await state.prepareAppointment()
        }
        state.paywallContext = nil
    }
}

/// Offline/demo fallback shown only when RevenueCat has no configured SDK key. Simulates a Plus
/// purchase locally so `swift build`/a fresh clone/UI tests keep working without network access.
struct TestStorePaywallFallbackView: View {
    @Environment(AppState.self) private var state
    let context: PaywallContext

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PlainPill(text: "Plus plan", icon: "sparkles", color: CareTheme.gold, fill: CareTheme.goldPale)
            Text(context == .careInsight ? "Unlock premium care insight" : "Unlock appointment preparation")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
            Text("Plus includes AI Care Insights, AI Appointment Prep, and support for up to five monitored seniors.")
                .font(.system(size: 18))
                .lineSpacing(5)
                .foregroundStyle(CareTheme.secondaryText)
            Spacer()
            Button {
                state.unlockPremiumPreview()
                Task {
                    if context == .careInsight {
                        await state.loadCareInsight()
                    } else {
                        await state.prepareAppointment()
                    }
                }
            } label: {
                Text("Buy with Test Store")
            }
            .buttonStyle(ReferenceButtonStyle(fill: CareTheme.sage, height: 62, radius: 22))
            .accessibilityIdentifier("paywall.buy")
            Button("Not now") { state.paywallContext = nil }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CareTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .padding(24)
        .background(CareTheme.background)
    }
}

/// The four-tier plan comparison: Free, Plus, Pro (all real) and Enterprise, which is a "contact
/// us" stub — see AGENTS.md's "Organization — Future" section and docs/REVENUECAT.md for why
/// Enterprise has no purchase button here.
struct PlansComparisonView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(PlanCatalog.all) { plan in
                        PlanCard(plan: plan, isCurrent: plan.tier == state.subscription.tier)
                    }
                }
                .padding(20)
            }
            .background(CareTheme.background)
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("plans.comparison")
    }
}

private struct PlanCard: View {
    let plan: PlanDescriptor
    let isCurrent: Bool
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LovableCard(
            fill: isCurrent ? CareTheme.sagePale : .white,
            stroke: isCurrent ? CareTheme.sage.opacity(0.4) : CareTheme.cardStroke
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.title).font(.system(size: 20, weight: .black))
                    if isCurrent {
                        PlainPill(text: "Current", icon: "checkmark", color: CareTheme.sageDark, fill: CareTheme.sagePale)
                    }
                    Spacer()
                }
                Text(plan.seniorLimitDescription)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CareTheme.secondaryText)
                ForEach(plan.features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.mutedText)
                }
                if plan.tier == .enterprise {
                    Button {
                        dismiss()
                        state.showDemoToast("Enterprise plans are configured with our team based on seat count. Email hello@carecompanion.app.")
                    } label: {
                        Text("Contact us").font(.system(size: 15, weight: .black)).foregroundStyle(CareTheme.sageDark)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plans.enterprise.contact")
                }
            }
        }
    }
}
