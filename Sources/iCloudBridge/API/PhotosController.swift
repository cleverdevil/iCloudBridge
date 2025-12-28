import Vapor
import Photos

struct PhotosController: RouteCollection {
    let photosService: PhotosService
    let selectedAlbumIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let photos = routes.grouped("photos")
        // Use catchall for photo ID since Photos IDs contain slashes (e.g., "ABC123/L0/040")
        photos.get("**", use: routeHandler)
    }

    @Sendable
    func routeHandler(req: Request) async throws -> Response {
        let pathComponents = req.parameters.getCatchall()
        guard !pathComponents.isEmpty else {
            throw Abort(.badRequest, reason: "Missing photo ID")
        }

        // Check what type of request this is based on last component
        let lastComponent = pathComponents.last!
        switch lastComponent {
        case "thumbnail":
            let photoId = pathComponents.dropLast().joined(separator: "/")
            return try await thumbnail(req: req, photoId: photoId)
        case "image":
            let photoId = pathComponents.dropLast().joined(separator: "/")
            return try await image(req: req, photoId: photoId)
        case "video":
            let photoId = pathComponents.dropLast().joined(separator: "/")
            return try await video(req: req, photoId: photoId)
        case "live-video":
            let photoId = pathComponents.dropLast().joined(separator: "/")
            return try await liveVideo(req: req, photoId: photoId)
        default:
            // No suffix means just the photo metadata
            let photoId = pathComponents.joined(separator: "/")
            return try await show(req: req, photoId: photoId)
        }
    }

    @Sendable
    func show(req: Request, photoId: String) async throws -> Response {
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

        let dto = await MainActor.run {
            photosService.toDTO(asset, albumId: albumId)
        }
        return try await dto.encodeResponse(for: req)
    }

    @Sendable
    func thumbnail(req: Request, photoId: String) async throws -> Response {
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
    func image(req: Request, photoId: String) async throws -> Response {
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
    func video(req: Request, photoId: String) async throws -> Response {
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
    func liveVideo(req: Request, photoId: String) async throws -> Response {
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
