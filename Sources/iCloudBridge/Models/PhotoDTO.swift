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
