# iCloud Bridge - Photos Integration Design

## Overview

Extend iCloudBridge to expose iCloud Photos albums via REST API, following the same pattern as Reminders. Users select which albums to share through the settings UI, and those albums become available via read-only API endpoints for gallery and slideshow applications.

## Requirements

- **Platform:** macOS (same Mac Mini running iCloudBridge)
- **UI:** Extend existing settings window with Photos section
- **API:** Read-only REST API for albums and photos
- **Permissions:** PhotoKit read access (no write operations)
- **Media Types:** Photos, videos (streaming), and Live Photos (still + motion)
- **Thumbnails:** Two sizes (small: 200px, medium: 800px) plus full resolution
- **Metadata:** Comprehensive photo metadata (dates, location, camera info, etc.)
- **Albums:** Both user-created and built-in albums (Favorites, Recents, etc.)
- **iCloud Handling:** On-demand download with polling or blocking modes
- **Pagination:** Support for large albums with limit/offset
- **Sorting:** Client-specified ordering (album order, date ascending/descending)
- **Extensibility:** Integrate cleanly with existing Reminders bridge

## Architecture

### Technology Stack

- **Framework:** PhotoKit (Apple's Photos framework)
- **Image Processing:** PHImageManager for thumbnails and full-resolution images
- **Video Handling:** PHAssetResourceManager for video streaming
- **Integration:** Follows existing Reminders pattern (Service → Controllers → Routes)

### Component Structure

```
┌─────────────────────────────────────────────────────────┐
│                   Settings Window                        │
├──────────────────────┬──────────────────────────────────┤
│   Reminders Tab      │      Photos Tab (NEW)            │
│   ☑ Shopping List    │   ☑ Favorites                    │
│   ☑ Work Tasks       │   ☑ Family Trip 2024             │
│                      │   ☐ Screenshots                   │
│                      │   ☐ Recently Deleted              │
└──────────────────────┴──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│  Services Layer                                          │
│  ┌──────────────────┐     ┌──────────────────────┐      │
│  │ RemindersService │     │ PhotosService (NEW)  │      │
│  │ (EventKit)       │     │ (PhotoKit)           │      │
│  └──────────────────┘     └──────────────────────┘      │
└─────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│  API Controllers (Vapor)                                 │
│  /api/v1/lists          /api/v1/albums (NEW)             │
│  /api/v1/reminders      /api/v1/photos (NEW)             │
└─────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Parallel Structure:** Photos follows same pattern as Reminders (service, DTOs, controllers)
2. **Shared AppState:** Extend existing AppState with `selectedAlbumIds: Set<String>`
3. **Independent Operation:** Photos and Reminders can work independently
4. **Read-Only:** No write operations to Photos library (only GET endpoints)
5. **Memory Efficient:** Stream images/videos rather than loading all in memory

## API Design

### Base URL
`http://localhost:31337/api/v1`

### Albums Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/albums` | List all selected albums with photo counts |
| `GET` | `/albums/:id` | Single album details |
| `GET` | `/albums/:id/photos` | Photos in album (metadata only, paginated) |

### Photos Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/photos/:id` | Single photo metadata |
| `GET` | `/photos/:id/thumbnail` | Thumbnail image (query: `size=small\|medium`) |
| `GET` | `/photos/:id/image` | Full-resolution image (query: `wait=true\|false`) |
| `GET` | `/photos/:id/video` | Video file for videos and Live Photos |
| `GET` | `/photos/:id/live-video` | Motion component for Live Photos only |

### Query Parameters

**For `/albums/:id/photos`:**
- `limit` (int, default: 100) - Number of photos per page
- `offset` (int, default: 0) - Skip N photos
- `sort` (string, default: "album") - Options: `album`, `date-asc`, `date-desc`

**For `/photos/:id/thumbnail`:**
- `size` (string, default: "medium") - Options: `small` (200px), `medium` (800px)

**For `/photos/:id/image`:**
- `wait` (bool, default: false) - If true, block until download completes; if false, return 202 if not ready

## Data Models

### AlbumDTO
```json
{
  "id": "album-123",
  "title": "Family Trip 2024",
  "albumType": "user",
  "photoCount": 247,
  "videoCount": 18,
  "startDate": "2024-06-15T10:00:00Z",
  "endDate": "2024-06-22T18:30:00Z"
}
```

**Fields:**
- `id`: Album identifier
- `title`: Album name
- `albumType`: `"user"` or `"smart"` (smart = built-in like Favorites, Recents)
- `photoCount`: Number of photos in album
- `videoCount`: Number of videos in album
- `startDate`: Creation date of oldest asset (nullable)
- `endDate`: Creation date of newest asset (nullable)

### PhotoDTO (Metadata)
```json
{
  "id": "photo-456",
  "albumId": "album-123",
  "mediaType": "photo",
  "creationDate": "2024-06-16T14:23:00Z",
  "modificationDate": "2024-06-17T09:15:00Z",
  "width": 4032,
  "height": 3024,
  "isFavorite": true,
  "isHidden": false,
  "filename": "IMG_1234.HEIC",
  "fileSize": 3145728,
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194
  },
  "camera": {
    "make": "Apple",
    "model": "iPhone 15 Pro",
    "lens": "Main Camera"
  },
  "settings": {
    "iso": 200,
    "aperture": 1.8,
    "shutterSpeed": "1/120",
    "focalLength": 24
  }
}
```

**Media Types:**
- `"photo"` - Standard photo
- `"video"` - Video file
- `"livePhoto"` - Live Photo (has both still and motion)

**Nullable fields:** `modificationDate`, `location`, `camera`, `settings`, `filename`

## Error Handling & Response Codes

### HTTP Status Codes

**Success:**
- `200 OK` - Successful request with data
- `202 Accepted` - Full-resolution image requested but not yet downloaded from iCloud (when `wait=false`)
- `206 Partial Content` - Video streaming range request

**Client Errors:**
- `400 Bad Request` - Invalid parameters (e.g., invalid sort option)
- `404 Not Found` - Album/photo not found or not in selected albums
- `416 Range Not Satisfiable` - Invalid range header for video streaming

**Server Errors:**
- `500 Internal Server Error` - PhotoKit operation failed
- `503 Service Unavailable` - Photos access denied or not authorized

### Error Response Format
```json
{
  "error": true,
  "reason": "Album not found or not selected"
}
```

### Special Response for Pending Downloads

When `GET /photos/:id/image?wait=false` and photo isn't downloaded:
```json
{
  "status": "pending",
  "message": "Photo is being downloaded from iCloud",
  "retryAfter": 5
}
```
**HTTP 202 Accepted** with `Retry-After: 5` header

### Permission Handling

- If Photos access not granted → All photo endpoints return `503 Service Unavailable`
- Settings UI shows permission status and "Grant Access" button
- Similar flow to Reminders permission handling

## UI Design

### Settings Window Updates

**Tab-based interface:**
```
┌─────────────────────────────────────────────────────┐
│  iCloud Bridge Settings                             │
├─────────────────────────────────────────────────────┤
│  [Reminders] [Photos] [Server]                      │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Photos Access:  ✓ Access granted                   │
│                                                      │
│  Select Photo Albums:                               │
│  ┌──────────────────────────────────────────────┐   │
│  │ ☑ 📷 Favorites (245 items)                   │   │
│  │ ☑ 🌄 Family Trip 2024 (87 items)             │   │
│  │ ☐ 📸 Screenshots (1,234 items)               │   │
│  │ ☐ 🗑️  Recently Deleted (12 items)            │   │
│  │ ☑ ⭐ Best Photos (156 items)                 │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│                         [Save]                       │
└─────────────────────────────────────────────────────┘
```

**Tabs:**
1. **Reminders** - Existing reminder list selection
2. **Photos** (NEW) - Album selection with permission status
3. **Server** - Port configuration, moved from Reminders tab

### Menu Bar Updates

```
┌─────────────────────────┐
│ iCloud Bridge           │
├─────────────────────────┤
│ ● Server Running :31337 │
│ 3 lists · 47 reminders  │
│ 5 albums · 823 photos   │
├─────────────────────────┤
│ Open Settings...        │
│ Copy API URL            │
├─────────────────────────┤
│ Quit                    │
└─────────────────────────┘
```

### Permission Flow

1. User opens Photos tab → Check PhotoKit authorization status
2. If not authorized → Show "Grant Access" button
3. Click "Grant Access" → Request PhotoKit library access
4. If denied → Show "Open System Settings" button
5. If granted → Load albums and show selection UI

## Project Structure

### New Files to Create

```
Sources/iCloudBridge/
├── Services/
│   ├── RemindersService.swift          (existing)
│   ├── PhotosService.swift             (NEW)
│   └── ServerManager.swift             (existing)
├── API/
│   ├── ListsController.swift           (existing)
│   ├── RemindersController.swift       (existing)
│   ├── AlbumsController.swift          (NEW)
│   ├── PhotosController.swift          (NEW)
│   └── Routes.swift                    (modify)
├── Models/
│   ├── ReminderDTO.swift               (existing)
│   ├── ListDTO.swift                   (existing)
│   ├── AlbumDTO.swift                  (NEW)
│   └── PhotoDTO.swift                  (NEW)
├── Views/
│   ├── SettingsView.swift              (modify - add tabs)
│   ├── RemindersSettingsView.swift     (NEW - extract from SettingsView)
│   └── PhotosSettingsView.swift        (NEW)
└── iCloudBridgeApp.swift               (modify - menu bar stats)
```

### Modified Files

**AppState.swift** - Add:
- `@Published var selectedAlbumIds: Set<String>`
- `let photosService: PhotosService`
- Load/save methods for album selection

**Routes.swift** - Add:
- Register `AlbumsController`
- Register `PhotosController`

**Info.plist** - Add:
- `NSPhotoLibraryUsageDescription` permission string

### Python Client Updates

```
python/
└── icloudbridge.py                     (extend)
    - Add Album class
    - Add Photo class
    - Add get_albums(), get_photos(), etc.
    - Add thumbnail/image download methods
    - Add polling logic for pending downloads
```

## Implementation Considerations

### PhotoKit Key Concepts

**PHPhotoLibrary** - Main entry point, handles authorization
**PHAssetCollection** - Represents albums (both user and smart albums)
**PHAsset** - Represents individual photos/videos
**PHImageManager** - Handles thumbnail and image requests
**PHAssetResourceManager** - Handles video file access and streaming

### Critical Implementation Details

**1. Authorization**
- Use `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (read-only still requires readWrite enum)
- Check status with `PHPhotoLibrary.authorizationStatus(for: .readWrite)`
- Similar pattern to Reminders `EKEventStore`

**2. Image Request Options**
- Thumbnails: `PHImageRequestOptions` with `deliveryMode = .highQualityFormat`
- Full resolution: `deliveryMode = .highQualityFormat`, `isNetworkAccessAllowed = true`
- For iCloud downloads: Set `progressHandler` to track download

**3. Video Streaming**
- Use `PHAssetResourceManager.writeData()` to stream video bytes
- Support HTTP Range requests for video seeking
- Set proper `Content-Type` headers (video/mp4, video/quicktime)

**4. Live Photos**
- Live Photo = PHAsset with `mediaSubtypes.contains(.photoLive)`
- Still image: Request as normal photo
- Motion video: Use `PHAssetResource` to get video complement resource

**5. Memory Management**
- Don't cache full-resolution images in memory
- Stream directly to HTTP response
- Use `autoreleasepool` for batch operations

**6. Performance**
- Fetch album counts using `PHAsset.fetchAssets(in: collection, options: nil).count`
- Use `PHFetchResult` efficiently (it's lazy)
- Consider caching metadata DTOs (but not images)

**7. Background Downloads**
- When `wait=false`, start download in background task
- Store pending download state (simple in-memory dict of photo ID → download status)
- Client polls `/photos/:id/image` until ready

## Summary

This design extends iCloudBridge with Photos support following the established Reminders pattern. The implementation:

- Adds PhotoKit integration via `PhotosService`
- Provides comprehensive read-only API for albums and photos
- Supports thumbnails, full-resolution images, videos, and Live Photos
- Handles iCloud downloads with both async polling and blocking modes
- Extends UI with tabbed settings for Photos album selection
- Maintains architectural consistency with existing codebase
- Enables rich gallery/slideshow applications via the API

The modular design allows Photos to work independently of Reminders while sharing common infrastructure (AppState, ServerManager, Routes).
