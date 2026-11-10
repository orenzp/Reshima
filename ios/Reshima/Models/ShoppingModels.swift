import Foundation

public enum UnitType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pcs = "pcs"
    case kg = "kg"
    case g = "g"
    case liter = "L"
    case pack = "pack"

    public var id: String { rawValue }

    public func localizedLabel(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.pcs, .hebrew): return "יח׳"
        case (.pcs, .english): return "pcs"
        case (.kg, .hebrew): return "ק״ג"
        case (.kg, .english): return "kg"
        case (.g, .hebrew): return "גרם"
        case (.g, .english): return "g"
        case (.liter, .hebrew): return "ליטר"
        case (.liter, .english): return "L"
        case (.pack, .hebrew): return "חב׳"
        case (.pack, .english): return "pack"
        }
    }

    public var stepIncrement: Double {
        switch self {
        case .pcs, .pack, .liter: return 1.0
        case .kg: return 0.5
        case .g: return 100.0
        }
    }
}

public struct Category: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var householdId: UUID
    public var nameHe: String
    public var nameEn: String
    public var icon: String
    public var colorHex: String
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        householdId: UUID,
        nameHe: String,
        nameEn: String,
        icon: String = "🛒",
        colorHex: String = "#10B981",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.householdId = householdId
        self.nameHe = nameHe
        self.nameEn = nameEn
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    public func localizedName(_ language: AppLanguage) -> String {
        language == .hebrew ? nameHe : nameEn
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case nameHe = "name_he"
        case nameEn = "name_en"
        case icon
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
    }
}

public struct CatalogItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var householdId: UUID
    public var name: String
    public var normalizedName: String
    public var defaultCategoryId: UUID?
    public var defaultUnit: UnitType
    public var usageCount: Int
    public var isStaple: Bool

    public init(
        id: UUID = UUID(),
        householdId: UUID,
        name: String,
        defaultCategoryId: UUID? = nil,
        defaultUnit: UnitType = .pcs,
        usageCount: Int = 1,
        isStaple: Bool = false
    ) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.normalizedName = Self.normalize(name)
        self.defaultCategoryId = defaultCategoryId
        self.defaultUnit = defaultUnit
        self.usageCount = usageCount
        self.isStaple = isStaple
    }

    public static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name
        case normalizedName = "normalized_name"
        case defaultCategoryId = "default_category_id"
        case defaultUnit = "default_unit"
        case usageCount = "usage_count"
        case isStaple = "is_staple"
    }
}

public struct ListItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var listId: UUID
    public var householdId: UUID
    public var categoryId: UUID?
    public var name: String
    public var quantity: Double
    public var unit: UnitType
    public var notes: String
    public var photoPath: String?
    public var isChecked: Bool
    public var checkedAt: Date?
    public var updatedBy: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        listId: UUID,
        householdId: UUID,
        categoryId: UUID? = nil,
        name: String,
        quantity: Double = 1.0,
        unit: UnitType = .pcs,
        notes: String = "",
        photoPath: String? = nil,
        isChecked: Bool = false,
        checkedAt: Date? = nil,
        updatedBy: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.listId = listId
        self.householdId = householdId
        self.categoryId = categoryId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.photoPath = photoPath
        self.isChecked = isChecked
        self.checkedAt = checkedAt
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(quantity))
        }
        return String(format: "%.1f", quantity)
    }

    public func quantityWithUnit(_ language: AppLanguage) -> String {
        "\(formattedQuantity) \(unit.localizedLabel(language))"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case householdId = "household_id"
        case categoryId = "category_id"
        case name
        case quantity
        case unit
        case notes
        case photoPath = "photo_path"
        case isChecked = "is_checked"
        case checkedAt = "checked_at"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct AisleGroup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var category: Category
    public var items: [ListItem]

    public init(category: Category, items: [ListItem]) {
        self.id = category.id
        self.category = category
        self.items = items
    }
}

public enum DefaultSeedData {
    public static func categories(householdId: UUID) -> [Category] {
        [
            Category(householdId: householdId, nameHe: "פירות וירקות", nameEn: "Produce", icon: "🥦", colorHex: "#10B981", sortOrder: 10),
            Category(householdId: householdId, nameHe: "מוצרי חלב וביצים", nameEn: "Dairy & Eggs", icon: "🧀", colorHex: "#3B82F6", sortOrder: 20),
            Category(householdId: householdId, nameHe: "מאפים ולחם", nameEn: "Bakery & Bread", icon: "🥖", colorHex: "#F59E0B", sortOrder: 30),
            Category(householdId: householdId, nameHe: "בשר, עוף ודגים", nameEn: "Meat & Fish", icon: "🥩", colorHex: "#EF4444", sortOrder: 40),
            Category(householdId: householdId, nameHe: "מזווה ובישול", nameEn: "Pantry & Dry Goods", icon: "🍝", colorHex: "#8B5CF6", sortOrder: 50),
            Category(householdId: householdId, nameHe: "קפואים", nameEn: "Frozen", icon: "🧊", colorHex: "#06B6D4", sortOrder: 60),
            Category(householdId: householdId, nameHe: "ניקיון ופארם", nameEn: "Home & Pharmacy", icon: "🧼", colorHex: "#EC4899", sortOrder: 70),
            Category(householdId: householdId, nameHe: "כללי", nameEn: "Other", icon: "🛒", colorHex: "#6B7280", sortOrder: 80)
        ]
    }

    public static func catalogItems(householdId: UUID, categories: [Category]) -> [CatalogItem] {
        let produceId = categories.first { $0.sortOrder == 10 }?.id
        let dairyId = categories.first { $0.sortOrder == 20 }?.id
        let bakeryId = categories.first { $0.sortOrder == 30 }?.id
        let meatId = categories.first { $0.sortOrder == 40 }?.id
        let pantryId = categories.first { $0.sortOrder == 50 }?.id
        let cleaningId = categories.first { $0.sortOrder == 70 }?.id

        return [
            CatalogItem(householdId: householdId, name: "חלב 3%", defaultCategoryId: dairyId, defaultUnit: .pcs, usageCount: 25, isStaple: true),
            CatalogItem(householdId: householdId, name: "ביצים L", defaultCategoryId: dairyId, defaultUnit: .pack, usageCount: 20, isStaple: true),
            CatalogItem(householdId: householdId, name: "קוטג׳ 5%", defaultCategoryId: dairyId, defaultUnit: .pcs, usageCount: 18, isStaple: true),
            CatalogItem(householdId: householdId, name: "לחם מחמצת", defaultCategoryId: bakeryId, defaultUnit: .pcs, usageCount: 18, isStaple: true),
            CatalogItem(householdId: householdId, name: "עגבניות", defaultCategoryId: produceId, defaultUnit: .kg, usageCount: 16, isStaple: true),
            CatalogItem(householdId: householdId, name: "מלפפונים", defaultCategoryId: produceId, defaultUnit: .kg, usageCount: 16, isStaple: true),
            CatalogItem(householdId: householdId, name: "בננות", defaultCategoryId: produceId, defaultUnit: .kg, usageCount: 14, isStaple: true),
            CatalogItem(householdId: householdId, name: "אבוקדו", defaultCategoryId: produceId, defaultUnit: .kg, usageCount: 12, isStaple: true),
            CatalogItem(householdId: householdId, name: "חזה עוף", defaultCategoryId: meatId, defaultUnit: .kg, usageCount: 10, isStaple: true),
            CatalogItem(householdId: householdId, name: "שמן זית", defaultCategoryId: pantryId, defaultUnit: .pcs, usageCount: 8, isStaple: true),
            CatalogItem(householdId: householdId, name: "נייר טואלט", defaultCategoryId: cleaningId, defaultUnit: .pack, usageCount: 7, isStaple: true),
            CatalogItem(householdId: householdId, name: "Milk 3%", defaultCategoryId: dairyId, defaultUnit: .pcs, usageCount: 10, isStaple: false),
            CatalogItem(householdId: householdId, name: "Tomatoes", defaultCategoryId: produceId, defaultUnit: .kg, usageCount: 8, isStaple: false)
        ]
    }
}
