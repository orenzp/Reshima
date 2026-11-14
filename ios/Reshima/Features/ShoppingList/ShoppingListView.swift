import SwiftUI

public struct ShoppingListView: View {
    @Bindable var store: ShoppingStore
    @State private var quickAddText: String = ""
    @State private var selectedItemForDetail: ListItem?
    @State private var isShowingSettings: Bool = false
    @State private var isCheckedSectionExpanded: Bool = true

    public init(store: ShoppingStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QuickAddBarView(
                    store: store,
                    query: $quickAddText
                )

                if store.activeAisleGroups.isEmpty && store.checkedItems.isEmpty {
                    emptyStateView
                } else {
                    shoppingListContent
                }
            }
            .navigationTitle(L10n.appTitle(store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    syncStatusBadge
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            store.language = (store.language == .hebrew) ? .english : .hebrew
                        } label: {
                            Text(store.language == .hebrew ? "EN" : "עב")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(item: $selectedItemForDetail) { item in
                ItemDetailSheet(store: store, item: item)
                    .environment(\.layoutDirection, store.language.isRTL ? .rightToLeft : .leftToRight)
            }
            .sheet(isPresented: $isShowingSettings) {
                CategoriesSettingsView(store: store)
                    .environment(\.layoutDirection, store.language.isRTL ? .rightToLeft : .leftToRight)
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    private var syncStatusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 8, height: 8)
            Text(syncStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var syncStatusColor: Color {
        switch store.syncState {
        case .synced: return .green
        case .connecting, .offline: return .orange
        case .needsCode: return .gray
        case .invalidCode, .error: return .red
        }
    }

    private var syncStatusText: String {
        switch store.syncState {
        case .synced: return L10n.syncStatusConnected(store.language)
        case .connecting: return L10n.syncStatusConnecting(store.language)
        case .offline: return L10n.syncStatusWaitingForNetwork(store.language)
        case .needsCode: return L10n.syncStatusNeedsCode(store.language)
        case .invalidCode: return L10n.syncStatusInvalidCode(store.language)
        case .error: return L10n.syncStatusError(store.language)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(L10n.emptyListTitle(store.language))
                .font(.title3.bold())
            Text(L10n.emptyListSubtitle(store.language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var shoppingListContent: some View {
        List {
            ForEach(store.activeAisleGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        ShoppingItemRow(
                            item: item,
                            language: store.language,
                            onToggleCheck: {
                                withAnimation(.snappy) {
                                    store.toggleChecked(item)
                                }
                            },
                            onIncrement: {
                                store.adjustQuantity(item, delta: item.unit.stepIncrement)
                            },
                            onDecrement: {
                                store.adjustQuantity(item, delta: -item.unit.stepIncrement)
                            },
                            onTapDetail: {
                                selectedItemForDetail = item
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.deleteItem(item)
                            } label: {
                                Label(L10n.deleteButton(store.language), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(group.category.icon)
                        Text(group.category.localizedName(store.language))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            if !store.checkedItems.isEmpty {
                Section {
                    if isCheckedSectionExpanded {
                        ForEach(store.checkedItems) { item in
                            ShoppingItemRow(
                                item: item,
                                language: store.language,
                                onToggleCheck: {
                                    withAnimation(.snappy) {
                                        store.toggleChecked(item)
                                    }
                                },
                                onIncrement: {},
                                onDecrement: {},
                                onTapDetail: {
                                    selectedItemForDetail = item
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteItem(item)
                                } label: {
                                    Label(L10n.deleteButton(store.language), systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Button {
                            withAnimation {
                                isCheckedSectionExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCheckedSectionExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.bold())
                                Text(L10n.inCartSectionTitle(store.language, count: store.checkedItems.count))
                                    .font(.subheadline.bold())
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(L10n.clearChecked(store.language)) {
                            withAnimation {
                                store.clearCheckedItems()
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct ShoppingItemRow: View {
    let item: ListItem
    let language: AppLanguage
    let onToggleCheck: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onTapDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCheck) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onTapDetail) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .strikethrough(item.isChecked)
                            .foregroundStyle(item.isChecked ? .secondary : .primary)

                        if item.photoPath != nil {
                            Image(systemName: "photo.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    if !item.notes.isEmpty {
                        Text(item.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !item.isChecked {
                HStack(spacing: 6) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(item.quantityWithUnit(language))
                        .font(.caption.monospacedDigit().bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())

                    Button(action: onIncrement) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(item.quantityWithUnit(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
