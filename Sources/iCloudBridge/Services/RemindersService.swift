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
    private var eventStore = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var allLists: [EKCalendar] = []

    private let logFileURL: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/iCloudBridge")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("reminders.log")
    }()

    init() {
        log("RemindersService initialized")
        updateAuthorizationStatus()
        // If already authorized, load lists immediately
        if authorizationStatus == .fullAccess {
            loadLists()
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
        print(message) // Also print to console when running from CLI
    }

    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            updateAuthorizationStatus()
            if granted {
                loadLists()
            }
            log("Access request result: \(granted)")
            return granted
        } catch {
            log("Failed to request access: \(error)")
            return false
        }
    }

    func loadLists() {
        // Reset the event store to ensure fresh data
        eventStore.reset()
        allLists = eventStore.calendars(for: .reminder)
        log("Loaded \(allLists.count) reminder lists")
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
            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: dueDate
            )
            components.calendar = Calendar.current
            reminder.dueDateComponents = components
        }

        do {
            try eventStore.save(reminder, commit: true)
            return reminder
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }
    }

    func updateReminder(_ reminder: EKReminder, title: String?, notes: String?, isCompleted: Bool?, priority: Int?, dueDate: Date?) throws -> EKReminder {
        log("Updating reminder: \(reminder.calendarItemIdentifier)")

        // Refresh the reminder to ensure we have the latest version
        reminder.refresh()

        if let title = title {
            log("  Setting title: \(title)")
            reminder.title = title
        }
        if let notes = notes {
            log("  Setting notes: \(notes)")
            reminder.notes = notes
        }
        if let isCompleted = isCompleted {
            log("  Setting completed: \(isCompleted)")
            reminder.isCompleted = isCompleted
        }
        if let priority = priority {
            log("  Setting priority: \(priority)")
            reminder.priority = priority
        }
        if let dueDate = dueDate {
            log("  Setting due date to: \(dueDate)")

            // Clear existing due date first to ensure clean update
            reminder.dueDateComponents = nil

            var components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: dueDate
            )
            components.calendar = Calendar.current
            reminder.dueDateComponents = components

            log("  DateComponents: year=\(components.year ?? 0) month=\(components.month ?? 0) day=\(components.day ?? 0) hour=\(components.hour ?? 0) minute=\(components.minute ?? 0) tz=\(components.timeZone?.identifier ?? "nil")")
        }

        do {
            try eventStore.save(reminder, commit: true)
            log("  Successfully saved reminder")

            // Reload the reminder to get fresh data
            eventStore.reset()
            guard let updatedReminder = eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
                throw RemindersError.saveFailed("Could not reload reminder after save")
            }

            log("  Reloaded reminder - due date now: \(updatedReminder.dueDateComponents?.date ?? Date.distantPast)")
            return updatedReminder
        } catch {
            log("  Save failed: \(error)")
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
