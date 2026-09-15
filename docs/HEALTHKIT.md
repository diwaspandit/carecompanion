# HealthKit Integration

CareCompanion integrates with Apple HealthKit to sync health data for seniors, allowing family members to monitor daily activity patterns while respecting privacy.

## Overview

The HealthKit integration is:
- **Read-only**: We never write data to HealthKit
- **Privacy-first**: Users control which data types to share
- **Source-labeled**: Health snapshots clearly indicate their source (demo, manual, or healthkit)
- **Graceful**: Permission denial or revocation doesn't break the app

## Health Data Types

We request **read-only** access to three health metrics:

| Type | Identifier | Purpose |
|------|------------|---------|
| **Steps** | `HKQuantityType.stepCount` | Daily step count to monitor activity levels |
| **Sleep** | `HKCategoryType.sleepAnalysis` | Sleep duration to track rest patterns |
| **Resting Heart Rate** | `HKQuantityType.restingHeartRate` | Heart rate measurements for wellness monitoring |

## Permission States

HealthKit permissions can be in one of four states:

### 1. Not Determined
- User hasn't been asked for permission yet
- App shows permission request UI with clear explanations
- Users can tap "Allow Health Access" to request permission

### 2. Authorized
- User has granted read access
- App can sync health data from HealthKit
- Background sync can be enabled (future feature)

### 3. Denied
- User explicitly denied permission
- App shows "Open Settings" button to allow re-authorization
- Health dashboard shows demo/manual data only
- No broken UI - graceful fallback

### 4. Restricted
- HealthKit is disabled by device restrictions (e.g., parental controls)
- App shows informational message
- Health dashboard uses alternative data sources

## Data Flow

### Permission Request
```
User opens Health Permissions →
  App explains data types →
    User taps "Allow Health Access" →
      iOS shows system permission dialog →
        User grants permission →
          App sets up automatic sync →
            Initial sync performed →
              Background observers started
```

### Automatic Sync (No User Action Required)
```
1. Background Sync:
   New health data added to Health app →
     HKObserverQuery detects change →
       Notification posted →
         AppState.syncHealthData() triggered →
           Data synced to database

2. Foreground Sync:
   App becomes active (user opens app) →
     scenePhase changes to .active →
       AppState.syncHealthData() triggered →
         Latest data synced to database

3. On Launch:
   App launches →
     setupAutomaticHealthSync() called →
       Background observers started →
         Ready for automatic updates
```

### Data Sync
```
App requests health data →
  HealthKit returns samples for last 7 days →
    App normalizes samples into HealthSnapshot objects →
      Snapshots are marked with source="healthkit" →
        Repository upserts snapshots →
          UI refreshes with HealthKit data
```

### Source Labeling
```swift
// Demo data
HealthSnapshot(source: "Demo data")

// HealthKit data
HealthSnapshot(source: "healthkit")

// Manual entry (future)
HealthSnapshot(source: "manual")
```

## Implementation Details

### Files

| File | Purpose |
|------|---------|
| `App/Services/HealthKitHealthDataProvider.swift` | Real HealthKit integration |
| `App/Features/HealthPermissionsView.swift` | Permission request UI |
| `Sources/CareCore/HealthDataProvider.swift` | Protocol definition |
| `Config/CareCompanion.entitlements` | HealthKit capability |
| `Config/App.xcconfig` | Privacy usage descriptions |

### Key Components

#### HealthKitHealthDataProvider
- Implements `HealthDataProvider` protocol
- Uses `HKHealthStore` to query health data
- Fetches steps using `HKStatisticsCollectionQuery` (daily aggregation)
- Fetches sleep using `HKSampleQuery` (filtering asleep states only)
- Fetches resting heart rate using `HKSampleQuery` (latest per day)
- Normalizes all data into `HealthSnapshot` objects

#### HealthPermissionsView
- Explains what data we access and why
- Shows current permission status
- Provides "Allow Health Access" button
- Opens iOS Settings if permission was denied
- Automatically triggers sync after authorization

#### AppState Integration
- `healthProvider: HealthDataProvider?` - Nil in demo mode, HealthKit in production
- `syncHealthData()` - Fetches and saves health snapshots
- `checkHealthPermissionStatus()` - Returns current permission state
- `requestHealthPermissions()` - Requests HealthKit authorization

## Privacy

### User Privacy Descriptions

```
NSHealthShareUsageDescription:
"CareCompanion needs access to your health data to sync steps, sleep,
and heart rate for Maya's care dashboard. This helps family members
understand daily activity patterns."

NSHealthUpdateUsageDescription:
"CareCompanion does not write health data."
```

### Data Handling
- Health data is **never sent to external servers** (all local processing)
- Only aggregated daily summaries are stored, not raw samples
- Source labels prevent confusion between demo and real data
- Users can revoke access anytime in iOS Settings → Privacy → Health

### Senior Device Link
- Only the senior's own linked login can sync (`AppState.healthSyncEligibility == .allowed`)
- A family member's phone shows why sync is unavailable and never prompts for HealthKit access
- Enforced server-side too: only the linked login can write `healthkit` snapshots (see docs/DATABASE.md, "Senior device link")

### Demo Mode
- HealthKit sync is disabled in demo mode (the demo `AppState` has no health provider)
- Demo health data is clearly labeled with `source = "Demo data"`
- No permission requests shown in demo mode
- Ensures demo remains fully offline

## Testing

### Manual Testing Steps

1. **Clean Install**
   ```bash
   # Remove app if installed
   xcrun simctl uninstall booted com.carecompanion.txst

   # Build and install
   xcodebuild -project CareCompanion.xcodeproj \
     -scheme CareCompanion \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     ONLY_ACTIVE_ARCH=YES build

   xcrun simctl install booted <path-to-CareCompanion.app>
   xcrun simctl launch booted com.carecompanion.txst
   ```

2. **Grant Permissions**
   - Navigate to Settings → Health Permissions
   - Tap "Allow Health Access"
   - Grant all three permissions in iOS dialog
   - Verify sync completes successfully
   - Check dashboard shows HealthKit data

3. **Deny Permissions**
   - Repeat step 1 (clean install)
   - Deny permissions in iOS dialog
   - Verify app shows "Open Settings" option
   - Verify dashboard uses demo/manual data only
   - Verify no crashes or broken UI

4. **Revoke Permissions**
   - After granting, go to iOS Settings → Privacy → Health → CareCompanion
   - Turn off all permissions
   - Return to app and trigger sync
   - Verify graceful error handling
   - Verify dashboard falls back to demo data

5. **Partial Permissions**
   - Grant only Steps permission
   - Verify sync works for granted types
   - Verify missing types show as 0 or N/A

### Unit Tests

```bash
swift test
# All tests should pass including:
# - testHealthSyncWithDemoProvider
# - testHealthPermissionStatusCheck
# - testHealthSyncUpdatesSnapshot
# - testHealthSnapshotsHaveCorrectSource
# - testHealthSyncStatusTracking
```

### Automated UI Tests
```swift
// Future enhancement
func testHealthPermissionFlow() {
    // Launch app
    // Navigate to health permissions
    // Verify permission UI displayed
    // Mock permission grant
    // Verify sync triggered
    // Verify dashboard updated
}
```

## Troubleshooting

### Permission Dialog Doesn't Appear
- Check `CareCompanion.entitlements` has HealthKit enabled
- Verify `NSHealthShareUsageDescription` is in Info.plist
- Ensure app is running on iOS 17+ simulator/device
- Check Xcode signing & capabilities tab

### Sync Returns Empty Data
- Verify permissions are granted in iOS Settings
- Check iOS Health app has data for the requested types
- Simulator may have no health data - add sample data in Health app
- Check console logs for HealthKit errors

### Build Errors with HealthKit
- Ensure `import HealthKit` is present
- Check deployment target is iOS 17.0+
- Verify HealthKit framework is linked
- Clean build folder and retry

### Demo Mode Shows HealthKit Data
- Verify `healthProvider` is nil in demo mode
- Check AppState initialization doesn't set healthProvider for demo
- Demo data should always have `source = "Demo data"`

## Automatic Sync

### Background Sync (✅ Implemented)
- `HKObserverQuery` monitors for new HealthKit data
- Background delivery enabled with hourly frequency
- Automatic sync triggered when new health data arrives
- No user action required

### Foreground Sync (✅ Implemented)
- Syncs when app becomes active
- Syncs on app launch
- Ensures fresh data when senior opens app

### Manual Sync (✅ Available)
- "Sync Now" button in Health Permissions view
- Fallback option for users who want immediate refresh

## Future Enhancements

### Incremental Sync (Phase 7)
- Deferred: re-fetching seven days is idempotent because snapshots upsert on (senior, date, source)
- Add `HKAnchoredObjectQuery` for delta sync
- Store sync anchors for efficient data retrieval
- Notify user when significant health changes detected

### Additional Metrics (Phase 5+)
- Blood Pressure (requires user tracking)
- Active Energy (calories burned)
- Exercise Minutes
- Weight trends

### Manual Entry (Phase 5+)
- Allow family members to manually log health data
- Source labeled as "manual"
- Useful for seniors without Apple Watch

### Health Insights (Phase 6+)
- AI analyzes health trends (never diagnoses)
- Flags significant changes for family attention
- Generates appointment prep questions based on trends
- All subject to premium AI safety rules

## Security Considerations

### What We Never Do
- ❌ Store raw HealthKit samples
- ❌ Send health data to external servers
- ❌ Write any data to HealthKit
- ❌ Request more permissions than needed
- ❌ Diagnose or prescribe based on health data
- ❌ Share health data without explicit user consent

### What We Do
- ✅ Request minimum necessary permissions
- ✅ Clearly explain data usage before requesting
- ✅ Label all data sources transparently
- ✅ Allow users to revoke access anytime
- ✅ Use health data only for family care coordination
- ✅ Keep all processing local
- ✅ Handle errors gracefully without breaking UX

## Compliance

### Apple Health Guidelines
- Follows all HealthKit Programming Guide requirements
- Privacy usage strings are clear and accurate
- Only requests necessary data types
- No misleading health claims
- No diagnostic or treatment advice

### HIPAA Considerations
- Health data stays on device (not covered entity)
- If future server integration: encrypt in transit and at rest
- Allow data export and deletion on request
- Maintain audit logs for data access

## References

- [HealthKit Documentation](https://developer.apple.com/documentation/healthkit)
- [Protecting User Privacy](https://developer.apple.com/documentation/healthkit/protecting_user_privacy)
- [FULL_DEVELOPMENT_PLAN.md](./FULL_DEVELOPMENT_PLAN.md) - Phase 4 details
