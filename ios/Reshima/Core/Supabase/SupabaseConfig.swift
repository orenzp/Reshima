import Foundation

public struct SupabaseConfig: Codable, Equatable, Sendable {
    public var urlString: String
    public var anonKey: String
    public var householdInviteCode: String

    public init(urlString: String, anonKey: String, householdInviteCode: String = "RESHIMA-HOME") {
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

        return SupabaseConfig(
            urlString: bundleUrl,
            anonKey: bundleKey,
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
