import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as an accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}

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
            SettingsContentView(
                appState: appState,
                remindersService: appState.remindersService,
                photosService: appState.photosService,
                onSave: startServer
            )
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
            handleLaunch()
        }
    }

    private func handleLaunch() {
        if appState.hasAllPermissions && appState.hasSavedSettings {
            // Returning user with all permissions - auto-start server silently
            startServer()
        } else {
            // Missing permissions OR no saved settings - open window
            openWindow(id: "settings")
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

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    let onStartServer: () -> Void
    let onStopServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("iCloud Bridge")
                .font(.headline)

            Divider()

            statusSection

            Divider()

            Button("Open Settings...") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            if appState.serverStatus.isRunning {
                Button("Copy API URL") {
                    copyAPIUrl()
                }
            }

            Divider()

            if appState.serverStatus.isRunning {
                Button("Stop Server") {
                    onStopServer()
                }
            } else if appState.hasValidSettings {
                Button("Start Server") {
                    onStartServer()
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch appState.serverStatus {
            case .stopped:
                Label("Server stopped", systemImage: "circle.fill")
                    .foregroundColor(.secondary)
            case .starting:
                Label("Starting...", systemImage: "circle.fill")
                    .foregroundColor(.yellow)
            case .running(let port):
                Label("Running on port \(port)", systemImage: "circle.fill")
                    .foregroundColor(.green)

                if !appState.selectedListIds.isEmpty {
                    Text("\(appState.selectedListIds.count) lists selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !appState.selectedAlbumIds.isEmpty {
                    Text("\(appState.selectedAlbumIds.count) albums selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .error(let message):
                Label("Error", systemImage: "circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func copyAPIUrl() {
        if case .running(let port) = appState.serverStatus {
            let url = "http://localhost:\(port)/api/v1"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }
}
