import Vapor

struct ErrorResponse: Content {
    let error: Bool
    let reason: String

    init(_ reason: String) {
        self.error = true
        self.reason = reason
    }
}
