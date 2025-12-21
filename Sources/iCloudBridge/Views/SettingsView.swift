import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void

    @State private var portString: String = ""
    @State private var showingPortError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("iCloud Bridge Settings")
                .font(.title)
                .padding(.bottom, 10)

            // Permission Status
            permissionSection

            Divider()

            // Lists Selection
            if appState.remindersService.authorizationStatus == .fullAccess {
                listsSection

                Divider()

                // Port Configuration
                portSection

                Divider()

                // Save Button
                HStack {
                    Spacer()
                    Button("Save & Start Server") {
                        saveAndStart()
                    }
                    .disabled(!appState.hasValidSettings || !isValidPort)
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 500)
        .onAppear {
            portString = String(appState.serverPort)
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

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server Port")
                .font(.headline)

            HStack {
                TextField("Port", text: $portString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: portString) { _, _ in
                        validatePort()
                    }

                if showingPortError {
                    Text("Invalid port (1024-65535)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var isValidPort: Bool {
        guard let port = Int(portString) else { return false }
        return port >= 1024 && port <= 65535
    }

    private func validatePort() {
        showingPortError = !portString.isEmpty && !isValidPort
    }

    private func saveAndStart() {
        guard let port = Int(portString) else { return }
        appState.serverPort = port
        appState.saveSettings()
        onSave()
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
