import Foundation
import Observation
import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

@Observable
@MainActor
public final class ShoppingStore {
    public var language: AppLanguage = .hebrew {
        didSet { persistLocally() }
    }
    public var householdId: UUID
    public var listId: UUID
    public var categories: [Category]
    public var catalog: [CatalogItem]
    public var items: [ListItem]
    public var config: SupabaseConfig
    public var isCloudConnected: Bool = false
    public var syncStatusMessage: String?

    private let persistence = LocalPersistence()
    private var pollTask: Task<Void, Never>?

    public init() {
        let loadedConfig = SupabaseConfig.loadDefault()
        self.config = loadedConfig

        if let cached = persistence.load() {
            self.householdId = SupabaseConfig.defaultHouseholdId
            self.listId = SupabaseConfig.defaultListId
            self.language = cached.language
            self.categories = cached.categories
            self.catalog = cached.catalog
            self.items = cached.items
        } else {
            let defaultHousehold = SupabaseConfig.defaultHouseholdId
            let defaultList = SupabaseConfig.defaultListId
            let seededCategories = DefaultSeedData.categories(householdId: defaultHousehold)
            let seededCatalog = DefaultSeedData.catalogItems(householdId: defaultHousehold, categories: seededCategories)

            self.householdId = defaultHousehold
            self.listId = defaultList
            self.language = .hebrew
            self.categories = seededCategories
            self.catalog = seededCatalog
            self.items = [
                ListItem(
                    listId: defaultList,
                    householdId: defaultHousehold,
                    categoryId: seededCategories.first(where: { $0.sortOrder == 20 })?.id,
                    name: "חלב 3%",
                    quantity: 2,
                    unit: .pcs,
                    notes: "תנובה קרטון"
                ),
                ListItem(
                    listId: defaultList,
                    householdId: defaultHousehold,
                    categoryId: seededCategories.first(where: { $0.sortOrder == 10 })?.id,
                    name: "עגבניות שרי",
                    quantity: 1,
                    unit: .pack
                ),
                ListItem(
                    listId: defaultList,
                    householdId: defaultHousehold,
                    categoryId: seededCategories.first(where: { $0.sortOrder == 30 })?.id,
                    name: "לחם מחמצת",
                    quantity: 1,
                    unit: .pcs
                )
            ]
            persistLocally()
        }

        if config.isConfigured {
            startCloudSync()
        }
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

    public var stapleItems: [CatalogItem] {
        ShoppingListEngine.autocompleteSuggestions(
            query: "",
            catalog: catalog,
            activeListItems: items,
            limit: 12
        )
    }

    public func suggestions(for query: String) -> [CatalogItem] {
        ShoppingListEngine.autocompleteSuggestions(
            query: query,
            catalog: catalog,
            activeListItems: items,
            limit: 6
        )
    }

    public func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }

    // MARK: - User Actions (Optimistic <16ms Updates + Background Cloud Sync)

    public func quickAddItem(name rawName: String, quantity: Double = 1.0, explicitCategory: UUID? = nil, explicitUnit: UnitType? = nil) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let inferred = ShoppingListEngine.inferCategoryAndUnit(
            for: trimmed,
            catalog: catalog,
            categories: categories
        )
        let targetCategory = explicitCategory ?? inferred.categoryId
        let targetUnit = explicitUnit ?? inferred.unit

        // If an unchecked item with the same normalized name already exists, increment its quantity
        let normalized = CatalogItem.normalize(trimmed)
        if let existingIndex = items.firstIndex(where: { !$0.isChecked && CatalogItem.normalize($0.name) == normalized }) {
            items[existingIndex].quantity += items[existingIndex].unit.stepIncrement
            items[existingIndex].updatedAt = Date()
            let updatedItem = items[existingIndex]
            persistLocally()
            Task { await pushItemUpsert(updatedItem) }
            return
        }

        let newItem = ListItem(
            listId: listId,
            householdId: householdId,
            categoryId: targetCategory,
            name: trimmed,
            quantity: quantity,
            unit: targetUnit
        )
        items.append(newItem)

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

        persistLocally()
        Task { await pushItemUpsert(newItem) }
    }

    public func toggleChecked(_ item: ListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isChecked.toggle()
        items[index].checkedAt = items[index].isChecked ? Date() : nil
        items[index].updatedAt = Date()
        let updated = items[index]
        persistLocally()
        Task { await pushItemUpsert(updated) }
    }

    public func adjustQuantity(_ item: ListItem, delta: Double) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let next = items[index].quantity + delta
        guard next > 0 else { return }
        items[index].quantity = next
        items[index].updatedAt = Date()
        let updated = items[index]
        persistLocally()
        Task { await pushItemUpsert(updated) }
    }

    public func updateItem(_ updated: ListItem, newPhotoData: Data? = nil) {
        guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
        var copy = updated
        if let newPhotoData {
            copy.photoPath = persistence.saveLocalPhoto(newPhotoData, for: updated.id)
        }
        copy.updatedAt = Date()
        items[index] = copy

        // Also update catalog default category & unit for future autocomplete
        let normalized = CatalogItem.normalize(copy.name)
        if let catIdx = catalog.firstIndex(where: { $0.normalizedName == normalized }) {
            catalog[catIdx].defaultCategoryId = copy.categoryId
            catalog[catIdx].defaultUnit = copy.unit
        }

        persistLocally()
        Task { await pushItemUpsert(copy) }
    }

    public func deleteItem(_ item: ListItem) {
        items.removeAll { $0.id == item.id }
        persistLocally()
        Task { await pushItemDelete(item.id) }
    }

    public func clearCheckedItems() {
        let checkedIds = items.filter { $0.isChecked }.map(\.id)
        items.removeAll { $0.isChecked }
        persistLocally()
        Task {
            for id in checkedIds {
                await pushItemDelete(id)
            }
        }
    }

    public func toggleStaple(_ catalogItem: CatalogItem) {
        guard let idx = catalog.firstIndex(where: { $0.id == catalogItem.id }) else { return }
        catalog[idx].isStaple.toggle()
        persistLocally()
    }

    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        var sorted = categories.sorted { $0.sortOrder < $1.sortOrder }
        sorted.move(fromOffsets: source, toOffset: destination)
        for idx in sorted.indices {
            sorted[idx].sortOrder = (idx + 1) * 10
        }
        categories = sorted
        persistLocally()
    }

    public func updateSupabaseConfig(_ newConfig: SupabaseConfig) {
        self.config = newConfig
        newConfig.save()
        if newConfig.isConfigured {
            startCloudSync()
        } else {
            isCloudConnected = false
            pollTask?.cancel()
        }
    }

    // MARK: - Persistence & Supabase Cloud Sync

    private func persistLocally() {
        let snapshot = PersistedSnapshot(
            householdId: householdId,
            listId: listId,
            language: language,
            categories: categories,
            catalog: catalog,
            items: items
        )
        persistence.save(snapshot)
    }

    public func startCloudSync() {
        guard config.isConfigured else {
            isCloudConnected = false
            return
        }
        isCloudConnected = true
        syncStatusMessage = L10n.syncStatusConnected(language)

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pullRemoteItems()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    public func pullRemoteItems() async {
        #if canImport(Supabase)
        guard config.isConfigured, let url = URL(string: config.urlString) else { return }
        do {
            let client = SupabaseClient(supabaseURL: url, supabaseKey: config.anonKey)
            let remoteCategories: [Category] = try await client
                .from("categories")
                .select()
                .eq("household_id", value: householdId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            if !remoteCategories.isEmpty {
                self.categories = remoteCategories
            }

            let remoteCatalog: [CatalogItem] = try await client
                .from("catalog_items")
                .select()
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
            if !remoteCatalog.isEmpty {
                self.catalog = remoteCatalog
            }

            let remoteItems: [ListItem] = try await client
                .from("list_items")
                .select()
                .eq("list_id", value: listId.uuidString)
                .execute()
                .value
            self.items = remoteItems
            self.persistLocally()
            self.isCloudConnected = true
        } catch {
            self.syncStatusMessage = error.localizedDescription
        }
        #endif
    }

    private func pushItemUpsert(_ item: ListItem) async {
        #if canImport(Supabase)
        guard config.isConfigured, let url = URL(string: config.urlString) else { return }
        do {
            let client = SupabaseClient(supabaseURL: url, supabaseKey: config.anonKey)
            try await client
                .from("list_items")
                .upsert(item)
                .execute()
        } catch {
            self.syncStatusMessage = error.localizedDescription
        }
        #endif
    }

    private func pushItemDelete(_ itemId: UUID) async {
        #if canImport(Supabase)
        guard config.isConfigured, let url = URL(string: config.urlString) else { return }
        do {
            let client = SupabaseClient(supabaseURL: url, supabaseKey: config.anonKey)
            try await client
                .from("list_items")
                .delete()
                .eq("id", value: itemId.uuidString)
                .execute()
        } catch {
            self.syncStatusMessage = error.localizedDescription
        }
        #endif
    }
}
