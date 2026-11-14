import SwiftUI

public struct CategoriesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ShoppingStore

    @State private var supabaseUrl: String
    @State private var supabaseAnonKey: String
    @State private var householdCode: String

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
                    Picker(L10n.languageLabel(store.language), selection: $store.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField(L10n.householdCodeLabel(store.language), text: $householdCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    Button(L10n.saveSyncSettingsButton(store.language)) {
                        saveSyncSettings()
                    }
                    .bold()

                    syncStatusRow
                } header: {
                    Text(L10n.householdCodeLabel(store.language))
                } footer: {
                    Text(L10n.householdCodeHint(store.language))
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

                Section(L10n.advancedSectionTitle(store.language)) {
                    TextField(L10n.serverUrlLabel(store.language), text: $supabaseUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L10n.serverKeyLabel(store.language), text: $supabaseAnonKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.caption.monospaced())
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.settingsTitle(store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.doneButton(store.language)) {
                        saveSyncSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveSyncSettings() {
        store.updateSupabaseConfig(
            SupabaseConfig(
                urlString: supabaseUrl,
                anonKey: supabaseAnonKey,
                householdInviteCode: householdCode
            )
        )
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch store.syncState {
        case .needsCode:
            EmptyView()
        case .connecting:
            Label(L10n.syncStatusConnecting(store.language), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .synced:
            Label(L10n.syncStatusConnected(store.language), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .offline:
            VStack(alignment: .leading, spacing: 2) {
                Label(L10n.syncStatusWaitingForNetwork(store.language), systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
                if store.pendingChangeCount > 0 {
                    Text(L10n.pendingChanges(store.language, count: store.pendingChangeCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .invalidCode:
            Label(L10n.invalidCodeMessage(store.language), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .error(let message):
            VStack(alignment: .leading, spacing: 2) {
                Label(L10n.syncStatusError(store.language), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
