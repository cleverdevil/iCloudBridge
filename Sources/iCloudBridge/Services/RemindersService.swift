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
            // Default to timed reminders for new reminders when time is not midnight
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: dueDate)
            let isMidnight = components.hour == 0 && components.minute == 0

            var dueDateComponents: DateComponents
            var startDateComponents: DateComponents

            if isMidnight {
                // Midnight = likely intended as all-day
                dueDateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                startDateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                log("Creating ALL-DAY reminder: \(title)")
            } else {
                // Has specific time
                dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: dueDate)
                startDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: dueDate)
                log("Creating TIMED reminder: \(title)")
            }

            dueDateComponents.calendar = calendar
            startDateComponents.calendar = calendar

            // CRITICAL: EventKit requires startDateComponents to be set when dueDateComponents is set
            reminder.startDateComponents = startDateComponents
            reminder.dueDateComponents = dueDateComponents
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

            // Check if existing reminder has time components or is all-day
            let existingComponents = reminder.dueDateComponents
            let hadExistingDate = existingComponents != nil
            let hasTime = existingComponents?.hour != nil || existingComponents?.minute != nil
            log("  Existing reminder had date: \(hadExistingDate), had time component: \(hasTime)")

            // CRITICAL: To update an existing due date, we must:
            // 1. Clear both start and due date components
            // 2. Save that change
            // 3. Then set new components
            // 4. Save again
            // This mimics manually clearing the date in Reminders app first

            if hadExistingDate {
                log("  Clearing existing date components first...")
                reminder.startDateComponents = nil
                reminder.dueDateComponents = nil

                // Save the cleared state
                do {
                    try eventStore.save(reminder, commit: true)
                    log("  Saved cleared date state")
                } catch {
                    log("  Failed to save cleared state: \(error)")
                    throw RemindersError.saveFailed("Failed to clear existing date: \(error.localizedDescription)")
                }

                // Reload the reminder to get fresh state
                eventStore.reset()
                guard let clearedReminder = eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
                    throw RemindersError.saveFailed("Could not reload reminder after clearing date")
                }

                // Update our reference to the cleared reminder
                reminder.refresh()
            }

            // Now set the new date components
            // Determine if this should be timed or all-day based on the provided date
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: dueDate)
            let isMidnight = timeComponents.hour == 0 && timeComponents.minute == 0

            // If the new date has a specific time (not midnight), make it timed
            // Otherwise make it all-day
            let shouldBeTimed = !isMidnight

            log("  Setting new date as \(shouldBeTimed ? "TIMED" : "ALL-DAY") (midnight=\(isMidnight))")

            var startComponents: DateComponents
            var dueComponents: DateComponents

            if shouldBeTimed {
                startComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .timeZone],
                    from: dueDate
                )
                dueComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .timeZone],
                    from: dueDate
                )
                log("  TIMED: year=\(dueComponents.year ?? 0) month=\(dueComponents.month ?? 0) day=\(dueComponents.day ?? 0) hour=\(dueComponents.hour ?? 0) minute=\(dueComponents.minute ?? 0) tz=\(dueComponents.timeZone?.identifier ?? "nil")")
            } else {
                startComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                dueComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
                log("  ALL-DAY: year=\(dueComponents.year ?? 0) month=\(dueComponents.month ?? 0) day=\(dueComponents.day ?? 0)")
            }

            startComponents.calendar = calendar
            dueComponents.calendar = calendar

            reminder.startDateComponents = startComponents
            reminder.dueDateComponents = dueComponents
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
