# First-Run Onboarding Design

## Problem

On first run, the app immediately requests permissions when the user opens Settings, with no explanation. After granting, nothing visually changes until "Save & Start Server" is clicked. This creates a confusing, jarring experience.

## Solution

Front-load the permission experience with a dedicated onboarding flow that:
1. Explains what permissions are needed and why
2. Guides users through granting each permission step-by-step
3. Transitions seamlessly to Settings or auto-starts based on existing saved settings

## Launch Flow

```
App Launches
     │
     ▼
Both permissions granted?
     │
    No ──────► Open window with OnboardingView
     │
    Yes
     │
     ▼
Saved settings exist?
     │
    No ──────► Open window with SettingsView (data pre-loaded)
     │
    Yes ─────► Auto-start server silently (no window)
```

The menu bar icon appears immediately in all cases.

## Permission Requirements

- **Both Reminders and Photos are required** - User must grant both before proceeding
- **Onboarding appears whenever permissions are missing** - Handles first run and permission revocation scenarios

## Onboarding View Flow

### Step 1: Reminders Permission

Shows explanation of why Reminders access is needed. Button triggers system permission dialog. After granted, shows checkmark and advances to Step 2.

### Step 2: Photos Permission

Shows completed Step 1 with checkmark. Shows explanation of why Photos access is needed. Button triggers system permission dialog.

### After Both Granted

- **If saved settings exist:** Window closes, server auto-starts
- **If no saved settings:** Transitions to normal SettingsView with data pre-loaded

### Denial Handling

If user denies a permission, the button changes to "Open System Settings" with explanation that they need to grant access in System Settings to continue.

## Implementation

### New Files

- `Sources/iCloudBridge/Views/OnboardingView.swift` - Step-by-step permission UI

### Modified Files

- `Sources/iCloudBridge/AppState.swift` - Add `hasAllPermissions` and `hasSavedSettings` computed properties
- `Sources/iCloudBridge/iCloudBridgeApp.swift` - Add launch logic for auto-start or window opening
- `Sources/iCloudBridge/Views/SettingsView.swift` - Wrap to show OnboardingView when permissions missing

### AppState Additions

```swift
var hasAllPermissions: Bool {
    remindersService.authorizationStatus == .fullAccess &&
    photosService.authorizationStatus == .authorized
}

var hasSavedSettings: Bool {
    !selectedListIds.isEmpty || !selectedAlbumIds.isEmpty
}
```

### Window Content Logic

The Settings window checks permission state to decide content:

```swift
if appState.hasAllPermissions {
    SettingsView(...)  // Normal tabbed settings
} else {
    OnboardingView(...)  // Permission flow
}
```

### Launch Sequence

On app launch, check state and act accordingly:

```swift
.onAppear {
    if appState.hasAllPermissions && appState.hasSavedSettings {
        startServer()  // Silent auto-start, no window
    } else {
        openWindow(id: "settings")  // Opens onboarding or settings
    }
}
```

## Existing Code Integration

The services already load data when authorized:
- `RemindersService.init()` calls `loadLists()` if already authorized
- `PhotosService.init()` calls `loadAlbums()` if already authorized

After onboarding completes, calling these methods again will populate data immediately with no additional permission prompts.
