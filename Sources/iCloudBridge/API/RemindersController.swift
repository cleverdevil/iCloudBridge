import Vapor
import EventKit

struct RemindersController: RouteCollection {
    let remindersService: RemindersService
    let selectedListIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let reminders = routes.grouped("reminders")
        reminders.get(":reminderId", use: show)
        reminders.put(":reminderId", use: update)
        reminders.delete(":reminderId", use: delete)
    }

    @Sendable
    func show(req: Request) async throws -> ReminderDTO {
        guard let reminderId = req.parameters.get("reminderId") else {
            throw Abort(.badRequest, reason: "Missing reminder ID")
        }

        guard let reminder = await MainActor.run(body: { remindersService.getReminder(id: reminderId) }) else {
            throw Abort(.notFound, reason: "Reminder not found")
        }

        let ids = selectedListIds()
        guard ids.contains(reminder.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Reminder not found or list not selected")
        }

        return await MainActor.run {
            remindersService.toDTO(reminder)
        }
    }

    @Sendable
    func update(req: Request) async throws -> ReminderDTO {
        guard let reminderId = req.parameters.get("reminderId") else {
            throw Abort(.badRequest, reason: "Missing reminder ID")
        }

        guard let reminder = await MainActor.run(body: { remindersService.getReminder(id: reminderId) }) else {
            throw Abort(.notFound, reason: "Reminder not found")
        }

        let ids = selectedListIds()
        guard ids.contains(reminder.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Reminder not found or list not selected")
        }

        let dto = try req.content.decode(UpdateReminderDTO.self)

        let updated = try await MainActor.run {
            try remindersService.updateReminder(
                reminder,
                title: dto.title,
                notes: dto.notes,
                isCompleted: dto.isCompleted,
                priority: dto.priority,
                dueDate: dto.dueDate
            )
        }

        return await MainActor.run {
            remindersService.toDTO(updated)
        }
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let reminderId = req.parameters.get("reminderId") else {
            throw Abort(.badRequest, reason: "Missing reminder ID")
        }

        guard let reminder = await MainActor.run(body: { remindersService.getReminder(id: reminderId) }) else {
            throw Abort(.notFound, reason: "Reminder not found")
        }

        let ids = selectedListIds()
        guard ids.contains(reminder.calendar.calendarIdentifier) else {
            throw Abort(.notFound, reason: "Reminder not found or list not selected")
        }

        try await MainActor.run {
            try remindersService.deleteReminder(reminder)
        }

        return .noContent
    }
}
