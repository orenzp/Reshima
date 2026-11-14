import Foundation

public enum ShoppingListEngine {
    /// Groups unchecked items by their supermarket aisle (`Category.sortOrder`),
    /// placing uncategorized items into a fallback "Other / כללי" aisle at the end.
    public static func groupActiveItemsByAisle(
        items: [ListItem],
        categories: [Category],
        householdId: UUID
    ) -> [AisleGroup] {
        let unchecked = items.filter { !$0.isChecked }
        guard !unchecked.isEmpty else { return [] }

        let sortedCategories = categories.sorted { $0.sortOrder < $1.sortOrder }
        let categoryMap = Dictionary(uniqueKeysWithValues: sortedCategories.map { ($0.id, $0) })

        let fallbackCategory = sortedCategories.first(where: { $0.kind == CategoryKind.other })
            ?? Category(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
                householdId: householdId,
                nameHe: "כללי",
                nameEn: "Other",
                icon: "🛒",
                colorHex: "#6B7280",
                sortOrder: 999,
                kind: CategoryKind.other
            )

        var grouped: [UUID: [ListItem]] = [:]
        for item in unchecked {
            let targetCatId: UUID
            if let catId = item.categoryId, categoryMap[catId] != nil {
                targetCatId = catId
            } else {
                targetCatId = fallbackCategory.id
            }
            grouped[targetCatId, default: []].append(item)
        }

        var result: [AisleGroup] = []
        for cat in sortedCategories {
            if let catItems = grouped[cat.id], !catItems.isEmpty {
                let ordered = catItems.sorted { $0.createdAt < $1.createdAt }
                result.append(AisleGroup(category: cat, items: ordered))
            }
        }

        if let fallbackItems = grouped[fallbackCategory.id],
           !fallbackItems.isEmpty,
           !result.contains(where: { $0.id == fallbackCategory.id }) {
            let ordered = fallbackItems.sorted { $0.createdAt < $1.createdAt }
            result.append(AisleGroup(category: fallbackCategory, items: ordered))
        }

        return result
    }

    /// Returns checked items sorted by most recently checked first.
    public static func checkedItems(from items: [ListItem]) -> [ListItem] {
        items
            .filter { $0.isChecked }
            .sorted { ($0.checkedAt ?? $0.updatedAt) > ($1.checkedAt ?? $1.updatedAt) }
    }

    /// Ranks catalog autocomplete suggestions by prefix match, staple status, and historical usage count.
    public static func autocompleteSuggestions(
        query: String,
        catalog: [CatalogItem],
        activeListItems: [ListItem],
        limit: Int = 6
    ) -> [CatalogItem] {
        let normalizedQuery = CatalogItem.normalize(query)
        let activeNames = Set(activeListItems.filter { !$0.isChecked }.map { CatalogItem.normalize($0.name) })

        let candidates = catalog.filter { item in
            guard !activeNames.contains(item.normalizedName) else { return false }
            if normalizedQuery.isEmpty {
                return item.isStaple
            }
            return item.normalizedName.contains(normalizedQuery)
        }

        return candidates.sorted { lhs, rhs in
            if !normalizedQuery.isEmpty {
                let lhsPrefix = lhs.normalizedName.hasPrefix(normalizedQuery)
                let rhsPrefix = rhs.normalizedName.hasPrefix(normalizedQuery)
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix
                }
            }
            if lhs.isStaple != rhs.isStaple {
                return lhs.isStaple
            }
            if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }
            return lhs.name < rhs.name
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Infers the best category and default unit for a newly typed item name using catalog history or keyword heuristics.
    public static func inferCategoryAndUnit(
        for rawName: String,
        catalog: [CatalogItem],
        categories: [Category]
    ) -> (categoryId: UUID?, unit: UnitType) {
        let normalized = CatalogItem.normalize(rawName)
        if let exact = catalog.first(where: { $0.normalizedName == normalized }) {
            return (exact.defaultCategoryId, exact.defaultUnit)
        }

        // Bilingual keyword heuristics. A keyword matches when a word of the name starts with it,
        // so "bun" does not match "abundance". Aisles are looked up by stable `kind`, not position.
        let words = normalized
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
        let matches: ([String]) -> Bool = { keywords in
            keywords.contains { keyword in words.contains { $0.hasPrefix(keyword) } }
        }
        let findCategory: (String) -> UUID? = { kind in
            categories.first(where: { $0.kind == kind })?.id
        }

        let produceKeywords = ["עגבני", "מלפפ", "בצל", "תפוח", "בננ", "אבוקד", "חסה", "גזר", "לימון", "פלפל", "חציל", "tomato", "cucumber", "apple", "banana", "avocado", "onion", "lemon", "eggplant"]
        if matches(produceKeywords) {
            return (findCategory(CategoryKind.produce), .kg)
        }

        // Checked before meat so "דגנים" (cereal) is not caught by "דג" (fish).
        let pantryKeywords = ["דגנ", "קורנפלקס", "פסטה", "אורז", "קמח", "סוכר", "cereal", "pasta", "rice", "flour", "sugar"]
        if matches(pantryKeywords) {
            return (findCategory(CategoryKind.pantry), .pcs)
        }

        let dairyKeywords = ["חלב", "קוטג", "גבינ", "יוגורט", "חמאה", "שמנת", "ביצ", "milk", "cheese", "yogurt", "butter", "egg"]
        if matches(dairyKeywords) {
            let unit: UnitType = matches(["ביצ", "egg"]) ? .pack : .pcs
            return (findCategory(CategoryKind.dairy), unit)
        }

        let bakeryKeywords = ["לחם", "פית", "חלה", "לחמני", "bread", "pita", "bagel", "bun"]
        if matches(bakeryKeywords) {
            return (findCategory(CategoryKind.bakery), .pcs)
        }

        let meatKeywords = ["עוף", "בשר", "טחו", "סלמון", "דג", "סטייק", "הודו", "chicken", "beef", "meat", "salmon", "fish"]
        if matches(meatKeywords) {
            return (findCategory(CategoryKind.meat), .kg)
        }

        return (findCategory(CategoryKind.other), .pcs)
    }
}
