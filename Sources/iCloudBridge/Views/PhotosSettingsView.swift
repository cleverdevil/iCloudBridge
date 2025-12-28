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
            if appState.photosService.authorizationStatus == .authorized {
                appState.photosService.loadAlbums()
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
                VStack(alignment: .leading, spacing: 0) {
                    // My Albums Section
                    sectionHeader("My Albums", count: appState.photosService.albumHierarchy.myAlbumsCount, section: "myAlbums")
                    if appState.isSectionExpanded("myAlbums") {
                        myAlbumsContent
                    }

                    // Shared Albums Section
                    if !appState.photosService.albumHierarchy.sharedAlbums.isEmpty {
                        sectionHeader("Shared Albums", count: appState.photosService.albumHierarchy.sharedAlbums.count, section: "sharedAlbums")
                        if appState.isSectionExpanded("sharedAlbums") {
                            albumList(appState.photosService.albumHierarchy.sharedAlbums, indent: 1)
                        }
                    }

                    // Smart Albums Section
                    sectionHeader("Smart Albums", count: appState.photosService.albumHierarchy.smartAlbums.count, section: "smartAlbums")
                    if appState.isSectionExpanded("smartAlbums") {
                        albumList(appState.photosService.albumHierarchy.smartAlbums, indent: 1)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }

    private func sectionHeader(_ title: String, count: Int, section: String) -> some View {
        Button(action: { appState.toggleSection(section) }) {
            HStack {
                Image(systemName: appState.isSectionExpanded(section) ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 12)
                Text(title)
                    .fontWeight(.medium)
                Text("(\(count))")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.1))
    }

    private var myAlbumsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top-level albums
            albumList(appState.photosService.albumHierarchy.myAlbums, indent: 1)

            // Folders
            ForEach(appState.photosService.albumHierarchy.folders) { folder in
                folderRow(folder)
            }
        }
    }

    private func folderRow(_ folder: FolderItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { appState.toggleFolderExpansion(folder.id) }) {
                HStack {
                    Image(systemName: appState.isFolderExpanded(folder.id) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    Text(folder.title)
                    Text("(\(folder.albums.count))")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.leading, 20)

            if appState.isFolderExpanded(folder.id) {
                albumList(folder.albums, indent: 2)
            }
        }
    }

    private func albumList(_ albums: [AlbumItem], indent: Int) -> some View {
        ForEach(albums) { album in
            albumRow(album, indent: indent)
        }
    }

    private func albumRow(_ album: AlbumItem, indent: Int) -> some View {
        Toggle(isOn: Binding(
            get: { appState.isAlbumSelected(album.id) },
            set: { _ in appState.toggleAlbum(album.id) }
        )) {
            HStack {
                Text(album.title)
                Spacer()
                Text("\(album.photoCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(indent * 20))
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}
