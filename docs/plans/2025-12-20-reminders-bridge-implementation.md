# iCloud Bridge - Reminders Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that exposes selected iCloud Reminders lists via a REST API.

**Architecture:** SwiftUI menu bar app with embedded Vapor server. EventKit provides Reminders access. UserDefaults persists configuration. Modular structure for future iCloud bridges.

**Tech Stack:** Swift 5.9+, SwiftUI, Vapor 4, EventKit, Swift Package Manager

---

### Task 1: Project Setup

**Files:**
- Create: `Package.swift`
- Create: `Sources/iCloudBridge/iCloudBridgeApp.swift`
- Create: `Sources/iCloudBridge/Info.plist`

**Step 1: Initialize git repository**

Run:
```bash
cd /Volumes/Chonker/Development/icloudbridge
git init
```

**Step 2: Create Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iCloudBridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "iCloudBridge",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/iCloudBridge",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
```

**Step 3: Create minimal app entry point**

Create `Sources/iCloudBridge/iCloudBridgeApp.swift`:

```swift
import SwiftUI

@main
struct iCloudBridgeApp: App {
    var body: some Scene {
        MenuBarExtra("iCloud Bridge", systemImage: "cloud") {
            Text("iCloud Bridge")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

**Step 4: Create Info.plist for permissions**

Create `Sources/iCloudBridge/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSRemindersUsageDescription</key>
    <string>iCloud Bridge needs access to Reminders to expose them via the REST API.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

**Step 5: Create .gitignore**

Create `.gitignore`:

```
.DS_Store
/.build
/Packages
xcuserdata/
DerivedData/
.swiftpm/
*.xcodeproj
```

**Step 6: Verify project builds**

Run:
```bash
cd /Volumes/Chonker/Development/icloudbridge
swift build
```

Expected: Build succeeds

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: initial project setup with SwiftUI menu bar app"
```

---

### Task 2: Data Models (DTOs)

**Files:**
- Create: `Sources/iCloudBridge/Models/ReminderDTO.swift`
- Create: `Sources/iCloudBridge/Models/ListDTO.swift`
- Create: `Sources/iCloudBridge/Models/ErrorResponse.swift`

**Step 1: Create ReminderDTO**

Create `Sources/iCloudBridge/Models/ReminderDTO.swift`:

```swift
import Foundation
import Vapor

struct ReminderDTO: Content {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let priority: Int
    let dueDate: Date?
    let completionDate: Date?
    let listId: String
}

struct CreateReminderDTO: Content {
    let title: String
    let notes: String?
    let priority: Int?
    let dueDate: Date?
}

struct UpdateReminderDTO: Content {
    let title: String?
    let notes: String?
    let isCompleted: Bool?
    let priority: Int?
    let dueDate: Date?
}
```

**Step 2: Create ListDTO**

Create `Sources/iCloudBridge/Models/ListDTO.swift`:

```swift
import Foundation
import Vapor

struct ListDTO: Content {
    let id: String
    let title: String
    let color: String?
    let reminderCount: Int
}
```

**Step 3: Create ErrorResponse**

Create `Sources/iCloudBridge/Models/ErrorResponse.swift`:

```swift
import Vapor

struct ErrorResponse: Content {
    let error: Bool
    let reason: String

    init(_ reason: String) {
        self.error = true
        self.reason = reason
    }
}
```

**Step 4: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DTO models for API responses"
```

---

### Task 3: RemindersService (EventKit Wrapper)

**Files:**
- Create: `Sources/iCloudBridge/Services/RemindersService.swift`

**Step 1: Create RemindersService**

Create `Sources/iCloudBridge/Services/RemindersService.swift`:

```swift
import EventKit
import Foundation

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
```

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add RemindersService for EventKit operations"
```

---

### Task 4: AppState (Observable State Object)

**Files:**
- Create: `Sources/iCloudBridge/AppState.swift`

**Step 1: Create AppState**

Create `Sources/iCloudBridge/AppState.swift`:

```swift
import Foundation
import SwiftUI

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
    @Published var serverPort: Int = 31337
    @Published var serverStatus: ServerStatus = .stopped
    @Published var showingSettings: Bool = false

    let remindersService: RemindersService

    private let selectedListIdsKey = "selectedListIds"
    private let serverPortKey = "serverPort"

    init(remindersService: RemindersService = RemindersService()) {
        self.remindersService = remindersService
        loadSettings()
    }

    var hasValidSettings: Bool {
        return !selectedListIds.isEmpty
    }

    var selectedLists: [String] {
        return Array(selectedListIds)
    }

    // MARK: - Persistence

    func loadSettings() {
        if let savedIds = UserDefaults.standard.array(forKey: selectedListIdsKey) as? [String] {
            selectedListIds = Set(savedIds)
        }
        let savedPort = UserDefaults.standard.integer(forKey: serverPortKey)
        if savedPort > 0 {
            serverPort = savedPort
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(Array(selectedListIds), forKey: selectedListIdsKey)
        UserDefaults.standard.set(serverPort, forKey: serverPortKey)
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
}
```

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add AppState for settings and state management"
```

---

### Task 5: API Controllers

**Files:**
- Create: `Sources/iCloudBridge/API/ListsController.swift`
- Create: `Sources/iCloudBridge/API/RemindersController.swift`
- Create: `Sources/iCloudBridge/API/Routes.swift`

**Step 1: Create ListsController**

Create `Sources/iCloudBridge/API/ListsController.swift`:

```swift
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

        let reminders = try await remindersService.getReminders(in: list)
        return await MainActor.run {
            reminders.map { remindersService.toDTO($0) }
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
```

**Step 2: Create RemindersController**

Create `Sources/iCloudBridge/API/RemindersController.swift`:

```swift
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
```

**Step 3: Create Routes**

Create `Sources/iCloudBridge/API/Routes.swift`:

```swift
import Vapor

func configureRoutes(_ app: Application, remindersService: RemindersService, selectedListIds: @escaping () -> [String]) throws {
    let api = app.grouped("api", "v1")

    try api.register(collection: ListsController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: RemindersController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    // Health check endpoint
    app.get("health") { req in
        return ["status": "ok"]
    }
}
```

**Step 4: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add API controllers and routes"
```

---

### Task 6: ServerManager (Vapor Lifecycle)

**Files:**
- Create: `Sources/iCloudBridge/Services/ServerManager.swift`

**Step 1: Create ServerManager**

Create `Sources/iCloudBridge/Services/ServerManager.swift`:

```swift
import Vapor
import Foundation

actor ServerManager {
    private var app: Application?
    private let remindersService: RemindersService
    private let selectedListIds: () -> [String]

    init(remindersService: RemindersService, selectedListIds: @escaping () -> [String]) {
        self.remindersService = remindersService
        self.selectedListIds = selectedListIds
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
        newApp.http.server.configuration.hostname = "0.0.0.0"
        newApp.http.server.configuration.port = port

        // Configure JSON encoder for dates
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        ContentConfiguration.global.use(encoder: encoder, for: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ContentConfiguration.global.use(decoder: decoder, for: .json)

        try configureRoutes(newApp, remindersService: remindersService, selectedListIds: selectedListIds)

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

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ServerManager for Vapor lifecycle"
```

---

### Task 7: Settings View

**Files:**
- Create: `Sources/iCloudBridge/Views/SettingsView.swift`

**Step 1: Create SettingsView**

Create `Sources/iCloudBridge/Views/SettingsView.swift`:

```swift
import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let onSave: () -> Void

    @State private var portString: String = ""
    @State private var showingPortError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("iCloud Bridge Settings")
                .font(.title)
                .padding(.bottom, 10)

            // Permission Status
            permissionSection

            Divider()

            // Lists Selection
            if appState.remindersService.authorizationStatus == .fullAccess {
                listsSection

                Divider()

                // Port Configuration
                portSection

                Divider()

                // Save Button
                HStack {
                    Spacer()
                    Button("Save & Start Server") {
                        saveAndStart()
                    }
                    .disabled(!appState.hasValidSettings || !isValidPort)
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 500)
        .onAppear {
            portString = String(appState.serverPort)
            Task {
                if appState.remindersService.authorizationStatus != .fullAccess {
                    _ = await appState.remindersService.requestAccess()
                } else {
                    appState.remindersService.loadLists()
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders Access")
                .font(.headline)

            HStack {
                switch appState.remindersService.authorizationStatus {
                case .fullAccess:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Access granted")
                case .denied, .restricted:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Access denied")
                    Spacer()
                    Button("Open System Settings") {
                        openSystemSettings()
                    }
                case .notDetermined, .writeOnly:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.yellow)
                    Text("Permission required")
                    Spacer()
                    Button("Grant Access") {
                        Task {
                            _ = await appState.remindersService.requestAccess()
                        }
                    }
                @unknown default:
                    Text("Unknown status")
                }
            }
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Reminders Lists")
                .font(.headline)

            Text("Choose which lists to expose via the API:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.remindersService.allLists, id: \.calendarIdentifier) { list in
                        Toggle(isOn: Binding(
                            get: { appState.isListSelected(list.calendarIdentifier) },
                            set: { _ in appState.toggleList(list.calendarIdentifier) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: list.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                                    .frame(width: 12, height: 12)
                                Text(list.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private var portSection: some View {
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
        }
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
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add SettingsView for configuration UI"
```

---

### Task 8: Menu Bar View & App Integration

**Files:**
- Modify: `Sources/iCloudBridge/iCloudBridgeApp.swift`

**Step 1: Update iCloudBridgeApp with full implementation**

Replace contents of `Sources/iCloudBridge/iCloudBridgeApp.swift`:

```swift
import SwiftUI

@main
struct iCloudBridgeApp: App {
    @StateObject private var appState = AppState()
    @State private var serverManager: ServerManager?

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

        Window("iCloud Bridge Settings", id: "settings") {
            SettingsView(appState: appState, onSave: startServer)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text("iCloud Bridge")
        }
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
                    selectedListIds: { appState.selectedLists }
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
}

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    let onStartServer: () -> Void
    let onStopServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("iCloud Bridge")
                .font(.headline)

            Divider()

            statusSection

            Divider()

            Button("Open Settings...") {
                openWindow(id: "settings")
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
                Text("\(appState.selectedListIds.count) lists selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

**Step 2: Verify build**

Run:
```bash
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: integrate menu bar, settings, and server management"
```

---

### Task 9: Final Integration & Testing

**Step 1: Build release version**

Run:
```bash
cd /Volumes/Chonker/Development/icloudbridge
swift build -c release
```

Expected: Build succeeds

**Step 2: Run the app**

Run:
```bash
.build/release/iCloudBridge
```

Expected: App appears in menu bar

**Step 3: Manual testing checklist**

- [ ] Menu bar icon appears
- [ ] Clicking menu bar shows menu
- [ ] "Open Settings" opens settings window
- [ ] Reminders permission prompt appears (first run)
- [ ] Lists appear after granting permission
- [ ] Can select/deselect lists
- [ ] Can change port number
- [ ] "Save & Start Server" starts server
- [ ] Menu bar shows "Running on port X"
- [ ] `curl http://localhost:31337/health` returns `{"status":"ok"}`
- [ ] `curl http://localhost:31337/api/v1/lists` returns selected lists
- [ ] Can create, read, update, delete reminders via API
- [ ] "Stop Server" stops server
- [ ] "Quit" exits app

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete iCloud Bridge reminders implementation"
```

---

## Summary

This plan implements:
1. **Project setup** with SwiftUI + Vapor via SPM
2. **Data models** for API responses (DTOs)
3. **RemindersService** wrapping EventKit operations
4. **AppState** for observable settings management
5. **API controllers** for lists and reminders CRUD
6. **ServerManager** for Vapor lifecycle
7. **SettingsView** for configuration UI
8. **Menu bar integration** with status display

Future extensions (calendars, contacts, photos) would follow the same pattern: add a service, controllers, and routes.
