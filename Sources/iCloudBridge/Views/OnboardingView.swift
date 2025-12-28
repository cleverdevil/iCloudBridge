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
