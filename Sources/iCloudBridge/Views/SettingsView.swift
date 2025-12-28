import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .reminders
    @State private var portString: String = ""
    @State private var showingPortError: Bool = false

    enum Tab {
        case reminders
        case photos
        case server
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("iCloud Bridge Settings")
                .font(.title)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Reminders").tag(Tab.reminders)
                Text("Photos").tag(Tab.photos)
                Text("Server").tag(Tab.server)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()

            // Tab Content
            TabView(selection: $selectedTab) {
                RemindersSettingsView(appState: appState)
                    .tag(Tab.reminders)

                PhotosSettingsView(appState: appState)
                    .tag(Tab.photos)

                serverSettingsView
                    .tag(Tab.server)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Footer with Save button
            HStack {
                Spacer()
                Button("Save & Start Server") {
                    saveAndStart()
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            portString = String(appState.serverPort)
        }
    }

    private var serverSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Server Configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Server Port")
                    .font(.subheadline)

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
