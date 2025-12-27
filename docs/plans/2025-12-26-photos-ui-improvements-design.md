# Photos Album UI Improvements Design

## Overview

Improve the Photos settings UI to better organize albums, support folder navigation, and include Shared Albums.

## Current Issues

1. **Shared Albums missing** - Cloud-shared albums not fetched
2. **No folder navigation** - Folders are skipped, nested albums inaccessible
3. **Random sort order** - No sorting applied to album list

## Design Decisions

| Decision | Choice |
|----------|--------|
| Organization | Grouped sections: My Albums, Shared Albums, Smart Albums |
| Sorting | Alphabetical by title within each section |
| Folder handling | Expandable folders in My Albums section |
| Shared albums | Include both owned and shared-with-me |

## Data Model Changes

Replace flat `[PHAssetCollection]` with hierarchical model:

```swift
struct AlbumItem {
    let collection: PHAssetCollection
    let photoCount: Int
}

struct FolderItem {
    let collectionList: PHCollectionList
    var albums: [AlbumItem]
    var isExpanded: Bool = false
}

struct AlbumHierarchy {
    var myAlbums: [AlbumItem]           // Top-level user albums
    var folders: [FolderItem]            // Folders with nested albums
    var sharedAlbums: [AlbumItem]        // Cloud shared albums
    var smartAlbums: [AlbumItem]         // System smart albums
}
```

## Album Loading Logic

### My Albums
Fetch top-level user collections, separating albums from folders:
```swift
let topLevel = PHCollectionList.fetchTopLevelUserCollections(with: nil)
// PHAssetCollection -> myAlbums
// PHCollectionList -> folders
```

### Folders
For each folder, fetch nested albums:
```swift
let contents = PHCollection.fetchCollections(in: folder, options: nil)
```

### Shared Albums
New fetch for cloud-shared albums:
```swift
PHAssetCollection.fetchAssetCollections(
    with: .album,
    subtype: .albumCloudShared,
    options: nil
)
```

### Smart Albums
Same as current - fetch specific useful subtypes (Favorites, Recently Added, Videos, etc.)

### Sorting & Filtering
- Each category sorted alphabetically by `localizedTitle`
- Exclude albums with zero assets

## Settings UI

```
┌─────────────────────────────────────────┐
│ Photos Access                           │
│ ✓ Access granted                        │
├─────────────────────────────────────────┤
│ Select Photo Albums                     │
│                                         │
│ ▼ My Albums (12)                        │
│   ☑ Family Photos                       │
│   ☐ Hiking Trips                        │
│   ▶ Vacation Photos (folder)            │
│       ☐ Hawaii 2023                     │
│       ☐ Paris 2024                      │
│   ☐ Work Events                         │
│                                         │
│ ▼ Shared Albums (3)                     │
│   ☐ Family Shared                       │
│   ☐ Wedding Photos                      │
│                                         │
│ ▼ Smart Albums (8)                      │
│   ☑ Favorites                           │
│   ☐ Recently Added                      │
│   ☐ Videos                              │
└─────────────────────────────────────────┘
```

### UI Behaviors
- Section headers collapsible with album count
- Folders have disclosure arrow, indent nested albums when expanded
- Folder expansion state persisted
- Album type badge removed (sections provide context)

## API Impact

No changes to REST API endpoints. One addition to AlbumDTO:

```swift
enum AlbumType: String, Codable {
    case user    // existing
    case smart   // existing
    case shared  // new - for cloud shared albums
}
```

## State Persistence

### Existing (unchanged)
- `selectedAlbumIds` in UserDefaults

### New persistence
```swift
@AppStorage("photosCollapsedSections")
private var collapsedSectionsData: Data = Data()

@AppStorage("photosExpandedFolders")
private var expandedFoldersData: Data = Data()
```

### Default states
- All sections expanded
- All folders collapsed
