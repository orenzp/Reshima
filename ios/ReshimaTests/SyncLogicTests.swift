import XCTest
#if canImport(ReshimaCore)
@testable import ReshimaCore
#else
@testable import Reshima
#endif

final class SyncLogicTests: XCTestCase {
    private let householdId = UUID()
    private let listId = UUID()

    private func makeItem(_ name: String, quantity: Double = 1, isChecked: Bool = false) -> ListItem {
        ListItem(listId: listId, householdId: householdId, name: name, quantity: quantity, isChecked: isChecked)
    }

    // MARK: - Pending queue

    func testQueueCoalescesUpdatesPerItem() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordUpdate(item.id, fields: [.quantity])
        queue.recordUpdate(item.id, fields: [.isChecked])

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.change(for: item.id)?.kind, .update)
        XCTAssertEqual(queue.change(for: item.id)?.fields, [.quantity, .isChecked])
    }

    func testQueueKeepsInsertWhenItemIsEditedBeforeSync() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordInsert(item.id)
        queue.recordUpdate(item.id, fields: [.notes])

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.change(for: item.id)?.kind, .insert)
    }

    func testDeletingNeverSentInsertLeavesNothingToSync() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordInsert(item.id)
        queue.recordDelete(item.id)

        XCTAssertTrue(queue.isEmpty)
    }

    func testDeletingInsertThatMayHaveReachedServerBecomesDelete() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordInsert(item.id)
        _ = queue.beginAttempt(item.id)
        queue.recordDelete(item.id)

        XCTAssertEqual(queue.change(for: item.id)?.kind, .delete)
    }

    func testConfirmKeepsChangeEditedWhileInFlight() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordUpdate(item.id, fields: [.quantity])
        let sent = queue.beginAttempt(item.id)!
        queue.recordUpdate(item.id, fields: [.notes])
        queue.confirm(sent)

        XCTAssertEqual(queue.change(for: item.id)?.fields, [.quantity, .notes])

        let resent = queue.beginAttempt(item.id)!
        queue.confirm(resent)
        XCTAssertTrue(queue.isEmpty)
    }

    func testRejectedChangeIsDroppedAfterRepeatedRefusals() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordUpdate(item.id, fields: [.quantity])

        XCTAssertFalse(queue.recordRejection(item.id, maxRejections: 2))
        XCTAssertEqual(queue.count, 1)
        XCTAssertTrue(queue.recordRejection(item.id, maxRejections: 2))
        XCTAssertTrue(queue.isEmpty)
    }

    func testUnknownUnitDecodesAsPieces() throws {
        let decoded = try JSONDecoder().decode([UnitType].self, from: Data(#"["kg","bottle"]"#.utf8))
        XCTAssertEqual(decoded, [.kg, .pcs])
    }

    func testQueueSurvivesPersistenceRoundTrip() throws {
        var queue = PendingItemQueue()
        queue.recordInsert(UUID())
        queue.recordUpdate(UUID(), fields: [.isChecked, .quantity])
        queue.recordDelete(UUID())

        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(PendingItemQueue.self, from: data)
        XCTAssertEqual(decoded, queue)
    }

    // MARK: - Merge

    func testMergeTakesServerStateWhenNothingIsPending() {
        let kept = makeItem("לחם")
        let deletedRemotely = makeItem("ביצים")
        var remoteKept = kept
        remoteKept.quantity = 3
        let addedRemotely = makeItem("בננות")

        let merged = SyncMerge.mergeItems(
            remote: [remoteKept, addedRemotely],
            local: [kept, deletedRemotely],
            pending: PendingItemQueue()
        )

        XCTAssertEqual(merged.map(\.id), [kept.id, addedRemotely.id])
        XCTAssertEqual(merged.first?.quantity, 3)
    }

    func testMergeKeepsOfflineEditsAndInserts() {
        // Local: checked off one item and added another while offline.
        let milkRemote = makeItem("חלב", quantity: 1)
        var milkLocal = milkRemote
        milkLocal.isChecked = true
        milkLocal.checkedAt = Date()
        let addedOffline = makeItem("אבוקדו")

        var queue = PendingItemQueue()
        queue.recordUpdate(milkLocal.id, fields: [.isChecked])
        queue.recordInsert(addedOffline.id)

        // Meanwhile the other phone changed the quantity of the same item.
        var milkRemoteNow = milkRemote
        milkRemoteNow.quantity = 4

        let merged = SyncMerge.mergeItems(remote: [milkRemoteNow], local: [milkLocal, addedOffline], pending: queue)

        XCTAssertEqual(merged.map(\.id), [milkRemote.id, addedOffline.id])
        XCTAssertEqual(merged[0].isChecked, true, "local check-off must survive the pull")
        XCTAssertEqual(merged[0].quantity, 4, "the other phone's quantity change must survive too")
    }

    func testMergeHidesItemsPendingDeletion() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordDelete(item.id)

        let merged = SyncMerge.mergeItems(remote: [item], local: [], pending: queue)
        XCTAssertTrue(merged.isEmpty)
    }

    func testRemoteDeleteWinsOverPendingUpdate() {
        let item = makeItem("חלב")
        var queue = PendingItemQueue()
        queue.recordUpdate(item.id, fields: [.quantity])

        let merged = SyncMerge.mergeItems(remote: [], local: [item], pending: queue)
        XCTAssertTrue(merged.isEmpty)

        SyncMerge.pruneOrphanedUpdates(&queue, remote: [])
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Patch payload

    func testPatchEncodesOnlyChangedFieldsWithExplicitNulls() throws {
        var item = makeItem("חלב", quantity: 2)
        item.categoryId = nil
        let patch = ItemPatch(item: item, fields: [.quantity, .categoryId])

        let data = try JSONEncoder().encode(patch)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["quantity", "category_id"])
        XCTAssertEqual(json["quantity"] as? Double, 2)
        XCTAssertTrue(json["category_id"] is NSNull)
    }

    func testChangedFieldsDetectsEdits() {
        let original = makeItem("חלב")
        var edited = original
        edited.notes = "תנובה"
        edited.unit = .liter
        edited.updatedAt = Date().addingTimeInterval(60)

        XCTAssertEqual(edited.changedFields(from: original), [.notes, .unit])
    }

    // MARK: - Catalog & categories

    func testCatalogMergeKeepsPendingLocalEntries() {
        let remoteMilk = CatalogItem(householdId: householdId, name: "חלב", usageCount: 5)
        var localMilk = remoteMilk
        localMilk.usageCount = 6
        localMilk.isStaple = true
        let localOnly = CatalogItem(householdId: householdId, name: "טחינה")
        let remoteBread = CatalogItem(householdId: householdId, name: "לחם", usageCount: 2)
        var staleLocalBread = remoteBread
        staleLocalBread.usageCount = 1

        let merged = SyncMerge.mergeCatalog(
            remote: [remoteMilk, remoteBread],
            local: [localMilk, localOnly, staleLocalBread],
            pendingNames: [localMilk.normalizedName, localOnly.normalizedName]
        )

        XCTAssertEqual(merged.map(\.name), ["חלב", "לחם", "טחינה"])
        XCTAssertEqual(merged[0].usageCount, 6)
        XCTAssertEqual(merged[1].usageCount, 2)
    }

    func testCategoryRemapMatchesLocallySeededAislesByKind() {
        let local = DefaultSeedData.categories(householdId: householdId)
        let remote = DefaultSeedData.categories(householdId: householdId)
        let remap = SyncMerge.categoryIdRemap(old: local, new: remote)

        let localDairy = local.first { $0.kind == CategoryKind.dairy }!
        let remoteDairy = remote.first { $0.kind == CategoryKind.dairy }!
        XCTAssertEqual(remap[localDairy.id], remoteDairy.id)
        XCTAssertEqual(remap.count, local.count)
        XCTAssertTrue(SyncMerge.categoryIdRemap(old: remote, new: remote).isEmpty)
    }

    func testAisleLogicSurvivesReordering() {
        // Move "Other" to the top and "Produce" to the bottom.
        var categories = DefaultSeedData.categories(householdId: householdId)
        let other = categories.first { $0.kind == CategoryKind.other }!
        let produce = categories.first { $0.kind == CategoryKind.produce }!
        for index in categories.indices {
            if categories[index].id == other.id { categories[index].sortOrder = 10 }
            if categories[index].id == produce.id { categories[index].sortOrder = 80 }
        }

        let inferred = ShoppingListEngine.inferCategoryAndUnit(for: "Tomato", catalog: [], categories: categories)
        XCTAssertEqual(inferred.categoryId, produce.id)

        let uncategorized = makeItem("משהו")
        let groups = ShoppingListEngine.groupActiveItemsByAisle(
            items: [uncategorized],
            categories: categories,
            householdId: householdId
        )
        XCTAssertEqual(groups.map(\.category.id), [other.id])
    }

    func testKeywordInferenceAvoidsFalseMatches() {
        let categories = DefaultSeedData.categories(householdId: householdId)
        let id: (String) -> UUID? = { kind in categories.first { $0.kind == kind }?.id }

        let eggplant = ShoppingListEngine.inferCategoryAndUnit(for: "Eggplant", catalog: [], categories: categories)
        XCTAssertEqual(eggplant.categoryId, id(CategoryKind.produce))

        let cereal = ShoppingListEngine.inferCategoryAndUnit(for: "דגנים", catalog: [], categories: categories)
        XCTAssertEqual(cereal.categoryId, id(CategoryKind.pantry))

        let fish = ShoppingListEngine.inferCategoryAndUnit(for: "דג סלמון", catalog: [], categories: categories)
        XCTAssertEqual(fish.categoryId, id(CategoryKind.meat))

        let unknown = ShoppingListEngine.inferCategoryAndUnit(for: "abundance", catalog: [], categories: categories)
        XCTAssertEqual(unknown.categoryId, id(CategoryKind.other))
    }
}
