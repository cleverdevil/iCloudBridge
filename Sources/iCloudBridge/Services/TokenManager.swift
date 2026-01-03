import Foundation
import CryptoKit
import Security  // For SecRandomCopyBytes

actor TokenManager {
    private let storageURL: URL
    private var tokens: [StoredToken] = []

    init() {
        // Store in Application Support/iCloudBridge/tokens.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("iCloudBridge", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent("tokens.json")
    }

    /// Generate a cryptographically secure token
    private func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw TokenError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Hash a token using SHA-256
    private func hashToken(_ token: String) -> String {
        let data = Data(token.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Load tokens from disk
    private func loadFromDisk() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            tokens = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        tokens = try JSONDecoder().decode([StoredToken].self, from: data)
    }

    /// Save tokens to disk
    private func saveToDisk() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tokens)
        try data.write(to: storageURL, options: .atomic)
    }

    /// Create a new token, returns the plaintext token and metadata
    func createToken(description: String) throws -> (token: String, metadata: APIToken) {
        try loadFromDisk()

        let token = try generateToken()
        let tokenHash = hashToken(token)
        let metadata = APIToken(description: description)

        let storedToken = StoredToken(
            id: metadata.id,
            hash: tokenHash,
            description: description,
            createdAt: metadata.createdAt
        )

        tokens.append(storedToken)
        try saveToDisk()

        return (token, metadata)
    }

    /// Load all token metadata
    func loadTokens() throws -> [APIToken] {
        try loadFromDisk()
        return tokens.map { APIToken(id: $0.id, description: $0.description, createdAt: $0.createdAt) }
    }

    /// Validate a token against stored hashes
    func validateToken(_ token: String) throws -> Bool {
        try loadFromDisk()
        let providedHash = hashToken(token)
        return tokens.contains { $0.hash == providedHash }
    }

    /// Revoke (delete) a token by ID
    func revokeToken(id: UUID) throws {
        try loadFromDisk()
        tokens.removeAll { $0.id == id }
        try saveToDisk()
    }
}

/// Internal structure for file storage
private struct StoredToken: Codable {
    let id: UUID
    let hash: String
    let description: String
    let createdAt: Date
}

enum TokenError: Error, LocalizedError {
    case randomGenerationFailed
    case storageError(Error)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Failed to generate secure random bytes"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        }
    }
}
