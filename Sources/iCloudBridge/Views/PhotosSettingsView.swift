import SwiftUI
import Photos

struct PhotosSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Permission Status
            permissionSection

            Divider()

            // Albums Selection
            if appState.photosService.authorizationStatus == .authorized {
                albumsSection
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            Task {
                if appState.photosService.authorizationStatus != .authorized {
                    _ = await appState.photosService.requestAccess()
                } else {
                    await MainActor.run {
                        appState.photosService.loadAlbums()
                    }
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos Access")
                .font(.headline)

            HStack {
                switch appState.photosService.authorizationStatus {
                case .authorized:
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
                case .notDetermined, .limited:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.yellow)
                    Text("Permission required")
                    Spacer()
                    Button("Grant Access") {
                        Task {
                            _ = await appState.photosService.requestAccess()
                        }
                    }
                @unknown default:
                    Text("Unknown status")
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Photo Albums")
                .font(.headline)

            Text("Choose which albums to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.photosService.allAlbums, id: \.localIdentifier) { album in
                        Toggle(isOn: Binding(
                            get: { appState.isAlbumSelected(album.localIdentifier) },
                            set: { _ in appState.toggleAlbum(album.localIdentifier) }
                        )) {
                            HStack {
                                Text(album.localizedTitle ?? "Untitled")
                                Spacer()
                                Text(getAlbumType(album))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func getAlbumType(_ album: PHAssetCollection) -> String {
        return album.assetCollectionType == .album ? "User Album" : "Smart Album"
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}
