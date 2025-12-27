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
        case shared
    }
}
