import Photos

struct AlbumItem: Identifiable {
    let collection: PHAssetCollection
    let photoCount: Int

    var id: String { collection.localIdentifier }
    var title: String { collection.localizedTitle ?? "Untitled" }
}

struct FolderItem: Identifiable {
    let collectionList: PHCollectionList
    var albums: [AlbumItem]
    var isExpanded: Bool = false

    var id: String { collectionList.localIdentifier }
    var title: String { collectionList.localizedTitle ?? "Untitled Folder" }
}

struct AlbumHierarchy {
    var myAlbums: [AlbumItem] = []
    var folders: [FolderItem] = []
    var sharedAlbums: [AlbumItem] = []
    var smartAlbums: [AlbumItem] = []

    var myAlbumsCount: Int {
        myAlbums.count + folders.reduce(0) { $0 + $1.albums.count }
    }

    var allSelectableAlbums: [PHAssetCollection] {
        var all: [PHAssetCollection] = []
        all.append(contentsOf: myAlbums.map { $0.collection })
        for folder in folders {
            all.append(contentsOf: folder.albums.map { $0.collection })
        }
        all.append(contentsOf: sharedAlbums.map { $0.collection })
        all.append(contentsOf: smartAlbums.map { $0.collection })
        return all
    }
}
