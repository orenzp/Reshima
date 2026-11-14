import Foundation
import Observation
import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

/// What the sync badge shows.
public enum SyncState: Equatable, Sendable {
    /// No household code entered yet: the list lives only on this phone.
    case needsCode
    case connecting
    case synced
    /// The network is unreachable; changes are queued and sent later.
    case offline
    /// The server does not know the household code.
    case invalidCode
    case error(String)
}

/// Single source of truth for the UI.
///
/// Every user action updates local state immediately, records the change in a persisted outbox and
/// then asks for a sync. A sync pass sends the outbox (only the changed fields), fetches the server
/// state and merges it with whatever is still pending — so nothing typed offline is ever overwritten.
/// Realtime change events from the other phone simply trigger the next pass.
@Observable
@MainActor
public final class ShoppingStore {
    public var language: AppLanguage = .hebrew {
        didSet { persistLocally() }
    }
    public private(set) var householdId: UUID
    public private(set) var listId: UUID
    public private(set) var categories: [Category]
    public private(set) var catalog: [CatalogItem]
    public private(set) var items: [ListItem]
    public private(set) var config: SupabaseConfig
    public private(set) var syncState: SyncState = .needsCode

    private var pendingItems = PendingItemQueue()
    private var pendingCatalog: [String: PendingCatalogChange] = [:]
    private var pendingCategoryOrder = false
    private var pendingPhotoUploads: [String] = []
    private var photoUploadRejections: [String: Int] = [:]

    private let persistence = LocalPersistence()
    private var sessionTask: Task<Void, Never>?
    private var isJoined = false
    private var isSyncing = false
    private var syncAgain = false
    #if canImport(Supabase)
    private var client: SupabaseClient?
    #endif

    private static let photoBucket = "item-photos"
    private static let pollInterval: Duration = .seconds(30)
    private static let retryInterval: Duration = .seconds(8)

    public init() {
        self.config = SupabaseConfig.loadDefault()

        if let cached = persistence.load() {
            self.householdId = cached.householdId
            self.listId = cached.listId
            self.language = cached.language
            self.categories = cached.categories
            self.catalog = cached.catalog
            self.items = cached.items
            self.pendingItems = cached.pendingItems ?? PendingItemQueue()
            self.pendingCatalog = cached.pendingCatalog ?? [:]
            self.pendingCategoryOrder = cached.pendingCategoryOrder ?? false
            self.pendingPhotoUploads = cached.pendingPhotoUploads ?? []
        } else {
            // First launch: a usable local list with the default aisles. The household's real data
            // replaces these once a code is entered (aisles are matched by `kind`).
            let localHousehold = SupabaseConfig.defaultHouseholdId
            let seededCategories = DefaultSeedData.categories(householdId: localHousehold)
            self.householdId = localHousehold
            self.listId = SupabaseConfig.defaultListId
            self.language = .hebrew
            self.categories = seededCategories
            self.catalog = DefaultSeedData.catalogItems(householdId: localHousehold, categories: seededCategories)
            self.items = []
            persistLocally()
        }

        startCloudSync()
    }

    // MARK: - Computed Views

    public var activeAisleGroups: [AisleGroup] {
        ShoppingListEngine.groupActiveItemsByAisle(
            items: items,
            categories: categories,
            householdId: householdId
        )
    }

    public var checkedItems: [ListItem] {
        ShoppingListEngine.checkedItems(from: items)
    }

    public func suggestions(for query: String) -> [CatalogItem] {
        ShoppingListEngine.autocompleteSuggestions(
            query: query,
            catalog: catalog,
            activeListItems: items,
            limit: query.isEmpty ? 12 : 6
        )
    }

    public func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }

    /// Local changes waiting to reach the server.
    public var pendingChangeCount: Int {
        pendingItems.count + pendingCatalog.count + pendingPhotoUploads.count + (pendingCategoryOrder ? 1 : 0)
    }

    // MARK: - User Actions (optimistic local update first, then background sync)

    public func quickAddItem(name rawName: String, quantity: Double = 1.0, explicitCategory: UUID? = nil, explicitUnit: UnitType? = nil) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If an unchecked item with the same normalized name already exists, increment its quantity
        let normalized = CatalogItem.normalize(trimmed)
        if let existingIndex = items.firstIndex(where: { !$0.isChecked && CatalogItem.normalize($0.name) == normalized }) {
            items[existingIndex].quantity += items[existingIndex].unit.stepIncrement
            items[existingIndex].updatedAt = Date()
            pendingItems.recordUpdate(items[existingIndex].id, fields: [.quantity])
            commitLocalChange()
            return
        }

        let inferred = ShoppingListEngine.inferCategoryAndUnit(
            for: trimmed,
            catalog: catalog,
            categories: categories
        )
        let targetCategory = explicitCategory ?? inferred.categoryId
        let targetUnit = explicitUnit ?? inferred.unit

        let newItem = ListItem(
            listId: listId,
            householdId: householdId,
            categoryId: targetCategory,
            name: trimmed,
            quantity: quantity,
            unit: targetUnit
        )
        items.append(newItem)
        pendingItems.recordInsert(newItem.id)

        // Update or insert into catalog history for smart autocomplete
        if let catIdx = catalog.firstIndex(where: { $0.normalizedName == normalized }) {
            catalog[catIdx].usageCount += 1
            if let targetCategory {
                catalog[catIdx].defaultCategoryId = targetCategory
            }
        } else {
            catalog.append(
                CatalogItem(
                    householdId: householdId,
                    name: trimmed,
                    defaultCategoryId: targetCategory,
                    defaultUnit: targetUnit,
                    usageCount: 1,
                    isStaple: false
                )
            )
        }
        markCatalogPending(normalized, usageDelta: 1)

        commitLocalChange()
    }

    public func toggleChecked(_ item: ListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isChecked.toggle()
        items[index].checkedAt = items[index].isChecked ? Date() : nil
        items[index].updatedAt = Date()
        pendingItems.recordUpdate(item.id, fields: [.isChecked])
        commitLocalChange()
    }

    public func adjustQuantity(_ item: ListItem, delta: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let next = items[index].quantity + delta
        guard next > 0 else { return }
        items[index].quantity = next
        items[index].updatedAt = Date()
        pendingItems.recordUpdate(item.id, fields: [.quantity])
        commitLocalChange()
    }

    /// Saves edits from the detail sheet. `newPhotoJPEG` must already be resized JPEG data.
    public func updateItem(_ updated: ListItem, newPhotoJPEG: Data? = nil) {
        guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = items[index]
        var copy = updated
        // The sheet edits a snapshot; keep fields it cannot change in step with the live item.
        copy.isChecked = old.isChecked
        copy.checkedAt = old.checkedAt
        copy.photoPath = old.photoPath

        if let newPhotoJPEG {
            let suffix = UUID().uuidString.prefix(8).lowercased()
            let storagePath = "\(householdId.uuidString.lowercased())/\(copy.id.uuidString.lowercased())-\(suffix).jpg"
            if persistence.savePhoto(newPhotoJPEG, storagePath: storagePath) {
                copy.photoPath = storagePath
                pendingPhotoUploads.append(storagePath)
                if let oldPath = old.photoPath {
                    discardPhoto(oldPath)
                }
            }
        }

        let changed = copy.changedFields(from: old)
        guard !changed.isEmpty else { return }
        copy.updatedAt = Date()
        items[index] = copy
        pendingItems.recordUpdate(copy.id, fields: changed)

        // Remember the corrected aisle & unit for future autocomplete
        if !changed.isDisjoint(with: [.categoryId, .unit]) {
            let normalized = CatalogItem.normalize(copy.name)
            if let catIdx = catalog.firstIndex(where: { $0.normalizedName == normalized }) {
                catalog[catIdx].defaultCategoryId = copy.categoryId
                catalog[catIdx].defaultUnit = copy.unit
                markCatalogPending(normalized)
            }
        }

        commitLocalChange()
    }

    public func deleteItem(_ item: ListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        pendingItems.recordDelete(removed.id)
        if let path = removed.photoPath {
            discardPhoto(path)
        }
        commitLocalChange()
    }

    public func clearCheckedItems() {
        let checked = items.filter(\.isChecked)
        guard !checked.isEmpty else { return }
        items.removeAll(where: \.isChecked)
        for item in checked {
            pendingItems.recordDelete(item.id)
            if let path = item.photoPath {
                discardPhoto(path)
            }
        }
        commitLocalChange()
    }

    public func toggleStaple(_ catalogItem: CatalogItem) {
        guard let idx = catalog.firstIndex(where: { $0.id == catalogItem.id }) else { return }
        catalog[idx].isStaple.toggle()
        markCatalogPending(catalog[idx].normalizedName)
        commitLocalChange()
    }

    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        var sorted = categories.sorted { $0.sortOrder < $1.sortOrder }
        sorted.move(fromOffsets: source, toOffset: destination)
        for idx in sorted.indices {
            sorted[idx].sortOrder = (idx + 1) * 10
        }
        categories = sorted
        pendingCategoryOrder = true
        commitLocalChange()
    }

    public func updateSupabaseConfig(_ newConfig: SupabaseConfig) {
        guard newConfig != config else { return }
        config = newConfig
        newConfig.save()
        startCloudSync()
    }

    /// Photo for an item: from the local cache, otherwise downloaded from Storage and cached.
    public func photoData(forStoragePath storagePath: String) async -> Data? {
        if let cached = persistence.loadPhoto(storagePath: storagePath) {
            return cached
        }
        #if canImport(Supabase)
        guard isJoined, let client, !storagePath.hasPrefix("/") else { return nil }
        guard let data = try? await client.storage.from(Self.photoBucket).download(path: storagePath) else {
            return nil
        }
        persistence.savePhoto(data, storagePath: storagePath)
        return data
        #else
        return nil
        #endif
    }

    // MARK: - Local bookkeeping

    private func commitLocalChange() {
        persistLocally()
        requestSync()
    }

    private func markCatalogPending(_ normalizedName: String, usageDelta: Int = 0) {
        var change = pendingCatalog[normalizedName] ?? PendingCatalogChange()
        change.usageDelta += usageDelta
        change.revision += 1
        pendingCatalog[normalizedName] = change
    }

    private func persistLocally() {
        persistence.save(
            PersistedSnapshot(
                householdId: householdId,
                listId: listId,
                language: language,
                categories: categories,
                catalog: catalog,
                items: items,
                pendingItems: pendingItems,
                pendingCatalog: pendingCatalog,
                pendingCategoryOrder: pendingCategoryOrder,
                pendingPhotoUploads: pendingPhotoUploads
            )
        )
    }

    /// Forgets a photo that is no longer referenced: local file, queued upload and (best effort) the uploaded object.
    private func discardPhoto(_ storagePath: String) {
        persistence.deletePhoto(storagePath: storagePath)
        if let queuedIndex = pendingPhotoUploads.firstIndex(of: storagePath) {
            pendingPhotoUploads.remove(at: queuedIndex)
            return // never uploaded
        }
        #if canImport(Supabase)
        guard isJoined, let client, !storagePath.hasPrefix("/") else { return }
        Task {
            _ = try? await client.storage.from(Self.photoBucket).remove(paths: [storagePath])
        }
        #endif
    }

    // MARK: - Cloud session

    /// (Re)starts syncing with the current configuration. Safe to call repeatedly.
    public func startCloudSync() {
        sessionTask?.cancel()
        sessionTask = nil
        isJoined = false

        #if canImport(Supabase)
        client = nil
        guard config.isConfigured, config.hasInviteCode, let url = URL(string: config.urlString) else {
            syncState = .needsCode
            return
        }
        let newClient = SupabaseClient(supabaseURL: url, supabaseKey: config.anonKey)
        client = newClient
        syncState = .connecting
        sessionTask = Task { [weak self] in
            await self?.runSession(newClient)
        }
        #else
        syncState = .needsCode
        #endif
    }

    /// Asks for a sync pass soon. Cheap to call often: overlapping requests collapse into one extra pass.
    public func requestSync() {
        Task { await performSync() }
    }

    /// Pull-to-refresh.
    public func refresh() async {
        await performSync()
    }

    #if canImport(Supabase)

    private struct JoinResult: Decodable {
        let householdId: UUID
        let listId: UUID

        enum CodingKeys: String, CodingKey {
            case householdId = "household_id"
            case listId = "list_id"
        }
    }

    private struct CatalogUpsertParams: Encodable {
        let item: CatalogItem
        let usageDelta: Int

        enum CodingKeys: String, CodingKey {
            case householdId = "p_household_id"
            case name = "p_name"
            case normalizedName = "p_normalized_name"
            case defaultCategoryId = "p_default_category_id"
            case defaultUnit = "p_default_unit"
            case isStaple = "p_is_staple"
            case usageDelta = "p_usage_delta"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(item.householdId, forKey: .householdId)
            try container.encode(item.name, forKey: .name)
            try container.encode(item.normalizedName, forKey: .normalizedName)
            try container.encode(item.defaultCategoryId, forKey: .defaultCategoryId) // explicit null when nil
            try container.encode(item.defaultUnit, forKey: .defaultUnit)
            try container.encode(item.isStaple, forKey: .isStaple)
            try container.encode(usageDelta, forKey: .usageDelta)
        }
    }

    private struct SortOrderPatch: Encodable {
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case sortOrder = "sort_order"
        }
    }

    /// Server-side error code raised by `join_household` for an unknown invite code.
    private static let invalidCodeErrorCode = "RS001"

    private func runSession(_ client: SupabaseClient) async {
        // 1. Sign in (anonymously) and join the household. Retries until it works or the code is refused.
        while !Task.isCancelled {
            do {
                try await signInAndJoin(client)
                break
            } catch {
                guard isCurrent(client) else { return }
                if let postgrestError = error as? PostgrestError, postgrestError.code == Self.invalidCodeErrorCode {
                    syncState = .invalidCode
                    return
                }
                syncState = Self.isTransient(error) ? .offline : .error(error.localizedDescription)
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
        guard !Task.isCancelled, isCurrent(client) else { return }
        isJoined = true

        // 2. Keep in sync: realtime events for instant updates, a slow poll as a safety net.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.listenForRemoteChanges(client) }
            group.addTask {
                while !Task.isCancelled {
                    await self.performSync()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
        }
    }

    private func isCurrent(_ client: SupabaseClient) -> Bool {
        self.client === client
    }

    private func signInAndJoin(_ client: SupabaseClient) async throws {
        if client.auth.currentSession == nil {
            try await client.auth.signInAnonymously()
        }
        let result: JoinResult
        do {
            result = try await joinHousehold(client)
        } catch let error as PostgrestError where Self.isAuthError(error) {
            // The stored session is no longer accepted (e.g. the user was deleted): start a fresh one.
            try? await client.auth.signOut(scope: .local)
            try await client.auth.signInAnonymously()
            result = try await joinHousehold(client)
        }
        guard isCurrent(client) else { return }
        adoptHousehold(result.householdId, listId: result.listId)
    }

    private func joinHousehold(_ client: SupabaseClient) async throws -> JoinResult {
        try await client
            .rpc("join_household", params: ["p_invite_code": config.householdInviteCode])
            .execute()
            .value
    }

    /// Points local data created before joining (or in another household) at the joined household.
    private func adoptHousehold(_ newHouseholdId: UUID, listId newListId: UUID) {
        guard newHouseholdId != householdId || newListId != listId else { return }
        householdId = newHouseholdId
        listId = newListId
        for index in items.indices {
            items[index].householdId = newHouseholdId
            items[index].listId = newListId
        }
        for index in catalog.indices {
            catalog[index].householdId = newHouseholdId
        }
        for index in categories.indices {
            categories[index].householdId = newHouseholdId
        }
        persistLocally()
    }

    private func listenForRemoteChanges(_ client: SupabaseClient) async {
        while !Task.isCancelled {
            let channel = client.channel("household-\(householdId.uuidString.lowercased())")
            let streams = ["list_items", "categories", "catalog_items"].map { table in
                channel.postgresChange(AnyAction.self, schema: "public", table: table)
            }
            do {
                try await channel.subscribeWithError()
                await withTaskGroup(of: Void.self) { group in
                    for stream in streams {
                        group.addTask {
                            for await _ in stream {
                                await self.performSync()
                            }
                        }
                    }
                }
            } catch {
                // Realtime is an optimisation; the periodic poll keeps the list correct meanwhile.
            }
            await client.removeChannel(channel)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    // MARK: - Sync pass

    private func performSync() async {
        guard isJoined, let client else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            syncAgain = false
            do {
                try await pushPendingChanges(client)
                try await pullRemoteState(client)
                guard isCurrent(client) else { return }
                syncState = .synced
            } catch {
                guard isCurrent(client) else { return }
                syncState = Self.isTransient(error) ? .offline : .error(error.localizedDescription)
                return
            }
        } while syncAgain && !Task.isCancelled
    }

    /// Sends the outbox. Throws only for transient (network/auth) failures, which abort the pass;
    /// changes the server refuses are retried a few times and then dropped so they cannot block the rest.
    private func pushPendingChanges(_ client: SupabaseClient) async throws {
        try await pushPhotoUploads(client)
        try await pushItemChanges(client)
        try await pushCategoryOrder(client)
        try await pushCatalogChanges(client)
    }

    private func pushPhotoUploads(_ client: SupabaseClient) async throws {
        for storagePath in pendingPhotoUploads {
            guard let data = persistence.loadPhoto(storagePath: storagePath) else {
                pendingPhotoUploads.removeAll { $0 == storagePath }
                continue
            }
            do {
                try await client.storage
                    .from(Self.photoBucket)
                    .upload(storagePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                pendingPhotoUploads.removeAll { $0 == storagePath }
            } catch {
                if Self.isTransient(error) { throw error }
                let rejections = photoUploadRejections[storagePath, default: 0] + 1
                photoUploadRejections[storagePath] = rejections
                if rejections >= SyncMerge.maxRejectedAttempts {
                    pendingPhotoUploads.removeAll { $0 == storagePath }
                }
            }
        }
        persistLocally()
    }

    private func pushItemChanges(_ client: SupabaseClient) async throws {
        defer { persistLocally() }

        // All deletions in one request.
        let deletions = pendingItems.changes.filter { $0.kind == .delete }.compactMap { pendingItems.beginAttempt($0.itemId) }
        if !deletions.isEmpty {
            do {
                try await client
                    .from("list_items")
                    .delete()
                    .in("id", values: deletions.map { $0.itemId.uuidString })
                    .execute()
                deletions.forEach { pendingItems.confirm($0) }
            } catch {
                if Self.isTransient(error) { throw error }
                deletions.forEach { pendingItems.recordRejection($0.itemId) }
            }
        }

        for queued in pendingItems.changes where queued.kind != .delete {
            // Re-read: the queue and the item may have changed while earlier requests were in flight.
            guard let current = pendingItems.change(for: queued.itemId), current.kind != .delete else { continue }
            guard let item = items.first(where: { $0.id == queued.itemId }) else {
                pendingItems.drop(queued.itemId)
                continue
            }
            guard let sent = pendingItems.beginAttempt(queued.itemId) else { continue }
            do {
                switch sent.kind {
                case .insert:
                    try await client.from("list_items").upsert(item, onConflict: "id").execute()
                case .update:
                    try await client
                        .from("list_items")
                        .update(ItemPatch(item: item, fields: sent.fields))
                        .eq("id", value: item.id.uuidString)
                        .execute()
                case .delete:
                    break
                }
                pendingItems.confirm(sent)
            } catch {
                if Self.isTransient(error) { throw error }
                pendingItems.recordRejection(sent.itemId)
            }
        }
    }

    private func pushCategoryOrder(_ client: SupabaseClient) async throws {
        guard pendingCategoryOrder else { return }
        let snapshot = categories
        do {
            for category in snapshot {
                try await client
                    .from("categories")
                    .update(SortOrderPatch(sortOrder: category.sortOrder))
                    .eq("id", value: category.id.uuidString)
                    .execute()
            }
        } catch {
            if Self.isTransient(error) { throw error }
        }
        // Keep the flag if the user reordered again while the requests were in flight.
        if categories.map(\.sortOrder) == snapshot.map(\.sortOrder) && categories.map(\.id) == snapshot.map(\.id) {
            pendingCategoryOrder = false
        }
        persistLocally()
    }

    private func pushCatalogChanges(_ client: SupabaseClient) async throws {
        defer { persistLocally() }
        for (normalizedName, sent) in pendingCatalog {
            guard let entry = catalog.first(where: { $0.normalizedName == normalizedName }) else {
                pendingCatalog[normalizedName] = nil
                continue
            }
            do {
                try await client
                    .rpc("record_catalog_item", params: CatalogUpsertParams(item: entry, usageDelta: sent.usageDelta))
                    .execute()
            } catch {
                if Self.isTransient(error) { throw error }
                pendingCatalog[normalizedName] = nil // refused by the server; not worth blocking on autocomplete history
                continue
            }
            if let current = pendingCatalog[normalizedName] {
                if current.revision == sent.revision {
                    pendingCatalog[normalizedName] = nil
                } else {
                    pendingCatalog[normalizedName]?.usageDelta = max(0, current.usageDelta - sent.usageDelta)
                }
            }
        }
    }

    /// Fetches the server state and merges it with local changes that are still pending.
    private func pullRemoteState(_ client: SupabaseClient) async throws {
        let remoteCategories: [Category] = try await client
            .from("categories")
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("sort_order", ascending: true)
            .execute()
            .value

        let remoteCatalog: [CatalogItem] = try await client
            .from("catalog_items")
            .select()
            .eq("household_id", value: householdId.uuidString)
            .execute()
            .value

        let remoteItems: [ListItem] = try await client
            .from("list_items")
            .select()
            .eq("list_id", value: listId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value

        // Everything below runs without suspension, so it sees a consistent local state.
        guard isCurrent(client) else { return }

        if !remoteCategories.isEmpty {
            // Locally seeded aisles are replaced by the household's; re-point local references by kind.
            let remap = SyncMerge.categoryIdRemap(old: categories, new: remoteCategories)
            if !remap.isEmpty {
                for index in items.indices {
                    if let id = items[index].categoryId, let replacement = remap[id] {
                        items[index].categoryId = replacement
                    }
                }
                for index in catalog.indices {
                    if let id = catalog[index].defaultCategoryId, let replacement = remap[id] {
                        catalog[index].defaultCategoryId = replacement
                    }
                }
            }

            var merged = remoteCategories
            if pendingCategoryOrder {
                // A local reorder has not reached the server yet: keep the local order.
                let localOrder = Dictionary(categories.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
                for index in merged.indices {
                    if let sortOrder = localOrder[merged[index].id] {
                        merged[index].sortOrder = sortOrder
                    }
                }
                merged.sort { $0.sortOrder < $1.sortOrder }
            }
            if merged != categories {
                categories = merged
            }
        }

        if !remoteCatalog.isEmpty {
            let mergedCatalog = SyncMerge.mergeCatalog(
                remote: remoteCatalog,
                local: catalog,
                pendingNames: Set(pendingCatalog.keys)
            )
            if mergedCatalog != catalog {
                catalog = mergedCatalog
            }
        }

        SyncMerge.pruneOrphanedUpdates(&pendingItems, remote: remoteItems)
        let mergedItems = SyncMerge.mergeItems(remote: remoteItems, local: items, pending: pendingItems)
        if mergedItems != items {
            items = mergedItems
        }

        persistLocally()
    }

    // MARK: - Error classification

    /// Network-level failures and expired sessions: worth retrying later with the same data.
    private static func isTransient(_ error: Error) -> Bool {
        if error is URLError || error is CancellationError {
            return true
        }
        if let postgrestError = error as? PostgrestError {
            return isAuthError(postgrestError)
        }
        return false
    }

    /// PostgREST reports JWT problems (expired, invalid, missing) as PGRST301–PGRST303.
    private static func isAuthError(_ error: PostgrestError) -> Bool {
        error.code?.hasPrefix("PGRST30") == true
    }

    #else

    private func performSync() async {}

    #endif
}
