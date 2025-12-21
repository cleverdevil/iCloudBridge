import Foundation
import Vapor

struct ReminderDTO: Content {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let priority: Int
    let dueDate: Date?
    let completionDate: Date?
    let listId: String
}

struct CreateReminderDTO: Content {
    let title: String
    let notes: String?
    let priority: Int?
    let dueDate: Date?
}

struct UpdateReminderDTO: Content {
    let title: String?
    let notes: String?
    let isCompleted: Bool?
    let priority: Int?
    let dueDate: Date?
}
