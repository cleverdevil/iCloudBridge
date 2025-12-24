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
