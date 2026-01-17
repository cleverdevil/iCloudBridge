import Vapor
import Foundation

actor ServerManager {
    private var app: Application?
    private let remindersService: RemindersService
    private let photosService: PhotosService
    private let calendarsService: CalendarsService
    private let selectedListIds: () -> [String]
    private let selectedAlbumIds: () -> [String]
    private let selectedCalendarIds: () -> [String]
    let tokenManager: TokenManager
    private let allowRemoteConnections: () -> Bool

    init(
        remindersService: RemindersService,
        photosService: PhotosService,
        calendarsService: CalendarsService,
        selectedListIds: @escaping () -> [String],
        selectedAlbumIds: @escaping () -> [String],
        selectedCalendarIds: @escaping () -> [String],
        tokenManager: TokenManager,
        allowRemoteConnections: @escaping () -> Bool
    ) {
        self.remindersService = remindersService
        self.photosService = photosService
        self.calendarsService = calendarsService
        self.selectedListIds = selectedListIds
        self.selectedAlbumIds = selectedAlbumIds
        self.selectedCalendarIds = selectedCalendarIds
        self.tokenManager = tokenManager
        self.allowRemoteConnections = allowRemoteConnections
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

        // Bind to all interfaces if remote connections allowed, otherwise localhost only
        newApp.http.server.configuration.hostname = allowRemoteConnections() ? "0.0.0.0" : "127.0.0.1"
        newApp.http.server.configuration.port = port

        // Configure JSON encoder for dates
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        ContentConfiguration.global.use(encoder: encoder, for: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ContentConfiguration.global.use(decoder: decoder, for: .json)

        try configureRoutes(
            newApp,
            remindersService: remindersService,
            photosService: photosService,
            calendarsService: calendarsService,
            selectedListIds: selectedListIds,
            selectedAlbumIds: selectedAlbumIds,
            selectedCalendarIds: selectedCalendarIds,
            tokenManager: tokenManager,
            isAuthEnabled: allowRemoteConnections
        )

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
