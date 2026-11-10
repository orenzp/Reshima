import Foundation

public struct PersistedSnapshot: Codable {
    public var householdId: UUID
    public var listId: UUID
    public var language: AppLanguage
    public var categories: [Category]
    public var catalog: [CatalogItem]
    public var items: [ListItem]
}

public final class LocalPersistence {
    private let fileURL: URL

    public init(filename: String = "reshima_offline_cache.json") {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = docDir.appendingPathComponent(filename)
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
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save local cache: \(error)")
        }
    }

    public func saveLocalPhoto(_ data: Data, for itemId: UUID) -> String? {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let photosDir = docDir.appendingPathComponent("ItemPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let file = photosDir.appendingPathComponent("\(itemId.uuidString).jpg")
        do {
            try data.write(to: file, options: .atomic)
            return file.path
        } catch {
            return nil
        }
    }
}
