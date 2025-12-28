# First-Run Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a guided first-run experience that requests permissions before showing Settings, with auto-start for returning users.

**Architecture:** New OnboardingView handles step-by-step permission requests. SettingsView wrapper checks permission state to show either OnboardingView or normal Settings. App launch logic checks permissions + saved settings to decide whether to auto-start or open window.

**Tech Stack:** SwiftUI, EventKit (EKEventStore), Photos (PHPhotoLibrary)

---

### Task 1: Add Permission and Settings State Helpers to AppState

**Files:**
- Modify: `Sources/iCloudBridge/AppState.swift`

**Step 1: Add computed properties**

Add these computed properties to the AppState class after the existing properties:

```swift
var hasAllPermissions: Bool {
    remindersService.authorizationStatus == .fullAccess &&
    photosService.authorizationStatus == .authorized
}

var hasSavedSettings: Bool {
    !selectedListIds.isEmpty || !selectedAlbumIds.isEmpty
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/AppState.swift
git commit -m "feat: add hasAllPermissions and hasSavedSettings helpers"
```

---

### Task 2: Create OnboardingView

**Files:**
- Create: `Sources/iCloudBridge/Views/OnboardingView.swift`

**Step 1: Create the OnboardingView file**

```swift
import SwiftUI
import EventKit
import Photos

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    let onComplete: () -> Void

    @State private var currentStep: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("iCloud Bridge Setup")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("iCloud Bridge needs access to your Reminders and Photos to expose them via a local API.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            .padding(.bottom, 30)

            Divider()

            // Permission Steps
            VStack(spacing: 16) {
                remindersStep
                photosStep
            }
            .padding(30)

            Spacer()

            // Footer
            HStack {
                Text("Step \(currentStep) of 2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(20)
        }
        .frame(width: 500, height: 500)
        .onAppear {
            updateCurrentStep()
        }
        .onChange(of: appState.remindersService.authorizationStatus) { _, _ in
            updateCurrentStep()
            checkCompletion()
        }
        .onChange(of: appState.photosService.authorizationStatus) { _, _ in
            updateCurrentStep()
            checkCompletion()
        }
    }

    private var remindersStep: some View {
        PermissionStepView(
            icon: "list.bullet.clipboard",
            title: "Reminders Access",
            description: "Required to read and manage your reminder lists through the API.",
            status: remindersStatus,
            action: requestRemindersAccess,
            openSettings: openRemindersSettings
        )
    }

    private var photosStep: some View {
        PermissionStepView(
            icon: "photo.on.rectangle",
            title: "Photos Access",
            description: "Required to browse albums and serve photos through the API.",
            status: photosStatus,
            isEnabled: appState.remindersService.authorizationStatus == .fullAccess,
            action: requestPhotosAccess,
            openSettings: openPhotosSettings
        )
    }

    private var remindersStatus: PermissionStatus {
        switch appState.remindersService.authorizationStatus {
        case .fullAccess:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private var photosStatus: PermissionStatus {
        switch appState.photosService.authorizationStatus {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private func updateCurrentStep() {
        if appState.remindersService.authorizationStatus == .fullAccess {
            currentStep = 2
        } else {
            currentStep = 1
        }
    }

    private func checkCompletion() {
        if appState.hasAllPermissions {
            // Small delay to show the completed state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete()
            }
        }
    }

    private func requestRemindersAccess() {
        Task {
            _ = await appState.remindersService.requestAccess()
        }
    }

    private func requestPhotosAccess() {
        Task {
            _ = await appState.photosService.requestAccess()
        }
    }

    private func openRemindersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openPhotosSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

struct PermissionStepView: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    var isEnabled: Bool = true
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Status icon
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .primary : .secondary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isEnabled {
                    actionButton
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isEnabled ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(status == .granted ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    private var statusIcon: String {
        switch status {
        case .granted:
            return "checkmark"
        case .denied:
            return icon
        case .notDetermined:
            return icon
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .granted:
            return Color.green.opacity(0.2)
        case .denied:
            return Color.red.opacity(0.2)
        case .notDetermined:
            return Color.accentColor.opacity(0.2)
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .accentColor
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .granted:
            Label("Access Granted", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        case .denied:
            Button("Open System Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        case .notDetermined:
            Button("Grant Access") {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/OnboardingView.swift
git commit -m "feat: add OnboardingView for guided permission setup"
```

---

### Task 3: Create Settings Content Wrapper

**Files:**
- Create: `Sources/iCloudBridge/Views/SettingsContentView.swift`

**Step 1: Create the wrapper view**

This view decides whether to show OnboardingView or SettingsView based on permission state:

```swift
import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if appState.hasAllPermissions {
            SettingsView(appState: appState, onSave: onSave)
        } else {
            OnboardingView(appState: appState, onComplete: handleOnboardingComplete)
        }
    }

    private func handleOnboardingComplete() {
        // Reload data now that we have permissions
        appState.remindersService.loadLists()
        appState.photosService.loadAlbums()

        if appState.hasSavedSettings {
            // Has saved settings - start server and close window
            onSave()
            dismiss()
        }
        // Otherwise, stay open to show SettingsView (view will re-render)
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/SettingsContentView.swift
git commit -m "feat: add SettingsContentView wrapper for permission check"
```

---

### Task 4: Update iCloudBridgeApp with Launch Logic

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Update the Window to use SettingsContentView**

Replace the Window scene body to use `SettingsContentView` instead of `SettingsView` directly:

Find this code (around line 27-33):
```swift
Window("iCloud Bridge Settings", id: "settings") {
    SettingsView(appState: appState, onSave: startServer)
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
```

Replace with:
```swift
Window("iCloud Bridge Settings", id: "settings") {
    SettingsContentView(appState: appState, onSave: startServer)
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
```

**Step 2: Add launch logic to AppDelegate**

Update the AppDelegate class to handle launch behavior. Replace the entire AppDelegate class:

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var openSettingsWindow: (() -> Void)?
    var startServer: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as an accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Delay slightly to ensure appState is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.handleLaunch()
        }
    }

    private func handleLaunch() {
        guard let appState = appState else { return }

        if appState.hasAllPermissions && appState.hasSavedSettings {
            // Returning user with all permissions - auto-start server silently
            startServer?()
        } else {
            // Missing permissions OR no saved settings - open window
            openSettingsWindow?()
        }
    }
}
```

**Step 3: Update iCloudBridgeApp to wire up the delegate**

Add an `@Environment` for openWindow and update the body to configure the delegate. Replace the entire struct:

```swift
@main
struct iCloudBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var serverManager: ServerManager?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appState,
                onStartServer: startServer,
                onStopServer: stopServer
            )
        } label: {
            menuBarLabel
        }

        Window("iCloud Bridge Settings", id: "settings") {
            SettingsContentView(appState: appState, onSave: startServer)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text("iCloud Bridge")
        }
        .onAppear {
            // Configure delegate callbacks
            appDelegate.appState = appState
            appDelegate.openSettingsWindow = { [self] in
                openWindow(id: "settings")
            }
            appDelegate.startServer = startServer
        }
    }

    private var statusIcon: String {
        switch appState.serverStatus {
        case .stopped:
            return "cloud"
        case .starting:
            return "cloud.bolt"
        case .running:
            return "cloud.fill"
        case .error:
            return "cloud.slash"
        }
    }

    private func startServer() {
        Task {
            await MainActor.run {
                appState.serverStatus = .starting
            }

            if serverManager == nil {
                serverManager = ServerManager(
                    remindersService: appState.remindersService,
                    photosService: appState.photosService,
                    selectedListIds: { appState.selectedLists },
                    selectedAlbumIds: { appState.selectedAlbums }
                )
            } else {
                await serverManager?.stop()
            }

            do {
                try await serverManager?.start(port: appState.serverPort)
                await MainActor.run {
                    appState.serverStatus = .running(port: appState.serverPort)
                }
            } catch {
                await MainActor.run {
                    appState.serverStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func stopServer() {
        Task {
            await serverManager?.stop()
            await MainActor.run {
                appState.serverStatus = .stopped
            }
        }
    }
}
```

**Step 4: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: add launch logic for auto-start and onboarding"
```

---

### Task 5: Remove Auto-Permission-Request from Settings Views

**Files:**
- Modify: `Sources/iCloudBridge/Views/RemindersSettingsView.swift`
- Modify: `Sources/iCloudBridge/Views/PhotosSettingsView.swift`

**Step 1: Update RemindersSettingsView**

Remove the `onAppear` permission request since OnboardingView now handles it. Find and remove or modify the `.onAppear` block (around lines 22-30):

Remove this:
```swift
.onAppear {
    Task {
        if appState.remindersService.authorizationStatus != .fullAccess {
            _ = await appState.remindersService.requestAccess()
        } else {
            appState.remindersService.loadLists()
        }
    }
}
```

Replace with just a data refresh (in case lists changed):
```swift
.onAppear {
    if appState.remindersService.authorizationStatus == .fullAccess {
        appState.remindersService.loadLists()
    }
}
```

**Step 2: Update PhotosSettingsView**

Find the PhotosSettingsView file and check if it has similar `onAppear` logic. If it does, update it the same way - only refresh data, don't request permissions.

Find and update the `.onAppear` block to only reload data when already authorized:

```swift
.onAppear {
    if appState.photosService.authorizationStatus == .authorized {
        appState.photosService.loadAlbums()
    }
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/Views/RemindersSettingsView.swift Sources/iCloudBridge/Views/PhotosSettingsView.swift
git commit -m "refactor: remove auto-permission-request from settings views"
```

---

### Task 6: Build and Create App Bundle

**Files:**
- None (build task)

**Step 1: Build release version**

Run: `swift build -c release`
Expected: Build succeeds

**Step 2: Create app bundle**

Run the bundling commands:
```bash
rm -rf iCloudBridge.app
mkdir -p iCloudBridge.app/Contents/MacOS
mkdir -p iCloudBridge.app/Contents/Resources
cp .build/release/iCloudBridge iCloudBridge.app/Contents/MacOS/
cp Sources/iCloudBridge/Resources/Info.plist iCloudBridge.app/Contents/
codesign --force --deep --sign - iCloudBridge.app
```

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: build first-run onboarding feature"
```

---

### Task 7: Manual Testing Checklist

**Test Cases:**

1. **First run (no permissions, no settings)**
   - Delete app preferences: `defaults delete com.example.iCloudBridge` (or your bundle ID)
   - Revoke permissions in System Settings > Privacy
   - Launch app
   - Expected: Window opens with OnboardingView
   - Click "Grant Access" for Reminders - system dialog appears
   - Grant permission - step shows checkmark, advances to Photos
   - Click "Grant Access" for Photos - system dialog appears
   - Grant permission - transitions to SettingsView
   - Select items, click "Save & Start Server"

2. **Return with permissions and settings**
   - Quit and relaunch app
   - Expected: No window opens, server auto-starts, menu bar shows "Running"

3. **Return with permissions but no settings**
   - Clear saved settings: `defaults delete com.example.iCloudBridge selectedListIds`
   - Relaunch app
   - Expected: Window opens with SettingsView (not onboarding)

4. **Permission revoked**
   - Revoke Reminders permission in System Settings
   - Relaunch app
   - Expected: Window opens with OnboardingView showing Reminders denied
   - "Open System Settings" button should appear

---
