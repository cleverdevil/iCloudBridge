import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .reminders
    @State private var portString: String = ""
    @State private var showingPortError: Bool = false

    enum Tab: Hashable {
        case reminders
        case photos
        case server
    }

    private var contentHeight: CGFloat {
        switch selectedTab {
        case .reminders:
            return 320
        case .photos:
            return 480
        case .server:
            return 200
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                RemindersSettingsView(appState: appState)
                    .tag(Tab.reminders)
                    .tabItem {
                        Label("Reminders", systemImage: "list.bullet.clipboard")
                    }

                PhotosSettingsView(appState: appState)
                    .tag(Tab.photos)
                    .tabItem {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                serverSettingsView
                    .tag(Tab.server)
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
        .frame(width: 500, height: contentHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
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
