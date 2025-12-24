import Vapor

func configureRoutes(
    _ app: Application,
    remindersService: RemindersService,
    photosService: PhotosService,
    selectedListIds: @escaping () -> [String],
    selectedAlbumIds: @escaping () -> [String]
) throws {
    let api = app.grouped("api", "v1")

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

    // Health check endpoint
    app.get("health") { req in
        return ["status": "ok"]
    }
}
