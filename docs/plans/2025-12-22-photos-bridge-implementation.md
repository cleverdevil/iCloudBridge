# Photos Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend iCloudBridge with PhotoKit integration to expose iCloud Photos albums via REST API for gallery and slideshow applications.

**Architecture:** Follows existing Reminders pattern with PhotosService wrapping PhotoKit, new controllers for albums/photos endpoints, tab-based settings UI, and Python client extensions. Supports photos, videos, Live Photos with thumbnails and full-resolution streaming.

**Tech Stack:** Swift 5.9+, SwiftUI, PhotoKit, Vapor 4, Python 3

---

### Task 1: Data Models (DTOs)

**Files:**
- Create: `Sources/iCloudBridge/Models/AlbumDTO.swift`
- Create: `Sources/iCloudBridge/Models/PhotoDTO.swift`

**Step 1: Create AlbumDTO**

Create `Sources/iCloudBridge/Models/AlbumDTO.swift`:

```swift
import Foundation
import Vapor

struct AlbumDTO: Content {
    let id: String
    let title: String
    let albumType: AlbumType
    let photoCount: Int
    let videoCount: Int
    let startDate: Date?
    let endDate: Date?

    enum AlbumType: String, Codable {
        case user
        case smart
    }
}
```

**Step 2: Create PhotoDTO with nested types**

Create `Sources/iCloudBridge/Models/PhotoDTO.swift`:

```swift
import Foundation
import Vapor

struct PhotoDTO: Content {
    let id: String
    let albumId: String
    let mediaType: MediaType
    let creationDate: Date
    let modificationDate: Date?
    let width: Int
    let height: Int
    let isFavorite: Bool
    let isHidden: Bool
    let filename: String?
    let fileSize: Int64?
    let location: Location?
    let camera: Camera?
    let settings: CameraSettings?

    enum MediaType: String, Codable {
        case photo
        case video
        case livePhoto
    }

    struct Location: Codable {
        let latitude: Double
        let longitude: Double
    }

    struct Camera: Codable {
        let make: String?
        let model: String?
        let lens: String?
    }

    struct CameraSettings: Codable {
        let iso: Int?
        let aperture: Double?
        let shutterSpeed: String?
        let focalLength: Double?
    }
}

struct PhotosListResponse: Content {
    let photos: [PhotoDTO]
    let total: Int
    let limit: Int
    let offset: Int
}

struct PendingDownloadResponse: Content {
    let status: String
    let message: String
    let retryAfter: Int
}
```

**Step 3: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/Models/AlbumDTO.swift Sources/iCloudBridge/Models/PhotoDTO.swift
git commit -m "feat: add Photos DTOs for API responses"
```

---

### Task 2: PhotosService (PhotoKit Wrapper)

**Files:**
- Create: `Sources/iCloudBridge/Services/PhotosService.swift`

**Step 1: Create PhotosService skeleton**

Create `Sources/iCloudBridge/Services/PhotosService.swift`:

```swift
import Photos
import Foundation
import AppKit

enum PhotosError: Error, LocalizedError {
    case accessDenied
    case albumNotFound(String)
    case photoNotFound(String)
    case downloadFailed(String)
    case invalidParameter(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to Photos was denied"
        case .albumNotFound(let id):
            return "Album not found: \(id)"
        case .photoNotFound(let id):
            return "Photo not found: \(id)"
        case .downloadFailed(let reason):
            return "Failed to download: \(reason)"
        case .invalidParameter(let param):
            return "Invalid parameter: \(param)"
        }
    }
}

@MainActor
class PhotosService: ObservableObject {
    private let imageManager = PHCachingImageManager()

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allAlbums: [PHAssetCollection] = []

    // Track pending downloads
    private var pendingDownloads: [String: Bool] = [:]

    init() {
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            updateAuthorizationStatus()
            if status == .authorized {
                loadAlbums()
            }
        }
        return status == .authorized
    }

    func loadAlbums() {
        allAlbums.removeAll()

        // Fetch user albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            self.allAlbums.append(collection)
        }

        // Fetch smart albums
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            self.allAlbums.append(collection)
        }
    }
}
```

**Step 2: Add album operations**

Add to `PhotosService`:

```swift
    // MARK: - Album Operations

    func getAlbums(ids: [String]) -> [PHAssetCollection] {
        return allAlbums.filter { ids.contains($0.localIdentifier) }
    }

    func getAlbum(id: String) -> PHAssetCollection? {
        return allAlbums.first { $0.localIdentifier == id }
    }

    func getAssets(in album: PHAssetCollection, limit: Int = 100, offset: Int = 0, sort: String = "album") -> (assets: [PHAsset], total: Int) {
        let fetchOptions = PHFetchOptions()

        // Configure sorting
        switch sort {
        case "date-asc":
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        case "date-desc":
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        default:
            // "album" - use default album order (no sort descriptor)
            break
        }

        let allAssets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        let total = allAssets.count

        var assets: [PHAsset] = []
        let endIndex = min(offset + limit, total)

        for index in offset..<endIndex {
            assets.append(allAssets.object(at: index))
        }

        return (assets, total)
    }

    func getAsset(id: String) -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: fetchOptions)
        return result.firstObject
    }

    func getAlbumCounts(album: PHAssetCollection) -> (photos: Int, videos: Int) {
        let allAssets = PHAsset.fetchAssets(in: album, options: nil)
        var photoCount = 0
        var videoCount = 0

        allAssets.enumerateObjects { asset, _, _ in
            switch asset.mediaType {
            case .image:
                photoCount += 1
            case .video:
                videoCount += 1
            default:
                break
            }
        }

        return (photoCount, videoCount)
    }

    func getAlbumDateRange(album: PHAssetCollection) -> (start: Date?, end: Date?) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)

        guard assets.count > 0 else {
            return (nil, nil)
        }

        let startDate = assets.firstObject?.creationDate
        let endDate = assets.lastObject?.creationDate

        return (startDate, endDate)
    }
```

**Step 3: Add image/thumbnail operations**

Add to `PhotosService`:

```swift
    // MARK: - Image Operations

    enum ThumbnailSize {
        case small  // 200x200
        case medium // 800x800

        var dimension: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 800
            }
        }
    }

    func getThumbnail(for asset: PHAsset, size: ThumbnailSize) async throws -> Data {
        let targetSize = CGSize(width: size.dimension, height: size.dimension)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                guard let image = image else {
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: PhotosError.downloadFailed(error.localizedDescription))
                    } else {
                        continuation.resume(throwing: PhotosError.downloadFailed("Unknown error"))
                    }
                    return
                }

                guard let data = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: data),
                      let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                    continuation.resume(throwing: PhotosError.downloadFailed("Failed to encode image"))
                    return
                }

                continuation.resume(returning: jpegData)
            }
        }
    }

    func getFullImage(for asset: PHAsset, wait: Bool) async throws -> Data {
        let assetId = asset.localIdentifier

        // Check if already downloading
        if !wait && pendingDownloads[assetId] == true {
            throw PhotosError.downloadFailed("Download already in progress")
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        if !wait {
            // Check if asset is available locally
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first else {
                throw PhotosError.downloadFailed("No resources found")
            }

            // For non-blocking mode, do a quick check
            options.progressHandler = { progress, error, stop, info in
                // Track that download started
                Task { @MainActor in
                    self.pendingDownloads[assetId] = true
                }
            }
        }

        pendingDownloads[assetId] = true

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                Task { @MainActor in
                    self.pendingDownloads.removeValue(forKey: assetId)
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: PhotosError.downloadFailed(error.localizedDescription))
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: PhotosError.downloadFailed("No image data"))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    func isDownloadPending(assetId: String) -> Bool {
        return pendingDownloads[assetId] ?? false
    }
```

**Step 4: Add video operations**

Add to `PhotosService`:

```swift
    // MARK: - Video Operations

    func getVideo(for asset: PHAsset) async throws -> URL {
        guard asset.mediaType == .video || asset.mediaSubtypes.contains(.photoLive) else {
            throw PhotosError.invalidParameter("Asset is not a video")
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: PhotosError.downloadFailed(error.localizedDescription))
                    return
                }

                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: PhotosError.downloadFailed("Could not get video URL"))
                    return
                }

                continuation.resume(returning: urlAsset.url)
            }
        }
    }

    func getLivePhotoVideo(for asset: PHAsset) async throws -> URL {
        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw PhotosError.invalidParameter("Asset is not a Live Photo")
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
            throw PhotosError.downloadFailed("No Live Photo video component found")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: videoResource, toFile: tempURL, options: options) { error in
                if let error = error {
                    continuation.resume(throwing: PhotosError.downloadFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: tempURL)
                }
            }
        }
    }
```

**Step 5: Add DTO conversion methods**

Add to `PhotosService`:

```swift
    // MARK: - DTO Conversions

    func toDTO(_ album: PHAssetCollection, photoCount: Int, videoCount: Int, dateRange: (Date?, Date?)) -> AlbumDTO {
        let albumType: AlbumDTO.AlbumType = album.assetCollectionType == .album ? .user : .smart

        return AlbumDTO(
            id: album.localIdentifier,
            title: album.localizedTitle ?? "Untitled",
            albumType: albumType,
            photoCount: photoCount,
            videoCount: videoCount,
            startDate: dateRange.0,
            endDate: dateRange.1
        )
    }

    func toDTO(_ asset: PHAsset, albumId: String) -> PhotoDTO {
        let mediaType: PhotoDTO.MediaType
        if asset.mediaSubtypes.contains(.photoLive) {
            mediaType = .livePhoto
        } else if asset.mediaType == .video {
            mediaType = .video
        } else {
            mediaType = .photo
        }

        var location: PhotoDTO.Location? = nil
        if let loc = asset.location {
            location = PhotoDTO.Location(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        }

        // Extract camera metadata
        let resources = PHAssetResource.assetResources(for: asset)
        let filename = resources.first?.originalFilename

        // Get EXIF data if available
        var camera: PhotoDTO.Camera? = nil
        var settings: PhotoDTO.CameraSettings? = nil

        // Note: Full EXIF data requires requesting image data, which we'll skip for metadata-only
        // Could be enhanced to fetch this on-demand if needed

        return PhotoDTO(
            id: asset.localIdentifier,
            albumId: albumId,
            mediaType: mediaType,
            creationDate: asset.creationDate ?? Date(),
            modificationDate: asset.modificationDate,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            filename: filename,
            fileSize: resources.first.map { Int64($0.value(forKey: "fileSize") as? Int ?? 0) },
            location: location,
            camera: camera,
            settings: settings
        )
    }
```

**Step 6: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 7: Commit**

```bash
git add Sources/iCloudBridge/Services/PhotosService.swift
git commit -m "feat: add PhotosService for PhotoKit operations"
```

---

### Task 3: Update AppState

**Files:**
- Modify: `Sources/iCloudBridge/AppState.swift`

**Step 1: Add Photos properties to AppState**

Modify `Sources/iCloudBridge/AppState.swift`:

Add after `let remindersService: RemindersService`:

```swift
    let photosService: PhotosService
```

Add after `@Published var selectedListIds: Set<String> = []`:

```swift
    @Published var selectedAlbumIds: Set<String> = []
```

Add after `private let serverPortKey = "serverPort"`:

```swift
    private let selectedAlbumIdsKey = "selectedAlbumIds"
```

**Step 2: Update init method**

Replace the init method:

```swift
    init(remindersService: RemindersService = RemindersService(), photosService: PhotosService = PhotosService()) {
        self.remindersService = remindersService
        self.photosService = photosService
        loadSettings()
    }
```

**Step 3: Update loadSettings method**

Add to `loadSettings()` method before the closing brace:

```swift
        if let savedAlbumIds = UserDefaults.standard.array(forKey: selectedAlbumIdsKey) as? [String] {
            selectedAlbumIds = Set(savedAlbumIds)
        }
```

**Step 4: Update saveSettings method**

Add to `saveSettings()` method before the closing brace:

```swift
        UserDefaults.standard.set(Array(selectedAlbumIds), forKey: selectedAlbumIdsKey)
```

**Step 5: Add album selection methods**

Add after the `isListSelected` method:

```swift
    // MARK: - Album Selection

    func toggleAlbum(_ id: String) {
        if selectedAlbumIds.contains(id) {
            selectedAlbumIds.remove(id)
        } else {
            selectedAlbumIds.insert(id)
        }
    }

    func isAlbumSelected(_ id: String) -> Bool {
        return selectedAlbumIds.contains(id)
    }

    var selectedAlbums: [String] {
        return Array(selectedAlbumIds)
    }
```

**Step 6: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 7: Commit**

```bash
git add Sources/iCloudBridge/AppState.swift
git commit -m "feat: extend AppState with Photos support"
```

---

### Task 4: API Controllers

**Files:**
- Create: `Sources/iCloudBridge/API/AlbumsController.swift`
- Create: `Sources/iCloudBridge/API/PhotosController.swift`

**Step 1: Create AlbumsController**

Create `Sources/iCloudBridge/API/AlbumsController.swift`:

```swift
import Vapor
import Photos

struct AlbumsController: RouteCollection {
    let photosService: PhotosService
    let selectedAlbumIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let albums = routes.grouped("albums")
        albums.get(use: index)
        albums.get(":albumId", use: show)
        albums.get(":albumId", "photos", use: photos)
    }

    @Sendable
    func index(req: Request) async throws -> [AlbumDTO] {
        let ids = selectedAlbumIds()
        let albums = await MainActor.run {
            photosService.getAlbums(ids: ids)
        }

        var result: [AlbumDTO] = []
        for album in albums {
            let counts = await MainActor.run {
                photosService.getAlbumCounts(album: album)
            }
            let dateRange = await MainActor.run {
                photosService.getAlbumDateRange(album: album)
            }
            let dto = await MainActor.run {
                photosService.toDTO(album, photoCount: counts.photos, videoCount: counts.videos, dateRange: dateRange)
            }
            result.append(dto)
        }

        return result
    }

    @Sendable
    func show(req: Request) async throws -> AlbumDTO {
        guard let albumId = req.parameters.get("albumId") else {
            throw Abort(.badRequest, reason: "Missing album ID")
        }

        let ids = selectedAlbumIds()
        guard ids.contains(albumId) else {
            throw Abort(.notFound, reason: "Album not found or not selected")
        }

        guard let album = await MainActor.run(body: { photosService.getAlbum(id: albumId) }) else {
            throw Abort(.notFound, reason: "Album not found")
        }

        let counts = await MainActor.run {
            photosService.getAlbumCounts(album: album)
        }
        let dateRange = await MainActor.run {
            photosService.getAlbumDateRange(album: album)
        }

        return await MainActor.run {
            photosService.toDTO(album, photoCount: counts.photos, videoCount: counts.videos, dateRange: dateRange)
        }
    }

    @Sendable
    func photos(req: Request) async throws -> PhotosListResponse {
        guard let albumId = req.parameters.get("albumId") else {
            throw Abort(.badRequest, reason: "Missing album ID")
        }

        let ids = selectedAlbumIds()
        guard ids.contains(albumId) else {
            throw Abort(.notFound, reason: "Album not found or not selected")
        }

        guard let album = await MainActor.run(body: { photosService.getAlbum(id: albumId) }) else {
            throw Abort(.notFound, reason: "Album not found")
        }

        // Get query parameters
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 100
        let offset = (try? req.query.get(Int.self, at: "offset")) ?? 0
        let sort = (try? req.query.get(String.self, at: "sort")) ?? "album"

        // Validate sort parameter
        guard ["album", "date-asc", "date-desc"].contains(sort) else {
            throw Abort(.badRequest, reason: "Invalid sort parameter. Must be: album, date-asc, or date-desc")
        }

        let result = await MainActor.run {
            photosService.getAssets(in: album, limit: limit, offset: offset, sort: sort)
        }

        let photoDTOs = await MainActor.run {
            result.assets.map { photosService.toDTO($0, albumId: albumId) }
        }

        return PhotosListResponse(
            photos: photoDTOs,
            total: result.total,
            limit: limit,
            offset: offset
        )
    }
}
```

**Step 2: Create PhotosController**

Create `Sources/iCloudBridge/API/PhotosController.swift`:

```swift
import Vapor
import Photos

struct PhotosController: RouteCollection {
    let photosService: PhotosService
    let selectedAlbumIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let photos = routes.grouped("photos")
        photos.get(":photoId", use: show)
        photos.get(":photoId", "thumbnail", use: thumbnail)
        photos.get(":photoId", "image", use: image)
        photos.get(":photoId", "video", use: video)
        photos.get(":photoId", "live-video", use: liveVideo)
    }

    @Sendable
    func show(req: Request) async throws -> PhotoDTO {
        guard let photoId = req.parameters.get("photoId") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        guard let asset = await MainActor.run(body: { photosService.getAsset(id: photoId) }) else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        // Verify asset belongs to a selected album
        let albumIds = selectedAlbumIds()
        // Note: PHAsset doesn't directly expose album membership, so we'll trust the ID for now
        // In production, you might want to verify this more strictly

        // Get the album ID from asset collections
        var foundAlbumId: String?
        let collections = await MainActor.run {
            PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        }

        await MainActor.run {
            collections.enumerateObjects { collection, _, stop in
                if albumIds.contains(collection.localIdentifier) {
                    foundAlbumId = collection.localIdentifier
                    stop.pointee = true
                }
            }
        }

        guard let albumId = foundAlbumId else {
            throw Abort(.notFound, reason: "Photo not found in selected albums")
        }

        return await MainActor.run {
            photosService.toDTO(asset, albumId: albumId)
        }
    }

    @Sendable
    func thumbnail(req: Request) async throws -> Response {
        guard let photoId = req.parameters.get("photoId") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        guard let asset = await MainActor.run(body: { photosService.getAsset(id: photoId) }) else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        let sizeParam = (try? req.query.get(String.self, at: "size")) ?? "medium"
        let size: PhotosService.ThumbnailSize

        switch sizeParam {
        case "small":
            size = .small
        case "medium":
            size = .medium
        default:
            throw Abort(.badRequest, reason: "Invalid size parameter. Must be: small or medium")
        }

        let imageData = try await photosService.getThumbnail(for: asset, size: size)

        return Response(
            status: .ok,
            headers: HTTPHeaders([("Content-Type", "image/jpeg")]),
            body: .init(data: imageData)
        )
    }

    @Sendable
    func image(req: Request) async throws -> Response {
        guard let photoId = req.parameters.get("photoId") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        guard let asset = await MainActor.run(body: { photosService.getAsset(id: photoId) }) else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        let wait = (try? req.query.get(Bool.self, at: "wait")) ?? false

        // Check if download is pending
        let isPending = await MainActor.run {
            photosService.isDownloadPending(assetId: photoId)
        }

        if !wait && isPending {
            let response = PendingDownloadResponse(
                status: "pending",
                message: "Photo is being downloaded from iCloud",
                retryAfter: 5
            )
            return try await response.encodeResponse(status: .accepted, headers: HTTPHeaders([("Retry-After", "5")]), for: req)
        }

        do {
            let imageData = try await photosService.getFullImage(for: asset, wait: wait)

            // Determine content type from data
            let contentType: String
            if imageData.starts(with: [0xFF, 0xD8, 0xFF]) {
                contentType = "image/jpeg"
            } else if imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                contentType = "image/png"
            } else {
                contentType = "application/octet-stream"
            }

            return Response(
                status: .ok,
                headers: HTTPHeaders([("Content-Type", contentType)]),
                body: .init(data: imageData)
            )
        } catch {
            if !wait {
                // Download not ready, return 202
                let response = PendingDownloadResponse(
                    status: "pending",
                    message: "Photo is being downloaded from iCloud",
                    retryAfter: 5
                )
                return try await response.encodeResponse(status: .accepted, headers: HTTPHeaders([("Retry-After", "5")]), for: req)
            } else {
                throw error
            }
        }
    }

    @Sendable
    func video(req: Request) async throws -> Response {
        guard let photoId = req.parameters.get("photoId") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        guard let asset = await MainActor.run(body: { photosService.getAsset(id: photoId) }) else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        guard asset.mediaType == .video || asset.mediaSubtypes.contains(.photoLive) else {
            throw Abort(.badRequest, reason: "Asset is not a video or Live Photo")
        }

        let videoURL = try await photosService.getVideo(for: asset)

        // Stream the video file
        return req.fileio.streamFile(at: videoURL.path)
    }

    @Sendable
    func liveVideo(req: Request) async throws -> Response {
        guard let photoId = req.parameters.get("photoId") else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        guard let asset = await MainActor.run(body: { photosService.getAsset(id: photoId) }) else {
            throw Abort(.notFound, reason: "Photo not found")
        }

        guard asset.mediaSubtypes.contains(.photoLive) else {
            throw Abort(.badRequest, reason: "Asset is not a Live Photo")
        }

        let videoURL = try await photosService.getLivePhotoVideo(for: asset)

        // Stream the live photo video component
        return req.fileio.streamFile(at: videoURL.path)
    }
}
```

**Step 3: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/API/AlbumsController.swift Sources/iCloudBridge/API/PhotosController.swift
git commit -m "feat: add Albums and Photos API controllers"
```

---

### Task 5: Update Routes

**Files:**
- Modify: `Sources/iCloudBridge/API/Routes.swift`

**Step 1: Add Photos controller registration**

Modify `Sources/iCloudBridge/API/Routes.swift`:

Update the function signature to include photosService:

```swift
func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String]
) throws {
```

Add after the RemindersController registration:

```swift
    try api.register(collection: AlbumsController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: PhotosController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))
```

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build fails (ServerManager needs updating)

**Step 3: Update ServerManager to pass photosService**

Modify `Sources/iCloudBridge/Services/ServerManager.swift`:

Update the actor to include photosService:

```swift
actor ServerManager {
    private var app: Application?
    private let remindersService: RemindersService
    private let photosService: PhotosService
    private let selectedListIds: () -> [String]
    private let selectedAlbumIds: () -> [String]

    init(
        remindersService: RemindersService,
        photosService: PhotosService,
        selectedListIds: @escaping () -> [String],
        selectedAlbumIds: @escaping () -> [String]
    ) {
        self.remindersService = remindersService
        self.photosService = photosService
        self.selectedListIds = selectedListIds
        self.selectedAlbumIds = selectedAlbumIds
    }
```

Update the configureRoutes call in the `start` method:

```swift
        try configureRoutes(
            newApp,
            remindersService: remindersService,
            photosService: photosService,
            selectedListIds: selectedListIds,
            selectedAlbumIds: selectedAlbumIds
        )
```

**Step 4: Verify build**

Run:
```bash
swift build
```

Expected: Build fails (iCloudBridgeApp needs updating)

**Step 5: Update iCloudBridgeApp to pass photosService**

Modify `Sources/iCloudBridge/iCloudBridgeApp.swift`:

Update the `startServer()` method's ServerManager initialization:

```swift
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
```

**Step 6: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 7: Commit**

```bash
git add Sources/iCloudBridge/API/Routes.swift Sources/iCloudBridge/Services/ServerManager.swift Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: integrate Photos controllers into routing"
```

---

### Task 6: UI Refactoring - Tab-Based Settings

**Files:**
- Create: `Sources/iCloudBridge/Views/RemindersSettingsView.swift`
- Create: `Sources/iCloudBridge/Views/PhotosSettingsView.swift`
- Modify: `Sources/iCloudBridge/Views/SettingsView.swift`

**Step 1: Extract RemindersSettingsView**

Create `Sources/iCloudBridge/Views/RemindersSettingsView.swift`:

```swift
import SwiftUI
import EventKit

struct RemindersSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Permission Status
            permissionSection

            Divider()

            // Lists Selection
            if appState.remindersService.authorizationStatus == .fullAccess {
                listsSection
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            Task {
                if appState.remindersService.authorizationStatus != .fullAccess {
                    _ = await appState.remindersService.requestAccess()
                } else {
                    appState.remindersService.loadLists()
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders Access")
                .font(.headline)

            HStack {
                switch appState.remindersService.authorizationStatus {
                case .fullAccess:
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
                case .notDetermined, .writeOnly:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.yellow)
                    Text("Permission required")
                    Spacer()
                    Button("Grant Access") {
                        Task {
                            _ = await appState.remindersService.requestAccess()
                        }
                    }
                @unknown default:
                    Text("Unknown status")
                }
            }
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Reminders Lists")
                .font(.headline)

            Text("Choose which lists to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.remindersService.allLists, id: \.calendarIdentifier) { list in
                        Toggle(isOn: Binding(
                            get: { appState.isListSelected(list.calendarIdentifier) },
                            set: { _ in appState.toggleList(list.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: list.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(list.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Step 2: Create PhotosSettingsView**

Create `Sources/iCloudBridge/Views/PhotosSettingsView.swift`:

```swift
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
```

**Step 3: Refactor SettingsView with tabs**

Replace `Sources/iCloudBridge/Views/SettingsView.swift` with:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void

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
    }
}
```

**Step 4: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add Sources/iCloudBridge/Views/RemindersSettingsView.swift Sources/iCloudBridge/Views/PhotosSettingsView.swift Sources/iCloudBridge/Views/SettingsView.swift
git commit -m "feat: refactor settings UI with tabs for Reminders/Photos/Server"
```

---

### Task 7: Update Menu Bar

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Update menu bar stats**

In `Sources/iCloudBridge/iCloudBridgeApp.swift`, find the `MenuBarContentView` and update the `statusSection`:

Replace the `.running` case with:

```swift
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
```

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: update menu bar to show Photos stats"
```

---

### Task 8: Update Info.plist

**Files:**
- Modify: `Sources/iCloudBridge/Resources/Info.plist` (or create if in different location)

**Step 1: Add Photos usage description**

Check where Info.plist is located:

Run:
```bash
find . -name "Info.plist" -not -path "./.build/*"
```

Expected: Shows location of Info.plist file

**Step 2: Add NSPhotoLibraryUsageDescription**

Edit the Info.plist file and add after `NSRemindersUsageDescription`:

```xml
    <key>NSPhotoLibraryUsageDescription</key>
    <string>iCloud Bridge needs access to Photos to expose albums via the REST API.</string>
```

**Step 3: Verify the complete Info.plist**

The file should look like:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSRemindersUsageDescription</key>
    <string>iCloud Bridge needs access to Reminders to expose them via the REST API.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>iCloud Bridge needs access to Photos to expose albums via the REST API.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

**Step 4: Commit**

```bash
git add iCloudBridge.app/Contents/Info.plist
git commit -m "feat: add Photos permission to Info.plist"
```

---

### Task 9: Python Client Extensions

**Files:**
- Modify: `python/icloudbridge.py`

**Step 1: Add Album and Photo classes**

Add after the `ReminderList` class:

```python
@dataclass
class Album:
    """Represents a photo album."""
    id: str
    title: str
    album_type: str
    photo_count: int
    video_count: int
    start_date: Optional[datetime]
    end_date: Optional[datetime]

    @classmethod
    def from_dict(cls, data: dict) -> Album:
        start_date = None
        if data.get("startDate"):
            start_date = _parse_iso_date(data["startDate"])

        end_date = None
        if data.get("endDate"):
            end_date = _parse_iso_date(data["endDate"])

        return cls(
            id=data["id"],
            title=data["title"],
            album_type=data["albumType"],
            photo_count=data["photoCount"],
            video_count=data["videoCount"],
            start_date=start_date,
            end_date=end_date,
        )


@dataclass
class Photo:
    """Represents a single photo."""
    id: str
    album_id: str
    media_type: str
    creation_date: datetime
    modification_date: Optional[datetime]
    width: int
    height: int
    is_favorite: bool
    is_hidden: bool
    filename: Optional[str]
    file_size: Optional[int]

    @classmethod
    def from_dict(cls, data: dict) -> Photo:
        creation_date = _parse_iso_date(data["creationDate"])

        modification_date = None
        if data.get("modificationDate"):
            modification_date = _parse_iso_date(data["modificationDate"])

        return cls(
            id=data["id"],
            album_id=data["albumId"],
            media_type=data["mediaType"],
            creation_date=creation_date,
            modification_date=modification_date,
            width=data["width"],
            height=data["height"],
            is_favorite=data["isFavorite"],
            is_hidden=data["isHidden"],
            filename=data.get("filename"),
            file_size=data.get("fileSize"),
        )
```

**Step 2: Add album operations to iCloudBridge class**

Add after the `complete_reminder` method:

```python
    # Album operations

    def get_albums(self) -> list[Album]:
        """
        Get all available photo albums.

        Returns:
            list[Album]: All albums configured in iCloud Bridge
        """
        data = self._request("GET", "/albums")
        return [Album.from_dict(item) for item in data]

    def get_album(self, album_id: str) -> Album:
        """
        Get a specific album by ID.

        Args:
            album_id: The album identifier

        Returns:
            Album: The requested album

        Raises:
            NotFoundError: If the album is not found
        """
        data = self._request("GET", f"/albums/{urllib.parse.quote(album_id)}")
        return Album.from_dict(data)

    def get_photos(
        self,
        album_id: str,
        limit: int = 100,
        offset: int = 0,
        sort: str = "album"
    ) -> tuple[list[Photo], int]:
        """
        Get photos in a specific album.

        Args:
            album_id: The album identifier
            limit: Number of photos per page (default: 100)
            offset: Number of photos to skip (default: 0)
            sort: Sort order - "album", "date-asc", or "date-desc" (default: "album")

        Returns:
            tuple[list[Photo], int]: Photos and total count

        Raises:
            NotFoundError: If the album is not found
        """
        path = f"/albums/{urllib.parse.quote(album_id)}/photos"
        params = []
        if limit != 100:
            params.append(f"limit={limit}")
        if offset != 0:
            params.append(f"offset={offset}")
        if sort != "album":
            params.append(f"sort={sort}")

        if params:
            path += "?" + "&".join(params)

        data = self._request("GET", path)
        photos = [Photo.from_dict(item) for item in data["photos"]]
        return photos, data["total"]

    def get_photo(self, photo_id: str) -> Photo:
        """
        Get a specific photo by ID.

        Args:
            photo_id: The photo identifier

        Returns:
            Photo: The requested photo

        Raises:
            NotFoundError: If the photo is not found
        """
        data = self._request("GET", f"/photos/{urllib.parse.quote(photo_id)}")
        return Photo.from_dict(data)

    def get_thumbnail(self, photo_id: str, size: str = "medium") -> bytes:
        """
        Get a thumbnail image.

        Args:
            photo_id: The photo identifier
            size: Thumbnail size - "small" (200px) or "medium" (800px)

        Returns:
            bytes: JPEG image data

        Raises:
            NotFoundError: If the photo is not found
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/thumbnail"
        if size != "medium":
            path += f"?size={size}"

        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")

    def get_image(self, photo_id: str, wait: bool = False, max_retries: int = 10) -> bytes:
        """
        Get full-resolution image.

        Args:
            photo_id: The photo identifier
            wait: If True, block until download completes; if False, poll with retries
            max_retries: Maximum retry attempts for non-blocking mode (default: 10)

        Returns:
            bytes: Image data

        Raises:
            NotFoundError: If the photo is not found
            iCloudBridgeError: If download fails or times out
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/image"
        if wait:
            path += "?wait=true"

        url = f"{self.base_url}{path}"

        for attempt in range(max_retries if not wait else 1):
            request = urllib.request.Request(url)

            try:
                with urllib.request.urlopen(request) as response:
                    return response.read()
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    raise NotFoundError(f"Photo not found: {photo_id}")
                elif e.code == 202:
                    # Download pending, retry
                    if wait:
                        raise iCloudBridgeError("Image download pending despite wait=true")

                    # Parse retry-after header
                    retry_after = int(e.headers.get("Retry-After", "5"))

                    if attempt < max_retries - 1:
                        import time
                        time.sleep(retry_after)
                        continue
                    else:
                        raise iCloudBridgeError(f"Image download timed out after {max_retries} retries")
                else:
                    raise APIError(e.code, str(e))
            except urllib.error.URLError as e:
                raise iCloudBridgeError(f"Connection failed: {e.reason}")

        raise iCloudBridgeError("Image download failed")

    def get_video(self, photo_id: str) -> bytes:
        """
        Get video file for a video or Live Photo.

        Args:
            photo_id: The photo identifier

        Returns:
            bytes: Video data

        Raises:
            NotFoundError: If the photo is not found
            APIError: If the photo is not a video
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/video"
        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")

    def get_live_video(self, photo_id: str) -> bytes:
        """
        Get motion video component for a Live Photo.

        Args:
            photo_id: The photo identifier (must be a Live Photo)

        Returns:
            bytes: Video data

        Raises:
            NotFoundError: If the photo is not found
            APIError: If the photo is not a Live Photo
        """
        path = f"/photos/{urllib.parse.quote(photo_id)}/live-video"
        url = f"{self.base_url}{path}"
        request = urllib.request.Request(url)

        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFoundError(f"Photo not found: {photo_id}")
            raise APIError(e.code, str(e))
        except urllib.error.URLError as e:
            raise iCloudBridgeError(f"Connection failed: {e.reason}")
```

**Step 3: Update demo code in __main__**

Replace the `if __name__ == "__main__":` section:

```python
if __name__ == "__main__":
    # Simple demo/test
    client = iCloudBridge()

    try:
        health = client.health()
        print(f"Server status: {health}")

        # Test Reminders
        lists = client.get_lists()
        print(f"\nFound {len(lists)} reminder lists:")
        for lst in lists:
            print(f"  - {lst.title} ({lst.reminder_count} reminders)")

        if lists:
            reminders = client.get_reminders(lists[0].id)
            print(f"\nIncomplete reminders in '{lists[0].title}':")
            for r in reminders:
                status = "[x]" if r.is_completed else "[ ]"
                print(f"  {status} {r.title}")

        # Test Photos
        albums = client.get_albums()
        print(f"\nFound {len(albums)} photo albums:")
        for album in albums:
            print(f"  - {album.title} ({album.photo_count} photos, {album.video_count} videos)")

        if albums:
            photos, total = client.get_photos(albums[0].id, limit=5)
            print(f"\nFirst 5 photos in '{albums[0].title}' (total: {total}):")
            for photo in photos:
                print(f"  - {photo.filename or photo.id} ({photo.width}x{photo.height}, {photo.media_type})")

    except iCloudBridgeError as e:
        print(f"Error: {e}")
```

**Step 4: Test Python client**

Run:
```bash
python python/icloudbridge.py
```

Expected: Should connect but fail if server not running (that's OK for now)

**Step 5: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat: extend Python client with Photos support"
```

---

### Task 10: Integration Testing

**Files:**
- None (manual testing)

**Step 1: Build release version**

Run:
```bash
swift build -c release
```

Expected: Build succeeds

**Step 2: Update app bundle**

Run:
```bash
cp .build/release/iCloudBridge "iCloudBridge.app/Contents/MacOS/iCloudBridge"
```

**Step 3: Launch app and grant Photos permission**

Run:
```bash
open iCloudBridge.app
```

Expected:
- App appears in menu bar
- Click menu → Open Settings
- Navigate to Photos tab
- Click "Grant Access"
- macOS permission dialog appears
- Grant full access

**Step 4: Select albums and start server**

In Settings:
- Photos tab: Select 1-2 albums
- Server tab: Verify port (31337)
- Click "Save & Start Server"

Expected: Server starts successfully

**Step 5: Test Albums API**

Run:
```bash
curl http://localhost:31337/api/v1/albums | jq
```

Expected: JSON array of selected albums

**Step 6: Test Photos API**

Get an album ID from previous response, then:

Run:
```bash
curl "http://localhost:31337/api/v1/albums/ALBUM_ID/photos?limit=5" | jq
```

Expected: JSON with photos array and metadata

**Step 7: Test thumbnail endpoint**

Get a photo ID from previous response, then:

Run:
```bash
curl "http://localhost:31337/api/v1/photos/PHOTO_ID/thumbnail?size=small" --output test-thumb.jpg
open test-thumb.jpg
```

Expected: JPEG thumbnail downloads and opens

**Step 8: Test Python client**

Run:
```bash
python python/icloudbridge.py
```

Expected: Prints albums and photos from your library

**Step 9: Test full image download**

Create test script `test_photos.py`:

```python
from python.icloudbridge import iCloudBridge

client = iCloudBridge()

albums = client.get_albums()
print(f"Found {len(albums)} albums")

if albums:
    album = albums[0]
    print(f"\nTesting album: {album.title}")

    photos, total = client.get_photos(album.id, limit=2)
    print(f"Got {len(photos)} photos (total: {total})")

    if photos:
        photo = photos[0]
        print(f"\nDownloading thumbnail for: {photo.filename or photo.id}")
        thumb = client.get_thumbnail(photo.id, size="small")
        print(f"Thumbnail size: {len(thumb)} bytes")

        with open("test-thumbnail.jpg", "wb") as f:
            f.write(thumb)
        print("Saved to test-thumbnail.jpg")
```

Run:
```bash
python test_photos.py
```

Expected: Downloads thumbnail successfully

**Step 10: Final commit**

```bash
git add -A
git commit -m "feat: complete Photos integration with API, UI, and Python client"
```

---

## Summary

This plan implements Photos integration for iCloudBridge:

1. **Data Models** - AlbumDTO, PhotoDTO with nested types
2. **PhotosService** - Complete PhotoKit wrapper with albums, photos, thumbnails, videos, Live Photos
3. **AppState** - Extended with album selection persistence
4. **API Controllers** - AlbumsController and PhotosController with full CRUD endpoints
5. **Routes** - Integrated Photos controllers
6. **UI** - Tab-based settings with separate views for Reminders/Photos/Server
7. **Menu Bar** - Updated stats display
8. **Permissions** - Photos usage description
9. **Python Client** - Full Photos API support with polling for downloads
10. **Testing** - Manual integration testing checklist

The implementation follows the established Reminders pattern while adding Photos-specific features like thumbnails, video streaming, and Live Photo support.
