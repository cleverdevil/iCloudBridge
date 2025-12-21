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

    init() {
        self.remindersService = RemindersService()
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
