import Foundation

/// Represents an API access token (metadata only - hash stored separately in Keychain)
struct APIToken: Identifiable, Codable, Equatable {
    let id: UUID
    let description: String
    let createdAt: Date

    init(id: UUID = UUID(), description: String, createdAt: Date = Date()) {
        self.id = id
        self.description = description
        self.createdAt = createdAt
    }
}
