import SwiftUI

public struct CategoriesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ShoppingStore

    @State private var supabaseUrl: String = ""
    @State private var supabaseAnonKey: String = ""
    @State private var householdCode: String = ""

    public init(store: ShoppingStore) {
        self.store = store
        self._supabaseUrl = State(initialValue: store.config.urlString)
        self._supabaseAnonKey = State(initialValue: store.config.anonKey)
        self._householdCode = State(initialValue: store.config.householdInviteCode)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Language / שפה", selection: $store.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(store.categories.sorted(by: { $0.sortOrder < $1.sortOrder })) { category in
                        HStack(spacing: 12) {
                            Text(category.icon)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text(category.nameHe)
                                    .font(.body.weight(.medium))
                                Text(category.nameEn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { indices, newOffset in
                        store.moveCategories(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    Text(L10n.categoryLabel(store.language))
                } footer: {
                    Text(L10n.reorderAislesHint(store.language))
                }

                Section {
                    TextField(L10n.householdCodeLabel(store.language), text: $householdCode)
                        .textInputAutocapitalization(.characters)
                    TextField("Supabase Project URL", text: $supabaseUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Supabase Anon Key", text: $supabaseAnonKey)

                    Button(store.language == .hebrew ? "שמור הגדרות סנכרון" : "Save Cloud Sync Settings") {
                        store.updateSupabaseConfig(
                            SupabaseConfig(
                                urlString: supabaseUrl,
                                anonKey: supabaseAnonKey,
                                householdInviteCode: householdCode
                            )
                        )
                    }
                    .bold()
                } header: {
                    Text(L10n.householdCodeLabel(store.language))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.settingsTitle(store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.saveButton(store.language)) {
                        dismiss()
                    }
                }
            }
        }
    }
}
