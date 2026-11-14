import Foundation

public struct PersistedSnapshot: Codable {
    public var householdId: UUID
    public var listId: UUID
    public var language: AppLanguage
    public var categories: [Category]
    public var catalog: [CatalogItem]
    public var items: [ListItem]
    // Outbox of changes not yet confirmed by the server (optional so older caches still load).
    public var pendingItems: PendingItemQueue?
    public var pendingCatalog: [String: PendingCatalogChange]?
    public var pendingCategoryOrder: Bool?
    public var pendingPhotoUploads: [String]?
}

public final class LocalPersistence {
    private let fileURL: URL
    private let photosDir: URL

    public init(filename: String = "reshima_offline_cache.json") {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = docDir.appendingPathComponent(filename)
        self.photosDir = docDir.appendingPathComponent("ItemPhotos", isDirectory: true)
    }

    public func load() -> PersistedSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistedSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public func save(_ snapshot: PersistedSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save local cache: \(error)")
        }
    }

    // MARK: - Photo cache
    // Photos are identified by their Storage object path ("<household>/<file>.jpg"), which is the
    // same on every phone. Only the file name is used locally, so the cache survives app updates.

    private func photoFileURL(forStoragePath storagePath: String) -> URL {
        let fileName = (storagePath as NSString).lastPathComponent
        return photosDir.appendingPathComponent(fileName)
    }

    @discardableResult
    public func savePhoto(_ data: Data, storagePath: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
            try data.write(to: photoFileURL(forStoragePath: storagePath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func loadPhoto(storagePath: String) -> Data? {
        if storagePath.hasPrefix("/") {
            // Legacy value from before photos were uploaded: an absolute path on the phone that took it.
            return try? Data(contentsOf: URL(fileURLWithPath: storagePath))
        }
        return try? Data(contentsOf: photoFileURL(forStoragePath: storagePath))
    }

    public func deletePhoto(storagePath: String) {
        guard !storagePath.hasPrefix("/") else { return }
        try? FileManager.default.removeItem(at: photoFileURL(forStoragePath: storagePath))
    }
}
