import Vapor
import EventKit

struct ListsController: RouteCollection {
    let remindersService: RemindersService
    let selectedListIds: () -> [String]

    func boot(routes: RoutesBuilder) throws {
        let lists = routes.grouped("lists")
        lists.get(use: index)
        lists.get(":listId", use: show)
        lists.get(":listId", "reminders", use: reminders)
        lists.post(":listId", "reminders", use: createReminder)
    }

    @Sendable
    func index(req: Request) async throws -> [ListDTO] {
        let ids = selectedListIds()
        let lists = await MainActor.run {
            remindersService.getLists(ids: ids)
        }

        var result: [ListDTO] = []
        for list in lists {
            let reminders = try await remindersService.getReminders(in: list)
            let dto = await MainActor.run {
                remindersService.toDTO(list, reminderCount: reminders.count)
            }
            result.append(dto)
        }
        return result
    }

    @Sendable
    func show(req: Request) async throws -> ListDTO {
        guard let listId = req.parameters.get("listId") else {
            throw Abort(.badRequest, reason: "Missing list ID")
        }

        let ids = selectedListIds()
        guard ids.contains(listId) else {
            throw Abort(.notFound, reason: "List not found or not selected")
        }

        guard let list = await MainActor.run(body: { remindersService.getList(id: listId) }) else {
            throw Abort(.notFound, reason: "List not found")
        }

        let reminders = try await remindersService.getReminders(in: list)
        return await MainActor.run {
            remindersService.toDTO(list, reminderCount: reminders.count)
        }
    }

    @Sendable
    func reminders(req: Request) async throws -> [ReminderDTO] {
        guard let listId = req.parameters.get("listId") else {
            throw Abort(.badRequest, reason: "Missing list ID")
        }

        let ids = selectedListIds()
        guard ids.contains(listId) else {
            throw Abort(.notFound, reason: "List not found or not selected")
        }

        guard let list = await MainActor.run(body: { remindersService.getList(id: listId) }) else {
            throw Abort(.notFound, reason: "List not found")
        }

        // Get includeCompleted query parameter (default: false)
        let includeCompleted = (try? req.query.get(Bool.self, at: "includeCompleted")) ?? false

        let allReminders = try await remindersService.getReminders(in: list)

        // Filter by completion status unless includeCompleted is true
        let filteredReminders = includeCompleted ? allReminders : allReminders.filter { !$0.isCompleted }

        return await MainActor.run {
            filteredReminders.map { remindersService.toDTO($0) }
        }
    }

    @Sendable
    func createReminder(req: Request) async throws -> ReminderDTO {
        guard let listId = req.parameters.get("listId") else {
            throw Abort(.badRequest, reason: "Missing list ID")
        }

        let ids = selectedListIds()
        guard ids.contains(listId) else {
            throw Abort(.notFound, reason: "List not found or not selected")
        }

        guard let list = await MainActor.run(body: { remindersService.getList(id: listId) }) else {
            throw Abort(.notFound, reason: "List not found")
        }

        let dto = try req.content.decode(CreateReminderDTO.self)

        let reminder = try await MainActor.run {
            try remindersService.createReminder(
                in: list,
                title: dto.title,
                notes: dto.notes,
                priority: dto.priority,
                dueDate: dto.dueDate
            )
        }

        return await MainActor.run {
            remindersService.toDTO(reminder)
        }
    }
}
