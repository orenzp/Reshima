import XCTest
#if canImport(ReshimaCore)
@testable import ReshimaCore
#else
@testable import Reshima
#endif

final class ShoppingListLogicTests: XCTestCase {
    private let householdId = UUID()
    private let listId = UUID()

    func testGroupActiveItemsBySupermarketAisleOrder() {
        let categories = DefaultSeedData.categories(householdId: householdId)
        let produceCat = categories.first { $0.kind == CategoryKind.produce }!
        let dairyCat = categories.first { $0.kind == CategoryKind.dairy }!
        let bakeryCat = categories.first { $0.kind == CategoryKind.bakery }!

        let items = [
            ListItem(listId: listId, householdId: householdId, categoryId: bakeryCat.id, name: "לחם מחמצת"),
            ListItem(listId: listId, householdId: householdId, categoryId: produceCat.id, name: "עגבניות", quantity: 1.5, unit: .kg),
            ListItem(listId: listId, householdId: householdId, categoryId: dairyCat.id, name: "חלב 3%", isChecked: true),
            ListItem(listId: listId, householdId: householdId, categoryId: dairyCat.id, name: "קוטג׳ 5%")
        ]

        let groups = ShoppingListEngine.groupActiveItemsByAisle(
            items: items,
            categories: categories,
            householdId: householdId
        )

        // Should have 3 active groups ordered by sortOrder: Produce (10), Dairy (20), Bakery (30)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].category.id, produceCat.id)
        XCTAssertEqual(groups[0].items.map(\.name), ["עגבניות"])
        XCTAssertEqual(groups[1].category.id, dairyCat.id)
        XCTAssertEqual(groups[1].items.map(\.name), ["קוטג׳ 5%"])
        XCTAssertEqual(groups[2].category.id, bakeryCat.id)
        XCTAssertEqual(groups[2].items.map(\.name), ["לחם מחמצת"])

        // Checked items should only contain "חלב 3%"
        let checked = ShoppingListEngine.checkedItems(from: items)
        XCTAssertEqual(checked.map(\.name), ["חלב 3%"])
    }

    func testSmartAutocompleteExcludesActiveItemsAndRanksByUsage() {
        let categories = DefaultSeedData.categories(householdId: householdId)
        let catalog = DefaultSeedData.catalogItems(householdId: householdId, categories: categories)

        // Suppose "חלב 3%" is already unchecked in the active list
        let activeItems = [
            ListItem(listId: listId, householdId: householdId, name: "חלב 3%", isChecked: false)
        ]

        let staples = ShoppingListEngine.autocompleteSuggestions(
            query: "",
            catalog: catalog,
            activeListItems: activeItems,
            limit: 5
        )

        XCTAssertFalse(staples.contains(where: { $0.name == "חלב 3%" }))
        XCTAssertEqual(staples.first?.name, "ביצים L")

        // Prefix search in Hebrew
        let searchResults = ShoppingListEngine.autocompleteSuggestions(
            query: "עגב",
            catalog: catalog,
            activeListItems: activeItems
        )
        XCTAssertEqual(searchResults.first?.name, "עגבניות")
    }

    func testBilingualCategoryAndUnitInference() {
        let categories = DefaultSeedData.categories(householdId: householdId)
        let catalog = DefaultSeedData.catalogItems(householdId: householdId, categories: categories)
        let produceCatId = categories.first { $0.kind == CategoryKind.produce }?.id
        let dairyCatId = categories.first { $0.kind == CategoryKind.dairy }?.id

        let inferredHebrew = ShoppingListEngine.inferCategoryAndUnit(
            for: "מלפפונים חמוצים או טריים",
            catalog: catalog,
            categories: categories
        )
        XCTAssertEqual(inferredHebrew.categoryId, produceCatId)
        XCTAssertEqual(inferredHebrew.unit, .kg)

        let inferredEnglish = ShoppingListEngine.inferCategoryAndUnit(
            for: "Organic Eggs",
            catalog: catalog,
            categories: categories
        )
        XCTAssertEqual(inferredEnglish.categoryId, dairyCatId)
        XCTAssertEqual(inferredEnglish.unit, .pack)
    }

    func testBilingualUnitAndQuantityFormatting() {
        let item = ListItem(
            listId: listId,
            householdId: householdId,
            name: "עגבניות",
            quantity: 1.5,
            unit: .kg
        )
        XCTAssertEqual(item.quantityWithUnit(.hebrew), "1.5 ק״ג")
        XCTAssertEqual(item.quantityWithUnit(.english), "1.5 kg")
    }
}
