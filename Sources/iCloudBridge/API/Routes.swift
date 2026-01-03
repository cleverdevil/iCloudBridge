import Vapor

func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String],
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
}
