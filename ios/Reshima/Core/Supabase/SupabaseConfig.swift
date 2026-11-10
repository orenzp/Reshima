import Foundation

public struct SupabaseConfig: Codable, Equatable, Sendable {
    public static let defaultHouseholdId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let defaultListId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    public static let defaultProjectURL = "https://wlvrqopqvmsbrcigftfo.supabase.co"
    public static let defaultAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndsdnJxb3Bxdm1zYnJjaWdmdGZvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyNjQ1NjgsImV4cCI6MjEwOTg0MDU2OH0.CjbZWPocQDQ3bQiFeEq_6lQ7LN6ouo3HHrx5sDLgF5U"

    public var urlString: String
    public var anonKey: String
    public var householdInviteCode: String

    public init(urlString: String, anonKey: String, householdInviteCode: String = "ZIPORI") {
        self.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.anonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.householdInviteCode = householdInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var isConfigured: Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              scheme.hasPrefix("http"),
              !urlString.contains("your-project-ref"),
              !anonKey.isEmpty,
              !anonKey.contains("your-public-anon-key") else {
            return false
        }
        return true
    }

    public static func loadDefault() -> SupabaseConfig {
        let defaults = UserDefaults.standard
        let savedUrl = defaults.string(forKey: "reshima.supabase.url") ?? ""
        let savedKey = defaults.string(forKey: "reshima.supabase.anonKey") ?? ""
        let savedCode = defaults.string(forKey: "reshima.household.code") ?? "ZIPORI"

        if !savedUrl.isEmpty && !savedKey.isEmpty {
            return SupabaseConfig(urlString: savedUrl, anonKey: savedKey, householdInviteCode: savedCode)
        }

        let bundleUrl = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let bundleKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""

        let effectiveUrl = (!bundleUrl.isEmpty && !bundleUrl.hasPrefix("$(")) ? bundleUrl : defaultProjectURL
        let effectiveKey = (!bundleKey.isEmpty && !bundleKey.hasPrefix("$(")) ? bundleKey : defaultAnonKey

        return SupabaseConfig(
            urlString: effectiveUrl,
            anonKey: effectiveKey,
            householdInviteCode: savedCode
        )
    }

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(urlString, forKey: "reshima.supabase.url")
        defaults.set(anonKey, forKey: "reshima.supabase.anonKey")
        defaults.set(householdInviteCode, forKey: "reshima.household.code")
    }
}
