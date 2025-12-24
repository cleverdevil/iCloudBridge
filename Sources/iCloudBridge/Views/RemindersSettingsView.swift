import SwiftUI
import EventKit

struct RemindersSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Permission Status
            permissionSection

            Divider()

            // Lists Selection
            if appState.remindersService.authorizationStatus == .fullAccess {
                listsSection
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            Task {
                if appState.remindersService.authorizationStatus != .fullAccess {
                    _ = await appState.remindersService.requestAccess()
                } else {
                    appState.remindersService.loadLists()
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders Access")
                .font(.headline)

            HStack {
                switch appState.remindersService.authorizationStatus {
                case .fullAccess:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Access granted")
                case .denied, .restricted:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Access denied")
                    Spacer()
                    Button("Open System Settings") {
                        openSystemSettings()
                    }
                case .notDetermined, .writeOnly:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.yellow)
                    Text("Permission required")
                    Spacer()
                    Button("Grant Access") {
                        Task {
                            _ = await appState.remindersService.requestAccess()
                        }
                    }
                @unknown default:
                    Text("Unknown status")
                }
            }
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Reminders Lists")
                .font(.headline)

            Text("Choose which lists to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.remindersService.allLists, id: \.calendarIdentifier) { list in
                        Toggle(isOn: Binding(
                            get: { appState.isListSelected(list.calendarIdentifier) },
                            set: { _ in appState.toggleList(list.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: list.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(list.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
