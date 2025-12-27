# Photos UI Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the Photos settings UI with grouped sections, folder navigation, shared albums support, and alphabetical sorting.

**Architecture:** Replace flat album array with hierarchical AlbumHierarchy model. Update loadAlbums() to fetch shared albums and folder contents. Rebuild PhotosSettingsView with collapsible sections and expandable folders.

**Tech Stack:** SwiftUI, PhotoKit (PHCollectionList, PHAssetCollection), AppStorage for persistence

---

### Task 1: Define Album Hierarchy Data Models

**Files:**
- Create: `Sources/iCloudBridge/Models/AlbumHierarchy.swift`

**Step 1: Create the data model file**

```swift
import Photos

struct AlbumItem: Identifiable {
    let collection: PHAssetCollection
    let photoCount: Int

    var id: String { collection.localIdentifier }
    var title: String { collection.localizedTitle ?? "Untitled" }
}

struct FolderItem: Identifiable {
    let collectionList: PHCollectionList
    var albums: [AlbumItem]
    var isExpanded: Bool = false

    var id: String { collectionList.localIdentifier }
    var title: String { collectionList.localizedTitle ?? "Untitled Folder" }
}

struct AlbumHierarchy {
    var myAlbums: [AlbumItem] = []
    var folders: [FolderItem] = []
    var sharedAlbums: [AlbumItem] = []
    var smartAlbums: [AlbumItem] = []

    var myAlbumsCount: Int {
        myAlbums.count + folders.reduce(0) { $0 + $1.albums.count }
    }

    var allSelectableAlbums: [PHAssetCollection] {
        var all: [PHAssetCollection] = []
        all.append(contentsOf: myAlbums.map { $0.collection })
        for folder in folders {
            all.append(contentsOf: folder.albums.map { $0.collection })
        }
        all.append(contentsOf: sharedAlbums.map { $0.collection })
        all.append(contentsOf: smartAlbums.map { $0.collection })
        return all
    }
}
```

**Step 2: Commit**

```bash
git add Sources/iCloudBridge/Models/AlbumHierarchy.swift
git commit -m "feat: add AlbumHierarchy data models"
```

---

### Task 2: Update PhotosService with New Loading Logic

**Files:**
- Modify: `Sources/iCloudBridge/Services/PhotosService.swift`

**Step 1: Replace allAlbums with albumHierarchy**

Change the published property from:
```swift
@Published var allAlbums: [PHAssetCollection] = []
```

To:
```swift
@Published var albumHierarchy: AlbumHierarchy = AlbumHierarchy()
```

**Step 2: Add helper function for creating AlbumItem**

Add after the `pendingDownloads` property:
```swift
private func makeAlbumItem(from collection: PHAssetCollection) -> AlbumItem? {
    let count = PHAsset.fetchAssets(in: collection, options: nil).count
    guard count > 0 else { return nil }
    return AlbumItem(collection: collection, photoCount: count)
}
```

**Step 3: Rewrite loadAlbums() method**

Replace the entire `loadAlbums()` function with:
```swift
func loadAlbums() {
    var hierarchy = AlbumHierarchy()

    // 1. Fetch top-level user collections
    let topLevelCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)

    topLevelCollections.enumerateObjects { collection, _, _ in
        if let album = collection as? PHAssetCollection {
            // Top-level album
            if let item = self.makeAlbumItem(from: album) {
                hierarchy.myAlbums.append(item)
            }
        } else if let folder = collection as? PHCollectionList {
            // Folder - fetch its contents
            var folderAlbums: [AlbumItem] = []
            let contents = PHCollection.fetchCollections(in: folder, options: nil)
            contents.enumerateObjects { nested, _, _ in
                if let nestedAlbum = nested as? PHAssetCollection {
                    if let item = self.makeAlbumItem(from: nestedAlbum) {
                        folderAlbums.append(item)
                    }
                }
            }
            if !folderAlbums.isEmpty {
                folderAlbums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                hierarchy.folders.append(FolderItem(
                    collectionList: folder,
                    albums: folderAlbums
                ))
            }
        }
    }

    // 2. Fetch shared albums
    let sharedAlbums = PHAssetCollection.fetchAssetCollections(
        with: .album,
        subtype: .albumCloudShared,
        options: nil
    )
    sharedAlbums.enumerateObjects { collection, _, _ in
        if let item = self.makeAlbumItem(from: collection) {
            hierarchy.sharedAlbums.append(item)
        }
    }

    // 3. Fetch smart albums
    let usefulSmartAlbumSubtypes: [PHAssetCollectionSubtype] = [
        .smartAlbumFavorites,
        .smartAlbumRecentlyAdded,
        .smartAlbumVideos,
        .smartAlbumSelfPortraits,
        .smartAlbumPanoramas,
        .smartAlbumLivePhotos,
        .smartAlbumScreenshots,
        .smartAlbumBursts,
        .smartAlbumSlomoVideos,
        .smartAlbumTimelapses,
        .smartAlbumDepthEffect,
        .smartAlbumRAW,
        .smartAlbumCinematic
    ]

    for subtype in usefulSmartAlbumSubtypes {
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: subtype,
            options: nil
        )
        albums.enumerateObjects { collection, _, _ in
            if let item = self.makeAlbumItem(from: collection) {
                hierarchy.smartAlbums.append(item)
            }
        }
    }

    // 4. Sort all categories alphabetically
    hierarchy.myAlbums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    hierarchy.folders.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    hierarchy.sharedAlbums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    hierarchy.smartAlbums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

    self.albumHierarchy = hierarchy
}
```

**Step 4: Update getAlbums and getAlbum methods**

Replace:
```swift
func getAlbums(ids: [String]) -> [PHAssetCollection] {
    return allAlbums.filter { ids.contains($0.localIdentifier) }
}

func getAlbum(id: String) -> PHAssetCollection? {
    return allAlbums.first { $0.localIdentifier == id }
}
```

With:
```swift
func getAlbums(ids: [String]) -> [PHAssetCollection] {
    return albumHierarchy.allSelectableAlbums.filter { ids.contains($0.localIdentifier) }
}

func getAlbum(id: String) -> PHAssetCollection? {
    return albumHierarchy.allSelectableAlbums.first { $0.localIdentifier == id }
}
```

**Step 5: Commit**

```bash
git add Sources/iCloudBridge/Services/PhotosService.swift
git commit -m "feat: update PhotosService with hierarchical album loading"
```

---

### Task 3: Add Folder Toggle Method to PhotosService

**Files:**
- Modify: `Sources/iCloudBridge/Services/PhotosService.swift`

**Step 1: Add method to toggle folder expansion**

Add after `loadAlbums()`:
```swift
func toggleFolder(_ folderId: String) {
    if let index = albumHierarchy.folders.firstIndex(where: { $0.id == folderId }) {
        albumHierarchy.folders[index].isExpanded.toggle()
    }
}
```

**Step 2: Commit**

```bash
git add Sources/iCloudBridge/Services/PhotosService.swift
git commit -m "feat: add folder toggle method"
```

---

### Task 4: Update AlbumDTO with Shared Type

**Files:**
- Modify: `Sources/iCloudBridge/Models/AlbumDTO.swift`

**Step 1: Add shared case to AlbumType enum**

Find:
```swift
enum AlbumType: String, Codable {
    case user
    case smart
}
```

Replace with:
```swift
enum AlbumType: String, Codable {
    case user
    case smart
    case shared
}
```

**Step 2: Commit**

```bash
git add Sources/iCloudBridge/Models/AlbumDTO.swift
git commit -m "feat: add shared album type to AlbumDTO"
```

---

### Task 5: Update PhotosService DTO Conversion

**Files:**
- Modify: `Sources/iCloudBridge/Services/PhotosService.swift`

**Step 1: Update toDTO to detect shared albums**

Find the `toDTO(_ album:` method and replace:
```swift
let albumType: AlbumDTO.AlbumType = album.assetCollectionType == .album ? .user : .smart
```

With:
```swift
let albumType: AlbumDTO.AlbumType
if album.assetCollectionSubtype == .albumCloudShared {
    albumType = .shared
} else if album.assetCollectionType == .smartAlbum {
    albumType = .smart
} else {
    albumType = .user
}
```

**Step 2: Commit**

```bash
git add Sources/iCloudBridge/Services/PhotosService.swift
git commit -m "feat: detect shared albums in DTO conversion"
```

---

### Task 6: Add State Persistence for UI Expansion States

**Files:**
- Modify: `Sources/iCloudBridge/AppState.swift`

**Step 1: Add persistence properties**

Find the AppState class and add these properties after `selectedAlbumIds`:
```swift
@AppStorage("photosCollapsedSections") private var collapsedSectionsData: Data = Data()
@AppStorage("photosExpandedFolders") private var expandedFoldersData: Data = Data()

var collapsedSections: Set<String> {
    get {
        (try? JSONDecoder().decode(Set<String>.self, from: collapsedSectionsData)) ?? []
    }
    set {
        collapsedSectionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
}

var expandedFolders: Set<String> {
    get {
        (try? JSONDecoder().decode(Set<String>.self, from: expandedFoldersData)) ?? []
    }
    set {
        expandedFoldersData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
}

func toggleSection(_ section: String) {
    if collapsedSections.contains(section) {
        collapsedSections.remove(section)
    } else {
        collapsedSections.insert(section)
    }
}

func isSectionExpanded(_ section: String) -> Bool {
    !collapsedSections.contains(section)
}

func toggleFolderExpansion(_ folderId: String) {
    if expandedFolders.contains(folderId) {
        expandedFolders.remove(folderId)
    } else {
        expandedFolders.insert(folderId)
    }
}

func isFolderExpanded(_ folderId: String) -> Bool {
    expandedFolders.contains(folderId)
}
```

**Step 2: Commit**

```bash
git add Sources/iCloudBridge/AppState.swift
git commit -m "feat: add UI state persistence for sections and folders"
```

---

### Task 7: Rewrite PhotosSettingsView with Sections

**Files:**
- Modify: `Sources/iCloudBridge/Views/PhotosSettingsView.swift`

**Step 1: Replace the entire albumsSection computed property**

Replace the existing `albumsSection` with:
```swift
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
```

**Step 2: Add helper views**

Add these helper methods after `albumsSection`:
```swift
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
```

**Step 3: Remove the old getAlbumType helper**

Delete:
```swift
private func getAlbumType(_ album: PHAssetCollection) -> String {
    return album.assetCollectionType == .album ? "User Album" : "Smart Album"
}
```

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/Views/PhotosSettingsView.swift
git commit -m "feat: rewrite PhotosSettingsView with collapsible sections and folders"
```

---

### Task 8: Build and Verify

**Step 1: Build the project**

Run:
```bash
swift build
```

Expected: Build succeeds with no errors (warnings acceptable)

**Step 2: Commit any remaining changes**

If there were any compilation fixes needed:
```bash
git add -A
git commit -m "fix: compilation fixes for photos UI"
```

---

### Task 9: Create App Bundle

**Step 1: Build release version**

Run:
```bash
swift build -c release
```

**Step 2: Update app bundle**

Run:
```bash
cp .build/release/iCloudBridge ../iCloudBridge.app/Contents/MacOS/
```

**Step 3: Commit**

```bash
git add -A
git commit -m "build: release build with photos UI improvements"
```

---

### Task 10: Final Verification

**Step 1: Test the app**

Run:
```bash
open ../iCloudBridge.app
```

**Step 2: Verify in Settings > Photos tab:**
- [ ] "My Albums" section appears with collapsible header
- [ ] Folders appear with folder icon and expand on click
- [ ] Nested albums appear indented under folders
- [ ] "Shared Albums" section appears (if user has shared albums)
- [ ] "Smart Albums" section appears
- [ ] All lists sorted alphabetically
- [ ] Photo count shown next to each album
- [ ] Checkboxes work for album selection
- [ ] Section collapse/expand state persists after restart
- [ ] Folder expand state persists after restart

**Step 3: Report results**

Report any issues found during testing.
