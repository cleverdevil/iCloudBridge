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
