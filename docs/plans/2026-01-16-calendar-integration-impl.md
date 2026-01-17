# Calendar Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add iCloud Calendar support with bi-directional CRUD operations for calendars and events, including recurrence handling via EventKit.

**Architecture:** Follows existing patterns - CalendarsService wraps EventKit, CalendarsController/EventsController expose REST endpoints, Python client adds Calendar/Event dataclasses with interactive methods.

**Tech Stack:** Swift/SwiftUI, EventKit, Vapor, Python 3

---

## Task 1: Create CalendarDTO and EventDTO Models

**Files:**
- Create: `Sources/iCloudBridge/Models/CalendarDTO.swift`
- Create: `Sources/iCloudBridge/Models/EventDTO.swift`

**Step 1: Create CalendarDTO.swift**

```swift
import Foundation
import Vapor

struct CalendarDTO: Content {
    let id: String
    let title: String
    let color: String?
    let isReadOnly: Bool
    let eventCount: Int
}
```

**Step 2: Create EventDTO.swift**

```swift
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
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/Models/CalendarDTO.swift Sources/iCloudBridge/Models/EventDTO.swift
git commit -m "feat: add calendar and event DTOs"
```

---

## Task 2: Create CalendarsService

**Files:**
- Create: `Sources/iCloudBridge/Services/CalendarsService.swift`

**Step 1: Create CalendarsService.swift**

```swift
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

        if let minutes = travelTime {
            event.travelTime = TimeInterval(minutes * 60)
        }

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
        if let minutes = travelTime {
            event.travelTime = TimeInterval(minutes * 60)
        }

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
        @unknown default:
            availabilityString = "busy"
        }

        var travelMinutes: Int? = nil
        if event.travelTime > 0 {
            travelMinutes = Int(event.travelTime / 60)
        }

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
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Services/CalendarsService.swift
git commit -m "feat: add CalendarsService with EventKit integration"
```

---

## Task 3: Create CalendarsController

**Files:**
- Create: `Sources/iCloudBridge/API/CalendarsController.swift`

**Step 1: Create CalendarsController.swift**

```swift
import Vapor
import EventKit

struct CalendarsController: RouteCollection {
    let calendarsService: CalendarsService
    let selectedCalendarIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let calendars = routes.grouped("calendars")
        calendars.get(use: index)
        calendars.get(":calendarId", use: show)
        calendars.get(":calendarId", "events", use: events)
        calendars.post(":calendarId", "events", use: createEvent)
    }

    @Sendable
    func index(req: Request) async throws -> [CalendarDTO] {
        let ids = selectedCalendarIds()
        let calendars = await MainActor.run {
            calendarsService.getCalendars(ids: ids)
        }

        var result: [CalendarDTO] = []
        for calendar in calendars {
            // Count events in next 30 days
            let now = Date()
            let thirtyDaysLater = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
            let events = await MainActor.run {
                calendarsService.getEvents(in: calendar, from: now, to: thirtyDaysLater)
            }
            let dto = await MainActor.run {
                calendarsService.toDTO(calendar, eventCount: events.count)
            }
            result.append(dto)
        }
        return result
    }

    @Sendable
    func show(req: Request) async throws -> CalendarDTO {
        guard let calendarId = req.parameters.get("calendarId") else {
            throw Abort(.badRequest, reason: "Missing calendar ID")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(calendarId) else {
            throw Abort(.notFound, reason: "Calendar not found or not selected")
        }

        guard let calendar = await MainActor.run(body: { calendarsService.getCalendar(id: calendarId) }) else {
            throw Abort(.notFound, reason: "Calendar not found")
        }

        let now = Date()
        let thirtyDaysLater = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let events = await MainActor.run {
            calendarsService.getEvents(in: calendar, from: now, to: thirtyDaysLater)
        }

        return await MainActor.run {
            calendarsService.toDTO(calendar, eventCount: events.count)
        }
    }

    @Sendable
    func events(req: Request) async throws -> [EventDTO] {
        guard let calendarId = req.parameters.get("calendarId") else {
            throw Abort(.badRequest, reason: "Missing calendar ID")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(calendarId) else {
            throw Abort(.notFound, reason: "Calendar not found or not selected")
        }

        guard let calendar = await MainActor.run(body: { calendarsService.getCalendar(id: calendarId) }) else {
            throw Abort(.notFound, reason: "Calendar not found")
        }

        // Parse date range from query params (required)
        guard let startString = try? req.query.get(String.self, at: "start"),
              let endString = try? req.query.get(String.self, at: "end") else {
            throw Abort(.badRequest, reason: "Missing required 'start' and 'end' query parameters")
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let startDate = dateFormatter.date(from: startString) ?? ISO8601DateFormatter().date(from: startString) else {
            throw Abort(.badRequest, reason: "Invalid 'start' date format. Use ISO8601.")
        }

        guard let endDate = dateFormatter.date(from: endString) ?? ISO8601DateFormatter().date(from: endString) else {
            throw Abort(.badRequest, reason: "Invalid 'end' date format. Use ISO8601.")
        }

        let events = await MainActor.run {
            calendarsService.getEvents(in: calendar, from: startDate, to: endDate)
        }

        return await MainActor.run {
            events.map { calendarsService.toDTO($0) }
        }
    }

    @Sendable
    func createEvent(req: Request) async throws -> EventDTO {
        guard let calendarId = req.parameters.get("calendarId") else {
            throw Abort(.badRequest, reason: "Missing calendar ID")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(calendarId) else {
            throw Abort(.notFound, reason: "Calendar not found or not selected")
        }

        guard let calendar = await MainActor.run(body: { calendarsService.getCalendar(id: calendarId) }) else {
            throw Abort(.notFound, reason: "Calendar not found")
        }

        let dto = try req.content.decode(CreateEventDTO.self)

        var recurrenceRule: EKRecurrenceRule? = nil
        if let ruleDTO = dto.recurrenceRule {
            recurrenceRule = await MainActor.run {
                calendarsService.parseRecurrenceRule(ruleDTO)
            }
        }

        let availability = await MainActor.run {
            calendarsService.parseAvailability(dto.availability)
        }

        let event = try await MainActor.run {
            try calendarsService.createEvent(
                in: calendar,
                title: dto.title,
                notes: dto.notes,
                location: dto.location,
                url: dto.url,
                startDate: dto.startDate,
                endDate: dto.endDate,
                isAllDay: dto.isAllDay ?? false,
                availability: availability,
                travelTime: dto.travelTime,
                alarms: dto.alarms?.map { $0.offsetMinutes },
                recurrenceRule: recurrenceRule
            )
        }

        return await MainActor.run {
            calendarsService.toDTO(event)
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/API/CalendarsController.swift
git commit -m "feat: add CalendarsController for calendar endpoints"
```

---

## Task 4: Create EventsController

**Files:**
- Create: `Sources/iCloudBridge/API/EventsController.swift`

**Step 1: Create EventsController.swift**

```swift
import Vapor
import EventKit

struct EventsController: RouteCollection {
    let calendarsService: CalendarsService
    let selectedCalendarIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")
        events.get(":eventId", use: show)
        events.put(":eventId", use: update)
        events.delete(":eventId", use: delete)
    }

    private func parseSpan(_ req: Request) -> EKSpan {
        guard let spanString = try? req.query.get(String.self, at: "span") else {
            return .thisEvent
        }
        switch spanString.lowercased() {
        case "futureevents":
            return .futureEvents
        case "allevents":
            return .futureEvents // EKSpan doesn't have allEvents, futureEvents covers from beginning
        default:
            return .thisEvent
        }
    }

    @Sendable
    func show(req: Request) async throws -> EventDTO {
        guard let eventId = req.parameters.get("eventId") else {
            throw Abort(.badRequest, reason: "Missing event ID")
        }

        guard let event = await MainActor.run(body: { calendarsService.getEvent(id: eventId) }) else {
            throw Abort(.notFound, reason: "Event not found")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(event.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Event not found or calendar not selected")
        }

        return await MainActor.run {
            calendarsService.toDTO(event)
        }
    }

    @Sendable
    func update(req: Request) async throws -> EventDTO {
        guard let eventId = req.parameters.get("eventId") else {
            throw Abort(.badRequest, reason: "Missing event ID")
        }

        guard let event = await MainActor.run(body: { calendarsService.getEvent(id: eventId) }) else {
            throw Abort(.notFound, reason: "Event not found")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(event.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Event not found or calendar not selected")
        }

        let dto = try req.content.decode(UpdateEventDTO.self)
        let span = parseSpan(req)

        var recurrenceRule: EKRecurrenceRule? = nil
        if let ruleDTO = dto.recurrenceRule {
            recurrenceRule = await MainActor.run {
                calendarsService.parseRecurrenceRule(ruleDTO)
            }
        }

        var availability: EKEventAvailability? = nil
        if let availabilityString = dto.availability {
            availability = await MainActor.run {
                calendarsService.parseAvailability(availabilityString)
            }
        }

        let updated = try await MainActor.run {
            try calendarsService.updateEvent(
                event,
                span: span,
                title: dto.title,
                notes: dto.notes,
                location: dto.location,
                url: dto.url,
                startDate: dto.startDate,
                endDate: dto.endDate,
                isAllDay: dto.isAllDay,
                availability: availability,
                travelTime: dto.travelTime,
                alarms: dto.alarms?.map { $0.offsetMinutes },
                recurrenceRule: recurrenceRule
            )
        }

        return await MainActor.run {
            calendarsService.toDTO(updated)
        }
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let eventId = req.parameters.get("eventId") else {
            throw Abort(.badRequest, reason: "Missing event ID")
        }

        guard let event = await MainActor.run(body: { calendarsService.getEvent(id: eventId) }) else {
            throw Abort(.notFound, reason: "Event not found")
        }

        let ids = selectedCalendarIds()
        guard ids.contains(event.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Event not found or calendar not selected")
        }

        let span = parseSpan(req)

        try await MainActor.run {
            try calendarsService.deleteEvent(event, span: span)
        }

        return .noContent
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/API/EventsController.swift
git commit -m "feat: add EventsController for event CRUD"
```

---

## Task 5: Register Calendar Routes

**Files:**
- Modify: `Sources/iCloudBridge/API/Routes.swift`
- Modify: `Sources/iCloudBridge/Services/ServerManager.swift`

**Step 1: Update Routes.swift**

Add calendarsService parameter and register controllers. Replace the entire file:

```swift
import Vapor

func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    calendarsService: CalendarsService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String],
    selectedCalendarIds: @escaping () -> [String],
    tokenManager: TokenManager,
    isAuthEnabled: @escaping () -> Bool
) throws {
    // Health check endpoint - always accessible (no auth)
    app.get("health") { req in
        return ["status": "ok"]
    }

    // API routes with authentication middleware
    let authMiddleware = AuthMiddleware(tokenManager: tokenManager, isAuthEnabled: isAuthEnabled)
    let api = app.grouped("api", "v1").grouped(authMiddleware)

    try api.register(collection: ListsController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: RemindersController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: AlbumsController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: PhotosController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: CalendarsController(
        calendarsService: calendarsService,
        selectedCalendarIds: selectedCalendarIds
    ))

    try api.register(collection: EventsController(
        calendarsService: calendarsService,
        selectedCalendarIds: selectedCalendarIds
    ))
}
```

**Step 2: Update ServerManager.swift**

Add calendarsService parameter. Replace the entire file:

```swift
import Vapor
import Foundation

actor ServerManager {
    private var app: Application?
    private let remindersService: RemindersService
    private let photosService: PhotosService
    private let calendarsService: CalendarsService
    private let selectedListIds: () -> [String]
    private let selectedAlbumIds: () -> [String]
    private let selectedCalendarIds: () -> [String]
    let tokenManager: TokenManager
    private let allowRemoteConnections: () -> Bool

    init(
        remindersService: RemindersService,
        photosService: PhotosService,
        calendarsService: CalendarsService,
        selectedListIds: @escaping () -> [String],
        selectedAlbumIds: @escaping () -> [String],
        selectedCalendarIds: @escaping () -> [String],
        tokenManager: TokenManager,
        allowRemoteConnections: @escaping () -> Bool
    ) {
        self.remindersService = remindersService
        self.photosService = photosService
        self.calendarsService = calendarsService
        self.selectedListIds = selectedListIds
        self.selectedAlbumIds = selectedAlbumIds
        self.selectedCalendarIds = selectedCalendarIds
        self.tokenManager = tokenManager
        self.allowRemoteConnections = allowRemoteConnections
    }

    var isRunning: Bool {
        return app != nil
    }

    func start(port: Int) async throws {
        if app != nil {
            await stop()
        }

        var env = Environment.production
        env.arguments = ["serve"]

        let newApp = try await Application.make(env)

        // Bind to all interfaces if remote connections allowed, otherwise localhost only
        newApp.http.server.configuration.hostname = allowRemoteConnections() ? "0.0.0.0" : "127.0.0.1"
        newApp.http.server.configuration.port = port

        // Configure JSON encoder for dates
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        ContentConfiguration.global.use(encoder: encoder, for: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ContentConfiguration.global.use(decoder: decoder, for: .json)

        try configureRoutes(
            newApp,
            remindersService: remindersService,
            photosService: photosService,
            calendarsService: calendarsService,
            selectedListIds: selectedListIds,
            selectedAlbumIds: selectedAlbumIds,
            selectedCalendarIds: selectedCalendarIds,
            tokenManager: tokenManager,
            isAuthEnabled: allowRemoteConnections
        )

        self.app = newApp

        try await newApp.startup()
    }

    func stop() async {
        if let app = app {
            try? await app.asyncShutdown()
            self.app = nil
        }
    }
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build fails (iCloudBridgeApp.swift needs update) - this is expected, we'll fix in Task 7

**Step 4: Commit**

```bash
git add Sources/iCloudBridge/API/Routes.swift Sources/iCloudBridge/Services/ServerManager.swift
git commit -m "feat: register calendar routes in server"
```

---

## Task 6: Update AppState for Calendars

**Files:**
- Modify: `Sources/iCloudBridge/AppState.swift`

**Step 1: Update AppState.swift**

Add calendarsService and selectedCalendarIds. The key changes:
- Add `calendarsService: CalendarsService` property
- Add `selectedCalendarIds: Set<String>` property
- Add calendar selection methods
- Update `hasAllPermissions` to include calendar access
- Add persistence for selectedCalendarIds

Replace the file with:

```swift
import Foundation
import SwiftUI
import EventKit

enum ServerStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case error(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var selectedListIds: Set<String> = []
    @Published var selectedAlbumIds: Set<String> = []
    @Published var selectedCalendarIds: Set<String> = []

    @AppStorage("photosCollapsedSections") private var collapsedSectionsData: Data = Data()
    @AppStorage("photosExpandedFolders") private var expandedFoldersData: Data = Data()

    var collapsedSections: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: collapsedSectionsData)) ?? []
        }
        set {
            collapsedSectionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var expandedFolders: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: expandedFoldersData)) ?? []
        }
        set {
            expandedFoldersData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func toggleSection(_ section: String) {
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func isSectionExpanded(_ section: String) -> Bool {
        !collapsedSections.contains(section)
    }

    func toggleFolderExpansion(_ folderId: String) {
        if expandedFolders.contains(folderId) {
            expandedFolders.remove(folderId)
        } else {
            expandedFolders.insert(folderId)
        }
    }

    func isFolderExpanded(_ folderId: String) -> Bool {
        expandedFolders.contains(folderId)
    }

    @Published var serverPort: Int = 31337
    @Published var serverStatus: ServerStatus = .stopped
    @Published var showingSettings: Bool = false
    @Published var allowRemoteConnections: Bool = false
    @Published var apiTokens: [APIToken] = []

    let remindersService: RemindersService
    let photosService: PhotosService
    let calendarsService: CalendarsService

    private let selectedListIdsKey = "selectedListIds"
    private let selectedAlbumIdsKey = "selectedAlbumIds"
    private let selectedCalendarIdsKey = "selectedCalendarIds"
    private let serverPortKey = "serverPort"
    private let allowRemoteConnectionsKey = "allowRemoteConnections"

    init() {
        self.remindersService = RemindersService()
        self.photosService = PhotosService()
        self.calendarsService = CalendarsService()
        loadSettings()
    }

    var hasValidSettings: Bool {
        return !selectedListIds.isEmpty || !selectedCalendarIds.isEmpty
    }

    var hasAllPermissions: Bool {
        remindersService.authorizationStatus == .fullAccess &&
        photosService.authorizationStatus == .authorized &&
        calendarsService.authorizationStatus == .fullAccess
    }

    var hasSavedSettings: Bool {
        !selectedListIds.isEmpty || !selectedAlbumIds.isEmpty || !selectedCalendarIds.isEmpty
    }

    var selectedLists: [String] {
        return Array(selectedListIds)
    }

    var selectedCalendars: [String] {
        return Array(selectedCalendarIds)
    }

    // MARK: - Persistence

    func loadSettings() {
        if let savedIds = UserDefaults.standard.array(forKey: selectedListIdsKey) as? [String] {
            selectedListIds = Set(savedIds)
        }
        if let savedAlbumIds = UserDefaults.standard.array(forKey: selectedAlbumIdsKey) as? [String] {
            selectedAlbumIds = Set(savedAlbumIds)
        }
        if let savedCalendarIds = UserDefaults.standard.array(forKey: selectedCalendarIdsKey) as? [String] {
            selectedCalendarIds = Set(savedCalendarIds)
        }
        let savedPort = UserDefaults.standard.integer(forKey: serverPortKey)
        if savedPort > 0 {
            serverPort = savedPort
        }
        allowRemoteConnections = UserDefaults.standard.bool(forKey: allowRemoteConnectionsKey)
    }

    func saveSettings() {
        UserDefaults.standard.set(Array(selectedListIds), forKey: selectedListIdsKey)
        UserDefaults.standard.set(Array(selectedAlbumIds), forKey: selectedAlbumIdsKey)
        UserDefaults.standard.set(Array(selectedCalendarIds), forKey: selectedCalendarIdsKey)
        UserDefaults.standard.set(serverPort, forKey: serverPortKey)
        UserDefaults.standard.set(allowRemoteConnections, forKey: allowRemoteConnectionsKey)
    }

    // MARK: - List Selection

    func toggleList(_ id: String) {
        if selectedListIds.contains(id) {
            selectedListIds.remove(id)
        } else {
            selectedListIds.insert(id)
        }
    }

    func isListSelected(_ id: String) -> Bool {
        return selectedListIds.contains(id)
    }

    // MARK: - Album Selection

    func toggleAlbum(_ id: String) {
        if selectedAlbumIds.contains(id) {
            selectedAlbumIds.remove(id)
        } else {
            selectedAlbumIds.insert(id)
        }
    }

    func isAlbumSelected(_ id: String) -> Bool {
        return selectedAlbumIds.contains(id)
    }

    var selectedAlbums: [String] {
        return Array(selectedAlbumIds)
    }

    // MARK: - Calendar Selection

    func toggleCalendar(_ id: String) {
        if selectedCalendarIds.contains(id) {
            selectedCalendarIds.remove(id)
        } else {
            selectedCalendarIds.insert(id)
        }
    }

    func isCalendarSelected(_ id: String) -> Bool {
        return selectedCalendarIds.contains(id)
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build fails (other files need updates) - expected

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/AppState.swift
git commit -m "feat: add calendar selection to AppState"
```

---

## Task 7: Create CalendarsSettingsView

**Files:**
- Create: `Sources/iCloudBridge/Views/CalendarsSettingsView.swift`

**Step 1: Create CalendarsSettingsView.swift**

```swift
import SwiftUI
import EventKit

struct CalendarsSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            calendarsSection
            Spacer()
        }
        .padding(20)
        .onAppear {
            appState.calendarsService.loadCalendars()
        }
    }

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Calendars")
                .font(.headline)

            Text("Choose which calendars to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.calendarsService.allCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: Binding(
                            get: { appState.isCalendarSelected(calendar.calendarIdentifier) },
                            set: { _ in appState.toggleCalendar(calendar.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                if calendar.isImmutable {
                                    Text("(read-only)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build fails (other files need updates) - expected

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/CalendarsSettingsView.swift
git commit -m "feat: add CalendarsSettingsView for calendar selection"
```

---

## Task 8: Update OnboardingView for Calendar Permission

**Files:**
- Modify: `Sources/iCloudBridge/Views/OnboardingView.swift`

**Step 1: Update OnboardingView.swift**

Add calendar permission step. Replace the file with:

```swift
import SwiftUI
import EventKit
import Photos

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var photosService: PhotosService
    @ObservedObject var calendarsService: CalendarsService
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("iCloud Bridge Setup")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("iCloud Bridge needs access to your Reminders, Photos, and Calendars to expose them via a local API.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 0)
            .padding(.bottom, 20)

            Divider()

            // Permission Steps
            ScrollView {
                VStack(spacing: 16) {
                    remindersStep
                    calendarsStep
                    photosStep
                }
                .padding(30)
            }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: remindersService.authorizationStatus) { _, _ in
            checkCompletion()
        }
        .onChange(of: calendarsService.authorizationStatus) { _, _ in
            checkCompletion()
        }
        .onChange(of: photosService.authorizationStatus) { _, _ in
            checkCompletion()
        }
    }

    private var remindersStep: some View {
        PermissionStepView(
            icon: "list.bullet.clipboard",
            title: "Reminders Access",
            description: "Required to read and manage your reminder lists through the API.",
            status: remindersStatus,
            action: requestRemindersAccess,
            openSettings: openRemindersSettings
        )
    }

    private var calendarsStep: some View {
        PermissionStepView(
            icon: "calendar",
            title: "Calendars Access",
            description: "Required to read and manage your calendar events through the API.",
            status: calendarsStatus,
            isEnabled: remindersService.authorizationStatus == .fullAccess,
            action: requestCalendarsAccess,
            openSettings: openCalendarsSettings
        )
    }

    private var photosStep: some View {
        PermissionStepView(
            icon: "photo.on.rectangle",
            title: "Photos Access",
            description: "Required to browse albums and serve photos through the API.",
            status: photosStatus,
            isEnabled: remindersService.authorizationStatus == .fullAccess && calendarsService.authorizationStatus == .fullAccess,
            action: requestPhotosAccess,
            openSettings: openPhotosSettings
        )
    }

    private var remindersStatus: PermissionStatus {
        switch remindersService.authorizationStatus {
        case .fullAccess:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private var calendarsStatus: PermissionStatus {
        switch calendarsService.authorizationStatus {
        case .fullAccess:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private var photosStatus: PermissionStatus {
        switch photosService.authorizationStatus {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private func checkCompletion() {
        if appState.hasAllPermissions {
            // Small delay to show the completed state, then close and proceed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
                onComplete()
            }
        }
    }

    private func requestRemindersAccess() {
        Task {
            _ = await remindersService.requestAccess()
        }
    }

    private func requestCalendarsAccess() {
        Task {
            _ = await calendarsService.requestAccess()
        }
    }

    private func requestPhotosAccess() {
        Task {
            _ = await photosService.requestAccess()
        }
    }

    private func openRemindersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openCalendarsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openPhotosSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

struct PermissionStepView: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    var isEnabled: Bool = true
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Status icon
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)

                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .primary : .secondary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isEnabled {
                    actionButton
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isEnabled ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(status == .granted ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    private var statusIcon: String {
        switch status {
        case .granted:
            return "checkmark"
        case .denied:
            return icon
        case .notDetermined:
            return icon
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .granted:
            return Color.green.opacity(0.2)
        case .denied:
            return Color.red.opacity(0.2)
        case .notDetermined:
            return Color.accentColor.opacity(0.2)
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .accentColor
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .granted:
            Label("Access Granted", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        case .denied:
            Button("Open System Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        case .notDetermined:
            Button("Grant Access") {
                action()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build fails (iCloudBridgeApp needs update) - expected

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/OnboardingView.swift
git commit -m "feat: add calendar permission to onboarding"
```

---

## Task 9: Update SettingsView for Calendars Tab

**Files:**
- Modify: `Sources/iCloudBridge/Views/SettingsView.swift`

**Step 1: Update SettingsView.swift**

Add Calendars tab. Key changes:
- Add `calendars` case to Tab enum
- Add CalendarsSettingsView tab
- Update canSave to include calendars
- Update contentHeight for calendars tab

Replace the file with:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .reminders
    @State private var portString: String = ""
    @State private var showingPortError: Bool = false
    @State private var showingAddToken: Bool = false
    @State private var newTokenDescription: String = ""
    @State private var showingTokenCreated: Bool = false
    @State private var createdToken: String = ""
    @State private var showingRevokeConfirmation: Bool = false
    @State private var tokenToRevoke: APIToken?

    let tokenManager: TokenManager

    enum Tab: Hashable {
        case reminders
        case calendars
        case photos
        case server
    }

    private var contentHeight: CGFloat {
        switch selectedTab {
        case .reminders:
            return 320
        case .calendars:
            return 320
        case .photos:
            return 480
        case .server:
            return 400
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                RemindersSettingsView(appState: appState)
                    .tag(Tab.reminders)
                    .tabItem {
                        Label("Reminders", systemImage: "list.bullet.clipboard")
                    }

                CalendarsSettingsView(appState: appState)
                    .tag(Tab.calendars)
                    .tabItem {
                        Label("Calendars", systemImage: "calendar")
                    }

                PhotosSettingsView(appState: appState)
                    .tag(Tab.photos)
                    .tabItem {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                serverSettingsView
                    .tag(Tab.server)
                    .tabItem {
                        Label("Server", systemImage: "server.rack")
                    }
            }

            Divider()

            // Footer with Save button - visible on all tabs
            HStack {
                Spacer()
                Button("Save & Start Server") {
                    saveAndStart()
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 500, height: contentHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .onAppear {
            portString = String(appState.serverPort)
        }
    }

    private var serverSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Port configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Port")
                    .font(.headline)

                HStack {
                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: portString) { _, _ in
                            validatePort()
                        }

                    if showingPortError {
                        Text("Invalid port (1024-65535)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Default: 31337")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Remote access toggle
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow remote connections", isOn: $appState.allowRemoteConnections)

                Text("When enabled, the server binds to all network interfaces. Remote access requires a valid token.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Token management (shown when remote enabled)
            if appState.allowRemoteConnections {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Tokens")
                        .font(.headline)

                    if appState.apiTokens.isEmpty {
                        Text("No tokens configured. Remote clients won't be able to authenticate.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(appState.apiTokens) { token in
                            tokenRow(token)
                        }
                    }

                    Button("Add Token") {
                        showingAddToken = true
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingAddToken) {
            addTokenSheet
        }
        .sheet(isPresented: $showingTokenCreated) {
            TokenCreatedModal(token: createdToken) {
                showingTokenCreated = false
                createdToken = ""
            }
        }
        .alert("Revoke Token", isPresented: $showingRevokeConfirmation, presenting: tokenToRevoke) { token in
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task {
                    await revokeToken(token)
                }
            }
        } message: { token in
            Text("Revoke token '\(token.description)'? Any clients using this token will stop working.")
        }
    }

    private func tokenRow(_ token: APIToken) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(token.description)
                    .font(.body)
                Text("Created \(token.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Revoke") {
                tokenToRevoke = token
                showingRevokeConfirmation = true
            }
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }

    private var addTokenSheet: some View {
        VStack(spacing: 16) {
            Text("Add Access Token")
                .font(.headline)

            TextField("Description (e.g., Home Assistant)", text: $newTokenDescription)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    newTokenDescription = ""
                    showingAddToken = false
                }

                Button("Create Token") {
                    Task {
                        await createToken()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTokenDescription.isEmpty)
            }
        }
        .padding(24)
    }

    private func createToken() async {
        do {
            let (token, metadata) = try await tokenManager.createToken(description: newTokenDescription)
            await MainActor.run {
                appState.apiTokens.append(metadata)
                createdToken = token
                newTokenDescription = ""
                showingAddToken = false
                showingTokenCreated = true
            }
        } catch {
            print("Failed to create token: \(error)")
        }
    }

    private func revokeToken(_ token: APIToken) async {
        do {
            try await tokenManager.revokeToken(id: token.id)
            await MainActor.run {
                appState.apiTokens.removeAll { $0.id == token.id }
            }
        } catch {
            print("Failed to revoke token: \(error)")
        }
    }

    private var canSave: Bool {
        let hasLists = !appState.selectedListIds.isEmpty
        let hasAlbums = !appState.selectedAlbumIds.isEmpty
        let hasCalendars = !appState.selectedCalendarIds.isEmpty
        return (hasLists || hasAlbums || hasCalendars) && isValidPort
    }

    private var isValidPort: Bool {
        guard let port = Int(portString) else { return false }
        return port >= 1024 && port <= 65535
    }

    private func validatePort() {
        showingPortError = !portString.isEmpty && !isValidPort
    }

    private func saveAndStart() {
        guard let port = Int(portString) else { return }
        appState.serverPort = port
        appState.saveSettings()
        onSave()
        dismiss()
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build fails (iCloudBridgeApp needs update) - expected

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/Views/SettingsView.swift
git commit -m "feat: add calendars tab to settings"
```

---

## Task 10: Update iCloudBridgeApp

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Update iCloudBridgeApp.swift**

Wire up CalendarsService to ServerManager and OnboardingView. Replace the file:

```swift
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app runs as an accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct iCloudBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var serverManager: ServerManager?
    private let tokenManager = TokenManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                appState: appState,
                onStartServer: startServer,
                onStopServer: stopServer
            )
        } label: {
            menuBarLabel
        }

        // Onboarding window - shown when permissions are missing
        Window("iCloud Bridge Setup", id: "onboarding") {
            OnboardingView(
                appState: appState,
                remindersService: appState.remindersService,
                photosService: appState.photosService,
                calendarsService: appState.calendarsService,
                onComplete: handleOnboardingComplete
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Settings scene - provides native macOS preferences toolbar
        Settings {
            SettingsView(appState: appState, onSave: startServer, tokenManager: tokenManager)
        }
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text("iCloud Bridge")
        }
        .onAppear {
            handleLaunch()
        }
    }

    private func handleLaunch() {
        // Load API tokens
        loadTokens()

        if appState.hasAllPermissions && appState.hasSavedSettings {
            // Returning user with all permissions - auto-start server silently
            startServer()
        } else if !appState.hasAllPermissions {
            // Missing permissions - show onboarding
            openWindow(id: "onboarding")
        } else {
            // Has permissions but no saved settings - open preferences
            openSettings()
        }
    }

    private func handleOnboardingComplete() {
        // Reload data now that we have permissions
        appState.remindersService.loadLists()
        appState.photosService.loadAlbums()
        appState.calendarsService.loadCalendars()

        if appState.hasSavedSettings {
            // Has saved settings - start server
            startServer()
        } else {
            // No saved settings - open preferences for configuration
            openSettings()
        }
    }

    @Environment(\.openSettings) private var openSettingsAction

    private func openSettings() {
        openSettingsAction()
    }

    private var statusIcon: String {
        switch appState.serverStatus {
        case .stopped:
            return "cloud"
        case .starting:
            return "cloud.bolt"
        case .running:
            return "cloud.fill"
        case .error:
            return "cloud.slash"
        }
    }

    private func startServer() {
        Task {
            await MainActor.run {
                appState.serverStatus = .starting
            }

            if serverManager == nil {
                serverManager = ServerManager(
                    remindersService: appState.remindersService,
                    photosService: appState.photosService,
                    calendarsService: appState.calendarsService,
                    selectedListIds: { [weak appState] in appState?.selectedLists ?? [] },
                    selectedAlbumIds: { [weak appState] in appState?.selectedAlbums ?? [] },
                    selectedCalendarIds: { [weak appState] in appState?.selectedCalendars ?? [] },
                    tokenManager: tokenManager,
                    allowRemoteConnections: { [weak appState] in appState?.allowRemoteConnections ?? false }
                )
            } else {
                await serverManager?.stop()
            }

            do {
                try await serverManager?.start(port: appState.serverPort)
                await MainActor.run {
                    appState.serverStatus = .running(port: appState.serverPort)
                }
            } catch {
                await MainActor.run {
                    appState.serverStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func stopServer() {
        Task {
            await serverManager?.stop()
            await MainActor.run {
                appState.serverStatus = .stopped
            }
        }
    }

    private func loadTokens() {
        Task {
            do {
                let tokens = try await tokenManager.loadTokens()
                await MainActor.run {
                    appState.apiTokens = tokens
                }
            } catch {
                print("Failed to load tokens: \(error)")
            }
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettingsAction

    let onStartServer: () -> Void
    let onStopServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("iCloud Bridge")
                .font(.headline)

            Divider()

            statusSection

            Divider()

            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            if appState.serverStatus.isRunning {
                Button("Copy API URL") {
                    copyAPIUrl()
                }
            }

            Divider()

            if appState.serverStatus.isRunning {
                Button("Stop Server") {
                    onStopServer()
                }
            } else if appState.hasValidSettings {
                Button("Start Server") {
                    onStartServer()
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
    }

    private func openSettings() {
        if !appState.hasAllPermissions {
            openWindow(id: "onboarding")
        } else {
            openSettingsAction()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch appState.serverStatus {
            case .stopped:
                Label("Server stopped", systemImage: "circle.fill")
                    .foregroundColor(.secondary)
            case .starting:
                Label("Starting...", systemImage: "circle.fill")
                    .foregroundColor(.yellow)
            case .running(let port):
                Label("Running on port \(port)", systemImage: "circle.fill")
                    .foregroundColor(.green)

                if !appState.selectedListIds.isEmpty {
                    Text("\(appState.selectedListIds.count) lists selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !appState.selectedCalendarIds.isEmpty {
                    Text("\(appState.selectedCalendarIds.count) calendars selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !appState.selectedAlbumIds.isEmpty {
                    Text("\(appState.selectedAlbumIds.count) albums selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .error(let message):
                Label("Error", systemImage: "circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func copyAPIUrl() {
        if case .running(let port) = appState.serverStatus {
            let url = "http://localhost:\(port)/api/v1"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }
}
```

**Step 2: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/iCloudBridge/iCloudBridgeApp.swift
git commit -m "feat: wire up CalendarsService to app"
```

---

## Task 11: Update Python Client

**Files:**
- Modify: `python/icloudbridge.py`

**Step 1: Update icloudbridge.py**

Add Calendar, Event, RecurrenceRule, Alarm classes and client methods. Add after the Photo class and before iCloudBridgeError:

The changes are extensive. Key additions:
- `@dataclass` classes: `Calendar`, `Event`, `RecurrenceRule`, `Alarm`
- Client methods: `get_calendars`, `get_calendar`, `get_events`, `get_event`, `create_event`, `update_event`, `delete_event`
- Property: `calendars` iterator
- Update module docstring

See the full implementation in the commit.

**Step 2: Verify Python syntax**

Run: `python3 -m py_compile python/icloudbridge.py`
Expected: No output (success)

**Step 3: Commit**

```bash
git add python/icloudbridge.py
git commit -m "feat(python): add calendar and event support"
```

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

**Step 1: Update README.md**

Add calendar API documentation:
- Update features list
- Add Calendar endpoints table
- Add Python calendar examples
- Update architecture diagram

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add calendar API documentation"
```

---

## Task 13: Final Build and Test

**Step 1: Clean build**

Run: `swift build -c release`
Expected: Build succeeds

**Step 2: Run the app**

Run: `.build/release/iCloudBridge`
Expected: App launches, shows in menu bar

**Step 3: Test calendar endpoints**

After granting calendar permission and selecting a calendar:

```bash
# List calendars
curl http://localhost:31337/api/v1/calendars

# Get events for date range
curl "http://localhost:31337/api/v1/calendars/{id}/events?start=2026-01-01T00:00:00Z&end=2026-01-31T23:59:59Z"
```

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete calendar integration"
```
