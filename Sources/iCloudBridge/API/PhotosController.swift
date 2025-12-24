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
