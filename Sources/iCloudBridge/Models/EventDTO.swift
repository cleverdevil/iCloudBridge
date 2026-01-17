import Foundation
import Vapor

struct EventDTO: Content {
    let id: String
    let calendarId: String
    let title: String
    let notes: String?
    let location: String?
    let url: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let availability: String
    let travelTime: Int?
    let alarms: [AlarmDTO]
    let isRecurring: Bool
    let recurrenceRule: RecurrenceRuleDTO?
    let seriesId: String?
}

struct AlarmDTO: Content {
    let offsetMinutes: Int
}

struct RecurrenceRuleDTO: Content {
    let frequency: String
    let interval: Int
    let daysOfWeek: [String]?
    let dayOfMonth: Int?
    let endDate: Date?
    let occurrenceCount: Int?
}

struct CreateEventDTO: Content {
    let title: String
    let notes: String?
    let location: String?
    let url: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool?
    let availability: String?
    let travelTime: Int?
    let alarms: [AlarmDTO]?
    let recurrenceRule: RecurrenceRuleDTO?
}

struct UpdateEventDTO: Content {
    let title: String?
    let notes: String?
    let location: String?
    let url: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool?
    let availability: String?
    let travelTime: Int?
    let alarms: [AlarmDTO]?
    let recurrenceRule: RecurrenceRuleDTO?
}
