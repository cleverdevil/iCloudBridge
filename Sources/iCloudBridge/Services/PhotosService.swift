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
    @Published var albumHierarchy: AlbumHierarchy = AlbumHierarchy()

    // Track pending downloads
    private var pendingDownloads: [String: Bool] = [:]

    private func makeAlbumItem(from collection: PHAssetCollection) -> AlbumItem? {
        let count = PHAsset.fetchAssets(in: collection, options: nil).count
        guard count > 0 else { return nil }
        return AlbumItem(collection: collection, photoCount: count)
    }

    init() {
        updateAuthorizationStatus()
        // If already authorized, load albums immediately
        if authorizationStatus == .authorized {
            loadAlbums()
        }
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

    // MARK: - Album Operations

    func getAlbums(ids: [String]) -> [PHAssetCollection] {
        return albumHierarchy.allSelectableAlbums.filter { ids.contains($0.localIdentifier) }
    }

    func getAlbum(id: String) -> PHAssetCollection? {
        return albumHierarchy.allSelectableAlbums.first { $0.localIdentifier == id }
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
                // Check if this is the final result (not a low-quality placeholder)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    return // Wait for the high quality image
                }

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
            guard resources.first != nil else {
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
        let camera: PhotoDTO.Camera? = nil
        let settings: PhotoDTO.CameraSettings? = nil

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
}
