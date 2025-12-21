import Foundation
import Vapor

struct ListDTO: Content {
    let id: String
    let title: String
    let color: String?
    let reminderCount: Int
}
