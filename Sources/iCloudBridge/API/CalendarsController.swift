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
