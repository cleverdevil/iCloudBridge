import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var portString: String = ""
    @State private var showingPortError: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                RemindersSettingsView(appState: appState)
                    .tabItem {
                        Label("Reminders", systemImage: "list.bullet.clipboard")
                    }

                PhotosSettingsView(appState: appState)
                    .tabItem {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                serverSettingsView
                    .tabItem {
                        Label("Server", systemImage: "server.rack")
                    }
            }

            Divider()

            // Footer with Save button - visible on all tabs
            HStack {
                Spacer()
                Button("Save & Start Server") {
                    saveAndStart()
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 500, height: 480)
        .onAppear {
            portString = String(appState.serverPort)
        }
    }

    private var serverSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
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

                Text("Default: 31337")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var canSave: Bool {
        let hasLists = !appState.selectedListIds.isEmpty
        let hasAlbums = !appState.selectedAlbumIds.isEmpty
        return (hasLists || hasAlbums) && isValidPort
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
        dismiss()
    }
}
