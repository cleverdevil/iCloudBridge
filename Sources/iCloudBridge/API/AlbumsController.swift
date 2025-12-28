import Vapor
import Photos

struct AlbumsController: RouteCollection {
    let photosService: PhotosService
    let selectedAlbumIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let albums = routes.grouped("albums")
        albums.get(use: index)
        // Use catchall for album ID since Photos IDs contain slashes (e.g., "ABC123/L0/040")
        albums.get("**", use: routeHandler)
    }

    @Sendable
    func routeHandler(req: Request) async throws -> Response {
        // Get the catchall path components
        let pathComponents = req.parameters.getCatchall()
        guard !pathComponents.isEmpty else {
            throw Abort(.badRequest, reason: "Missing album ID")
        }

        // Check if this is a photos request (last component is "photos")
        if pathComponents.last == "photos" {
            let albumId = pathComponents.dropLast().joined(separator: "/")
            return try await photosResponse(req: req, albumId: albumId)
        } else {
            let albumId = pathComponents.joined(separator: "/")
            return try await showResponse(req: req, albumId: albumId)
        }
    }

    @Sendable
    func showResponse(req: Request, albumId: String) async throws -> Response {
        let dto = try await show(req: req, albumId: albumId)
        return try await dto.encodeResponse(for: req)
    }

    @Sendable
    func photosResponse(req: Request, albumId: String) async throws -> Response {
        let dto = try await photos(req: req, albumId: albumId)
        return try await dto.encodeResponse(for: req)
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
    func show(req: Request, albumId: String) async throws -> AlbumDTO {
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
    func photos(req: Request, albumId: String) async throws -> PhotosListResponse {
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
        let mediaType = try? req.query.get(String.self, at: "type")

        // Validate sort parameter
        guard ["album", "date-asc", "date-desc"].contains(sort) else {
            throw Abort(.badRequest, reason: "Invalid sort parameter. Must be: album, date-asc, or date-desc")
        }

        // Validate media type parameter
        if let mediaType = mediaType, !["photo", "video", "live", "all"].contains(mediaType) {
            throw Abort(.badRequest, reason: "Invalid type parameter. Must be: photo, video, live, or all")
        }

        let result = await MainActor.run {
            photosService.getAssets(in: album, limit: limit, offset: offset, sort: sort, mediaType: mediaType)
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
