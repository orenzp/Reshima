import SwiftUI

public struct QuickAddBarView: View {
    @Bindable var store: ShoppingStore
    @Binding var query: String

    public init(store: ShoppingStore, query: Binding<String>) {
        self.store = store
        self._query = query
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.quickAddPlaceholder(store.language), text: $query)
                    .submitLabel(.done)
                    .onSubmit {
                        submitCurrentQuery()
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        submitCurrentQuery()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            let currentSuggestions = store.suggestions(for: query)
            if !currentSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if query.isEmpty {
                            Text(L10n.staplesTitle(store.language) + ":")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }

                        ForEach(currentSuggestions) { suggestion in
                            Button {
                                withAnimation(.snappy) {
                                    store.quickAddItem(
                                        name: suggestion.name,
                                        explicitCategory: suggestion.defaultCategoryId,
                                        explicitUnit: suggestion.defaultUnit
                                    )
                                    query = ""
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if let cat = store.category(for: suggestion.defaultCategoryId) {
                                        Text(cat.icon)
                                            .font(.caption)
                                    }
                                    Text(suggestion.name)
                                        .font(.caption.weight(.medium))
                                    Image(systemName: "plus")
                                        .font(.caption2.bold())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color(.systemBackground))
    }

    private func submitCurrentQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.snappy) {
            store.quickAddItem(name: trimmed)
            query = ""
        }
    }
}
