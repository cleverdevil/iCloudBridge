import Vapor

func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    calendarsService: CalendarsService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String],
    selectedCalendarIds: @escaping () -> [String],
    tokenManager: TokenManager,
    isAuthEnabled: @escaping () -> Bool
) throws {
    // Health check endpoint - always accessible (no auth)
    app.get("health") { req in
        return ["status": "ok"]
    }

    // API routes with authentication middleware
    let authMiddleware = AuthMiddleware(tokenManager: tokenManager, isAuthEnabled: isAuthEnabled)
    let api = app.grouped("api", "v1").grouped(authMiddleware)

    try api.register(collection: ListsController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: RemindersController(
        remindersService: remindersService,
        selectedListIds: selectedListIds
    ))

    try api.register(collection: AlbumsController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: PhotosController(
        photosService: photosService,
        selectedAlbumIds: selectedAlbumIds
    ))

    try api.register(collection: CalendarsController(
        calendarsService: calendarsService,
        selectedCalendarIds: selectedCalendarIds
    ))

    try api.register(collection: EventsController(
        calendarsService: calendarsService,
        selectedCalendarIds: selectedCalendarIds
    ))
}
