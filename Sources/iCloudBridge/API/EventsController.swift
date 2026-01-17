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
