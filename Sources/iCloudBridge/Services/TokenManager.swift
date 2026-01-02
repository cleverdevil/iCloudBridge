import Foundation
import Security
import CryptoKit

actor TokenManager {
    private let serviceName = "com.icloudbridge.api-tokens"

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

    /// Store a new token in Keychain, returns the token metadata
    func createToken(description: String) throws -> (token: String, metadata: APIToken) {
        let token = try generateToken()
        let tokenHash = hashToken(token)
        let metadata = APIToken(description: description)

        let tokenData = TokenData(hash: tokenHash, description: description, createdAt: metadata.createdAt)
        let jsonData = try JSONEncoder().encode(tokenData)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: metadata.id.uuidString,
            kSecValueData as String: jsonData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenError.keychainError(status)
        }

        return (token, metadata)
    }

    /// Load all token metadata from Keychain
    func loadTokens() throws -> [APIToken] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            throw TokenError.keychainError(status)
        }

        return items.compactMap { item -> APIToken? in
            guard let accountString = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: accountString),
                  let data = item[kSecValueData as String] as? Data,
                  let tokenData = try? JSONDecoder().decode(TokenData.self, from: data) else {
                return nil
            }
            return APIToken(id: id, description: tokenData.description, createdAt: tokenData.createdAt)
        }
    }

    /// Validate a token against stored hashes
    func validateToken(_ token: String) throws -> Bool {
        let providedHash = hashToken(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return false
        }

        guard status == errSecSuccess,
              let items = result as? [Data] else {
            throw TokenError.keychainError(status)
        }

        for data in items {
            if let tokenData = try? JSONDecoder().decode(TokenData.self, from: data),
               tokenData.hash == providedHash {
                return true
            }
        }

        return false
    }

    /// Revoke (delete) a token by ID
    func revokeToken(id: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: id.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenError.keychainError(status)
        }
    }
}

/// Internal structure for Keychain storage
private struct TokenData: Codable {
    let hash: String
    let description: String
    let createdAt: Date
}

enum TokenError: Error, LocalizedError {
    case keychainError(OSStatus)
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .randomGenerationFailed:
            return "Failed to generate secure random bytes"
        }
    }
}
