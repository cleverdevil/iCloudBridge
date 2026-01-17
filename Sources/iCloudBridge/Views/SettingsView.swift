import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .reminders
    @State private var portString: String = ""
    @State private var showingPortError: Bool = false
    @State private var showingAddToken: Bool = false
    @State private var newTokenDescription: String = ""
    @State private var showingTokenCreated: Bool = false
    @State private var createdToken: String = ""
    @State private var showingRevokeConfirmation: Bool = false
    @State private var tokenToRevoke: APIToken?

    let tokenManager: TokenManager

    enum Tab: Hashable {
        case reminders
        case calendars
        case photos
        case server
    }

    private var contentHeight: CGFloat {
        switch selectedTab {
        case .reminders:
            return 320
        case .calendars:
            return 320
        case .photos:
            return 480
        case .server:
            return 400
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

                CalendarsSettingsView(appState: appState)
                    .tag(Tab.calendars)
                    .tabItem {
                        Label("Calendars", systemImage: "calendar")
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
        VStack(alignment: .leading, spacing: 16) {
            // Port configuration
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

            Divider()

            // Remote access toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow remote connections", isOn: $appState.allowRemoteConnections)

                Text("When enabled, the server binds to all network interfaces. Remote access requires a valid token.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Token management (shown when remote enabled)
            if appState.allowRemoteConnections {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Tokens")
                        .font(.headline)

                    if appState.apiTokens.isEmpty {
                        Text("No tokens configured. Remote clients won't be able to authenticate.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(appState.apiTokens) { token in
                            tokenRow(token)
                        }
                    }

                    Button("Add Token") {
                        showingAddToken = true
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingAddToken) {
            addTokenSheet
        }
        .sheet(isPresented: $showingTokenCreated) {
            TokenCreatedModal(token: createdToken) {
                showingTokenCreated = false
                createdToken = ""
            }
        }
        .alert("Revoke Token", isPresented: $showingRevokeConfirmation, presenting: tokenToRevoke) { token in
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task {
                    await revokeToken(token)
                }
            }
        } message: { token in
            Text("Revoke token '\(token.description)'? Any clients using this token will stop working.")
        }
    }

    private func tokenRow(_ token: APIToken) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(token.description)
                    .font(.body)
                Text("Created \(token.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Revoke") {
                tokenToRevoke = token
                showingRevokeConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }

    private var addTokenSheet: some View {
        VStack(spacing: 16) {
            Text("Add Access Token")
                .font(.headline)

            TextField("Description (e.g., Home Assistant)", text: $newTokenDescription)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    newTokenDescription = ""
                    showingAddToken = false
                }

                Button("Create Token") {
                    Task {
                        await createToken()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTokenDescription.isEmpty)
            }
        }
        .padding(24)
    }

    private func createToken() async {
        do {
            let (token, metadata) = try await tokenManager.createToken(description: newTokenDescription)
            await MainActor.run {
                appState.apiTokens.append(metadata)
                createdToken = token
                newTokenDescription = ""
                showingAddToken = false
                showingTokenCreated = true
            }
        } catch {
            print("Failed to create token: \(error)")
        }
    }

    private func revokeToken(_ token: APIToken) async {
        do {
            try await tokenManager.revokeToken(id: token.id)
            await MainActor.run {
                appState.apiTokens.removeAll { $0.id == token.id }
            }
        } catch {
            print("Failed to revoke token: \(error)")
        }
    }

    private var canSave: Bool {
        let hasLists = !appState.selectedListIds.isEmpty
        let hasAlbums = !appState.selectedAlbumIds.isEmpty
        let hasCalendars = !appState.selectedCalendarIds.isEmpty
        return (hasLists || hasAlbums || hasCalendars) && isValidPort
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
