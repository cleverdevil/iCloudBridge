import EventKit
import Foundation
import AppKit

enum RemindersError: Error, LocalizedError {
    case accessDenied
    case listNotFound(String)
    case reminderNotFound(String)
    case saveFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to Reminders was denied"
        case .listNotFound(let id):
            return "List not found: \(id)"
        case .reminderNotFound(let id):
            return "Reminder not found: \(id)"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete: \(reason)"
        }
    }
}

@MainActor
class RemindersService: ObservableObject {
    private let eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var allLists: [EKCalendar] = []

    init() {
        updateAuthorizationStatus()
    }

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            await MainActor.run {
                updateAuthorizationStatus()
                if granted {
                    loadLists()
                }
            }
            return granted
        } catch {
            print("Failed to request access: \(error)")
            return false
        }
    }

    func loadLists() {
        allLists = eventStore.calendars(for: .reminder)
    }

    // MARK: - List Operations

    func getLists(ids: [String]) -> [EKCalendar] {
        return allLists.filter { ids.contains($0.calendarIdentifier) }
    }

    func getList(id: String) -> EKCalendar? {
        return allLists.first { $0.calendarIdentifier == id }
    }

    // MARK: - Reminder Operations

    func getReminders(in list: EKCalendar) async throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [list])
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func getReminder(id: String) -> EKReminder? {
        return eventStore.calendarItem(withIdentifier: id) as? EKReminder
    }

    func createReminder(in list: EKCalendar, title: String, notes: String?, priority: Int?, dueDate: Date?) throws -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority ?? 0

        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        do {
            try eventStore.save(reminder, commit: true)
            return reminder
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }
    }

    func updateReminder(_ reminder: EKReminder, title: String?, notes: String?, isCompleted: Bool?, priority: Int?, dueDate: Date?) throws -> EKReminder {
        if let title = title {
            reminder.title = title
        }
        if let notes = notes {
            reminder.notes = notes
        }
        if let isCompleted = isCompleted {
            reminder.isCompleted = isCompleted
        }
        if let priority = priority {
            reminder.priority = priority
        }
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        do {
            try eventStore.save(reminder, commit: true)
            return reminder
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }
    }

    func deleteReminder(_ reminder: EKReminder) throws {
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw RemindersError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - DTO Conversions

    func toDTO(_ reminder: EKReminder) -> ReminderDTO {
        var dueDate: Date? = nil
        if let components = reminder.dueDateComponents {
            dueDate = Calendar.current.date(from: components)
        }

        return ReminderDTO(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            dueDate: dueDate,
            completionDate: reminder.completionDate,
            listId: reminder.calendar.calendarIdentifier
        )
    }

    func toDTO(_ list: EKCalendar, reminderCount: Int) -> ListDTO {
        var colorHex: String? = nil
        if let cgColor = list.cgColor {
            let nsColor = NSColor(cgColor: cgColor)
            if let rgb = nsColor?.usingColorSpace(.sRGB) {
                colorHex = String(format: "#%02X%02X%02X",
                    Int(rgb.redComponent * 255),
                    Int(rgb.greenComponent * 255),
                    Int(rgb.blueComponent * 255))
            }
        }

        return ListDTO(
            id: list.calendarIdentifier,
            title: list.title,
            color: colorHex,
            reminderCount: reminderCount
        )
    }
}
