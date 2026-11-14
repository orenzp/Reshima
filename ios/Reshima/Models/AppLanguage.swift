import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case hebrew = "he"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hebrew: return "עברית"
        case .english: return "English"
        }
    }

    public var isRTL: Bool {
        self == .hebrew
    }
}

public struct L10n {
    public static func appTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "רשימה" : "Reshima"
    }

    public static func quickAddPlaceholder(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "הוסף מוצר לרשימה..." : "Add item to list..."
    }

    public static func staplesTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מוצרים קבועים" : "Household Staples"
    }

    public static func inCartSectionTitle(_ lang: AppLanguage, count: Int) -> String {
        lang == .hebrew ? "בסל (\(count))" : "In Cart (\(count))"
    }

    public static func clearChecked(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "נקה פריטים שסומנו" : "Clear Checked"
    }

    public static func emptyListTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "הרשימה ריקה!" : "Your list is empty!"
    }

    public static func emptyListSubtitle(_ lang: AppLanguage) -> String {
        lang == .hebrew
            ? "הקלד למעלה או בחר מהמוצרים הקבועים כדי להתחיל."
            : "Type above or tap a staple item to start adding groceries."
    }

    public static func itemDetailsTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "פרטי מוצר" : "Item Details"
    }

    public static func quantityLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "כמות" : "Quantity"
    }

    public static func unitLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "יחידת מידה" : "Unit"
    }

    public static func categoryLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מחלקה בסופר" : "Supermarket Aisle"
    }

    public static func notesLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "הערות (מותג, סוג...)" : "Notes (brand, details...)"
    }

    public static func photoLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "תמונת מוצר" : "Item Photo"
    }

    public static func saveButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "שמור" : "Save"
    }

    public static func cancelButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "ביטול" : "Cancel"
    }

    public static func deleteButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מחק" : "Delete"
    }

    public static func settingsTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "הגדרות ומחלקות" : "Settings & Aisles"
    }

    public static func householdCodeLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "קוד משק בית משותף" : "Shared Household Code"
    }

    public static func syncStatusConnected(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מסונכרן בזמן אמת" : "Live Sync Active"
    }

    public static func reorderAislesHint(_ lang: AppLanguage) -> String {
        lang == .hebrew
            ? "גרור כדי להתאים את סדר המחלקות לסופר שלכם"
            : "Drag to match your supermarket's aisle walking order"
    }

    // MARK: Sync status

    public static func syncStatusConnecting(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מתחבר..." : "Connecting..."
    }

    public static func syncStatusNeedsCode(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מקומי בלבד" : "Local only"
    }

    public static func syncStatusWaitingForNetwork(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "אופליין" : "Offline"
    }

    public static func syncStatusInvalidCode(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "קוד שגוי" : "Wrong code"
    }

    public static func syncStatusError(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "שגיאת סנכרון" : "Sync error"
    }

    public static func pendingChanges(_ lang: AppLanguage, count: Int) -> String {
        lang == .hebrew ? "\(count) שינויים ממתינים לשליחה" : "\(count) changes waiting to be sent"
    }

    // MARK: Settings

    public static func householdCodeHint(_ lang: AppLanguage) -> String {
        lang == .hebrew
            ? "הזינו את קוד משק הבית בשני המכשירים כדי לשתף את הרשימה. בלי קוד הרשימה נשמרת רק במכשיר הזה."
            : "Enter the household code on both phones to share the list. Without a code the list stays on this phone only."
    }

    public static func invalidCodeMessage(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "הקוד לא מוכר. בדקו אותו ונסו שוב." : "This code is not recognised. Check it and try again."
    }

    public static func saveSyncSettingsButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "שמור והתחבר" : "Save & Connect"
    }

    public static func languageLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "שפה" : "Language"
    }

    public static func advancedSectionTitle(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מתקדם: שרת" : "Advanced: Server"
    }

    public static func serverUrlLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "כתובת פרויקט Supabase" : "Supabase Project URL"
    }

    public static func serverKeyLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "מפתח Anon של Supabase" : "Supabase Anon Key"
    }

    public static func doneButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "סיום" : "Done"
    }

    // MARK: Item details

    public static func itemNamePlaceholder(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "שם המוצר" : "Item name"
    }

    public static func choosePhotoButton(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "בחר תמונה מהגלריה" : "Choose Item Photo"
    }

    public static func noCategoryLabel(_ lang: AppLanguage) -> String {
        lang == .hebrew ? "ללא מחלקה" : "No aisle"
    }
}
