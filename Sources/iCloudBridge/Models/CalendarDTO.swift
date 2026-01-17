import Foundation
import Vapor

struct CalendarDTO: Content {
    let id: String
    let title: String
    let color: String?
    let isReadOnly: Bool
    let eventCount: Int
}
