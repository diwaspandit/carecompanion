# RevenueCat integration

Phase 3 of `docs/FULL_DEVELOPMENT_PLAN.md`. Real RevenueCat Purchases + RevenueCatUI, replacing
the local Test Store fallback sheet as the primary paywall whenever the SDK is configured.

## Plans and entitlements

Per `AGENTS.md`'s "Plans" section, there are three real, purchasable tiers plus one stub:

| Tier | Entitlement | Senior limit | Purchasable via RevenueCat |
| --- | --- | --- | --- |
| Free | (none) | 1 | No — default, no purchase needed |
| Plus | `plus_plan` | 5 | Yes |
| Pro | `pro_plan` | 25 | Yes |
| Enterprise | `enterprise_plan` | configurable | **No — see "Enterprise is a stub" below** |

`premium_insights` also unlocks premium AI (`SubscriptionAccess.canUsePremiumAI`) without changing
the senior limit — it's the entitlement `unlockPremiumPreview()` grants for the local demo
fallback, kept separate from the real plan entitlements so demo unlocks are never mistaken for a
real purchase.

## Enterprise is a stub, on purpose

`AGENTS.md` explicitly excludes "production enterprise billing" and organization UI from this
hackathon build ("Organization — Future ... Do not build organization UI"). When Phase 3 was
scoped, the product ask was expanded to a 4-tier system including Enterprise with a
per-organization seat count — but StoreKit/RevenueCat sell fixed SKUs, not an arbitrary typed-in
quantity, so a real self-serve Enterprise purchase would need a custom billing backend, which
`AGENTS.md`'s tech constraints also forbid (no custom REST server).

The resolution (confirmed with the product owner during this phase): Free, Plus and Pro are real,
RevenueCat-backed tiers. Enterprise appears in the 4-tier "Compare plans" screen
(`App/Features/PaywallHostView.swift`, `PlansComparisonView`) with full marketing copy, but its
card has no purchase button — only a "Contact us" action. There is no `enterprise_plan` product in
the RevenueCat dashboard.

`PlanTier.enterprise`, `SubscriptionAccess.enterpriseSeatLimit` and the `enterprise_plan`
entitlement string exist in `Sources/CareCore` so the architecture doesn't need to change shape
again later — they're inert until a real product decision is made. **If Enterprise ever becomes a
real purchase**, the recommended design (also decided during this phase) is fixed seat-tier SKUs:
offer a handful of Enterprise products in the dashboard (e.g. Enterprise 50 / 100 / 250 seniors),
each granting the same `enterprise_plan` entitlement; the app reads which product was purchased to
set `enterpriseSeatLimit`. That keeps checkout self-serve through a stock RevenueCatUI paywall
instead of building custom per-seat billing. The alternative — a sales-configured seat count stored
out-of-band (e.g. in Supabase `subscription_statuses.seat_limit`) — was considered and rejected for
now because it isn't self-serve or demoable end-to-end.

## Dashboard setup checklist

1. Create (or open) the RevenueCat project for CareCompanion.
2. **Project Settings → API Keys → Apple App Store**: copy the public iOS SDK key. Use the **Test
   Store** key (`test_...`) during development — never the App Store Connect key from a hackathon
   sandbox. Put it in `Config/Secrets.xcconfig` (git-ignored, copy from `Secrets.xcconfig.example`):
   ```
   REVENUECAT_API_KEY = test_...
   ```
3. **Entitlements**: create exactly `plus_plan` and `pro_plan` (plus `premium_insights` if you want
   a separate demo-only entitlement, though the app never grants it via a real purchase).
4. **Products**: create one Plus product and one Pro product (Test Store products don't need App
   Store Connect — RevenueCat's Test Store simulates the purchase sheet). Attach each product to
   its entitlement.
5. **Offerings**: add both packages to the "default" (current) offering. RevenueCatUI's stock
   `PaywallView()` renders whatever is configured on the current offering — no app code changes
   needed when you adjust pricing or copy in the dashboard.
6. Design the paywall in **Paywalls** (RevenueCatUI's dashboard-driven templates). A multi-package
   template showing Plus and Pro side by side matches the "4 plan system" ask most closely, with
   Free and Enterprise handled by the app's own `PlansComparisonView` around it.

## How the app wires this up

- `App/Services/RevenueCatConfiguration.swift` reads `REVENUECAT_API_KEY` from Info.plist (same
  pattern as `SupabaseConfig`) and calls `Purchases.configure(withAPIKey:)` once at launch, only if
  a real key is present. No key → `isConfigured == false` → the app stays fully offline/demo.
- `App/Services/RevenueCatSubscriptionService.swift` implements CareCore's `SubscriptionService`
  protocol against `Purchases.shared`, and is also the `PurchasesDelegate` so entitlement changes
  pushed by RevenueCat (renewals, cross-device purchases, cancellations) reach the app without a
  manual refresh.
- `App/Services/SubscriptionController.swift` owns the lifecycle: applies a cached last-known
  entitlement set immediately at cold launch (`UserDefaults`, never treated as authoritative),
  refreshes from RevenueCat in the background, and refreshes again on every app foreground
  (`scenePhase == .active`) and on every purchase/restore/CustomerInfo push.
- `App/Features/PaywallHostView.swift` is the one place `state.showPaywall(for:)` opens. It shows
  the real `RevenueCatUI.PaywallView()` when configured, or `TestStorePaywallFallbackView` (the
  original local simulated purchase) when it isn't. **CareCore and the rest of the app never import
  RevenueCat** — only these two `App/Services` files and this view do, per `AGENTS.md`'s "Views
  must not call ... RevenueCat ... directly."
- `Sources/CareCore/AppState.swift` exposes `applySubscriptionAccess(_:)` as the one bridge point
  vendor code uses to update `AppState.subscription`.

## Verification

- **Cold start, no secrets**: fresh clone, no `Config/Secrets.xcconfig` → app launches in demo
  mode, `state.showPaywall(for:)` shows `TestStorePaywallFallbackView`, "Buy with Test Store"
  unlocks premium exactly as before Phase 3.
- **Test Store purchase**: with a real `test_...` key configured, opening the paywall shows the
  real RevenueCatUI sheet; completing a Test Store purchase for Plus calls
  `onPurchaseCompleted`, which maps `CustomerInfo.entitlements.active` into `SubscriptionAccess`
  and unlocks the AI insight / appointment prep the user was trying to reach.
- **Cancellation grants nothing**: dismissing or cancelling the RevenueCatUI sheet never calls
  `applySubscriptionAccess` — `AppState.subscription` is untouched.
- **Restore**: RevenueCatUI's stock paywall includes a restore affordance; the demo menu also has
  a "Restore purchases" action (visible only when RevenueCat is configured) that calls
  `SubscriptionController.restore(applyingTo:)`.
- **Senior limits**: `AccessPolicy`/`DefaultPlanService` unit tests cover free=1, plus=5, pro=25,
  and enterprise with/without an explicit seat count (`Int.max` fallback) —
  `Tests/CareCoreTests/CareCoreTests.swift`, "Phase 3 Plan Tier Tests".

## Known limitation

The hidden `#if DEBUG` "Live Supabase" developer screen (`App/Features/LiveModeView.swift`) swaps
`AppState` for a second instance (`LiveModeController.liveState`) when a developer goes live.
`SubscriptionController` currently applies entitlement updates to the base demo `AppState` only, so
if a developer is simultaneously in Live Supabase mode, `AppState.subscription` on the live state
instance won't reflect a real purchase made in that session. This only affects the hidden developer
flow, not the main demo path (SOS → check-in → mood → paywall → AI insight), and is a reasonable
follow-up for the phase that unifies demo/live `AppState` lifecycles rather than something to
special-case here.
