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
