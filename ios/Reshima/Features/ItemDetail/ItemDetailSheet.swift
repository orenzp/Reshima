import SwiftUI
import PhotosUI

public struct ItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ShoppingStore

    @State private var draft: ListItem
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedPhotoData: Data?

    public init(store: ShoppingStore, item: ListItem) {
        self.store = store
        self._draft = State(initialValue: item)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.itemDetailsTitle(store.language), text: $draft.name)
                        .font(.headline)

                    HStack {
                        Text(L10n.quantityLabel(store.language))
                        Spacer()
                        Stepper(
                            value: $draft.quantity,
                            in: 0.5...100,
                            step: draft.unit.stepIncrement
                        ) {
                            Text(draft.formattedQuantity)
                                .font(.body.monospacedDigit().bold())
                        }
                    }

                    Picker(L10n.unitLabel(store.language), selection: $draft.unit) {
                        ForEach(UnitType.allCases) { unitType in
                            Text(unitType.localizedLabel(store.language))
                                .tag(unitType)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(L10n.categoryLabel(store.language)) {
                    Picker(L10n.categoryLabel(store.language), selection: $draft.categoryId) {
                        ForEach(store.categories.sorted(by: { $0.sortOrder < $1.sortOrder })) { cat in
                            Text("\(cat.icon) \(cat.localizedName(store.language))")
                                .tag(Optional(cat.id))
                        }
                    }
                }

                Section(L10n.notesLabel(store.language)) {
                    TextField(L10n.notesLabel(store.language), text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(L10n.photoLabel(store.language)) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            store.language == .hebrew ? "בחר תמונה מהגלריה" : "Choose Item Photo",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .onChange(of: selectedPhotoItem) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                attachedPhotoData = data
                            }
                        }
                    }

                    if let data = attachedPhotoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let existingPath = draft.photoPath,
                              let uiImage = UIImage(contentsOfFile: existingPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.deleteItem(draft)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label(L10n.deleteButton(store.language), systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(L10n.itemDetailsTitle(store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancelButton(store.language)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.saveButton(store.language)) {
                        store.updateItem(draft, newPhotoData: attachedPhotoData)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
