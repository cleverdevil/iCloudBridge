import Vapor

/// Middleware that requires Bearer token authentication for remote requests
struct AuthMiddleware: AsyncMiddleware {
    let tokenManager: TokenManager
    let isAuthEnabled: () -> Bool

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Skip auth if disabled
        guard isAuthEnabled() else {
            return try await next.respond(to: request)
        }

        // Allow localhost requests without auth
        if isLocalhost(request) {
            return try await next.respond(to: request)
        }

        // Require Bearer token for remote requests
        guard let authHeader = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        let token = authHeader.token

        do {
            let isValid = try await tokenManager.validateToken(token)
            guard isValid else {
                throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
            }
        } catch {
            request.logger.warning("Auth validation error: \(error)")
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        return try await next.respond(to: request)
    }

    private func isLocalhost(_ request: Request) -> Bool {
        guard let peerAddress = request.peerAddress else {
            return false
        }

        let hostname = peerAddress.hostname ?? ""

        // Check for IPv4 localhost
        if hostname == "127.0.0.1" {
            return true
        }

        // Check for IPv6 localhost variants
        if hostname == "::1" || hostname == "0:0:0:0:0:0:0:1" {
            return true
        }

        // Check for IPv6-mapped IPv4 localhost (::ffff:127.0.0.1)
        if hostname.lowercased().hasPrefix("::ffff:127.0.0.1") {
            return true
        }

        // Check for bracketed IPv6 (some systems use [::1])
        if hostname == "[::1]" {
            return true
        }

        return false
    }
}
