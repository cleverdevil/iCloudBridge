import EventKit
import Foundation
import AppKit

enum CalendarsError: Error, LocalizedError {
    case accessDenied
    case calendarNotFound(String)
    case eventNotFound(String)
    case saveFailed(String)
    case deleteFailed(String)
    case readOnlyCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to Calendars was denied"
        case .calendarNotFound(let id):
            return "Calendar not found: \(id)"
        case .eventNotFound(let id):
            return "Event not found: \(id)"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete: \(reason)"
        case .readOnlyCalendar:
            return "Calendar is read-only"
        }
    }
}

@MainActor
class CalendarsService: ObservableObject {
    private var eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var allCalendars: [EKCalendar] = []

    private let logFileURL: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/iCloudBridge")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("calendars.log")
    }()

    init() {
        log("CalendarsService initialized")
        updateAuthorizationStatus()
        if authorizationStatus == .fullAccess {
            loadCalendars()
        }
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
        print(message)
    }

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            updateAuthorizationStatus()
            if granted {
                loadCalendars()
            }
            log("Calendar access request result: \(granted)")
            return granted
        } catch {
            log("Failed to request calendar access: \(error)")
            return false
        }
    }

    func loadCalendars() {
        eventStore.reset()
        allCalendars = eventStore.calendars(for: .event)
        log("Loaded \(allCalendars.count) calendars")
    }

    // MARK: - Calendar Operations

    func getCalendars(ids: [String]) -> [EKCalendar] {
        return allCalendars.filter { ids.contains($0.calendarIdentifier) }
    }

    func getCalendar(id: String) -> EKCalendar? {
        return allCalendars.first { $0.calendarIdentifier == id }
    }

    // MARK: - Event Operations

    func getEvents(in calendar: EKCalendar, from startDate: Date, to endDate: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        return eventStore.events(matching: predicate)
    }

    func getEvent(id: String) -> EKEvent? {
        return eventStore.event(withIdentifier: id)
    }

    func createEvent(
        in calendar: EKCalendar,
        title: String,
        notes: String?,
        location: String?,
        url: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        availability: EKEventAvailability,
        travelTime: Int?,
        alarms: [Int]?,
        recurrenceRule: EKRecurrenceRule?
    ) throws -> EKEvent {
        guard !calendar.isImmutable else {
            throw CalendarsError.readOnlyCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.location = location
        if let urlString = url, let eventURL = URL(string: urlString) {
            event.url = eventURL
        }
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.availability = availability

        // Note: travelTime is not available on EKEvent in macOS
        _ = travelTime

        if let alarmOffsets = alarms {
            for offset in alarmOffsets {
                let alarm = EKAlarm(relativeOffset: TimeInterval(offset * 60))
                event.addAlarm(alarm)
            }
        }

        if let rule = recurrenceRule {
            event.addRecurrenceRule(rule)
        }

        try eventStore.save(event, span: .thisEvent)
        return event
    }

    func updateEvent(
        _ event: EKEvent,
        span: EKSpan,
        title: String?,
        notes: String?,
        location: String?,
        url: String?,
        startDate: Date?,
        endDate: Date?,
        isAllDay: Bool?,
        availability: EKEventAvailability?,
        travelTime: Int?,
        alarms: [Int]?,
        recurrenceRule: EKRecurrenceRule?
    ) throws -> EKEvent {
        guard !event.calendar.isImmutable else {
            throw CalendarsError.readOnlyCalendar
        }

        if let title = title {
            event.title = title
        }
        if let notes = notes {
            event.notes = notes
        }
        if let location = location {
            event.location = location
        }
        if let urlString = url, let eventURL = URL(string: urlString) {
            event.url = eventURL
        }
        if let startDate = startDate {
            event.startDate = startDate
        }
        if let endDate = endDate {
            event.endDate = endDate
        }
        if let isAllDay = isAllDay {
            event.isAllDay = isAllDay
        }
        if let availability = availability {
            event.availability = availability
        }
        // Note: travelTime is not available on EKEvent in macOS
        _ = travelTime

        if let alarmOffsets = alarms {
            // Remove existing alarms
            if let existingAlarms = event.alarms {
                for alarm in existingAlarms {
                    event.removeAlarm(alarm)
                }
            }
            // Add new alarms
            for offset in alarmOffsets {
                let alarm = EKAlarm(relativeOffset: TimeInterval(offset * 60))
                event.addAlarm(alarm)
            }
        }

        if let rule = recurrenceRule {
            // Remove existing recurrence rules
            if let existingRules = event.recurrenceRules {
                for existingRule in existingRules {
                    event.removeRecurrenceRule(existingRule)
                }
            }
            event.addRecurrenceRule(rule)
        }

        try eventStore.save(event, span: span)
        return event
    }

    func deleteEvent(_ event: EKEvent, span: EKSpan) throws {
        do {
            try eventStore.remove(event, span: span)
        } catch {
            throw CalendarsError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - DTO Conversions

    func toDTO(_ calendar: EKCalendar, eventCount: Int) -> CalendarDTO {
        var colorHex: String? = nil
        if let cgColor = calendar.cgColor {
            let nsColor = NSColor(cgColor: cgColor)
            if let rgb = nsColor?.usingColorSpace(.sRGB) {
                colorHex = String(format: "#%02X%02X%02X",
                    Int(rgb.redComponent * 255),
                    Int(rgb.greenComponent * 255),
                    Int(rgb.blueComponent * 255))
            }
        }

        return CalendarDTO(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: colorHex,
            isReadOnly: calendar.isImmutable,
            eventCount: eventCount
        )
    }

    func toDTO(_ event: EKEvent) -> EventDTO {
        let alarms: [AlarmDTO] = (event.alarms ?? []).compactMap { alarm in
            guard let offset = alarm.relativeOffset as TimeInterval? else { return nil }
            return AlarmDTO(offsetMinutes: Int(offset / 60))
        }

        var recurrenceRuleDTO: RecurrenceRuleDTO? = nil
        if let rule = event.recurrenceRules?.first {
            recurrenceRuleDTO = toDTO(rule)
        }

        let availabilityString: String
        switch event.availability {
        case .busy:
            availabilityString = "busy"
        case .free:
            availabilityString = "free"
        case .tentative:
            availabilityString = "tentative"
        case .unavailable:
            availabilityString = "unavailable"
        case .notSupported:
            availabilityString = "busy"
        @unknown default:
            availabilityString = "busy"
        }

        // Note: travelTime is not available on EKEvent in macOS
        let travelMinutes: Int? = nil

        return EventDTO(
            id: event.eventIdentifier,
            calendarId: event.calendar.calendarIdentifier,
            title: event.title ?? "",
            notes: event.notes,
            location: event.location,
            url: event.url?.absoluteString,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            availability: availabilityString,
            travelTime: travelMinutes,
            alarms: alarms,
            isRecurring: event.hasRecurrenceRules,
            recurrenceRule: recurrenceRuleDTO,
            seriesId: event.hasRecurrenceRules ? event.eventIdentifier : nil
        )
    }

    func toDTO(_ rule: EKRecurrenceRule) -> RecurrenceRuleDTO {
        let frequencyString: String
        switch rule.frequency {
        case .daily:
            frequencyString = "daily"
        case .weekly:
            frequencyString = "weekly"
        case .monthly:
            frequencyString = "monthly"
        case .yearly:
            frequencyString = "yearly"
        @unknown default:
            frequencyString = "daily"
        }

        var daysOfWeek: [String]? = nil
        if let days = rule.daysOfTheWeek {
            daysOfWeek = days.map { day in
                switch day.dayOfTheWeek {
                case .sunday: return "sunday"
                case .monday: return "monday"
                case .tuesday: return "tuesday"
                case .wednesday: return "wednesday"
                case .thursday: return "thursday"
                case .friday: return "friday"
                case .saturday: return "saturday"
                @unknown default: return "monday"
                }
            }
        }

        var dayOfMonth: Int? = nil
        if let days = rule.daysOfTheMonth, let first = days.first {
            dayOfMonth = first.intValue
        }

        var endDate: Date? = nil
        var occurrenceCount: Int? = nil
        if let recurrenceEnd = rule.recurrenceEnd {
            if let date = recurrenceEnd.endDate {
                endDate = date
            } else if recurrenceEnd.occurrenceCount > 0 {
                occurrenceCount = recurrenceEnd.occurrenceCount
            }
        }

        return RecurrenceRuleDTO(
            frequency: frequencyString,
            interval: rule.interval,
            daysOfWeek: daysOfWeek,
            dayOfMonth: dayOfMonth,
            endDate: endDate,
            occurrenceCount: occurrenceCount
        )
    }

    func parseRecurrenceRule(_ dto: RecurrenceRuleDTO) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch dto.frequency.lowercased() {
        case "daily":
            frequency = .daily
        case "weekly":
            frequency = .weekly
        case "monthly":
            frequency = .monthly
        case "yearly":
            frequency = .yearly
        default:
            return nil
        }

        var daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil
        if let days = dto.daysOfWeek {
            daysOfTheWeek = days.compactMap { dayString in
                let day: EKWeekday
                switch dayString.lowercased() {
                case "sunday": day = .sunday
                case "monday": day = .monday
                case "tuesday": day = .tuesday
                case "wednesday": day = .wednesday
                case "thursday": day = .thursday
                case "friday": day = .friday
                case "saturday": day = .saturday
                default: return nil
                }
                return EKRecurrenceDayOfWeek(day)
            }
        }

        var daysOfTheMonth: [NSNumber]? = nil
        if let dayOfMonth = dto.dayOfMonth {
            daysOfTheMonth = [NSNumber(value: dayOfMonth)]
        }

        var recurrenceEnd: EKRecurrenceEnd? = nil
        if let endDate = dto.endDate {
            recurrenceEnd = EKRecurrenceEnd(end: endDate)
        } else if let count = dto.occurrenceCount {
            recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count)
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: dto.interval,
            daysOfTheWeek: daysOfTheWeek,
            daysOfTheMonth: daysOfTheMonth,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: recurrenceEnd
        )
    }

    func parseAvailability(_ string: String?) -> EKEventAvailability {
        guard let string = string else { return .busy }
        switch string.lowercased() {
        case "free":
            return .free
        case "tentative":
            return .tentative
        case "unavailable":
            return .unavailable
        default:
            return .busy
        }
    }
}
